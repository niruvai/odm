// Adds ODM download buttons on YouTube (like IDM's video panel):
//  • a "⬇ ODM" pill next to YouTube's Like / Share buttons (always visible)
//  • a "Download" button on the top-right of the video player
// Choosing a quality sends the page link (with your sign-in cookies, via the background
// script) to the ODM app, which downloads it with yt-dlp.

(() => {
  if (window.__odmYouTubeLoaded) return; // injected twice (manifest + after an update)
  window.__odmYouTubeLoaded = true;

  // Each copy of this script marks its buttons. After the extension is updated, the new copy
  // replaces the old copy's buttons (whose clicks can no longer reach the extension).
  const INSTANCE = String(Date.now()) + Math.random().toString(36).slice(2);

  function extensionAlive() {
    try {
      return !!(chrome.runtime && chrome.runtime.id);
    } catch (e) {
      return false;
    }
  }

  const QUALITIES = [
    ["best", "Best available"],
    ["1080", "1080p"],
    ["720", "720p"],
    ["480", "480p"],
    ["360", "360p"],
    ["audio", "Audio only (m4a)"],
  ];

  const STYLE = `
    .odm-wrap { position: relative; display: inline-flex; font: 500 14px/1.2 Roboto, -apple-system, BlinkMacSystemFont, sans-serif; }
    .odm-btn { display: inline-flex; align-items: center; gap: 6px; height: 36px; padding: 0 14px; border: 0; border-radius: 18px;
      background: #1a5ae6; color: #fff; cursor: pointer; font: inherit; white-space: nowrap; }
    .odm-btn:hover { background: #2f6cf0; }
    .odm-btn svg { width: 18px; height: 18px; flex: none; }
    #odm-inline { margin-left: 8px; align-self: center; }
    #odm-player { position: absolute; top: 12px; right: 12px; z-index: 1000; }
    #odm-player .odm-btn { height: 32px; padding: 0 12px; font-size: 13px; opacity: .55; box-shadow: 0 2px 8px rgba(0,0,0,.35); transition: opacity .15s; }
    .html5-video-player:hover #odm-player .odm-btn, #odm-player.open .odm-btn { opacity: 1; }
    .ytp-autohide:not(:hover) #odm-player:not(.open) { opacity: 0; transition: opacity .3s; }
    .odm-menu { display: none; position: absolute; right: 0; top: calc(100% + 6px); min-width: 180px; padding: 6px 0; z-index: 2300;
      background: rgba(28, 28, 30, 0.98); border-radius: 10px; box-shadow: 0 6px 24px rgba(0,0,0,.45); }
    .odm-wrap.open .odm-menu { display: block; }
    .odm-menu button { display: block; width: 100%; padding: 9px 16px; border: 0; background: none; color: #fff;
      text-align: left; cursor: pointer; font: 400 14px Roboto, -apple-system, sans-serif; }
    .odm-menu button:hover { background: rgba(255,255,255,.12); }
    .odm-head { padding: 4px 16px 6px; color: #9a9a9e; font-size: 11px; text-transform: uppercase; letter-spacing: .05em; }
    #odm-toast { position: fixed; bottom: 28px; left: 50%; transform: translateX(-50%); z-index: 2147483000;
      padding: 10px 16px; border-radius: 10px; background: rgba(28,28,30,.95); color: #fff;
      font: 500 14px Roboto, -apple-system, sans-serif; box-shadow: 0 6px 24px rgba(0,0,0,.4); }
  `;

  // Built with DOM calls: YouTube blocks innerHTML via Trusted Types.
  function icon() {
    const NS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(NS, "svg");
    svg.setAttribute("viewBox", "0 0 24 24");
    svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor");
    svg.setAttribute("stroke-width", "2.4");
    svg.setAttribute("stroke-linecap", "round");
    svg.setAttribute("stroke-linejoin", "round");
    for (const d of ["M12 4v11", "m6 10 6 6 6-6", "M5 20h14"]) {
      const p = document.createElementNS(NS, "path");
      p.setAttribute("d", d);
      svg.appendChild(p);
    }
    return svg;
  }

  function toast(text) {
    document.getElementById("odm-toast")?.remove();
    const t = document.createElement("div");
    t.id = "odm-toast";
    t.textContent = text;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 3500);
  }

  function isVideoPage() {
    return location.pathname === "/watch" || location.pathname.startsWith("/shorts/");
  }

  function send(quality) {
    try {
      chrome.runtime.sendMessage({ type: "video", url: location.href, quality }, (res) => {
        if (chrome.runtime.lastError || !res || !res.ok) {
          toast("ODM app is not running — open ODM and try again.");
        } else {
          toast("Sent to ODM ✓");
        }
      });
    } catch (e) {
      // The extension was reloaded; this old copy of the script can't talk to it any more.
      toast("ODM extension was updated — refresh this page (⌘R) and try again.");
    }
  }

  function closeMenus() {
    document.querySelectorAll(".odm-wrap.open").forEach((w) => w.classList.remove("open"));
  }

  function buildButton(id, labelText) {
    const wrap = document.createElement("div");
    wrap.id = id;
    wrap.className = "odm-wrap";
    wrap.dataset.odmInstance = INSTANCE;

    const btn = document.createElement("button");
    btn.className = "odm-btn";
    btn.title = "Download this video with ODM";
    const label = document.createElement("span");
    label.textContent = labelText;
    btn.append(icon(), label);

    const menu = document.createElement("div");
    menu.className = "odm-menu";
    const head = document.createElement("div");
    head.className = "odm-head";
    head.textContent = "Download with ODM";
    menu.appendChild(head);
    for (const [q, text] of QUALITIES) {
      const b = document.createElement("button");
      b.textContent = text;
      b.addEventListener("click", (e) => {
        e.stopPropagation();
        closeMenus();
        send(q);
      });
      menu.appendChild(b);
    }

    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      e.preventDefault();
      const open = !wrap.classList.contains("open");
      closeMenus();
      if (open) wrap.classList.add("open");
    });
    // Keep clicks on our UI from pausing / playing the video
    for (const ev of ["mousedown", "mouseup", "dblclick", "pointerdown", "pointerup"]) {
      wrap.addEventListener(ev, (e) => e.stopPropagation());
    }

    wrap.append(btn, menu);
    return wrap;
  }

  function injectPlayerButton() {
    const player = document.querySelector("#movie_player");
    const existing = document.getElementById("odm-player");
    if (!player) return;
    if (existing && player.contains(existing) && existing.dataset.odmInstance === INSTANCE) return;
    existing?.remove();
    player.appendChild(buildButton("odm-player", "Download"));
  }

  function injectInlineButton() {
    // The row with Like / Share / Download under the video title
    const row =
      document.querySelector("ytd-watch-metadata #top-level-buttons-computed") ||
      document.querySelector("ytd-watch-metadata #actions-inner") ||
      document.querySelector("ytd-watch-metadata #actions") ||
      document.querySelector("#above-the-fold #top-row");
    const existing = document.getElementById("odm-inline");
    if (!row) return;
    if (existing && row.contains(existing) && existing.dataset.odmInstance === INSTANCE) return;
    existing?.remove();
    row.appendChild(buildButton("odm-inline", "ODM"));
  }

  let timer = null;

  function inject() {
    if (!extensionAlive()) {
      // This copy was left behind by an extension update; stop and let the new copy take over.
      if (timer) clearInterval(timer);
      return;
    }
    if (!isVideoPage()) {
      document.getElementById("odm-player")?.remove();
      document.getElementById("odm-inline")?.remove();
      return;
    }
    injectPlayerButton();
    if (location.pathname === "/watch") injectInlineButton();
  }

  const style = document.createElement("style");
  style.textContent = STYLE;
  (document.head || document.documentElement).appendChild(style);

  document.addEventListener("click", closeMenus);
  // YouTube is a single-page app: re-check after navigation and periodically.
  window.addEventListener("yt-navigate-finish", () => setTimeout(inject, 300));
  timer = setInterval(inject, 1500);
  inject();
})();
