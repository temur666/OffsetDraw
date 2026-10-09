'use strict';
(() => {
  const status = document.getElementById('remoteStatus');
  const applied = document.getElementById('appliedSettings');
  document.getElementById('serverAddress').textContent =
    ['127.0.0.1', 'localhost'].includes(location.hostname) ? '192.168.0.101:' + (location.port || '18765') : location.host;
  let revision = 0, savedRevision = 0, sending = false, initialized = false, debounce;
  const snapshot = () => ({ ...settings, color: ink });
  function showApplied(value) { applied.textContent = JSON.stringify(value, null, 2); }
  async function request(method, value) {
    const response = await fetch('/api/settings', {
      method, cache: 'no-store', signal: AbortSignal.timeout(4000),
      ...(value ? { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) } : {})
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.json();
  }
  async function flush() {
    if (sending || savedRevision === revision) return;
    sending = true;
    const current = revision, value = snapshot();
    status.textContent = '正在同步到电脑服务…';
    try {
      const result = await request('PUT', value);
      savedRevision = current;
      initialized = true;
      showApplied(result);
      status.textContent = '已同步到服务 · 手机下一笔生效';
    } catch (error) {
      status.textContent = '同步失败，保留本地调节，2 秒后重试';
      clearTimeout(debounce);
      debounce = setTimeout(flush, 2000);
    } finally {
      sending = false;
      // Edits made during a request must be sent afterward, never in parallel.
      if (revision !== current) { clearTimeout(debounce); debounce = setTimeout(flush, 100); }
    }
  }
  function edited() {
    revision++;
    status.textContent = '参数已修改 · 等待同步…';
    clearTimeout(debounce);
    debounce = setTimeout(flush, 100);
  }
  for (const key of Object.keys(defaults)) document.getElementById(key).addEventListener('input', edited);
  document.getElementById('color').addEventListener('input', edited);
  document.querySelectorAll('.swatch').forEach(button => button.addEventListener('click', edited));
  document.getElementById('reset').addEventListener('click', edited);
  async function initialize() {
    if (initialized || revision > 0) return;
    try {
      const value = await request('GET');
      if (revision > 0) return;
      for (const key of Object.keys(defaults)) document.getElementById(key).value = value[key];
      controls();
      setColor(value.color);
      showApplied(value);
      initialized = true;
      status.textContent = '已连接调参服务 · 拖动滑块自动同步';
    } catch (error) {
      status.textContent = '调参服务未连接 · 2 秒后重试，本地试画仍可用';
      setTimeout(initialize, 2000);
    }
  }
  initialize();
})();
