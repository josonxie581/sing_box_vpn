'use strict';

const HOST = 'io.gsou.dmit';
const DMIT_URL = 'https://www.dmit.io/clientarea.php';
const MAX_MESSAGE_BYTES = 1024 * 1024;
const RESULT_CODES = new Set(['loginRequired', 'verificationRequired', 'pageNotOpen',
  'ambiguousAccount', 'requestFailed', 'invalidData', 'pageLoading']);
// A live Port is a transient browser handle, not persisted application state.
// All popup/status metadata lives in chrome.storage.session.
let nativePort = null;

async function updateState(values) {
  await chrome.storage.session.set(values);
  if (values.code) {
    const badge = values.code === 'ok' ? 'OK' : values.code === 'syncing' ? '...' : '!';
    await chrome.action.setBadgeText({text: badge});
  }
}

function safely(action) {
  void (async () => {
    try { await action(); }
    catch (_) {
      try { await updateState({code: 'requestFailed', busy: false}); }
      catch (_) { /* Browser shutdown can invalidate extension APIs. */ }
    }
  })();
}

function postNative(port, message) {
  if (port !== nativePort) throw new Error('Disconnected');
  if (new TextEncoder().encode(JSON.stringify(message)).length > MAX_MESSAGE_BYTES) {
    throw new Error('Oversized message');
  }
  port.postMessage(message);
}

function connectNative() {
  if (nativePort) return;
  const port = chrome.runtime.connectNative(HOST);
  nativePort = port;
  safely(async () => updateState({bridgeConnected: false, busy: false, code: 'connecting'}));
  port.onMessage.addListener(message => safely(async () => {
    if (port !== nativePort || !message || typeof message !== 'object') return;
    switch (message.type) {
      case 'ready':
        if (message.protocol !== 1) {
          await updateState({bridgeConnected: false, busy: false, code: 'protocolError'});
          port.disconnect();
          nativePort = null;
          return;
        }
        await updateState({bridgeConnected: true, busy: false, code: 'connected'});
        safely(async () => sync());
        break;
      case 'ping':
        postNative(port, {type: 'pong'});
        break;
      case 'refresh':
        if (typeof message.requestId === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(message.requestId)) {
          safely(async () => sync(message.requestId));
        }
        break;
      case 'ack':
        if (message.forType === 'snapshot') {
          const state = await chrome.storage.session.get('activeRequestId');
          const values = {lastSyncedAt: message.updatedAt, serverCount: message.serverCount};
          if (state.activeRequestId === message.requestId) {
            Object.assign(values, {code: 'ok', busy: false});
          }
          await updateState(values);
        }
        break;
      case 'error': {
        const code = ['alreadyConnected', 'invalidData', 'protocolError'].includes(message.code)
          ? message.code : 'requestFailed';
        await updateState({code, busy: false});
        break;
      }
    }
  }));
  port.onDisconnect.addListener(() => {
    // Read lastError to acknowledge it, but never log payloads or local paths.
    void chrome.runtime.lastError;
    if (nativePort !== port) return;
    nativePort = null;
    safely(async () => {
      const state = await chrome.storage.session.get('code');
      await updateState({bridgeConnected: false, busy: false,
        code: ['alreadyConnected', 'protocolError'].includes(state.code) ? state.code : 'nativeUnavailable'});
    });
  });
}

async function sync(requestId) {
  const options = requestId ? {} : {ifAvailable: true};
  await navigator.locks.request('gsou-dmit-sync', options, async lock => {
    if (!lock) return;
    const port = nativePort;
    const state = await chrome.storage.session.get('bridgeConnected');
    if (!port || !state.bridgeConnected) {
      connectNative();
      return;
    }
    const id = requestId || 'auto-' + crypto.randomUUID();
    await updateState({code: 'syncing', busy: true, activeRequestId: id});
    try {
      postNative(port, {type: 'status', code: 'syncing', requestId: id});
      const tabs = (await chrome.tabs.query({url: 'https://www.dmit.io/*'})).filter(tab => {
        try { return new URL(tab.url).pathname === '/clientarea.php'; }
        catch (_) { return false; }
      });
      let result;
      if (tabs.length === 0) result = {code: 'pageNotOpen'};
      else if (tabs.length > 1) result = {code: 'ambiguousAccount'};
      else {
        const executions = await chrome.scripting.executeScript({
          target: {tabId: tabs[0].id}, files: ['collector.js'], world: 'ISOLATED',
        });
        result = executions.find(item => item.frameId === 0)?.result;
      }
      if (result?.code === 'ok' && Array.isArray(result.items)) {
        postNative(port, {type: 'snapshot', requestId: id, items: result.items});
        // Only a native-host acknowledgement establishes a successful sync.
      } else {
        const code = result?.code === 'loading' ? 'pageLoading'
          : RESULT_CODES.has(result?.code) ? result.code : 'requestFailed';
        postNative(port, {type: 'status', code, requestId: id});
        await updateState({code, busy: false});
      }
    } catch (_) {
      try { postNative(port, {type: 'status', code: 'requestFailed', requestId: id}); }
      catch (_) { /* Disconnect is reported by the port listener. */ }
      await updateState({code: nativePort ? 'requestFailed' : 'nativeUnavailable', busy: false});
    }
  });
}

async function setupAlarms() {
  if (!await chrome.alarms.get('dmit-reconnect')) {
    await chrome.alarms.create('dmit-reconnect', {periodInMinutes: 1});
  }
  if (!await chrome.alarms.get('dmit-sync')) {
    await chrome.alarms.create('dmit-sync', {periodInMinutes: 5});
  }
}

chrome.runtime.onInstalled.addListener(() => safely(async () => {
  await setupAlarms();
  connectNative();
}));
chrome.runtime.onStartup.addListener(() => safely(async () => {
  await setupAlarms();
  connectNative();
}));
chrome.alarms.onAlarm.addListener(alarm => safely(async () => {
  if (alarm.name === 'dmit-reconnect') connectNative();
  if (alarm.name === 'dmit-sync') await sync();
}));
chrome.tabs.onUpdated.addListener((_tabId, change, tab) => safely(async () => {
  if (change.status !== 'complete' || !tab.url) return;
  const url = new URL(tab.url);
  if (url.origin === 'https://www.dmit.io' && url.pathname === '/clientarea.php') await sync();
}));
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('popup/popup.html')) return;
  void (async () => {
    try {
      switch (message?.type) {
        case 'state':
          sendResponse(await chrome.storage.session.get(['code', 'busy', 'bridgeConnected', 'lastSyncedAt', 'serverCount']));
          return;
        case 'connect':
          connectNative();
          break;
        case 'refresh':
          await sync('popup-' + crypto.randomUUID());
          break;
        case 'open':
          await chrome.tabs.create({url: DMIT_URL, active: true});
          break;
        default:
          sendResponse({ok: false});
          return;
      }
      sendResponse({ok: true});
    } catch (_) { sendResponse({ok: false}); }
  })();
  return true;
});

// Startup may be caused by a popup/event rather than browser onStartup.
safely(async () => {
  await setupAlarms();
  connectNative();
});

