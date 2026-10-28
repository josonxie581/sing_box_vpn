'use strict';

const messages = {
  connecting: '正在连接本机 Gsou…',
  connected: '连接已建立，正在准备同步。',
  syncing: '正在读取 DMIT 服务器数据，不会切换或刷新网页。',
  ok: '已成功同步到本机 Gsou。',
  nativeUnavailable: '本机连接不可用。请运行发布包配套的本机连接注册脚本，再点击“连接本机应用”。',
  disconnected: '本机连接已断开，请重新连接。',
  loginRequired: '请在浏览器中登录 DMIT，扩展不会读取或填写你的密码。',
  verificationRequired: '请在 DMIT 页面完成真人验证或二次验证。扩展已暂停取数，不会重载页面。',
  pageNotOpen: '请打开 DMIT 客户中心，并保持该页面打开。',
  pageLoading: 'DMIT 页面仍在加载，加载完成后会自动同步。',
  ambiguousAccount: '打开了多个 DMIT 客户中心页面。为避免同步错误账号，请只保留需要同步的一个页面。',
  requestFailed: '读取失败，请检查 DMIT 页面和网络后重试。',
  invalidData: '返回的数据格式无效，未覆盖 Gsou 的上次数据。',
  alreadyConnected: '另一浏览器或用户配置已连接本机桥。请只在需要使用的浏览器配置中启用此扩展。',
  protocolError: '本机桥与扩展版本不一致或通信异常，请使用同一 Release 目录中的组件。',
};
let current = {};

function render(state) {
  current = state;
  document.getElementById('connection').textContent = state.bridgeConnected ? '本机连接：已连接' : '本机连接：未连接';
  document.getElementById('status').textContent = messages[state.code] || '等待本机连接。';
  const date = state.lastSyncedAt ? new Date(state.lastSyncedAt) : null;
  document.getElementById('updated').textContent = date && !Number.isNaN(date.getTime()) ? date.toLocaleString() : '尚未同步';
  document.getElementById('count').textContent = Number.isInteger(state.serverCount) ? String(state.serverCount) : '--';
  document.getElementById('connect').disabled = !!state.bridgeConnected;
  document.getElementById('refresh').disabled = !state.bridgeConnected || !!state.busy;
}

async function action(type) {
  try {
    const reply = await chrome.runtime.sendMessage({type});
    if (!reply?.ok) document.getElementById('status').textContent = '操作未完成，请检查扩展连接后重试。';
  } catch (_) {
    document.getElementById('status').textContent = '扩展暂时不可用，请关闭此窗口后重新打开。';
  }
}

document.getElementById('connect').addEventListener('click', () => { void action('connect'); });
document.getElementById('refresh').addEventListener('click', () => { void action('refresh'); });
document.getElementById('open').addEventListener('click', () => { void action('open'); });
chrome.storage.onChanged.addListener((changes, area) => {
  if (area !== 'session') return;
  const state = {...current};
  for (const [key, change] of Object.entries(changes)) state[key] = change.newValue;
  render(state);
});
void (async () => {
  try { render(await chrome.runtime.sendMessage({type: 'state'})); }
  catch (_) { render({code: 'nativeUnavailable', bridgeConnected: false}); }
})();

