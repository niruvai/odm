# ODM — Open Source Download Manager for macOS

**ODM** is a free, open-source download manager for macOS in the spirit of Internet Download Manager (IDM) for Windows.
Built with SwiftUI, no Xcode required — Apple's Command Line Tools are enough.

- **Multi-connection downloads** (1–32 connections per file) with IDM-style dynamic segmentation
- **Pause / resume**, survives network drops and app restarts
- **Download queue**, category folders, menu-bar icon, completion notifications
- **Chrome / Edge / Brave extension** that hands browser downloads to the app (with cookies and referrer)
- **Web video downloads via [yt-dlp](https://github.com/yt-dlp/yt-dlp)** — a Download button on YouTube videos, plus a “Download video” button for any page yt-dlp supports

> Only download videos you have the right to save — your own uploads, Creative Commons content, or with the owner's permission. Respect each site's terms of service.

---

## বাংলায়

### কী কী আছে

- **মাল্টি-কানেকশন ডাউনলোড**: একটা ফাইল একসাথে ৮টা (১–৩২ পর্যন্ত সেট করা যায়) আলাদা কানেকশনে নামে
- **ডাইনামিক সেগমেন্টেশন** (IDM-এর আসল কৌশল): কোনো কানেকশন আগে শেষ হলে সে সবচেয়ে বড় বাকি অংশের অর্ধেক নিজে নিয়ে নেয়
- **Pause / Resume**: নেট কেটে গেলে বা অ্যাপ বন্ধ করলেও যেখানে থেমেছিল সেখান থেকে শুরু
- **নিজে থেকে আবার চেষ্টা**: কানেকশন ড্রপ হলে প্রতিটা অংশ ৮ বার পর্যন্ত আবার চেষ্টা করে
- **ডাউনলোড কিউ**: একসাথে কয়টা ডাউনলোড চলবে ঠিক করা যায় (ডিফল্ট ৩)
- **ধরন অনুযায়ী ফোল্ডার**: Video, Music, Compressed, Programs, Documents, Images
- **Chrome / Edge / Brave এক্সটেনশন**: ব্রাউজারের ডাউনলোড নিজে থেকেই অ্যাপে চলে যায়, কুকি আর রেফারার সহ
- **ভিডিও ডাউনলোড (yt-dlp)**: YouTube ভিডিওর উপর **Download** বাটন আর কোয়ালিটি মেনু; এক্সটেনশনের পপআপ থেকে যেকোনো ভিডিও পেজ (Facebook, Vimeo ইত্যাদি)
- মেনু বারে আইকন, Dock-এ চলমান ডাউনলোডের সংখ্যা, ডাউনলোডের সময় ম্যাক ঘুমায় না
- উইন্ডোতে লিংক ড্র্যাগ করে ছাড়লেই ডাউনলোড শুরু

### যা লাগবে

- macOS 13 (Ventura) বা নতুন
- Apple Command Line Tools (পুরো Xcode লাগবে না)

```bash
xcode-select --install
```

### বিল্ড ও ইনস্টল

```bash
git clone https://github.com/niruvai/odm.git
cd odm
./build.sh --install
```

এটা কম্পাইল করে `/Applications/ODM.app` বানাবে এবং চালু করবে।
এক্সটার্নাল ড্রাইভে (exFAT) রাখা ফোল্ডার থেকেও বিল্ড করা যায়। অ্যাপটা ভেতরের ডিস্কে সাইন করা হয়।

### Chrome এক্সটেনশন বসানো

1. ODM খুলে **Settings (⌘,) → Browser → Show Extension Folder** চাপুন
2. Chrome-এ যান `chrome://extensions` → ডানদিকে উপরে **Developer mode** চালু করুন
3. **Load unpacked** চেপে, ⌘⇧G দিয়ে এই পাথ দিন: `~/Library/Application Support/ODM/ChromeExtension`

এক্সটেনশন আপডেট হলে আবার **Show Extension Folder** চাপুন, তারপর `chrome://extensions`-এ ODM-এর ↻ (Reload) বাটন চাপুন।

টিপ: Chrome Settings → Downloads → **“Ask where to save each file”** বন্ধ রাখুন।

### ভিডিও ডাউনলোড

- **YouTube**: ভিডিওর উপর মাউস রাখলে ডানদিকে উপরে নীল **Download** বাটন আসবে → কোয়ালিটি বেছে নিন
- **অন্য সাইট**: এক্সটেনশনের আইকনে চাপুন → **Download video**, অথবা পেজে রাইট-ক্লিক → **Download video with ODM**
- অ্যাপে ⌘N দিয়ে YouTube/Facebook/Vimeo লিংক দিলেও নিজে থেকে ভিডিও হিসেবে নামবে

প্রথম ভিডিওর সময় ODM নিজে yt-dlp ডাউনলোড করে নেয় (`~/Library/Application Support/ODM/bin`)। Settings → Video থেকে আপডেট করা যায়।

**HD ভিডিওর জন্য ffmpeg লাগবে।** YouTube-এ 720p-এর বেশি ভিডিও আর অডিও আলাদা থাকে, ffmpeg সেগুলো জোড়া লাগায়। না থাকলে শুধু কম কোয়ালিটির (প্রায় 360p) ফাইল পাওয়া যাবে। [Homebrew](https://brew.sh) থাকলে:

```bash
brew install ffmpeg
```

তারপর ODM আবার চালু করুন।

> যে ভিডিও ডাউনলোডের অধিকার আপনার আছে শুধু সেগুলোই নামান: নিজের আপলোড, Creative Commons, বা মালিকের অনুমতি নিয়ে।

### ব্যবহার

| কাজ | কীভাবে |
|---|---|
| নতুন ডাউনলোড | ⌘N (কপি করা লিংক নিজে বসে যায়), একসাথে অনেক লিংক এক লাইনে একটা করে |
| থামানো / চালু | টুলবারের Pause / Resume, অথবা রাইট-ক্লিক |
| সব থামানো / সব চালু | ⇧⌘P / ⇧⌘R |
| ফাইল খোলা | তালিকায় ডাবল-ক্লিক |
| সেটিংস | ⌘, |

ফাইল সেভ হয় `~/Downloads/ODM/<ধরন>/` এ।

### সীমাবদ্ধতা

- যে সার্ভার “Range” রিকোয়েস্ট সমর্থন করে না, সেখানে একটাই কানেকশন চলে আর Resume হয় না
- POST ফর্ম দিয়ে শুরু হওয়া কিছু ডাউনলোড অ্যাপে পাঠানো যায় না
- লগইন লাগে এমন ভিডিও (প্রাইভেট, মেম্বারশিপ) yt-dlp দিয়ে নামবে না
- অ্যাপটি ad-hoc সাইন করা, তাই প্রতিটা ম্যাকে `build.sh` দিয়ে বানিয়ে নেওয়াই সহজ

## Project layout

```
Sources/ODM/
  DownloadEngine.swift   multi-connection engine, dynamic segmentation, retries
  Prober.swift           size, file name and range support detection
  YtDlp.swift            yt-dlp install/update and the video download runner
  DownloadManager.swift  list, queue, persistence, notifications
  LocalServer.swift      127.0.0.1:9614 bridge for the browser extension
  ContentView.swift      main window
  OtherViews.swift       add dialog, detail panel, settings, menu bar
  UIState.swift          window/dialog state (no @State, so it builds without Xcode)
ChromeExtension/         browser extension (Manifest V3)
build.sh                 builds, signs and installs ODM.app
```

## License

MIT — see [LICENSE](LICENSE). yt-dlp is downloaded separately at runtime and has its own license (Unlicense).
