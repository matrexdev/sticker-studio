import UIKit
import UniformTypeIdentifiers

enum WhatsAppExporter {
    static func payload(pack: StickerPack, images: [UIImage]) throws -> Data {
        guard (3...30).contains(images.count), images.count == pack.stickerIDs.count else {
            throw StudioError.message(L10n.text("A pack needs 3–30 stickers to export to WhatsApp. Add any missing images again."))
        }
        let name = pack.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 128 else { throw StudioError.message(L10n.text("Pack names must contain 1–128 characters.")) }
        let tray = ImageProcessor.render(images[0], style: StickerStyle(scale: 1), side: 96)
        guard let trayData = tray.pngData(), trayData.count <= 50 * 1024 else { throw StudioError.message(L10n.text("Could not create the pack icon.")) }
        let stickers = try images.map { image -> [String: Any] in
            ["image_data": try ImageProcessor.webP(from: image).base64EncodedString(), "emojis": ["✨"]]
        }
        return try JSONSerialization.data(withJSONObject: [
            "identifier": pack.id.uuidString, "name": name, "publisher": "Sticker Studio",
            "tray_image": trayData.base64EncodedString(), "stickers": stickers
        ])
    }

    @MainActor static func send(pack: StickerPack, library: StickerLibrary) async throws {
        guard let url = URL(string: "whatsapp://stickerPack"), UIApplication.shared.canOpenURL(url) else {
            throw StudioError.message(L10n.text("WhatsApp was not found. Try exporting on an iPhone with WhatsApp installed."))
        }
        let images = library.stickers(in: pack).compactMap { library.image(for: $0) }
        let data = try await Task.detached(priority: .userInitiated) { try payload(pack: pack, images: images) }.value
        UIPasteboard.general.setItems([["net.whatsapp.third-party.sticker-pack": data]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
        guard await UIApplication.shared.open(url) else { throw StudioError.message(L10n.text("Could not open WhatsApp. Please try again.")) }
    }

    @MainActor static func copy(_ image: UIImage, openWhatsApp: Bool) async throws {
        guard let data = image.pngData() else { throw StudioError.message(L10n.text("Could not copy the sticker.")) }
        if openWhatsApp {
            guard let url = URL(string: "whatsapp://"), UIApplication.shared.canOpenURL(url) else {
                throw StudioError.message(L10n.text("WhatsApp is not installed on this device. You can still use Copy to copy the sticker."))
            }
            UIPasteboard.general.setItems([[UTType.png.identifier: data]], options: [.localOnly: true])
            guard await UIApplication.shared.open(url) else { throw StudioError.message(L10n.text("Could not open WhatsApp. Your sticker was copied to the clipboard.")) }
        } else {
            UIPasteboard.general.setItems([[UTType.png.identifier: data]], options: [.localOnly: true])
        }
    }
}
