import SwiftUI
import UIKit

struct SavedSticker: Identifiable, Codable, Hashable {
    var id = UUID()
    var createdAt = Date()
    var caption: String
    var filename: String { "\(id.uuidString).png" }
}

struct StickerPack: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var stickerIDs: [UUID]
    var createdAt = Date()
}

struct LibraryDocument: Codable {
    var version = 1
    var stickers: [SavedSticker] = []
    var packs: [StickerPack] = []
}

enum StudioError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(message) = self { return message }
        return nil
    }
}

@MainActor @Observable
final class StickerLibrary {
    private(set) var document = LibraryDocument()
    var errorMessage: String?
    private(set) var isAvailable = true
    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("StickerStudio", isDirectory: true)
        cache.countLimit = 80
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let url = self.directory.appendingPathComponent("library.json")
            if FileManager.default.fileExists(atPath: url.path) {
                document = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf: url))
                guard document.version == 1 else { throw StudioError.message(L10n.text("This library requires a newer app version.")) }
            }
        } catch {
            isAvailable = false
            errorMessage = L10n.text("Could not open your library. Your data was not overwritten. %@", error.localizedDescription)
        }
    }

    var stickers: [SavedSticker] { document.stickers }
    var packs: [StickerPack] { document.packs }
    var looseStickers: [SavedSticker] {
        let packed = Set(packs.flatMap(\.stickerIDs))
        return stickers.filter { !packed.contains($0.id) }
    }

    func stickers(in pack: StickerPack) -> [SavedSticker] {
        pack.stickerIDs.compactMap { id in stickers.first { $0.id == id } }
    }

    func image(for sticker: SavedSticker) -> UIImage? {
        let key = sticker.filename as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(contentsOfFile: directory.appendingPathComponent(sticker.filename).path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// The manifest is committed only after every image has been written atomically.
    @discardableResult
    func save(images: [UIImage], captions: [String], packID: UUID?, newPackName: String?) throws -> UUID? {
        guard isAvailable else { throw StudioError.message(L10n.text("Saving is disabled because the library could not be read. Try reopening the app.")) }
        guard !images.isEmpty, images.count <= 30 else { throw StudioError.message(L10n.text("You can save 1–30 stickers at a time.")) }
        var next = document
        var targetID = packID
        if let name = newPackName {
            let cleaned = try validatedName(name)
            let pack = StickerPack(name: cleaned, stickerIDs: [])
            next.packs.insert(pack, at: 0)
            targetID = pack.id
        }
        if let targetID {
            guard let pack = next.packs.first(where: { $0.id == targetID }) else { throw StudioError.message(L10n.text("Pack not found.")) }
            guard pack.stickerIDs.count + images.count <= 30 else { throw StudioError.message(L10n.text("A pack can contain up to 30 stickers.")) }
        }
        var added: [SavedSticker] = []
        for (index, image) in images.enumerated() {
            let sticker = SavedSticker(caption: captions.indices.contains(index) ? captions[index] : "")
            guard let data = image.pngData() else { throw StudioError.message(L10n.text("Could not create the sticker file.")) }
            try data.write(to: directory.appendingPathComponent(sticker.filename), options: [.atomic, .completeFileProtectionUnlessOpen])
            added.append(sticker)
        }
        next.stickers.insert(contentsOf: added, at: 0)
        if let targetID, let index = next.packs.firstIndex(where: { $0.id == targetID }) {
            next.packs[index].stickerIDs.append(contentsOf: added.map(\.id))
        }
        try commit(next)
        return targetID
    }

    func add(_ sticker: SavedSticker, to pack: StickerPack) throws {
        var next = document
        guard let index = next.packs.firstIndex(where: { $0.id == pack.id }), next.stickers.contains(where: { $0.id == sticker.id }) else { return }
        guard !next.packs[index].stickerIDs.contains(sticker.id) else { return }
        guard next.packs[index].stickerIDs.count < 30 else { throw StudioError.message(L10n.text("This pack is full. Choose another one.")) }
        next.packs[index].stickerIDs.append(sticker.id)
        try commit(next)
    }

    func createPack(name: String, sticker: SavedSticker) throws {
        var next = document
        next.packs.insert(StickerPack(name: try validatedName(name), stickerIDs: [sticker.id]), at: 0)
        try commit(next)
    }

    func rename(_ pack: StickerPack, to name: String) throws {
        var next = document
        guard let index = next.packs.firstIndex(where: { $0.id == pack.id }) else { return }
        next.packs[index].name = try validatedName(name)
        try commit(next)
    }

    func removePack(_ pack: StickerPack) throws {
        var next = document
        guard let storedPack = next.packs.first(where: { $0.id == pack.id }) else { return }
        let deletedIDs = Set(storedPack.stickerIDs)
        next.packs.removeAll { $0.id == pack.id }
        next.stickers.removeAll { deletedIDs.contains($0.id) }
        for index in next.packs.indices {
            next.packs[index].stickerIDs.removeAll { deletedIDs.contains($0) }
        }
        try commit(next)
        try deleteImageFiles(deletedIDs)
    }

    func remove(_ sticker: SavedSticker, from pack: StickerPack) throws {
        var next = document
        guard let index = next.packs.firstIndex(where: { $0.id == pack.id }) else { return }
        next.packs[index].stickerIDs.removeAll { $0 == sticker.id }
        try commit(next)
    }

    func delete(_ sticker: SavedSticker) throws {
        var next = document
        next.stickers.removeAll { $0.id == sticker.id }
        for index in next.packs.indices { next.packs[index].stickerIDs.removeAll { $0 == sticker.id } }
        try commit(next)
        try deleteImageFiles([sticker.id])
    }

    private func deleteImageFiles(_ ids: Set<UUID>) throws {
        var failed = false
        for id in ids {
            let filename = "\(id.uuidString).png"
            cache.removeObject(forKey: filename as NSString)
            let url = directory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do { try FileManager.default.removeItem(at: url) }
            catch { failed = true }
        }
        if failed {
            throw StudioError.message(L10n.text("Your collection was updated, but some image files could not be removed from storage."))
        }
    }

    private func validatedName(_ name: String) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 128 else { throw StudioError.message(L10n.text("Pack names must contain 1–128 characters.")) }
        return cleaned
    }

    private func commit(_ next: LibraryDocument) throws {
        guard isAvailable else { throw StudioError.message(L10n.text("Saving is disabled because the library could not be read. Try reopening the app.")) }
        let data = try JSONEncoder().encode(next)
        try data.write(to: directory.appendingPathComponent("library.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        document = next
    }
}
