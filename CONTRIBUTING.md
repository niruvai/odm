# Contributing to ODM

Thanks for helping make ODM better. Bug fixes, new features, translations and documentation are all welcome.

[বাংলায় পড়ুন](#বাংলা)

## Before you start

- **Bugs and ideas:** search the [Issues](https://github.com/niruvai/odm/issues) first. If nothing matches, open a new one using the template.
- **Big changes** (a new download engine feature, changes to the browser extension or the local bridge): open an issue first and describe your plan, so we can agree on the approach before you spend time on it.
- **Security problems:** do not open a public issue. Follow the [security policy](SECURITY.md).

## Setting up

Requires macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`); full Xcode is not needed.

```bash
git clone https://github.com/<your-username>/odm.git
cd odm
./build.sh --install    # builds ODM.app and installs it to /Applications
```

To try the Chrome extension, open `chrome://extensions`, turn on **Developer mode** and load the `ChromeExtension` folder with **Load unpacked**.

The project structure is described in the [README](README.md#building-from-source).

## Making a pull request

1. Fork the repository and create a branch from `main` (for example `fix-resume-after-sleep`).
2. Keep each pull request focused on one fix or feature.
3. Build with `./build.sh --install` and test your change. For engine changes, try a large file, pause and resume, and a dropped connection.
4. Open the pull request and fill in the template. Add screenshots for anything visible.

### Important: every merge becomes a release

Every push to `main` that changes code is built by GitHub Actions and published as a new release, which installed copies of ODM offer to their users. Because of this:

- **Do not edit `.github/workflows/`, `build.sh` or `Updater.swift`** unless the maintainer has asked for it in an issue.
- The maintainer reviews every pull request before it is merged.

### Please do not

- Add analytics, tracking, or any network calls other than downloads, video component setup and the update check.
- Send browser cookies or any user data off the Mac.
- Make the local bridge (`127.0.0.1:9614`) reachable from other computers or from arbitrary websites.
- Add new dependencies without explaining why in the pull request.

## Code style

- Swift with SwiftUI. Follow the style of the file you're editing.
- The app is built with Swift Package Manager, not Xcode projects; don't add `.xcodeproj` files.
- Write clear commit messages that say what changed and why.

## License

By contributing, you agree that your contributions are released under the [MIT License](LICENSE).

---

## বাংলা

ODM-এ অবদান রাখার জন্য ধন্যবাদ।

- **বাগ বা আইডিয়া:** আগে [Issues](https://github.com/niruvai/odm/issues)-এ খুঁজে দেখুন, না পেলে নতুন Issue খুলুন।
- **বড় পরিবর্তন** করার আগে একটা Issue খুলে পরিকল্পনাটা জানান।
- **Pull Request:** রিপো fork করুন, `main` থেকে নতুন branch বানান, `./build.sh --install` দিয়ে বিল্ড করে পরীক্ষা করুন, তারপর PR খুলে টেমপ্লেটটা পূরণ করুন।
- **মনে রাখবেন:** `main`-এ কোডের প্রতিটা পরিবর্তন নিজে থেকে নতুন রিলিজ হয়ে সব ইউজারের কাছে আপডেট হিসেবে যায়। তাই `.github/workflows/`, `build.sh` বা `Updater.swift` বদলাবেন না, যদি না মেইনটেইনার Issue-তে সেটা চেয়ে থাকেন।
- নিরাপত্তার সমস্যা পাবলিক Issue-তে না লিখে [নিরাপত্তা নীতি](SECURITY.md) অনুসরণ করুন।
