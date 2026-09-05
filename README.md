# Sticker Studio

An iOS app for making WhatsApp stickers from your photos. Built with SwiftUI.

- Import photos from your library or clipboard.
- Crop, remove backgrounds, add text, resize, and rotate.
- Save stickers individually or organize them into packs.
- English and Turkish, with light and dark themes.

Photos and edits stay on your device. Background removal uses Apple Vision.

## Run locally

Requires Xcode 26+ and iOS 17+.

Open `Sticker Wp.xcodeproj`, let Swift Package Manager resolve dependencies, and run the `Sticker Wp` scheme with **⌘R**. Run tests with **⌘U**.

For your iPhone, enable Developer Mode and set your signing team. You can copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and enter your team ID to keep it out of Git.

## WhatsApp

Packs need **3–30 stickers**. The app handles WebP conversion and file-size limits. Single stickers can be copied and pasted into a chat.

Deleting a pack also deletes its stickers from the app, including references in other packs. Copies already added to WhatsApp stay there.

Only static stickers are supported. WhatsApp export needs a physical iPhone.

Uses [libwebp](https://github.com/SDWebImage/libwebp-Xcode) under its BSD license. See [CONTRIBUTING.md](CONTRIBUTING.md) for development notes. An application source license has not yet been selected.
