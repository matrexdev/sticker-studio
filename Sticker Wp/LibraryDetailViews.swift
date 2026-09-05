import SwiftUI
import PhotosUI

struct PackDetailView: View {
    @AppStorage("appLanguage") private var language = "en"
    let library: StickerLibrary
    let packID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotosPickerItem] = []
    @State private var session: EditingSession?
    @State private var busy = false
    @State private var message: String?
    @State private var rename = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var showExisting = false
    private var pack: StickerPack? { library.packs.first { $0.id == packID } }

    var body: some View {
        let _ = language
        Group {
            if let pack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pack.name).font(.system(size: 32, weight: .bold, design: .rounded))
                                Text(L10n.text("%d / 30 stickers", pack.stickerIDs.count)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.stack.3d.up.fill").font(.largeTitle).foregroundStyle(StudioTheme.onLime).padding(18).background(StudioTheme.lime, in: RoundedRectangle(cornerRadius: 22))
                        }
                        StudioNotice(text: pack.stickerIDs.count < 3 ? L10n.text("Add %d more stickers to export to WhatsApp.", 3 - pack.stickerIDs.count) : L10n.text("Your pack is ready. Confirm adding it in WhatsApp. Export it again after making changes."))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 12) {
                            ForEach(library.stickers(in: pack)) { sticker in
                                NavigationLink {
                                    StickerDetailView(library: library, sticker: sticker)
                                } label: { StickerThumbnail(image: library.image(for: sticker)) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(sticker.caption.isEmpty ? L10n.text("Open sticker") : sticker.caption)
                                    .contextMenu {
                                        Button(L10n.text("Remove from pack"), systemImage: "minus.circle") {
                                            do { try library.remove(sticker, from: pack) } catch { message = error.localizedDescription }
                                        }
                                    }
                            }
                        }
                        if pack.stickerIDs.count < 30 {
                            PhotosPicker(selection: $photos, maxSelectionCount: 30 - pack.stickerIDs.count, matching: .images) {
                                Label(L10n.text("Add stickers from photos"), systemImage: "plus").font(.headline).frame(maxWidth: .infinity).padding(17).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
                            }.disabled(busy)
                            Button { showExisting = true } label: {
                                Label(L10n.text("Add from collection"), systemImage: "square.grid.2x2").frame(maxWidth: .infinity)
                            }.disabled(busy)
                        }
                        if busy { ProgressView(L10n.text("Preparing…")).frame(maxWidth: .infinity) }
                    }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
                }.safeAreaInset(edge: .bottom) {
                    Button {
                        busy = true
                        Task {
                            defer { busy = false }
                            do {
                                try await WhatsAppExporter.send(pack: pack, library: library)
                                message = L10n.text("WhatsApp opened. Finish adding your pack there.")
                            } catch { message = error.localizedDescription }
                        }
                    } label: { Label(L10n.text("Add to WhatsApp"), systemImage: "arrow.up.forward.app").modifier(PrimaryButton()) }
                        .disabled(pack.stickerIDs.count < 3 || busy).opacity(pack.stickerIDs.count < 3 ? 0.5 : 1)
                        .padding(22).background(StudioTheme.paper)
                }
            } else { ContentUnavailableView(L10n.text("Pack not found"), systemImage: "square.stack") }
        }.background(StudioTheme.paper).navigationTitle(L10n.text("My pack")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(L10n.text("Rename"), systemImage: "pencil") { name = pack?.name ?? ""; rename = true }
                        Button(L10n.text("Delete pack"), systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: { Image(systemName: "ellipsis.circle") }.disabled(busy)
                }
            }
            .onChange(of: photos) { _, items in
                guard !items.isEmpty else { return }
                busy = true
                Task {
                    var images: [UIImage] = []
                    var failures = 0
                    for item in items {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else { failures += 1; continue }
                            images.append(try await Task.detached { try ImageProcessor.importImage(data) }.value)
                        } catch { failures += 1 }
                    }
                    photos = []; busy = false
                    if !images.isEmpty { session = EditingSession(images: images, targetPackID: packID) }
                    if failures > 0 { message = L10n.text("Could not load %d photos. Check your iCloud connection and try again.", failures) }
                }
            }
            .fullScreenCover(item: $session) { session in StickerEditorView(session: session, library: library) }
            .sheet(isPresented: $showExisting) { existingSheet }
            .alert(L10n.text("Pack name"), isPresented: $rename) {
                TextField(L10n.text("Name"), text: $name)
                Button(L10n.text("Save")) { if let pack { do { try library.rename(pack, to: name) } catch { message = error.localizedDescription } } }
                Button(L10n.text("Cancel"), role: .cancel) { }
            }
            .confirmationDialog(L10n.text("Delete this pack and all its stickers? They will also be removed from other local packs that contain them. This cannot be undone. Copies in WhatsApp are unaffected."), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L10n.text("Delete pack"), role: .destructive) {
                    if let pack { do { try library.removePack(pack); dismiss() } catch { message = error.localizedDescription } }
                }
            }
            .alert(L10n.text("Notice"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(L10n.text("OK"), role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
    }

    private var existingSheet: some View {
        NavigationStack {
            ScrollView {
                let available = library.stickers.filter { !(pack?.stickerIDs.contains($0.id) ?? true) }
                if available.isEmpty {
                    ContentUnavailableView(L10n.text("No stickers to add"), systemImage: "square.stack", description: Text(L10n.text("Choose a new photo from your library.")))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))]) {
                        ForEach(available) { sticker in
                            Button {
                                guard let pack else { return }
                                do { try library.add(sticker, to: pack); showExisting = false } catch { message = error.localizedDescription }
                            } label: { StickerThumbnail(image: library.image(for: sticker)) }
                                .accessibilityLabel(L10n.text("Add sticker to pack"))
                        }
                    }.padding(20)
                }
            }.background(StudioTheme.paper).navigationTitle(L10n.text("Choose a sticker")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Close")) { showExisting = false } } }
        }
    }
}

struct StickerDetailView: View {
    @AppStorage("appLanguage") private var language = "en"
    let library: StickerLibrary
    let sticker: SavedSticker
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var showPacks = false
    @State private var newPack = false
    @State private var name = ""
    @State private var confirmDelete = false
    @State private var session: EditingSession?

    var body: some View {
        let _ = language
        ScrollView {
            VStack(spacing: 24) {
                if let image = library.image(for: sticker) {
                    ZStack {
                        Checkerboard()
                        Image(uiImage: image).resizable().scaledToFit().padding(20)
                    }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28))
                    StudioNotice(text: L10n.text("Open a chat and paste into the message field. You can add the sent sticker to favorites in WhatsApp."))
                    Button { copy(image, open: true) } label: { Label(L10n.text("Copy and open WhatsApp"), systemImage: "arrow.up.forward.app").modifier(PrimaryButton()) }
                    HStack(spacing: 24) {
                        Button { copy(image, open: false) } label: { Label(L10n.text("Copy"), systemImage: "doc.on.doc") }
                        Button { showPacks = true } label: { Label(L10n.text("Add to pack"), systemImage: "plus.rectangle.on.rectangle") }
                    }.font(.subheadline.weight(.semibold))
                    Button(L10n.text("Edit as a new copy")) { session = EditingSession(images: [image]) }.font(.subheadline)
                } else {
                    ContentUnavailableView(L10n.text("Could not open image"), systemImage: "photo.badge.exclamationmark", description: Text(L10n.text("Add the photo from your library again.")))
                }
            }.padding(22).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }.background(StudioTheme.paper).navigationTitle(L10n.text("My sticker")).navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel(L10n.text("Delete sticker")) } }
            .fullScreenCover(item: $session) { session in StickerEditorView(session: session, library: library) }
            .confirmationDialog(L10n.text("Which pack should it go in?"), isPresented: $showPacks, titleVisibility: .visible) {
                Button(L10n.text("Create a new pack")) { newPack = true }
                ForEach(library.packs.filter { $0.stickerIDs.count < 30 && !$0.stickerIDs.contains(sticker.id) }) { pack in
                    Button(pack.name) {
                        do { try library.add(sticker, to: pack); message = L10n.text("Added to %@.", pack.name) } catch { message = error.localizedDescription }
                    }
                }
                Button(L10n.text("Cancel"), role: .cancel) { }
            }
            .alert(L10n.text("New pack"), isPresented: $newPack) {
                TextField(L10n.text("Pack name"), text: $name)
                Button(L10n.text("Create")) {
                    do { try library.createPack(name: name, sticker: sticker); message = L10n.text("Pack created. Add 2 more stickers to export to WhatsApp.") }
                    catch { message = error.localizedDescription }
                }
                Button(L10n.text("Cancel"), role: .cancel) { }
            }
            .confirmationDialog(L10n.text("Delete this sticker from your collection and all local packs? This cannot be undone. Copies in WhatsApp are unaffected."), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L10n.text("Delete sticker"), role: .destructive) {
                    do { try library.delete(sticker); dismiss() } catch { message = error.localizedDescription }
                }
            }
            .alert(L10n.text("Notice"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(L10n.text("OK"), role: .cancel) { message = nil }
            } message: { Text(message ?? "") }
    }

    private func copy(_ image: UIImage, open: Bool) {
        Task {
            do { try await WhatsAppExporter.copy(image, openWhatsApp: open); if !open { message = L10n.text("Sticker copied to clipboard.") } }
            catch { message = error.localizedDescription }
        }
    }
}
