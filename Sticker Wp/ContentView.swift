import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct EditingSession: Identifiable {
    let id = UUID()
    let images: [UIImage]
    var targetPackID: UUID?
}

struct ContentView: View {
    @AppStorage("appLanguage") private var language = "en"
    @AppStorage("appAppearance") private var appearance = "system"
    @Environment(\.colorScheme) private var colorScheme
    @State private var library = StickerLibrary()
    @State private var selection: [PhotosPickerItem] = []
    @State private var session: EditingSession?
    @State private var importing = false
    @State private var segment = 0
    @State private var showInfo = false

    var body: some View {
        let _ = language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    createCard
                    HStack {
                        Text(L10n.text("My collection")).font(.title2.bold())
                        Spacer()
                        Text(L10n.text("%d stickers", library.stickers.count)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Picker(L10n.text("Collection view"), selection: $segment) {
                        Text(L10n.text("Packs · %d", library.packs.count)).tag(0)
                        Text(L10n.text("Singles · %d", library.looseStickers.count)).tag(1)
                    }.pickerStyle(.segmented)
                    if segment == 0 {
                        if library.packs.isEmpty { emptyState }
                        else {
                            ForEach(library.packs) { pack in
                                NavigationLink {
                                    PackDetailView(library: library, packID: pack.id)
                                } label: { packCard(pack) }.buttonStyle(.plain)
                            }
                        }
                    } else if library.looseStickers.isEmpty {
                        ContentUnavailableView(L10n.text("Great on their own"), systemImage: "square.on.square.dashed", description: Text(L10n.text("Stickers saved without a pack appear here.")))
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                            ForEach(library.looseStickers) { sticker in
                                NavigationLink {
                                    StickerDetailView(library: library, sticker: sticker)
                                } label: {
                                    StickerThumbnail(image: library.image(for: sticker))
                                        .accessibilityLabel(sticker.caption.isEmpty ? L10n.text("Open sticker") : sticker.caption)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Label(L10n.text("All yours. All on your device."), systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 8)
                }.padding(22).frame(maxWidth: 720).frame(maxWidth: .infinity)
            }
            .background(StudioTheme.paper)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if importing { ProgressView(L10n.text("Preparing photos…")).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
            }
            .onChange(of: selection) { _, items in
                guard !items.isEmpty else { return }
                Task { await importPhotos(items) }
            }
            .fullScreenCover(item: $session) { session in StickerEditorView(session: session, library: library) }
            .sheet(isPresented: $showInfo) { infoSheet }
            .alert(L10n.text("Notice"), isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } })) {
                Button(L10n.text("OK"), role: .cancel) { library.errorMessage = nil }
            } message: { Text(library.errorMessage ?? "") }
        }.tint(StudioTheme.green)
            .environment(\.locale, Locale(identifier: language))
            .modifier(AppearancePreference())
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("SMALL STICKERS, BIG REACTIONS")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(StudioTheme.green)
                Text(L10n.text("Sticker\nStudio")).font(.system(size: 40, weight: .bold, design: .rounded)).tracking(-1.5).lineSpacing(-4)
            }
            Spacer()
            VStack(spacing: 10) {
                Button {
                    appearance = colorScheme == .dark ? "light" : "dark"
                } label: {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                        .font(.headline).frame(width: 44, height: 44).background(StudioTheme.surface, in: Circle())
                }.accessibilityLabel(L10n.text(colorScheme == .dark ? "Switch to light mode" : "Switch to dark mode"))
                Button { showInfo = true } label: {
                    Image(systemName: "slider.horizontal.3").font(.headline).frame(width: 44, height: 44).background(StudioTheme.surface, in: Circle())
                }.accessibilityLabel(L10n.text("Settings"))
            }
        }.foregroundStyle(StudioTheme.ink).padding(.top, 12)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("One photo.\nA thousand reactions.")).font(.system(size: 27, weight: .bold, design: .rounded))
                    Text(L10n.text("Pick, make it yours, send.")).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                }
                Spacer(minLength: 0)
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(StudioTheme.lime).frame(width: 70, height: 80).rotationEffect(.degrees(12))
                    Image(systemName: "face.smiling.inverse").font(.system(size: 44)).foregroundStyle(StudioTheme.forest).rotationEffect(.degrees(12))
                }.accessibilityHidden(true)
            }
            PhotosPicker(selection: $selection, maxSelectionCount: 30, matching: .images) {
                Label(L10n.text("Choose photos"), systemImage: "photo.on.rectangle.angled")
                    .font(.headline).frame(maxWidth: .infinity).padding(16)
                    .foregroundStyle(StudioTheme.onLime).background(StudioTheme.lime, in: RoundedRectangle(cornerRadius: 16))
            }.disabled(importing || !library.isAvailable)
            PasteButton(supportedContentTypes: [.image]) { providers in
                Task { await importPaste(providers) }
            }.labelStyle(.titleAndIcon).buttonStyle(.borderedProminent)
                .tint(StudioTheme.lime).foregroundStyle(StudioTheme.onLime).frame(maxWidth: .infinity)
                .disabled(importing || !library.isAvailable)
            Text(L10n.text("Use Paste to add a photo from your clipboard.")).font(.caption).foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity)
        }.padding(22).foregroundStyle(.white).background(StudioTheme.forest, in: RoundedRectangle(cornerRadius: 28))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 34, weight: .light)).foregroundStyle(StudioTheme.green).padding(20).background(StudioTheme.surface, in: Circle())
            Text(L10n.text("Your first pack awaits")).font(.headline)
            Text(L10n.text("Start with a few photos.\nThe best reactions are the ones you make.")).multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 20).frame(maxWidth: .infinity)
    }

    private func packCard(_ pack: StickerPack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ForEach(library.stickers(in: pack).prefix(3)) { sticker in StickerThumbnail(image: library.image(for: sticker)) }
                if pack.stickerIDs.isEmpty { Image(systemName: "plus.square.dashed").frame(height: 90).frame(maxWidth: .infinity).foregroundStyle(.secondary) }
            }.frame(maxHeight: 120)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.name).font(.headline).lineLimit(1)
                    Text(L10n.text("%d / 30 stickers", pack.stickerIDs.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(pack.stickerIDs.count >= 3 ? L10n.text("Ready") : L10n.text("Draft")).font(.caption.bold()).foregroundStyle(StudioTheme.onLime).padding(.horizontal, 11).padding(.vertical, 7).background(StudioTheme.lime.opacity(0.5), in: Capsule())
                Image(systemName: "chevron.right").font(.caption.bold())
            }
        }.padding(16).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    @MainActor private func importPhotos(_ items: [PhotosPickerItem]) async {
        importing = true
        var images: [UIImage] = []
        var failures = 0
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { failures += 1; continue }
                let image = try await Task.detached(priority: .userInitiated) { try ImageProcessor.importImage(data) }.value
                images.append(image)
            } catch { failures += 1 }
        }
        selection = []
        importing = false
        if !images.isEmpty { session = EditingSession(images: images) }
        if failures > 0 { library.errorMessage = L10n.text("Could not load %d photos. Check your iCloud connection and try again.", failures) }
    }

    @MainActor private func importPaste(_ providers: [NSItemProvider]) async {
        importing = true
        defer { importing = false }
        var images: [UIImage] = []
        var failures = 0
        for provider in providers.prefix(30) {
            do {
                guard let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { failures += 1; continue }
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                        if let data { continuation.resume(returning: data) }
                        else { continuation.resume(throwing: error ?? StudioError.message(L10n.text("Could not read the clipboard image."))) }
                    }
                }
                images.append(try await Task.detached { try ImageProcessor.importImage(data) }.value)
            } catch { failures += 1 }
        }
        if !images.isEmpty { session = EditingSession(images: images) }
        if failures > 0 { library.errorMessage = L10n.text("Could not open %d clipboard images. Try copying the photos again.", failures) }
    }

    private var infoSheet: some View {
        NavigationStack {
            List {
                Section(L10n.text("Preferences")) {
                    Picker(L10n.text("Language"), selection: $language) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                            Text(language.name).tag(language.rawValue)
                        }
                    }
                    Picker(L10n.text("Appearance"), selection: $appearance) {
                        Text(L10n.text("System")).tag("system")
                        Text(L10n.text("Light")).tag("light")
                        Text(L10n.text("Dark")).tag("dark")
                    }
                    Text(L10n.text("Language and appearance are saved automatically. System photo and paste controls may follow your iPhone language."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L10n.text("Your own little studio")) {
                    Text(L10n.text("Your photos and stickers stay on your device. No accounts, ads, or analytics. Background removal runs on your device using Apple Vision."))
                    Text(L10n.text("The photo picker shares only the images you select. Clipboard images are read only when you tap Paste."))
                }
                Section(L10n.text("Export to WhatsApp")) {
                    Text(L10n.text("Packs contain 3–30 stickers, exported as 512 × 512 WebP images. You confirm adding the pack inside WhatsApp."))
                    Text(L10n.text("Copy a single sticker and paste it into a WhatsApp chat. This does not automatically add it to favorites; you can favorite the sent sticker in WhatsApp."))
                    Text(L10n.text("Export a pack again after editing it in the app."))
                }
                Section(L10n.text("Open-source components")) {
                    Link(L10n.text("libwebp · BSD license"), destination: URL(string: "https://github.com/SDWebImage/libwebp-Xcode")!)
                    Link(L10n.text("WhatsApp sticker documentation"), destination: URL(string: "https://github.com/WhatsApp/stickers/tree/main/iOS")!)
                }
            }.navigationTitle(L10n.text("Settings")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showInfo = false } } }
        }.presentationDragIndicator(.visible)
    }
}

#Preview {
    ContentView()
}
