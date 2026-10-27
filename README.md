# ODM — Open Source Download Manager for macOS

**[English](#english) · [বাংলা](#bangla)**

**ODM** is a free, open-source download manager for macOS, in the spirit of Internet Download Manager (IDM) for Windows.
**ODM** হলো macOS-এর জন্য একটা ফ্রি, ওপেন-সোর্স ডাউনলোড ম্যানেজার, Windows-এর IDM-এর মতো।

Made by **[Nirob Islam](https://www.nirobislam.com/en/)**

---

## English

### Features

- **Multi-connection downloads**: each file downloads over 8 parallel connections (adjustable from 1 to 32)
- **Dynamic segmentation** (IDM's core trick): when a connection finishes early, it takes over half of the largest remaining part, so every connection stays busy until the end
- **Pause / Resume**: continues where it stopped, even after a network drop or an app restart
- **Automatic retries**: a dropped connection retries each part up to 8 times
- **Download queue**: choose how many downloads run at the same time (default 3)
- **Category folders**: Video, Music, Compressed, Programs, Documents, Images
- **Chrome / Edge / Brave extension**: browser downloads go to ODM automatically, with cookies and referrer, so sites that need a login still work
- **Video downloads**: a **⬇ ODM** button under YouTube videos and a **Download** button on the player, with a quality menu (Best, 1080p, 720p, 480p, 360p, audio only); a **Download video** button in the extension popup for other sites (Facebook, Vimeo and more)
- **Automatic updates**: when a new version is out, ODM shows **Update Now** inside the app
- Menu-bar icon, active-download count on the Dock icon, and your Mac doesn't sleep while downloading
- Drag a link onto the window to start a download

### Requirements

- macOS 13 (Ventura) or newer
- Apple Silicon or Intel Mac

### Install

1. Download **ODM.zip** from the [latest release](https://github.com/niruvai/odm/releases/latest)
2. Unzip it and drag **ODM.app** into your **Applications** folder
3. Open ODM. The first time, macOS may say it can't verify the developer:
   - Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, or
   - Run this once in Terminal: `xattr -dr com.apple.quarantine /Applications/ODM.app`

#### Or build from source

You need Apple's Command Line Tools (`xcode-select --install`); full Xcode is not required.

```bash
git clone https://github.com/niruvai/odm.git
cd odm
./build.sh --install
```

This builds ODM and installs it to `/Applications/ODM.app`. Building from a folder on an external drive (exFAT) also works.

### Install the Chrome extension

1. Open ODM → **Settings (⌘,) → Browser → Show Extension Folder**
2. In Chrome, open `chrome://extensions` and turn on **Developer mode** (top right)
3. Click **Load unpacked**, press **⌘⇧G** and enter: `~/Library/Application Support/ODM/ChromeExtension`

After ODM updates, click the **↻ Reload** button for ODM in `chrome://extensions`.

Tip: in Chrome **Settings → Downloads**, turn off **“Ask where to save each file before downloading”**.

### How to use

| Task | How |
|---|---|
| New download | **⌘N**: a copied link is filled in automatically; paste several links, one per line |
| From Chrome | Download as usual; ODM takes over automatically |
| YouTube video | Click **⬇ ODM** under the video (or **Download** on the player) and pick a quality |
| Other video sites | Click the ODM extension icon → **Download video**, or right-click the page → **Download video with ODM** |
| Pause / Resume | Toolbar buttons or right-click |
| Pause all / Resume all | **⇧⌘P** / **⇧⌘R** |
| Open a file | Double-click it in the list |
| Settings | **⌘,** |

Files are saved to `~/Downloads/ODM/<category>/`.

### Updates

ODM checks for a new version when it starts and every 6 hours. When one is available, a blue banner appears at the top of the window: click **Update Now**. ODM downloads the new version, replaces itself and restarts, and unfinished downloads continue where they left off. To check yourself: menu **ODM → Check for Updates…**

Every push to the `main` branch is built automatically by GitHub Actions and published as a release (`build-<number>`); that is where updates come from.

### Troubleshooting

- **“Sign in to confirm you're not a bot”** or **HTTP 403** on a video: turn on **Settings → Video → Use my browser sign-in**, then send the video again with the ODM button on the page (the extension passes your sign-in to ODM)
- **No ODM button on YouTube**: refresh the page (**⌘R**)
- **Extension says ODM is not running**: open the ODM app
- The first video download takes a minute longer while ODM prepares its video tools

> Only download videos you have the right to save — your own uploads, Creative Commons content, or with the owner's permission. Respect each site's terms of service.

### Limitations

- If a server doesn't support byte ranges, the file downloads over one connection and can't be resumed
- Some downloads that start from a POST form can't be handed to ODM
- Private or members-only videos can't be downloaded
- ODM is not notarized by Apple, so macOS asks for confirmation the first time you open it

---

<a id="bangla"></a>

## বাংলা

### কী কী আছে

- **মাল্টি-কানেকশন ডাউনলোড**: প্রতিটা ফাইল একসাথে ৮টা আলাদা কানেকশনে নামে (১ থেকে ৩২ পর্যন্ত বদলানো যায়)
- **ডাইনামিক সেগমেন্টেশন** (IDM-এর আসল কৌশল): কোনো কানেকশন আগে শেষ হলে সে সবচেয়ে বড় বাকি অংশের অর্ধেক নিজে নিয়ে নেয়, তাই শেষ পর্যন্ত সব কানেকশন কাজে থাকে
- **Pause / Resume**: নেট কেটে গেলে বা অ্যাপ বন্ধ করলেও যেখানে থেমেছিল সেখান থেকে আবার শুরু হয়
- **নিজে থেকে আবার চেষ্টা**: কানেকশন ড্রপ হলে প্রতিটা অংশ ৮ বার পর্যন্ত আবার চেষ্টা করে
- **ডাউনলোড কিউ**: একসাথে কয়টা ডাউনলোড চলবে ঠিক করা যায় (ডিফল্ট ৩)
- **ধরন অনুযায়ী ফোল্ডার**: Video, Music, Compressed, Programs, Documents, Images
- **Chrome / Edge / Brave এক্সটেনশন**: ব্রাউজারের ডাউনলোড নিজে থেকেই ODM-এ চলে যায়, কুকি আর রেফারার সহ, তাই লগইন লাগে এমন সাইটেও কাজ করে
- **ভিডিও ডাউনলোড**: YouTube ভিডিওর নিচে **⬇ ODM** বাটন আর প্লেয়ারের উপর **Download** বাটন, কোয়ালিটি মেনু সহ (Best, 1080p, 720p, 480p, 360p, শুধু অডিও); অন্য সাইটের (Facebook, Vimeo ইত্যাদি) জন্য এক্সটেনশনের পপআপে **Download video** বাটন
- **অটো-আপডেট**: নতুন ভার্সন এলে অ্যাপের ভেতরেই **Update Now** দেখায়
- মেনু বারে আইকন, Dock-এ চলমান ডাউনলোডের সংখ্যা, আর ডাউনলোডের সময় ম্যাক ঘুমিয়ে পড়ে না
- উইন্ডোতে লিংক টেনে এনে ছাড়লেই ডাউনলোড শুরু হয়

### যা লাগবে

- macOS 13 (Ventura) বা নতুন
- Apple Silicon বা Intel ম্যাক

### ইনস্টল

1. [সর্বশেষ রিলিজ](https://github.com/niruvai/odm/releases/latest) থেকে **ODM.zip** নামান
2. জিপ খুলে **ODM.app** টেনে **Applications** ফোল্ডারে রাখুন
3. ODM খুলুন। প্রথমবার macOS বলতে পারে ডেভেলপার যাচাই করা যায়নি। তখন:
   - **System Settings → Privacy & Security**-এ গিয়ে নিচে **Open Anyway** চাপুন, অথবা
   - Terminal-এ একবার চালান: `xattr -dr com.apple.quarantine /Applications/ODM.app`

#### অথবা সোর্স থেকে বিল্ড করুন

Apple-এর Command Line Tools লাগবে (`xcode-select --install`), পুরো Xcode লাগবে না।

```bash
git clone https://github.com/niruvai/odm.git
cd odm
./build.sh --install
```

এটা ODM বিল্ড করে `/Applications/ODM.app`-এ ইনস্টল করে দেয়। এক্সটার্নাল ড্রাইভে (exFAT) রাখা ফোল্ডার থেকেও বিল্ড করা যায়।

### Chrome এক্সটেনশন বসানো

1. ODM খুলে **Settings (⌘,) → Browser → Show Extension Folder** চাপুন
2. Chrome-এ `chrome://extensions` খুলুন, ডানদিকে উপরে **Developer mode** চালু করুন
3. **Load unpacked** চাপুন, **⌘⇧G** দিয়ে এই পাথ দিন: `~/Library/Application Support/ODM/ChromeExtension`

ODM আপডেট হওয়ার পর `chrome://extensions`-এ ODM-এর **↻ Reload** বাটন চাপুন।

টিপ: Chrome-এর **Settings → Downloads**-এ **“Ask where to save each file before downloading”** বন্ধ রাখুন।

### ব্যবহার

| কাজ | কীভাবে |
|---|---|
| নতুন ডাউনলোড | **⌘N**: কপি করা লিংক নিজে বসে যায়; একসাথে অনেক লিংক দিতে চাইলে এক লাইনে একটা করে |
| Chrome থেকে | স্বাভাবিকভাবে ডাউনলোড করুন, ODM নিজেই ধরে নেবে |
| YouTube ভিডিও | ভিডিওর নিচে **⬇ ODM** (অথবা প্লেয়ারের উপর **Download**) চেপে কোয়ালিটি বেছে নিন |
| অন্য ভিডিও সাইট | এক্সটেনশনের আইকন → **Download video**, অথবা পেজে রাইট-ক্লিক → **Download video with ODM** |
| থামানো / চালু | টুলবারের বাটন অথবা রাইট-ক্লিক |
| সব থামানো / সব চালু | **⇧⌘P** / **⇧⌘R** |
| ফাইল খোলা | তালিকায় ডাবল-ক্লিক |
| সেটিংস | **⌘,** |

ফাইল সেভ হয় `~/Downloads/ODM/<ধরন>/`-এ।

### আপডেট

ODM চালু হওয়ার সময় আর প্রতি ৬ ঘণ্টায় নতুন ভার্সন খোঁজে। নতুন ভার্সন পেলে উইন্ডোর উপরে নীল ব্যানার আসে, সেখানে **Update Now** চাপুন। ODM নতুন ভার্সন নামিয়ে নিজেকে বদলে আবার চালু হয়, আর চলমান ডাউনলোড যেখানে ছিল সেখান থেকে চলতে থাকে। নিজে চেক করতে চাইলে: মেনু **ODM → Check for Updates…**

`main` ব্রাঞ্চে প্রতিটা পুশের পর GitHub Actions নিজে অ্যাপ বিল্ড করে একটা রিলিজ (`build-<নম্বর>`) বানায়। আপডেট সেখান থেকেই আসে।

### সমস্যা হলে

- ভিডিওতে **“Sign in to confirm you're not a bot”** বা **HTTP 403** এলে: **Settings → Video → Use my browser sign-in** চালু করুন, তারপর পেজের ODM বাটন দিয়ে ভিডিওটা আবার পাঠান (এক্সটেনশন আপনার লগইন ODM-কে দিয়ে দেয়)
- **YouTube-এ ODM বাটন দেখা যাচ্ছে না**: পেজ রিফ্রেশ করুন (**⌘R**)
- **এক্সটেনশন বলছে ODM চলছে না**: ODM অ্যাপটা খুলুন
- প্রথম ভিডিও ডাউনলোডে এক মিনিট বেশি লাগে, কারণ ODM তখন ভিডিওর টুলগুলো প্রস্তুত করে

> যে ভিডিও ডাউনলোডের অধিকার আপনার আছে শুধু সেগুলোই নামান: নিজের আপলোড, Creative Commons, বা মালিকের অনুমতি নিয়ে। প্রতিটা সাইটের নিয়ম মেনে চলুন।

### সীমাবদ্ধতা

- যে সার্ভার byte range সমর্থন করে না, সেখানে একটাই কানেকশন চলে আর Resume হয় না
- POST ফর্ম দিয়ে শুরু হওয়া কিছু ডাউনলোড ODM-এ পাঠানো যায় না
- প্রাইভেট বা মেম্বারশিপ ভিডিও নামানো যায় না
- ODM Apple-এর notarization করা নয়, তাই প্রথমবার খোলার সময় macOS নিশ্চিত হতে চায়

---

## Project layout / প্রজেক্টের গঠন

```
Sources/ODM/
  DownloadEngine.swift   multi-connection engine, dynamic segmentation, retries
  Prober.swift           size, file name and range support detection
  YtDlp.swift            video tools setup (yt-dlp, Deno, ffmpeg) and the video download runner
  DownloadManager.swift  list, queue, persistence, notifications
  Updater.swift          in-app updates from GitHub Releases
  LocalServer.swift      127.0.0.1:9614 bridge for the browser extension
  ContentView.swift      main window
  OtherViews.swift       add dialog, detail panel, settings, menu bar
  Author.swift           About window and credits
  UIState.swift          window/dialog state (no @State, so it builds without Xcode)
ChromeExtension/         browser extension (Manifest V3)
build.sh                 builds, signs and installs ODM.app
.github/workflows/       builds and publishes a release on every push
```

Video downloads use [yt-dlp](https://github.com/yt-dlp/yt-dlp), [Deno](https://deno.com) and [FFmpeg](https://ffmpeg.org), which ODM downloads on first use. Each has its own license.
ভিডিও ডাউনলোডে [yt-dlp](https://github.com/yt-dlp/yt-dlp), [Deno](https://deno.com) আর [FFmpeg](https://ffmpeg.org) ব্যবহার হয়, ODM প্রথমবার এগুলো নিজে নামিয়ে নেয়। প্রত্যেকটার নিজস্ব লাইসেন্স আছে।

## Author / নির্মাতা

**ODM is made by Nirob Islam.**
**ODM তৈরি করেছেন নিরব ইসলাম।**

- Website: https://www.nirobislam.com/en/
- Facebook: https://www.facebook.com/mdnurunnabiislamniroob
- Instagram: https://www.instagram.com/niru_bhai_0/

If you share, fork or build on ODM, please keep the author's name and the license notice.
ODM শেয়ার, fork বা এর উপর ভিত্তি করে কিছু বানালে নির্মাতার নাম আর লাইসেন্সের লেখা রেখে দিন।

## License / লাইসেন্স

MIT — © 2026 Nirob Islam, see [LICENSE](LICENSE). The copyright notice and author credit must be kept in copies and modified versions.
MIT লাইসেন্স — © ২০২৬ নিরব ইসলাম, বিস্তারিত [LICENSE](LICENSE)-এ। কপি বা পরিবর্তিত সংস্করণে copyright notice আর নির্মাতার নাম রাখা বাধ্যতামূলক।
