# Security Policy / নিরাপত্তা নীতি

## Supported versions / সমর্থিত ভার্সন

Only the [latest release](https://github.com/niruvai/odm/releases/latest) of ODM receives security fixes. ODM updates itself, so please keep it up to date (menu **ODM → Check for Updates…**).

শুধু ODM-এর [সর্বশেষ রিলিজ](https://github.com/niruvai/odm/releases/latest)-এ নিরাপত্তা সংশোধন আসে। ODM নিজে থেকে আপডেট হয়, তাই সবসময় সর্বশেষ ভার্সন ব্যবহার করুন (মেনু **ODM → Check for Updates…**)।

## Reporting a vulnerability / নিরাপত্তা ত্রুটি জানানো

**Please do not report security problems in public issues.**

Report them privately instead:
1. Open the [Security tab](https://github.com/niruvai/odm/security) of this repository
2. Click **Report a vulnerability**
3. Describe the problem, how to reproduce it, and which ODM build you use (Settings → About)

You will get a reply within 7 days. Once the problem is fixed, a new release is published and you will be credited if you wish.

**নিরাপত্তার সমস্যা পাবলিক Issue-তে লিখবেন না।**

গোপনে জানান:
1. এই রেপোর [Security ট্যাব](https://github.com/niruvai/odm/security) খুলুন
2. **Report a vulnerability** চাপুন
3. সমস্যাটা কী, কীভাবে আবার ঘটানো যায়, আর আপনি ODM-এর কোন বিল্ড ব্যবহার করছেন (Settings → About) লিখুন

৭ দিনের মধ্যে উত্তর পাবেন। সমস্যা ঠিক হলে নতুন রিলিজ প্রকাশ করা হবে, আর আপনি চাইলে আপনার নাম কৃতজ্ঞতায় উল্লেখ করা হবে।

## What counts / কোনগুলো নিরাপত্তা সমস্যা

Examples / উদাহরণ:
- A website being able to start downloads or read data through ODM's local bridge (`127.0.0.1:9614`) / কোনো ওয়েবসাইট ODM-এর লোকাল ব্রিজ দিয়ে ডাউনলোড শুরু বা তথ্য পড়তে পারা
- Browser sign-in cookies leaving your Mac / ব্রাউজারের লগইন কুকি আপনার ম্যাকের বাইরে চলে যাওয়া
- A download writing files outside the chosen download folder / ডাউনলোড বেছে নেওয়া ফোল্ডারের বাইরে ফাইল লেখা
- The updater installing something that is not an official ODM release / আপডেটার অফিশিয়াল ODM রিলিজ ছাড়া অন্য কিছু ইনস্টল করা

Maintainer / রক্ষণাবেক্ষণকারী: [Nirob Islam](https://www.nirobislam.com/en/)
