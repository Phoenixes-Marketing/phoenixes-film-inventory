(() => {
  const config = window.INVENTORY_INTERNAL_ACCESS_CONFIG || {};
  const apiBase = String(config.apiBase || "").replace(/\/+$/, "");
  const storageKey = "phoenixes.inventory.internal-access.v1";
  const endpoints = {
    session: `${apiBase}/api/session`,
    login: `${apiBase}/api/login`,
    internalData: `${apiBase}/api/internal-data`
  };

  const ui = {
    button: null,
    layer: null,
    form: null,
    password: null,
    error: null,
    loginPanel: null,
    unlockedPanel: null,
    expiry: null,
    toast: null,
    toastTimer: null
  };

  const lockIcon = `
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="5" y="10" width="14" height="10" rx="3" stroke="currentColor" stroke-width="1.8"/>
      <path d="M8.5 10V7.4a3.5 3.5 0 0 1 7 0V10" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
    </svg>
  `;

  const unlockedIcon = `
    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="5" y="10" width="14" height="10" rx="3" stroke="currentColor" stroke-width="1.8"/>
      <path d="M15.5 10V7.4a3.5 3.5 0 0 0-6.8-1.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
    </svg>
  `;

  function readStoredSession() {
    try {
      const value = JSON.parse(window.localStorage.getItem(storageKey) || "{}");
      if (typeof value.token !== "string" || !value.token) return null;
      return value;
    } catch (_) {
      return null;
    }
  }

  function saveSession(payload) {
    window.localStorage.setItem(storageKey, JSON.stringify({
      token: payload.token,
      expiresAt: payload.expiresAt
    }));
  }

  function clearSession() {
    window.localStorage.removeItem(storageKey);
  }

  function authorizationHeaders(token, extra = {}) {
    return {
      ...extra,
      Authorization: `Bearer ${token}`
    };
  }

  function createInterface() {
    const headerActions = document.querySelector(".header-actions");
    const refreshButton = document.getElementById("refresh-data");
    if (!headerActions || !refreshButton || !apiBase.startsWith("https://")) {
      return false;
    }

    ui.button = document.createElement("button");
    ui.button.className = "internal-access-button";
    ui.button.type = "button";
    ui.button.dataset.state = "locked";
    ui.button.innerHTML = `${lockIcon}<span>顯示平均成本</span>`;
    ui.button.addEventListener("click", openDialog);
    headerActions.insertBefore(ui.button, refreshButton);

    ui.layer = document.createElement("div");
    ui.layer.className = "internal-auth-layer";
    ui.layer.id = "internal-auth-layer";
    ui.layer.hidden = true;
    ui.layer.innerHTML = `
      <section class="internal-auth-card" role="dialog" aria-modal="true" aria-labelledby="internal-auth-title">
        <header class="internal-auth-header">
          <div>
            <p class="internal-auth-eyebrow">內部資料</p>
            <h2 class="internal-auth-title" id="internal-auth-title">解鎖平均成本（未稅）</h2>
          </div>
          <button class="internal-auth-close" type="button" aria-label="關閉">×</button>
        </header>
        <div class="internal-auth-body">
          <div data-panel="login">
            <p class="internal-auth-copy">輸入共用密碼後，這個瀏覽器會保持解鎖30天。未解鎖前，成本資料不會傳送到瀏覽器。</p>
            <form class="internal-auth-form">
              <label class="internal-auth-label">
                共用密碼
                <input class="internal-auth-input" name="password" type="password" autocomplete="current-password" required>
              </label>
              <button class="internal-auth-submit" type="submit">解鎖平均成本</button>
              <p class="internal-auth-error" role="alert" aria-live="polite"></p>
            </form>
            <p class="internal-auth-note">密碼存放在 Cloudflare 的加密設定中，不會寫進公開網頁或 GitHub。</p>
          </div>
          <div data-panel="unlocked" hidden>
            <div class="internal-auth-status">
              <strong>平均成本已解鎖</strong>
              <span data-expiry>這個瀏覽器30天內不用重新輸入密碼。</span>
            </div>
            <button class="internal-auth-lock" type="button">立即鎖定這個瀏覽器</button>
          </div>
        </div>
      </section>
    `;
    document.body.appendChild(ui.layer);

    ui.form = ui.layer.querySelector(".internal-auth-form");
    ui.password = ui.layer.querySelector(".internal-auth-input");
    ui.error = ui.layer.querySelector(".internal-auth-error");
    ui.loginPanel = ui.layer.querySelector('[data-panel="login"]');
    ui.unlockedPanel = ui.layer.querySelector('[data-panel="unlocked"]');
    ui.expiry = ui.layer.querySelector("[data-expiry]");

    ui.layer.querySelector(".internal-auth-close").addEventListener("click", closeDialog);
    ui.layer.querySelector(".internal-auth-lock").addEventListener("click", lockNow);
    ui.form.addEventListener("submit", submitPassword);
    ui.layer.addEventListener("click", (event) => {
      if (event.target === ui.layer) closeDialog();
    });
    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape" && !ui.layer.hidden) closeDialog();
    });

    ui.toast = document.createElement("div");
    ui.toast.className = "internal-auth-toast";
    ui.toast.hidden = true;
    document.body.appendChild(ui.toast);
    return true;
  }

  function showToast(message) {
    window.clearTimeout(ui.toastTimer);
    ui.toast.textContent = message;
    ui.toast.hidden = false;
    ui.toastTimer = window.setTimeout(() => {
      ui.toast.hidden = true;
    }, 3600);
  }

  function formatExpiry(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "這個瀏覽器30天內不用重新輸入密碼。";
    return `解鎖有效至 ${new Intl.DateTimeFormat("zh-Hant-TW", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit"
    }).format(date)}`;
  }

  function updateInterface(unlocked, expiresAt = "") {
    state.internalUnlocked = unlocked;
    if (!unlocked) {
      costSalesData = { items: {}, source: {} };
    }
    renderContent();

    ui.button.dataset.state = unlocked ? "unlocked" : "locked";
    ui.button.innerHTML = unlocked
      ? `${unlockedIcon}<span>平均成本已解鎖</span>`
      : `${lockIcon}<span>顯示平均成本</span>`;
    ui.button.title = unlocked ? formatExpiry(expiresAt) : "輸入共用密碼顯示平均成本（未稅）";

    ui.loginPanel.hidden = unlocked;
    ui.unlockedPanel.hidden = !unlocked;
    ui.expiry.textContent = formatExpiry(expiresAt);
  }

  function openDialog() {
    ui.error.textContent = "";
    ui.layer.hidden = false;
    document.body.style.overflow = "hidden";
    if (!state.internalUnlocked) {
      window.setTimeout(() => ui.password.focus(), 30);
    }
  }

  function closeDialog() {
    ui.layer.hidden = true;
    document.body.style.overflow = "";
    ui.password.value = "";
    ui.error.textContent = "";
    ui.button.focus();
  }

  async function readJson(response) {
    let payload = {};
    try {
      payload = await response.json();
    } catch (_) {
      payload = {};
    }
    if (!response.ok) {
      const error = new Error(payload.message || "目前無法完成驗證，請稍後再試。");
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  async function loadInternalData(token, expiresAt = "") {
    const response = await fetch(endpoints.internalData, {
      headers: authorizationHeaders(token),
      cache: "no-store"
    });
    const payload = await readJson(response);
    costSalesData = payload;
    updateInterface(true, expiresAt);
  }

  async function submitPassword(event) {
    event.preventDefault();
    const submitButton = ui.form.querySelector(".internal-auth-submit");
    submitButton.disabled = true;
    submitButton.textContent = "驗證中…";
    ui.error.textContent = "";

    try {
      const response = await fetch(endpoints.login, {
        method: "POST",
        cache: "no-store",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ password: ui.password.value })
      });
      const payload = await readJson(response);
      saveSession(payload);
      await loadInternalData(payload.token, payload.expiresAt);
      closeDialog();
      showToast("平均成本（未稅）已解鎖。");
    } catch (error) {
      clearSession();
      ui.error.textContent = error.message;
      ui.password.select();
    } finally {
      submitButton.disabled = false;
      submitButton.textContent = "解鎖平均成本";
    }
  }

  function lockNow() {
    clearSession();
    updateInterface(false);
    closeDialog();
    showToast("這個瀏覽器已重新鎖定。");
  }

  async function restoreSession() {
    const session = readStoredSession();
    if (!session) {
      updateInterface(false);
      return;
    }

    try {
      const response = await fetch(endpoints.session, {
        headers: authorizationHeaders(session.token),
        cache: "no-store"
      });
      const payload = await readJson(response);
      await loadInternalData(session.token, payload.expiresAt);
    } catch (_) {
      clearSession();
      updateInterface(false);
    }
  }

  function init() {
    if (!createInterface()) return;
    updateInterface(false);
    restoreSession();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
