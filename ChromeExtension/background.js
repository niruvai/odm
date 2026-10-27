// ODM browser integration.
// When the ODM app is running, Chrome downloads are cancelled and handed to the app
// (with cookies + referrer so links that need a login still work).
// When the app is closed, Chrome downloads normally.

const API = "http://127.0.0.1:9614";
const bypass = new Set(); // URLs we deliberately let Chrome download (fallback)

async function appAlive() {
  try {
    const r = await fetch(API + "/ping", { signal: AbortSignal.timeout(800) });
    return r.ok;
  } catch (e) {
    return false;
  }
}

async function settings() {
  const s = await chrome.storage.local.get({ enabled: true });
  return s;
}

async function cookieHeader(url) {
  try {
    const cookies = await chrome.cookies.getAll({ url });
    return cookies.map((c) => `${c.name}=${c.value}`).join("; ");
  } catch (e) {
    return "";
  }
}

async function sendToApp(url, filename, referrer) {
  const body = {
    url,
    filename: filename || null,
    referrer: referrer || null,
    cookies: await cookieHeader(url),
    userAgent: navigator.userAgent,
  };
  try {
    const r = await fetch(API + "/add", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return r.ok;
  } catch (e) {
    return false;
  }
}

function baseName(path) {
  if (!path) return "";
  const parts = path.split(/[\\/]/);
  return parts[parts.length - 1];
}

function baseDomain(host) {
  host = host.toLowerCase();
  if (host === "youtu.be" || host.endsWith(".youtu.be")) return "youtube.com";
  return host.split(".").slice(-2).join(".");
}

// The site's cookies (e.g. your YouTube sign-in), so yt-dlp passes "confirm you're not a bot" checks.
// They are sent only to the ODM app on this Mac (127.0.0.1).
async function siteCookies(url) {
  try {
    const domain = baseDomain(new URL(url).hostname);
    const list = await chrome.cookies.getAll({ domain });
    return list.map((c) => ({
      domain: c.domain,
      name: c.name,
      value: c.value,
      path: c.path,
      secure: c.secure,
      httpOnly: c.httpOnly,
      hostOnly: c.hostOnly,
      expirationDate: c.expirationDate ? Math.floor(c.expirationDate) : 0,
    }));
  } catch (e) {
    return [];
  }
}

async function sendVideo(url, quality) {
  try {
    const r = await fetch(API + "/video", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ url, quality: quality || null, cookies: await siteCookies(url) }),
    });
    return r.ok;
  } catch (e) {
    return false;
  }
}

// Messages from the YouTube button and the popup
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg && msg.type === "video" && /^https?:/i.test(msg.url || "")) {
    sendVideo(msg.url, msg.quality).then((ok) => sendResponse({ ok }));
    return true; // keep the channel open for the async reply
  }
  return false;
});

// Capture normal browser downloads
chrome.downloads.onCreated.addListener(async (item) => {
  const url = item.finalUrl || item.url;
  if (!/^https?:/i.test(url)) return; // blob:, data:, file: stay in Chrome
  if (bypass.has(url)) {
    bypass.delete(url);
    return;
  }
  const { enabled } = await settings();
  if (!enabled) return;
  if (!(await appAlive())) return;

  try {
    await chrome.downloads.cancel(item.id);
    await chrome.downloads.erase({ id: item.id });
  } catch (e) {
    /* already finished or gone */
  }

  const ok = await sendToApp(url, baseName(item.filename), item.referrer);
  if (!ok) {
    // App refused or vanished: give the download back to Chrome.
    bypass.add(url);
    chrome.downloads.download({ url });
  }
});

// After install / update, add the YouTube buttons to tabs that are already open
// (otherwise they only appear after the page is refreshed).
chrome.runtime.onInstalled.addListener(async () => {
  try {
    const tabs = await chrome.tabs.query({ url: ["https://www.youtube.com/*", "https://m.youtube.com/*"] });
    for (const tab of tabs) {
      chrome.scripting.executeScript({ target: { tabId: tab.id }, files: ["youtube.js"] }).catch(() => {});
    }
  } catch (e) {
    /* ignore */
  }
});

// Right-click menu: "Download with ODM"
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "odm-link",
      title: "Download with ODM",
      contexts: ["link", "video", "audio", "image"],
    });
    chrome.contextMenus.create({
      id: "odm-video",
      title: "Download video with ODM",
      contexts: ["page", "link", "video"],
    });
  });
});

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let ok;
  if (info.menuItemId === "odm-video") {
    const url = info.linkUrl || info.pageUrl || (tab && tab.url);
    if (!url || !/^https?:/i.test(url)) return;
    ok = await sendVideo(url, null);
  } else {
    const url = info.linkUrl || info.srcUrl;
    if (!url || !/^https?:/i.test(url)) return;
    ok = await sendToApp(url, null, info.pageUrl || (tab && tab.url));
  }
  if (!ok) {
    chrome.notifications?.create?.({
      type: "basic",
      iconUrl: "icons/icon128.png",
      title: "ODM is not running",
      message: "Open the ODM app and try again.",
    });
  }
});
