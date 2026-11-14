# AWS VPS 安装脚本 ss4.sh

`ss4.sh` 已同步 `secure_ss4.sh` 的 sing-box 1.14.4、Snell v6、Naive HTTP/2/HTTP/3、Hysteria2 Gecko/Salamander 混淆及 BBR profile 配置。节点链接直接从实际配置生成，Naive 直连公网 IP，并通过 SNI 验证域名证书。下载必须匹配 GitHub 官方发布资产的 SHA-256。

保留 AWS 版的差异：所有代理入口监听 `0.0.0.0`，公网 IP 仅用于分享链接；保活和端口检查优先使用 `ss`；安装系统命令和 systemd 服务使用 `sudo`，服务仍使用安装者账户。安装账户需要 sudo 权限，Naive 证书和私钥必须能被该账户读取。

需要 Bash、Python 3、OpenSSL、curl 和脚本原有工具。协议参数与[通用说明](SECURE_SS4_PROTOCOLS.md)一致，将命令中的脚本名换为 `ss4.sh` 即可，例如：

```bash
HY2_OBFS=salamander HY2_BBR_PROFILE=conservative bash ss4.sh
```

安装后可使用 `singbox` 查看帮助，`singbox show` 查看节点，`singbox keep status` 查看保活状态，`singbox auto status` 查看开机启动状态。管理命令现已保留运行时参数，并包含证书、诊断等子命令需要的函数。

脚本最后会列出实际需要开放的 TCP、UDP 端口。EC2 安全组或 Lightsail 实例防火墙需要另行放行；脚本不会调用 AWS API 修改账号规则。Naive 的同一端口需要同时放行 TCP 和 UDP，Snell 使用 TCP，Hysteria2/TUIC 使用 UDP。不要删除现有 SSH 规则。

此脚本仍是安装/重装工具，选择重装会删除原安装目录。已有实例请先保存需要的配置及节点信息，不能视为无损原地升级。

脚本开发阶段的验证包括本机隔离安装回归、AWS 监听与服务账户检查、实际生成管理命令的参数传递，以及 Windows 1.14.4 内核对完整配置的校验。后续实机部署记录见下节。

## dev-tokyo 实际部署（2026-11-15）

现已在 `dev-tokyo` 部署并进行公网验证。域名 `aws.voxinks.com` 以仅 DNS 方式指向 `52.69.86.148`，Naive 使用 TCP/UDP 10443；既有节点的端口和凭据保留。

证书由 Certbot 通过 HTTP-01 申请，`certbot.timer` 自动检查续期。Lightsail 的 TCP 80 规则需保留供后续验证使用。证书原件在 `/etc/letsencrypt/live/aws.voxinks.com/`；代理账户使用 `/etc/sing-box-certs/aws.voxinks.com/current/` 下的受限副本。私钥权限为 `640 root:ubuntu`，无需放宽整个 Let's Encrypt 目录权限。

续期部署钩子位于 `/etc/letsencrypt/renewal-hooks/deploy/gsou-naive`，源码为 `tools/aws_naive_cert_deploy.py`。它校验证书和私钥，切换完整证书版本，以 ubuntu 身份检查配置，并仅对该安装目录的 sing-box 进程发送 SIGHUP。已通过包含部署钩子的 `certbot renew --dry-run --run-deploy-hooks` 模拟续期验证。

使用 `singbox show` 查看并导入新生成的两条 Naive 链接；不要把带密码的节点链接公开。
