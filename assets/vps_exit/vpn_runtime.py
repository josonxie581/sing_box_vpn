"""Root-only runtime operations. Candidate configs stay in memory, never in backups."""
import copy,hashlib,json,os,pathlib,signal,socket,struct,subprocess,tempfile,time,urllib.parse
from vpn_policy import select,AU_TAG
ROOT=pathlib.Path('/root/sing-box')
EXE=str(ROOT/'sing-box')
LIVE=ROOT/'config.json'
TAG=AU_TAG
def exit_metadata():
 data=json.loads(pathlib.Path('/var/lib/shaowei-vpn/exits.json').read_text())
 for key in ('direct','au'):
  __import__('ipaddress').ip_address(data[key]['ip'])
 return data
def validate(config):
 r=subprocess.run([EXE,'check','-c','/dev/stdin'],input=json.dumps(config).encode(),capture_output=True,cwd=str(ROOT),timeout=10)
 if r.returncode:raise ValueError('VPS 配置校验失败，尚未应用')
def reserve():
 with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
def stop(p):
 if p and p.poll() is None:
  p.terminate()
  try:p.wait(timeout=4)
  except subprocess.TimeoutExpired:p.kill();p.wait(timeout=4)
def ready(p,port,host='127.0.0.1'):
 for _ in range(60):
  if p.poll() is not None:raise RuntimeError('probe_process_terminated')
  try:
   with socket.create_connection((host,port),timeout=.1):return
  except OSError:time.sleep(.05)
 raise RuntimeError('probe_listener_timeout')
def run_config(c,log):
 p=subprocess.Popen([EXE,'run','-c','/dev/stdin'],cwd=str(ROOT),stdin=subprocess.PIPE,stdout=log,stderr=log,text=True)
 p.stdin.write(json.dumps(c));p.stdin.close()
 return p
def exact(s,n):
 b=b''
 while len(b)<n:
  q=s.recv(n-len(b))
  if not q:raise RuntimeError('socks_closed')
  b+=q
 return b
def udp_test(port,expected):
 with socket.create_connection(('127.0.0.1',port),timeout=4) as control:
  control.settimeout(4);control.sendall(b'\x05\x01\x00');assert exact(control,2)==b'\x05\x00'
  control.sendall(b'\x05\x03\x00\x01'+b'\0'*6);h=exact(control,4);assert h[1]==0
  if h[3]==1:relay=socket.inet_ntoa(exact(control,4))
  elif h[3]==3:relay=exact(control,exact(control,1)[0]).decode()
  else:relay=socket.inet_ntop(socket.AF_INET6,exact(control,16))
  rp=struct.unpack('!H',exact(control,2))[0]
  if relay=='0.0.0.0':relay='127.0.0.1'
  token=os.urandom(12);cookie=bytes.fromhex('2112a442');payload=bytes.fromhex('000100002112a442')+token
  dest=socket.gethostbyname('stun.cloudflare.com')
  with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as u:
   u.settimeout(5);u.sendto(b'\0\0\0\x01'+socket.inet_aton(dest)+struct.pack('!H',3478)+payload,(relay,rp));d,_=u.recvfrom(4096)
  off=10 if d[3]==1 else 22 if d[3]==4 else 7+d[4];body=d[off:];i=20;mapped=None
  while i+4<=len(body):
   typ,n=struct.unpack('!HH',body[i:i+4]);v=body[i+4:i+4+n];i+=4+((n+3)//4)*4
   if typ==0x20 and n>=8 and v[1]==1:mapped=socket.inet_ntoa(bytes(v[4+k]^cookie[k] for k in range(4)))
  return {'name':'non_claude_udp_stun','valid_stun':body[8:20]==token,'exit_ip':mapped,'passed':body[8:20]==token and mapped==expected}
def probe(config,live=False,emit=False,policy=None):
 exits=exit_metadata()
 server=None;client=None;tests=[];server_logs=tempfile.TemporaryFile(mode='w+t');client_logs=tempfile.TemporaryFile(mode='w+t')
 try:
  vm=copy.deepcopy(next(x for x in config['inbounds'] if x['type']=='vmess'))
  if live:server_host=vm['listen'];server_port=vm['listen_port']
  else:
   server_host='127.0.0.1';server_port=reserve();vm.update(listen=server_host,listen_port=server_port)
   isolated={k:copy.deepcopy(config[k]) for k in ('dns','outbounds','route') if k in config}
   isolated['log']={'level':'debug','timestamp':False};isolated['inbounds']=[vm]
   server=run_config(isolated,server_logs);ready(server,server_port)
  port=reserve();user=vm['users'][0]
  outbound={'type':'vmess','tag':'tunnel','server':server_host,'server_port':server_port,'uuid':user['uuid'],'security':'auto','alter_id':user.get('alterId',0)}
  if vm.get('transport'):outbound['transport']=copy.deepcopy(vm['transport'])
  cc={'log':{'level':'warn'},'inbounds':[{'type':'mixed','tag':'validation','listen':'127.0.0.1','listen_port':port}],'outbounds':[outbound],'route':{'final':'tunnel'}}
  client=run_config(cc,client_logs);ready(client,port)
  plans=[
   ('claude_web_exit','https://claude.ai/cdn-cgi/trace','socks5h',TAG,200,exits['au']['ip']),
   ('anthropic_api','https://api.anthropic.com/v1/models','socks5h',TAG,401,None),
   ('claude_literal_ip_sni','https://claude.ai/cdn-cgi/trace','socks5',TAG,200,exits['au']['ip']),
   ('openai_api','https://api.openai.com/v1/models','socks5h','direct',401,None),
   ('openai_exit','https://api.openai.com/cdn-cgi/trace','socks5h','direct',200,exits['direct']['ip']),
   ('ordinary_site_exit','https://www.cloudflare.com/cdn-cgi/trace','socks5h','direct',200,exits['direct']['ip']),
   ('google_direct','https://www.google.com/generate_204','socks5h','direct',204,None),
   ('ping0_direct','https://ping0.cc/env','socks5h','direct',200,None)]
  for name,url,scheme,wanted,status,expected_ip in plans:
   if policy:
    choice=select(policy,urllib.parse.urlsplit(url).hostname)
    wanted=TAG if choice=='au' else 'direct'
    if expected_ip:expected_ip=exits['au']['ip'] if choice=='au' else exits['direct']['ip']
   server_logs.seek(0,2);start=server_logs.tell();t=time.monotonic()
   r=subprocess.run(['curl','-q','-4','--noproxy','','--proxy',f'{scheme}://127.0.0.1:{port}','--silent','--show-error','--connect-timeout','6','--max-time','12','--max-filesize','500000','--write-out','\nCHECK_HTTP=%{http_code}',url],capture_output=True,text=True,timeout=15)
   body,sep,code=r.stdout.rpartition('\nCHECK_HTTP=');time.sleep(.05)
   fields=dict(line.split('=',1) for line in body.splitlines() if '=' in line) if expected_ip else {}
   item={'name':name,'expected_outbound':wanted,'http':int(code) if sep and code.isdigit() else None,'seconds':round(time.monotonic()-t,3),'curl_exit':r.returncode}
   if expected_ip:item.update(exit_ip=fields.get('ip'),country=fields.get('loc'))
   if not live:
    server_logs.seek(start);lines=server_logs.read();marker='outbound/socks['+TAG+']' if wanted==TAG else 'outbound/direct[direct]'
    evidence=[line for line in lines.splitlines() if marker in line and ('outbound connection' in line or 'outbound packet' in line)]
    item['outbound_confirmed']=bool(evidence);item['route_evidence']=evidence[:1]
   item['passed']=r.returncode==0 and item['http']==status and (not expected_ip or fields.get('ip')==expected_ip) and (live or item.get('outbound_confirmed',False))
   tests.append(item)
   if emit:print('LIVE_TEST' if live else 'STAGE_TEST',json.dumps(item),flush=True)
  try:item=udp_test(port,exits['au']['ip'] if policy and policy['default']=='au' else exits['direct']['ip'])
  except Exception as e:item={'name':'non_claude_udp_stun','passed':False,'error':type(e).__name__}
  tests.append(item)
  if emit:print('LIVE_TEST' if live else 'STAGE_TEST',json.dumps(item),flush=True)
  if not all(x['passed'] for x in tests):raise RuntimeError('probe_validation_failed')
  return tests
 except BaseException:
  secrets=[]
  for out in config.get('outbounds',[]):
   secrets += [str(out[k]) for k in ('username','password','uuid') if out.get(k)]
  for ib in config.get('inbounds',[]):
   for user in ib.get('users',[]):secrets += [str(user[k]) for k in ('password','uuid') if user.get(k)]
  for label,log in [('server',server_logs),('client',client_logs)]:
   log.seek(0);tail=log.read()[-1800:]
   for secret in secrets:tail=tail.replace(secret,'[REDACTED]')
   print('PROBE_DIAGNOSTIC',json.dumps({'component':label,'tail':tail}),flush=True)
  raise
 finally:
  stop(client);stop(server);server_logs.close();client_logs.close()
def main_pid():
 matches=[]
 for p in os.listdir('/proc'):
  if p.isdigit():
   try:
    cmd=open('/proc/'+p+'/cmdline','rb').read().split(b'\0')
    if cmd[0] in (b'./sing-box',str(ROOT/'sing-box').encode()) and cmd[1:4]==[b'run',b'-c',b'config.json']:matches.append(int(p))
   except (OSError,IndexError):pass
 if len(matches)!=1:raise RuntimeError('main_process_not_unique')
 return matches[0]
def identity(pid):return pathlib.Path('/proc/'+str(pid)+'/stat').read_text().split()[21]
def terminate_exact(pid,ident):
 try:
  if identity(pid)!=ident:raise RuntimeError('process_identity_changed')
  os.kill(pid,signal.SIGTERM)
  for _ in range(50):
   if not pathlib.Path('/proc/'+str(pid)).exists():return
   time.sleep(.1)
  if identity(pid)==ident:os.kill(pid,signal.SIGKILL)
 except FileNotFoundError:pass
def launch_main():
 f=open(ROOT/'sing-box.log','ab',buffering=0)
 try:return subprocess.Popen(['./sing-box','run','-c','config.json'],cwd=str(ROOT),stdin=subprocess.DEVNULL,stdout=f,stderr=f,start_new_session=True)
 finally:f.close()

def write_config(raw):
 fd,path=tempfile.mkstemp(prefix='.routes-',suffix='.tmp',dir=str(ROOT))
 try:
  os.fchmod(fd,0o600)
  with os.fdopen(fd,'wb') as f:
   f.write(raw);f.flush();os.fsync(f.fileno())
  os.replace(path,LIVE)
 finally:
  if os.path.exists(path):os.unlink(path)
def replace_config(previous,candidate,policy):
 encoded=(json.dumps(candidate,ensure_ascii=False,indent=2)+'\n').encode()
 if json.loads(previous)==candidate:
  return {'unchanged':True,'tests':probe(candidate,live=True,policy=policy)}
 if LIVE.read_bytes()!=previous:raise ValueError('配置已被其他操作更新，请刷新后重试')
 pid=main_pid();ident=identity(pid);keepers=[]
 for p in os.listdir('/proc'):
  if not p.isdigit():continue
  try:
   cmd=pathlib.Path('/proc/'+p+'/cmdline').read_bytes().split(b'\0')
   if cmd[:3]==[b'/bin/bash',b'./keepalive.sh',b'main'] and os.readlink('/proc/'+p+'/cwd')==str(ROOT):keepers.append((int(p),identity(int(p))))
  except OSError:pass
 paused=[];newproc=None;stopped=False
 try:
  for keeper,kid in keepers:
   if identity(keeper)!=kid:raise RuntimeError('keeper_identity_changed')
   os.kill(keeper,signal.SIGSTOP);paused.append((keeper,kid))
  if LIVE.read_bytes()!=previous:raise ValueError('配置已被其他操作更新，请刷新后重试')
  terminate_exact(pid,ident);stopped=True
  write_config(encoded);newproc=launch_main()
  vm=next(x for x in candidate['inbounds'] if x['type']=='vmess');ready(newproc,vm['listen_port'],vm['listen'])
  tests=probe(candidate,live=True,policy=policy)
  if newproc.poll() is not None or LIVE.read_bytes()!=encoded:raise RuntimeError('active_verification_failed')
  return {'unchanged':False,'tests':tests,'pid':newproc.pid}
 except BaseException as error:
  if stopped:
   stop(newproc);write_config(previous)
   restored=launch_main();vm=next(x for x in json.loads(previous)['inbounds'] if x['type']=='vmess')
   try:ready(restored,vm['listen_port'],vm['listen'])
   except Exception:raise RuntimeError('应用与自动恢复均未通过，请通过 SSH 检查服务') from None
   raise ValueError('应用验证失败，已自动恢复原配置') from None
  raise error
 finally:
  for keeper,kid in paused:
   try:
    if identity(keeper)==kid:os.kill(keeper,signal.SIGCONT)
   except OSError:pass

