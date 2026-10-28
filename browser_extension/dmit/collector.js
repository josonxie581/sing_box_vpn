// Injected on demand into an existing https://www.dmit.io tab by the service
// worker (chrome.scripting.executeScript, isolated world). It performs only
// read-only same-origin GET requests with the browser's own session, projects a
// fixed whitelist of fields and returns either items or a bare status code.
// It never exports passwords, cookies, verification tokens, emails or raw bodies;
// it never navigates, reloads the page or solves challenges.
//
// The value of the last expression (a promise) is the injection result.
(async () => {
  'use strict';

  const ORIGIN = 'https://www.dmit.io';
  const PER_PAGE = 50;
  const MAX_PAGES = 20;
  const MAX_ITEMS = 1000;
  const MAX_LIST = 64;
  const MAX_STRING = 2048;
  const MAX_BODY_CHARS = 2000000;
  const REQUEST_TIMEOUT_MS = 20000;
  const TOTAL_TIMEOUT_MS = 90000;
  const deadline = Date.now() + TOTAL_TIMEOUT_MS;

  class Failure extends Error {
    constructor(code) {
      super(code);
      this.code = code;
    }
  }

  // ---- Page state: DOM inspection only, zero requests -------------------
  // Content scripts cannot see window._cf_chl_opt, so full-page challenges are
  // recognised through DOM markers, the page title and inline challenge script.
  const hasChallengeMarkers = () => {
    if (document.querySelector(
      '#challenge-form, #challenge-running, #challenge-stage, #cf-challenge-running, ' +
      '#cf-wrapper, #cf-please-wait, #challenge-error-text, .cf-browser-verification, ' +
      'script[src*="/cdn-cgi/challenge-platform/"][src*="/orchestrate/"]')) {
      return true;
    }
    if (/^(just a moment|attention required|checking your browser|请稍候|请稍等|正在验证)/i
      .test((document.title || '').trim())) {
      return true;
    }
    for (const script of document.scripts) {
      if (!script.src && script.textContent &&
          script.textContent.length < 300000 &&
          script.textContent.includes('_cf_chl_opt')) {
        return true;
      }
    }
    return false;
  };

  const pageState = () => {
    if (location.origin !== ORIGIN) return 'notOpen';
    if (document.readyState === 'loading') return 'loading';
    if (hasChallengeMarkers()) return 'challenge';
    const responses = [...document.querySelectorAll(
      '[name="cf-turnstile-response"], [name="g-recaptcha-response"], [name="h-captcha-response"]')];
    if (responses.some((input) => !input.value) ||
        (!responses.length && document.querySelector(
          '.cf-turnstile, .g-recaptcha, .h-captcha, iframe[src*="challenges.cloudflare.com"]'))) {
      return 'challenge';
    }
    if (document.querySelector(
      'input[autocomplete="one-time-code"], input[name="twofactorcode"], input[name="code"]')) {
      return 'otp';
    }
    const password = document.querySelector('#inputPassword[name="password"]');
    const email = document.querySelector('#inputEmail[name="username"]');
    if (password && email && password.form === email.form) return 'login';
    if (document.querySelector('input[type="password"]')) return 'unknownAuth';
    return 'page';
  };

  const state = pageState();
  if (state === 'loading') return { code: 'loading' };
  if (state === 'notOpen') return { code: 'pageNotOpen' };
  if (state === 'challenge' || state === 'otp') return { code: 'verificationRequired' };
  if (state === 'login' || state === 'unknownAuth') return { code: 'loginRequired' };

  // ---- Safe projection ---------------------------------------------------
  const scalar = (value) => {
    if (value === null || typeof value === 'boolean') return value;
    if (typeof value === 'number') return Number.isFinite(value) ? value : undefined;
    if (typeof value === 'string') return value.length <= MAX_STRING ? value : undefined;
    return undefined;
  };
  const scalarOrList = (value) => {
    if (!Array.isArray(value)) return scalar(value);
    if (value.length > MAX_LIST) return undefined;
    const out = value.map(scalar);
    return out.every((entry) => entry !== undefined) ? out : undefined;
  };
  const addressMap = (value) => {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return undefined;
    const out = {};
    for (const key of ['v4', 'v6']) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
      const entry = scalarOrList(value[key]);
      if (entry !== undefined) out[key] = entry;
    }
    return out;
  };
  const pick = (source, fields) => {
    if (source === null || typeof source !== 'object' || Array.isArray(source)) {
      throw new Failure('invalidData');
    }
    const out = {};
    for (const field of fields) {
      if (!Object.prototype.hasOwnProperty.call(source, field)) continue;
      const value = field === 'ips' ? addressMap(source[field]) : scalarOrList(source[field]);
      if (value !== undefined) out[field] = value;
    }
    return out;
  };
  const PRODUCT_FIELDS = ['id', 'domain', 'primaryip', 'ips'];
  const DETAIL_FIELDS = ['serviceid', 'hostname', 'dedicatedip', 'assignedips', 'vm_core',
    'vm_ram', 'disklimit', 'bwusage', 'bwlimit', 'bw_method', 'bw_disable_reset',
    'nextduedate', 'suspendonexceeded'];

  // ---- Read-only same-origin requests ------------------------------------
  const classifyHtml = (text) => {
    if (/_cf_chl_opt|\/cdn-cgi\/challenge-platform\/[^"']*\/orchestrate\//.test(text)) {
      return 'verificationRequired';
    }
    if (/type=["']password["']/.test(text)) return 'loginRequired';
    return null;
  };

  const getJson = async (path) => {
    const remaining = deadline - Date.now();
    if (remaining <= 0) throw new Failure('requestFailed');
    let response;
    let text;
    try {
      response = await fetch(path, {
        method: 'GET',
        credentials: 'same-origin',
        cache: 'no-store',
        redirect: 'follow',
        signal: AbortSignal.timeout(Math.min(REQUEST_TIMEOUT_MS, remaining)),
      });
      if (response.headers.get('cf-mitigated') === 'challenge') {
        throw new Failure('verificationRequired');
      }
      if (new URL(response.url).origin !== ORIGIN) throw new Failure('requestFailed');
      text = await response.text();
    } catch (error) {
      throw error instanceof Failure ? error : new Failure('requestFailed');
    }
    if (text.length > MAX_BODY_CHARS) throw new Failure('invalidData');
    if (!response.ok) throw new Failure(classifyHtml(text) ?? 'requestFailed');
    let body;
    try {
      body = JSON.parse(text);
    } catch (_) {
      throw new Failure(classifyHtml(text) ?? 'requestFailed');
    }
    if (body === null || typeof body !== 'object' || Array.isArray(body)) {
      throw new Failure('invalidData');
    }
    if (body.result !== 'success') throw new Failure('loginRequired');
    return body;
  };

  try {
    const items = [];
    const seen = new Set();
    let pages = 1;
    for (let page = 1; page <= pages; page++) {
      const result = await getJson(
        '/modules/addons/dmit_kernel/get_products.php?page=' + page + '&per_page=' + PER_PAGE);
      const data = result.data;
      if (!data || !Array.isArray(data.items) || !Number.isInteger(data.total_pages) ||
          data.total_pages < 0 || data.total_pages > MAX_PAGES ||
          (page > 1 && data.total_pages !== pages)) {
        throw new Failure('invalidData');
      }
      pages = data.total_pages;
      for (const product of data.items) {
        if (product === null || typeof product !== 'object' ||
            !/^\d+$/.test(String(product.id)) || seen.has(String(product.id)) ||
            items.length >= MAX_ITEMS) {
          throw new Failure('invalidData');
        }
        seen.add(String(product.id));
        const response = await getJson(
          '/clientarea.php?action=productdetails&id=' + encodeURIComponent(product.id) +
          '&json=1&pure=1&page=standard&subaction=whmcsdetail');
        const detail = response.success;
        if (!detail || typeof detail !== 'object' ||
            String(detail.serviceid) !== String(product.id)) {
          throw new Failure('invalidData');
        }
        items.push({
          product: pick(product, PRODUCT_FIELDS),
          detail: pick(detail, DETAIL_FIELDS),
        });
      }
    }
    return { code: 'ok', items };
  } catch (error) {
    return { code: error instanceof Failure ? error.code : 'requestFailed' };
  }
})();

