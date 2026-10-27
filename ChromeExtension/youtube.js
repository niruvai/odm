// Adds a "Download" button with a quality menu on top of YouTube videos (like IDM's video panel).
// Clicking a quality sends the page link to the ODM app, which downloads it with yt-dlp.

(() => {
  const QUALITIES = [
    ["best", "Best available"],
    ["1080", "1080p"],
    ["720", "720p"],
    ["480", "480p"],
    ["360", "360p"],
    ["audio", "Audio only (m4a)"],
  ];

  const STYLE = `
    #odm-wrap { position: absolute; top: 12px; right: 12px; z-index: 60; font: 500 13px/1.2 -apple-system, BlinkMacSystemFont, Roboto, sans-serif; }
    #odm-btn { display: flex; align-items: center; gap: 6px; padding: 7px 12px; border: 0; border-radius: 18px;
      background: rgba(20, 90, 230, 0.92); color: #fff; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,.35);
      opacity: 0; transition: opacity .15s; font: inherit; }
    .html5-video-player:hover #odm-btn, #odm-wrap.open #odm-btn { opacity: 1; }
    #odm-btn svg { width: 15px; height: 15px; }
    #odm-menu { display: none; position: absolute; right: 0; top: 40px; min-width: 170px; padding: 6px 0;
      background: rgba(28, 28, 30, 0.97); border-radius: 10px; box-shadow: 0 6px 24px rgba(0,0,0,.45); }
    #odm-wrap.open #odm-menu { display: block; }
    #odm-menu button { display: block; width: 100%; padding: 8px 14px; border: 0; background: none; color: #fff;
      text-align: left; cursor: pointer; font: inherit; }
    #odm-menu button:hover { background: rgba(255,255,255,.12); }
    #odm-menu .odm-head { padding: 4px 14px 6px; color: #9a9a9e; font-size: 11px; text-transform: uppercase; letter-spacing: .04em; }
    #odm-toast { position: fixed; bottom: 28px; left: 50%; transform: translateX(-50%); z-index: 99999;
      padding: 10px 16px; border-radius: 10px; background: rgba(28,28,30,.95); color: #fff;
      font: 500 13px -apple-system, BlinkMacSystemFont, Roboto, sans-serif; box-shadow: 0 6px 24px rgba(0,0,0,.4); }
  `;

  // Built with DOM calls (YouTube blocks innerHTML via Trusted Types).
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
    chrome.runtime.sendMessage({ type: "video", url: location.href, quality }, (res) => {
      if (chrome.runtime.lastError || !res || !res.ok) {
        toast("ODM app is not running — open it and try again.");
      } else {
        toast("Sent to ODM ✓");
      }
    });
  }

  function build() {
    const wrap = document.createElement("div");
    wrap.id = "odm-wrap";

    const btn = document.createElement("button");
    btn.id = "odm-btn";
    const label = document.createElement("span");
    label.textContent = "Download";
    btn.append(icon(), label);
    btn.title = "Download this video with ODM";

    const menu = document.createElement("div");
    menu.id = "odm-menu";
    const head = document.createElement("div");
    head.className = "odm-head";
    head.textContent = "ODM";
    menu.appendChild(head);
    for (const [id, label] of QUALITIES) {
      const b = document.createElement("button");
      b.textContent = label;
      b.addEventListener("click", (e) => {
        e.stopPropagation();
        wrap.classList.remove("open");
        send(id);
      });
      menu.appendChild(b);
    }

    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      wrap.classList.toggle("open");
    });
    // Don't let clicks on our UI pause/play the video
    for (const ev of ["mousedown", "mouseup", "dblclick"]) {
      wrap.addEventListener(ev, (e) => e.stopPropagation());
    }
    document.addEventListener("click", () => wrap.classList.remove("open"));

    wrap.append(btn, menu);
    return wrap;
  }

  function inject() {
    const player = document.querySelector("#movie_player");
    const existing = document.getElementById("odm-wrap");
    if (!isVideoPage() || !player) {
      if (existing && !isVideoPage()) existing.remove();
      return;
    }
    if (existing && player.contains(existing)) return;
    existing?.remove();
    player.appendChild(build());
  }

  const style = document.createElement("style");
  style.textContent = STYLE;
  document.documentElement.appendChild(style);

  // YouTube is a single-page app: re-check after navigation and periodically.
  window.addEventListener("yt-navigate-finish", inject);
  setInterval(inject, 1500);
  inject();
})();
