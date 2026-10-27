const dot = document.getElementById("dot");
const statusText = document.getElementById("statusText");
const enabled = document.getElementById("enabled");

chrome.storage.local.get({ enabled: true }).then((s) => {
  enabled.checked = s.enabled;
});
enabled.addEventListener("change", () => {
  chrome.storage.local.set({ enabled: enabled.checked });
});

fetch("http://127.0.0.1:9614/ping", { signal: AbortSignal.timeout(1000) })
  .then((r) => r.ok)
  .catch(() => false)
  .then((ok) => {
    dot.className = "dot " + (ok ? "on" : "off");
    statusText.textContent = ok ? "Connected to ODM" : "ODM app is not running";
  });

// "Download video" for the current tab (YouTube, Facebook, Vimeo… anything yt-dlp supports)
const grab = document.getElementById("grab");
const grabStatus = document.getElementById("grabStatus");
const quality = document.getElementById("quality");

chrome.storage.local.get({ quality: "1080" }).then((s) => (quality.value = s.quality));
quality.addEventListener("change", () => chrome.storage.local.set({ quality: quality.value }));

chrome.tabs.query({ active: true, currentWindow: true }).then(([tab]) => {
  if (!tab || !/^https?:/i.test(tab.url || "")) {
    grab.disabled = true;
    grabStatus.textContent = "Open a video page first.";
  }
});

grab.addEventListener("click", async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) return;
  grab.disabled = true;
  grabStatus.textContent = "Sending…";
  chrome.runtime.sendMessage({ type: "video", url: tab.url, quality: quality.value }, (res) => {
    grab.disabled = false;
    grabStatus.textContent = res && res.ok ? "Sent to ODM ✓" : "ODM app is not running.";
  });
});
