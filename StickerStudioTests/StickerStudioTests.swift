import XCTest
import UIKit
import ImageIO
@testable import Sticker_Wp

@MainActor
final class StickerStudioTests: XCTestCase {
    private func fixture() -> UIImage {
        ImageProcessor.renderer(size: CGSize(width: 512, height: 512)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 80, y: 40, width: 352, height: 200))
            UIColor.blue.withAlphaComponent(0.5).setFill()
            ctx.fill(CGRect(x: 80, y: 250, width: 352, height: 200))
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("StickerStudioTests-\(UUID().uuidString)", isDirectory: true)
    }

    func testRenderKeepsCanvasAndTransparency() throws {
        let result = ImageProcessor.render(fixture(), style: StickerStyle())
        let cg = try XCTUnwrap(result.cgImage)
        XCTAssertEqual(cg.width, 512)
        XCTAssertEqual(cg.height, 512)
        XCTAssertEqual(pixel(result, x: 0, y: 0)[3], 0)
        XCTAssertGreaterThan(pixel(result, x: 256, y: 150)[3], 240)
    }

    func testWebPIsRealBoundedAndPreservesAlphaAndOrientation() throws {
        let data = try ImageProcessor.webP(from: fixture())
        XCTAssertLessThanOrEqual(data.count, 100 * 1024)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data.subdata(in: 8..<12), encoding: .ascii), "WEBP")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(cg.width, 512)
        XCTAssertEqual(cg.height, 512)
        let decoded = UIImage(cgImage: cg)
        XCTAssertEqual(pixel(decoded, x: 0, y: 0)[3], 0)
        let red = pixel(decoded, x: 256, y: 100)
        XCTAssertGreaterThan(red[0], 220)
        XCTAssertLessThan(red[2], 30)
        let blue = pixel(decoded, x: 256, y: 350)
        XCTAssertEqual(Int(blue[3]), 128, accuracy: 2)
        XCTAssertGreaterThan(blue[2], 110)
    }

    func testExportRejectsWrongDimensionsAndPackCounts() throws {
        let small = ImageProcessor.renderer(size: CGSize(width: 96, height: 96)).image { _ in }
        XCTAssertThrowsError(try ImageProcessor.webP(from: small))
        for count in [0, 1, 2, 31] {
            let pack = StickerPack(name: "Test", stickerIDs: (0..<count).map { _ in UUID() })
            XCTAssertThrowsError(try WhatsAppExporter.payload(pack: pack, images: Array(repeating: fixture(), count: count)))
        }
    }

    func testExportJSONContainsValidTrayAndAllStickers() throws {
        let pack = StickerPack(name: "Reactions", stickerIDs: (0..<3).map { _ in UUID() })
        let payload = try WhatsAppExporter.payload(pack: pack, images: Array(repeating: fixture(), count: 3))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(json["identifier"] as? String, pack.id.uuidString)
        XCTAssertEqual(json["name"] as? String, "Reactions")
        let stickers = try XCTUnwrap(json["stickers"] as? [[String: Any]])
        XCTAssertEqual(stickers.count, 3)
        let trayData = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(json["tray_image"] as? String)))
        let tray = try XCTUnwrap(UIImage(data: trayData))
        XCTAssertEqual(tray.size, CGSize(width: 96, height: 96))
        XCTAssertLessThanOrEqual(trayData.count, 50 * 1024)
        let webp = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(stickers[0]["image_data"] as? String)))
        XCTAssertEqual(String(data: webp.subdata(in: 8..<12), encoding: .ascii), "WEBP")
    }

    func testLibraryPersistsLooseStickerAndPackEdits() throws {
        let folder = temporaryDirectory()
        let library = StickerLibrary(directory: folder)
        try library.save(images: [fixture()], captions: ["hello 🌍"], packID: nil, newPackName: nil)
        let sticker = try XCTUnwrap(library.looseStickers.first)
        try library.createPack(name: "  Reactions  ", sticker: sticker)
        let pack = try XCTUnwrap(library.packs.first)
        try library.add(sticker, to: pack)
        XCTAssertEqual(library.packs[0].stickerIDs.count, 1)
        XCTAssertTrue(library.looseStickers.isEmpty)
        let reopened = StickerLibrary(directory: folder)
        XCTAssertEqual(reopened.packs[0].name, "Reactions")
        XCTAssertEqual(reopened.stickers[0].caption, "hello 🌍")
        XCTAssertNotNil(reopened.image(for: sticker))
        try reopened.rename(pack, to: "New name")
        XCTAssertEqual(StickerLibrary(directory: folder).packs[0].name, "New name")
        try reopened.removePack(pack)
        XCTAssertTrue(StickerLibrary(directory: folder).looseStickers.isEmpty)
        XCTAssertTrue(StickerLibrary(directory: folder).stickers.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sticker.filename).path))
    }

    func testFullPackAndInvalidNameDoNotMutateLibrary() throws {
        let library = StickerLibrary(directory: temporaryDirectory())
        let image = fixture()
        let id = try XCTUnwrap(library.save(images: Array(repeating: image, count: 30), captions: [], packID: nil, newPackName: "Full"))
        XCTAssertThrowsError(try library.save(images: [image], captions: [], packID: id, newPackName: nil))
        XCTAssertThrowsError(try library.save(images: [image], captions: [], packID: nil, newPackName: "  "))
        XCTAssertEqual(library.stickers.count, 30)
        XCTAssertEqual(library.packs.count, 1)
    }

    func testDeleteRemovesReferencesFromEveryPack() throws {
        let library = StickerLibrary(directory: temporaryDirectory())
        try library.save(images: [fixture()], captions: [], packID: nil, newPackName: "One")
        let sticker = try XCTUnwrap(library.stickers.first)
        try library.createPack(name: "Two", sticker: sticker)
        try library.delete(sticker)
        XCTAssertTrue(library.stickers.isEmpty)
        XCTAssertTrue(library.packs.allSatisfy { $0.stickerIDs.isEmpty })
    }

    func testCorruptManifestIsNotOverwritten() throws {
        let folder = temporaryDirectory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("library.json")
        let corrupt = Data("broken".utf8)
        try corrupt.write(to: url)
        let library = StickerLibrary(directory: folder)
        XCTAssertFalse(library.isAvailable)
        XCTAssertThrowsError(try library.save(images: [fixture()], captions: [], packID: nil, newPackName: nil))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
    }

    func testCropAndImportNormalizeOrientation() throws {
        let landscape = ImageProcessor.renderer(size: CGSize(width: 800, height: 400)).image { ctx in
            UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.blue.setFill(); ctx.fill(CGRect(x: 400, y: 0, width: 400, height: 400))
        }
        let crop = ImageProcessor.crop(landscape, zoom: 1, offset: CGSize(width: 0.5, height: 0))
        XCTAssertEqual(crop.size, CGSize(width: 1200, height: 1200))
        XCTAssertGreaterThan(pixel(crop, x: 600, y: 600)[0], 240)
        let rotated = UIImage(cgImage: try XCTUnwrap(landscape.cgImage), scale: 1, orientation: .right)
        let normalized = ImageProcessor.normalized(rotated)
        XCTAssertEqual(normalized.imageOrientation, .up)
        XCTAssertEqual(normalized.size, CGSize(width: 400, height: 800))
    }

    func testDeletingPackRemovesFilesAndSharedReferencesButKeepsUnrelatedStickers() throws {
        let folder = temporaryDirectory()
        let library = StickerLibrary(directory: folder)
        try library.save(images: [fixture(), fixture()], captions: [], packID: nil, newPackName: "Delete me")
        let target = try XCTUnwrap(library.packs.first)
        let deleted = library.stickers(in: target)
        try library.createPack(name: "Keep me", sticker: deleted[0])
        let remainingPack = try XCTUnwrap(library.packs.first)
        try library.save(images: [fixture()], captions: ["unrelated"], packID: remainingPack.id, newPackName: nil)
        try library.save(images: [fixture()], captions: ["single"], packID: nil, newPackName: nil)
        let loose = try XCTUnwrap(library.looseStickers.first)
        for sticker in deleted { XCTAssertNotNil(library.image(for: sticker)) }

        try library.removePack(target)

        let reopened = StickerLibrary(directory: folder)
        XCTAssertEqual(reopened.packs.count, 1)
        XCTAssertEqual(reopened.packs[0].id, remainingPack.id)
        XCTAssertEqual(reopened.packs[0].stickerIDs.count, 1)
        XCTAssertEqual(reopened.stickers.count, 2)
        XCTAssertEqual(reopened.looseStickers.map(\.id), [loose.id])
        for sticker in deleted {
            XCTAssertNil(library.image(for: sticker))
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sticker.filename).path))
        }
        XCTAssertNotNil(reopened.image(for: loose))
        try library.removePack(target)
        XCTAssertEqual(library.stickers.count, 2)
    }

    func testDeletingPackUsesLatestMembershipAndToleratesMissingImage() throws {
        let folder = temporaryDirectory()
        let library = StickerLibrary(directory: folder)
        try library.save(images: [fixture()], captions: [], packID: nil, newPackName: "Pack")
        let stalePack = try XCTUnwrap(library.packs.first)
        try library.save(images: [fixture()], captions: [], packID: stalePack.id, newPackName: nil)
        let latest = library.stickers
        try FileManager.default.removeItem(at: folder.appendingPathComponent(latest[0].filename))
        try library.removePack(stalePack)
        XCTAssertTrue(library.stickers.isEmpty)
        XCTAssertTrue(library.looseStickers.isEmpty)
        XCTAssertTrue(library.packs.isEmpty)
        for sticker in latest {
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sticker.filename).path))
        }
    }

    func testFailedPackDeletionPreservesManifestStateAndImageFiles() throws {
        let folder = temporaryDirectory()
        let library = StickerLibrary(directory: folder)
        try library.save(images: [fixture()], captions: [], packID: nil, newPackName: "Keep")
        let pack = try XCTUnwrap(library.packs.first)
        let sticker = try XCTUnwrap(library.stickers.first)
        let manifest = folder.appendingPathComponent("library.json")
        try FileManager.default.moveItem(at: manifest, to: folder.appendingPathComponent("backup.json"))
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: false)
        XCTAssertThrowsError(try library.removePack(pack))
        XCTAssertEqual(library.packs.count, 1)
        XCTAssertEqual(library.stickers.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(sticker.filename).path))
    }

    func testRemovingStickerFromPackStillPreservesStandaloneSticker() throws {
        let folder = temporaryDirectory()
        let library = StickerLibrary(directory: folder)
        try library.save(images: [fixture()], captions: [], packID: nil, newPackName: "Pack")
        let pack = try XCTUnwrap(library.packs.first)
        let sticker = try XCTUnwrap(library.stickers.first)
        try library.remove(sticker, from: pack)
        XCTAssertEqual(library.looseStickers.map(\.id), [sticker.id])
        XCTAssertNotNil(library.image(for: sticker))
    }

    func testTranslationsHaveMatchingKeysAndFormatArguments() throws {
        func table(_ language: String) throws -> [String: String] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
        }
        let english = try table("en")
        let turkish = try table("tr")
        XCTAssertEqual(Set(english.keys), Set(turkish.keys))
        let pattern = try NSRegularExpression(pattern: "%[@d]")
        for (key, value) in english {
            let translation = try XCTUnwrap(turkish[key])
            XCTAssertFalse(translation.isEmpty)
            func placeholders(_ string: String) -> [String] {
                pattern.matches(in: string, range: NSRange(string.startIndex..., in: string)).map {
                    (string as NSString).substring(with: $0.range)
                }
            }
            XCTAssertEqual(placeholders(value), placeholders(translation), key)
        }
        XCTAssertEqual(L10n.localized("Settings", language: .english), "Settings")
        XCTAssertEqual(L10n.localized("Settings", language: .turkish), "Ayarlar")
        XCTAssertEqual(L10n.localized("%d stickers", language: .english, arguments: [3]), "3 stickers")
        XCTAssertEqual(L10n.localized("%d stickers", language: .turkish, arguments: [3]), "3 çıkartma")
        XCTAssertEqual(L10n.localized("Added to %@.", language: .turkish, arguments: ["Travel 🌍"]), "Travel 🌍 paketine eklendi.")
        XCTAssertEqual(L10n.localized("Missing translation", language: .turkish), "Missing translation")
    }

    func testRuntimeLanguageSwitchAndEnglishFallback() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "appLanguage")
        defer {
            if let previous { defaults.set(previous, forKey: "appLanguage") }
            else { defaults.removeObject(forKey: "appLanguage") }
        }
        defaults.set("tr", forKey: "appLanguage")
        XCTAssertEqual(L10n.text("Settings"), "Ayarlar")
        defaults.set("en", forKey: "appLanguage")
        XCTAssertEqual(L10n.text("Settings"), "Settings")
        defaults.set("unsupported", forKey: "appLanguage")
        XCTAssertEqual(L10n.text("Settings"), "Settings")
    }

    private func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8] {
        let width = Int(image.size.width), height = Int(image.size.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image.cgImage!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let start = (y * width + x) * 4
        return Array(bytes[start..<start + 4])
    }
}
