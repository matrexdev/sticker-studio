# Sticker Studio

A native, privacy-focused iOS sticker maker built with SwiftUI. Turn photos into stickers, organize your collection, and export packs to WhatsApp.

## Features

- Import 1–30 photos from the system photo picker or paste images from the clipboard.
- Crop and zoom, remove backgrounds on-device with Apple Vision, add a caption, adjust its color and outline, resize, rotate, and undo edits.
- Save single stickers without a pack, create packs, or add to existing packs.
- Export packs as real WebP images with size validation.
- Switch between **English** (default) and **Turkish** in Settings.
- Choose **System**, **Light**, or **Dark** appearance. The moon/sun button on the home screen switches directly between light and dark.
- Store photos, stickers, and preferences locally. No accounts, ads, analytics, or server.

## Requirements and setup

- Xcode 26 or later.
- iOS 17 or later, on iPhone or iPad.
- Swift Package Manager resolves the pinned **libwebp 1.6.0** dependency.

1. Open `Sticker Wp.xcodeproj`.
2. Select the `Sticker Wp` scheme and an iPhone simulator.
3. Run with **⌘R**.
4. To run on a physical iPhone, select your team under **Signing & Capabilities**, enable automatic signing, and enable Developer Mode on the phone.

To keep your team out of version control, copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and replace `YOUR_TEAM_ID`. This optional local file is ignored by Git and loaded by both build configurations.

For a fork, choose your own unique bundle identifier. When updating an existing installation, keep its identifier to preserve access to its local collection. Project and target paths retain their original names for compatibility; the app is displayed as **Sticker Studio**.

## Language and appearance

Open **Settings** using the sliders button in the top-right corner. Language and appearance changes take effect immediately and persist between launches. New installations default to English and follow the system appearance. The moon/sun shortcut selects an explicit theme; choose System in Settings to follow iOS again.

Pack names and sticker captions are user content and are never translated. System-provided photo, paste, and permission interfaces may follow the device language instead of the in-app selection.

Source code and localization keys are in English. Translations live in:

- `Sticker Wp/en.lproj/Localizable.strings`
- `Sticker Wp/tr.lproj/Localizable.strings`

To contribute another language, add a matching `<language>.lproj/Localizable.strings` file, preserve format placeholders, and add the language to `AppLanguage` and `CFBundleLocalizations`. Use `L10n.text("English source text")` for user-facing strings. Pass variable values as format arguments instead of translating user content.

## Working with packs

**Single photo:** save without a pack or choose a new/existing pack. A standalone sticker can be added to a pack later.

**Multiple photos:** save to a new or existing pack. Two-sticker packs are saved as drafts until they contain enough stickers for WhatsApp.

**Remove from pack:** long-press a sticker in a pack and choose this action to detach it. The sticker stays in your collection.

**Delete pack:** permanently deletes the pack, all of its stickers, and their PNG files. If a sticker is shared by other local packs, its references are removed there too. Unrelated stickers are preserved. Deleted stickers do not appear under Singles. The app asks for confirmation before deletion.

**Delete sticker:** removes the sticker from the collection, every local pack, and local image storage. Copies already imported into WhatsApp are not affected by local deletion.

## WhatsApp integration

The official iOS integration requires 3–30 stickers per pack. Each static sticker must be 512 × 512 pixels and no larger than 100 KB. The tray icon is a 96 × 96 PNG, up to 50 KB.

PNG originals are stored locally. WebP encoding runs in the background during export and progressively reduces quality to meet the size limit. The app refuses oversized output. It never pads packs with duplicate stickers to reach the minimum.

Export uses Base64 WebP data in JSON, the `net.whatsapp.third-party.sticker-pack` pasteboard type, and `whatsapp://stickerPack`. Pack export data is device-local and expires after 60 seconds. Pack identifiers remain stable across updates.

Tap **Add to WhatsApp**, then confirm in WhatsApp. The app can detect whether WhatsApp opened, but cannot confirm that the user actually saved the pack. Export again after changing a pack.

For a single sticker, use **Copy and open WhatsApp**, paste into a chat, and favorite the sent sticker inside WhatsApp. This is not a direct favorites API; behavior depends on WhatsApp and iOS.

References: [WhatsApp iOS documentation](https://github.com/WhatsApp/stickers/tree/main/iOS), [libwebp](https://github.com/SDWebImage/libwebp-Xcode).

## Architecture

| File | Responsibility |
| --- | --- |
| `ContentView.swift` | Photo/clipboard import, collection, and settings |
| `StickerEditorView.swift` | Batch editor, crop, and save flow |
| `ImageProcessor.swift` | Normalization, Vision processing, rendering, and WebP encoding |
| `StickerLibrary.swift` | Codable models, atomic persistence, and cascading deletion |
| `LibraryDetailViews.swift` | Pack and sticker management |
| `WhatsAppExporter.swift` | Export validation, JSON, and WhatsApp handoff |
| `AppPreferences.swift` | Language lookup and persisted appearance |
| `StudioTheme.swift` | Adaptive colors and shared UI components |

Image files and the JSON manifest live in Application Support. New images are written before the manifest is committed atomically. Deletion commits the manifest before removing files, so a failed manifest write does not destroy images. File-cleanup failures are reported. Corrupt or unsupported manifests disable writes instead of overwriting user data.

Preferences use app-local UserDefaults, declared in the privacy manifest with reason CA92.1. Images may be included in system backups according to the user's backup settings. Removing files is not a guarantee of secure erasure from backups. Existing unreferenced files from older versions are not proactively purged.

## Testing

Use **⌘U** in Xcode, or:

```sh
xcodebuild -project 'Sticker Wp.xcodeproj' -scheme 'Sticker Wp' \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/sticker-studio-build CODE_SIGNING_ALLOWED=NO test
```

Tests cover WebP format, transparency and orientation, export payloads, pack limits, persistence, cascading deletion and file removal, stale pack snapshots, failed writes, localization parity, format arguments, and language switching.

On a physical device, verify photo/clipboard import, background removal on a real subject, WhatsApp single-sticker paste, pack import, and pack re-export. The simulator cannot validate all Vision and WhatsApp behavior.

## Scope

Static photo stickers only; GIF and Live Photo motion is not preserved. Cropping uses a square frame, with no freehand selection. Captions use one text layer. Undo history lasts for the editing session; finished stickers are flattened PNGs. Editing a saved sticker creates a new copy.

Cloud sync, archive import/export, a recycle bin, and a separate WhatsApp Business destination are not implemented.

## Contributing and publishing

See [CONTRIBUTING.md](CONTRIBUTING.md). A shared Xcode scheme, dependency lockfile, tests, privacy manifest, and third-party license notice are included.

An open-source license for the application source has not yet been selected. Avoid committing signing credentials or personal Xcode settings. Files already tracked by Git are not removed from history by `.gitignore`.

libwebp's BSD notice is bundled as `ThirdPartyNotices.txt`. Sticker Studio is not affiliated with WhatsApp or Meta.

Regenerate the app icon with `swift Tools/GenerateIcon.swift`.
