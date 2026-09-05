import SwiftUI

struct EditState {
    var image: UIImage
    var style = StickerStyle()
}

struct EditableSticker: Identifiable {
    let id = UUID()
    let original: UIImage
    var state: EditState
    var history: [EditState] = []
}

struct StickerEditorView: View {
    @AppStorage("appLanguage") private var language = "en"
    let session: EditingSession
    let library: StickerLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var items: [EditableSticker]
    @State private var index = 0
    @State private var tool = 0
    @State private var busy = false
    @State private var showCrop = false
    @State private var showSave = false
    @State private var confirmDiscard = false
    @State private var error: String?
    @State private var background = 0

    init(session: EditingSession, library: StickerLibrary) {
        self.session = session
        self.library = library
        _items = State(initialValue: session.images.map { EditableSticker(original: $0, state: EditState(image: $0)) })
    }

    private var rendered: UIImage { ImageProcessor.render(items[index].state.image, style: items[index].state.style) }

    var body: some View {
        let _ = language
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HStack {
                        Text(L10n.text("MAKE IT YOURS")).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(1.5)
                        Spacer()
                        Text("\(index + 1) / \(items.count)").font(.subheadline.monospacedDigit())
                    }.foregroundStyle(StudioTheme.green)
                    ZStack {
                        if background == 0 { Checkerboard() }
                        else { (background == 1 ? Color(red: 0.12, green: 0.16, blue: 0.14) : Color(red: 0.91, green: 0.84, blue: 0.98)) }
                        Image(uiImage: rendered).resizable().scaledToFit().padding(12)
                        if busy { ProgressView(L10n.text("Removing background…")).padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) }
                    }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(StudioTheme.green.opacity(0.08)))
                        .accessibilityLabel(L10n.text("Sticker preview"))
                    HStack(spacing: 10) {
                        Label(L10n.text("512 × 512 · Transparent canvas"), systemImage: "square.dashed").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button { background = (background + 1) % 3 } label: { Image(systemName: "circle.lefthalf.filled").padding(8) }
                            .accessibilityLabel(L10n.text("Change preview background"))
                        Button {
                            if let previous = items[index].history.popLast() { items[index].state = previous }
                        } label: { Image(systemName: "arrow.uturn.backward").padding(8) }
                            .disabled(items[index].history.isEmpty || busy).accessibilityLabel(L10n.text("Undo"))
                    }
                    if items.count > 1 {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                                    Button { index = position } label: {
                                        StickerThumbnail(image: ImageProcessor.render(item.state.image, style: item.state.style))
                                            .frame(width: 62, height: 62)
                                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(position == index ? StudioTheme.green : .clear, lineWidth: 2))
                                    }.accessibilityLabel(L10n.text("Edit photo %d", position + 1))
                                }
                            }.padding(3)
                        }.disabled(busy)
                    }
                    tools
                    toolControls
                }.padding(22).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(StudioTheme.paper)
                .navigationTitle(L10n.text("Edit")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { confirmDiscard = true }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { showSave = true }.fontWeight(.bold).disabled(busy) }
                }
                .safeAreaInset(edge: .bottom) {
                    Button { showSave = true } label: {
                        Label(items.count > 1 ? L10n.text("Finish %d stickers", items.count) : L10n.text("Finish sticker"), systemImage: "checkmark")
                            .modifier(PrimaryButton())
                    }.disabled(busy).padding(.horizontal, 22).padding(.vertical, 10).background(StudioTheme.paper)
                }
                .sheet(isPresented: $showCrop) {
                    CropView(image: items[index].state.image) { cropped in
                        remember()
                        items[index].state.image = cropped
                    }
                }
                .sheet(isPresented: $showSave) {
                    SaveStickersView(library: library,
                        images: items.map { ImageProcessor.render($0.state.image, style: $0.state.style) },
                        captions: items.map { $0.state.style.text }, initialPackID: session.targetPackID) { dismiss() }
                }
                .confirmationDialog(L10n.text("Discard your unsaved edits?"), isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button(L10n.text("Discard edits"), role: .destructive) { dismiss() }
                    Button(L10n.text("Keep editing"), role: .cancel) { }
                }
                .alert(L10n.text("Could not complete the action"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(L10n.text("OK"), role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }.tint(StudioTheme.green).modifier(AppearancePreference()).interactiveDismissDisabled()
    }

    private var tools: some View {
        HStack(spacing: 8) {
            toolButton(L10n.text("Crop"), icon: "crop", selected: false) { showCrop = true }
            toolButton(L10n.text("Background"), icon: "wand.and.stars", selected: tool == 0) { tool = 0 }
            toolButton(L10n.text("Text"), icon: "textformat", selected: tool == 1) { remember(); tool = 1 }
            toolButton(L10n.text("Size"), icon: "arrow.up.left.and.arrow.down.right", selected: tool == 2) { tool = 2 }
        }.disabled(busy)
    }

    private func toolButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) { Image(systemName: icon).font(.title3); Text(title).font(.caption.weight(.semibold)) }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .foregroundStyle(selected ? .white : StudioTheme.green)
                .background(selected ? StudioTheme.forest : StudioTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var toolControls: some View {
        if tool == 0 {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("Keep the main character.")).font(.headline)
                Text(L10n.text("Automatically isolate the subjects and make the background transparent.")).font(.subheadline).foregroundStyle(.secondary)
                Button { removeBackground() } label: {
                    Label(L10n.text("Remove background"), systemImage: "wand.and.stars").font(.headline).frame(maxWidth: .infinity).padding(14)
                        .foregroundStyle(StudioTheme.onLime).background(StudioTheme.lime, in: RoundedRectangle(cornerRadius: 14))
                }.disabled(busy)
                Button(L10n.text("Reset to original")) { remember(); items[index].state = EditState(image: items[index].original) }
                    .font(.subheadline).frame(maxWidth: .infinity).disabled(busy)
            }.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        } else if tool == 1 {
            VStack(alignment: .leading, spacing: 14) {
                TextField(L10n.text("For example: me right now"), text: $items[index].state.style.text, axis: .vertical)
                    .lineLimit(1...3).textFieldStyle(.roundedBorder)
                    .onChange(of: items[index].state.style.text) { _, value in
                        if value.count > 100 { items[index].state.style.text = String(value.prefix(100)) }
                    }
                slider(L10n.text("Text size"), value: $items[index].state.style.textSize, range: 20...90)
                slider(L10n.text("Text position"), value: $items[index].state.style.textY, range: 0.08...0.92)
                HStack {
                    ColorPicker(L10n.text("Text color"), selection: Binding(get: { Color(uiColor: items[index].state.style.textColor) }, set: { items[index].state.style.textColor = UIColor($0) }), supportsOpacity: false)
                    Toggle(L10n.text("Outline"), isOn: $items[index].state.style.outline).fixedSize()
                }.font(.subheadline)
            }.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        } else {
            VStack(alignment: .leading, spacing: 16) {
                slider(L10n.text("Image size"), value: $items[index].state.style.scale, range: 0.25...1.4)
                slider(L10n.text("Rotate"), value: $items[index].state.style.rotation, range: -180...180)
                Text(L10n.text("The canvas stays at 512 × 512. Scale the image to fit; anything outside the canvas is cropped.")).font(.caption).foregroundStyle(.secondary)
            }.padding(18).background(StudioTheme.surface, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium))
            Slider(value: value, in: range, onEditingChanged: { editing in if editing { remember() } }).accessibilityLabel(title)
        }
    }

    private func remember() {
        items[index].history.append(items[index].state)
        if items[index].history.count > 12 { items[index].history.removeFirst() }
    }

    private func removeBackground() {
        guard let data = items[index].state.image.pngData() else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) { try ImageProcessor.removeBackground(from: data) }.value
                guard let image = UIImage(data: result) else { throw StudioError.message(L10n.text("Could not open the processed image.")) }
                remember()
                items[index].state.image = image
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct CropView: View {
    @AppStorage("appLanguage") private var language = "en"
    let image: UIImage
    let onCrop: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var dragOrigin = CGSize.zero

    var body: some View {
        let _ = language
        NavigationStack {
            VStack(spacing: 24) {
                Text(L10n.text("Drag the frame and zoom in on what matters.")).font(.subheadline).foregroundStyle(.secondary)
                GeometryReader { geometry in
                    let side = geometry.size.width
                    let ratio = side / min(image.size.width, image.size.height) * zoom
                    ZStack {
                        Color.black
                        Image(uiImage: image).resizable()
                            .frame(width: image.size.width * ratio, height: image.size.height * ratio)
                            .offset(x: offset.width * side, y: offset.height * side)
                        Path { path in
                            for fraction in [CGFloat(1.0 / 3), CGFloat(2.0 / 3)] {
                                path.move(to: CGPoint(x: side * fraction, y: 0)); path.addLine(to: CGPoint(x: side * fraction, y: side))
                                path.move(to: CGPoint(x: 0, y: side * fraction)); path.addLine(to: CGPoint(x: side, y: side * fraction))
                            }
                        }.stroke(.white.opacity(0.5), lineWidth: 1)
                    }.frame(width: side, height: side).clipped().contentShape(Rectangle())
                        .gesture(DragGesture().onChanged { value in
                            offset = clamp(CGSize(width: dragOrigin.width + value.translation.width / side, height: dragOrigin.height + value.translation.height / side))
                        }.onEnded { _ in dragOrigin = offset })
                }.aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 22))
                HStack { Image(systemName: "minus.magnifyingglass"); Slider(value: $zoom, in: 1...4); Image(systemName: "plus.magnifyingglass") }
                    .accessibilityLabel(L10n.text("Crop zoom"))
                    .onChange(of: zoom) { _, _ in offset = clamp(offset); dragOrigin = offset }
                Button(L10n.text("Reset crop")) { zoom = 1; offset = .zero; dragOrigin = .zero }
                Spacer()
            }.padding(24).background(StudioTheme.paper)
                .navigationTitle(L10n.text("Crop")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n.text("Apply")) { onCrop(ImageProcessor.crop(image, zoom: zoom, offset: offset)); dismiss() }
                    }
                }
        }.tint(StudioTheme.green)
    }

    private func clamp(_ value: CGSize) -> CGSize {
        let short = min(image.size.width, image.size.height)
        let x = max(0, (image.size.width / short * zoom - 1) / 2)
        let y = max(0, (image.size.height / short * zoom - 1) / 2)
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
}

struct SaveStickersView: View {
    @AppStorage("appLanguage") private var language = "en"
    let library: StickerLibrary
    let images: [UIImage]
    let captions: [String]
    let onFinished: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var destination: String
    @State private var name = ""
    @State private var saving = false
    @State private var saved = false
    @State private var savedPackID: UUID?
    @State private var error: String?
    @State private var status: String?

    init(library: StickerLibrary, images: [UIImage], captions: [String], initialPackID: UUID?, onFinished: @escaping () -> Void) {
        self.library = library; self.images = images; self.captions = captions; self.onFinished = onFinished
        _destination = State(initialValue: initialPackID?.uuidString ?? (images.count == 1 ? "loose" : "new"))
    }

    var body: some View {
        let _ = language
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(saved ? L10n.text("Ready. Unmistakably you.") : (images.count == 1 ? L10n.text("Where should it go?") : L10n.text("Your next favorite pack."))).font(.system(size: 30, weight: .bold, design: .rounded))
                    ScrollView(.horizontal) {
                        HStack { ForEach(images.indices, id: \.self) { i in StickerThumbnail(image: images[i]).frame(width: 90) } }
                    }
                    if !saved {
                        Text(images.count == 1 ? L10n.text("Save it on its own or add it to a pack.") : L10n.text("Bring these stickers together in a new or existing pack.")).foregroundStyle(.secondary)
                        Picker(L10n.text("Save destination"), selection: $destination) {
                            if images.count == 1 { Text(L10n.text("Save without a pack")).tag("loose") }
                            Text(L10n.text("Create a new pack")).tag("new")
                            ForEach(library.packs.filter { $0.stickerIDs.count + images.count <= 30 }) { pack in
                                Text("\(pack.name) (\(pack.stickerIDs.count)/30)").tag(pack.id.uuidString)
                            }
                        }.pickerStyle(.menu)
                        if destination == "new" {
                            TextField(L10n.text("Pack name"), text: $name).textFieldStyle(.roundedBorder)
                                .onChange(of: name) { _, value in if value.count > 128 { name = String(value.prefix(128)) } }
                        }
                        if images.count < 3 && destination == "new" {
                            StudioNotice(text: L10n.text("Save the pack now. You need at least 3 stickers to export it to WhatsApp."))
                        }
                        Button { save() } label: { Text(L10n.text("Save")).modifier(PrimaryButton()) }
                            .disabled(saving || (destination == "new" && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                    } else {
                        Label(L10n.text("Saved to your collection"), systemImage: "checkmark.circle.fill").foregroundStyle(StudioTheme.green)
                        if let id = savedPackID, let pack = library.packs.first(where: { $0.id == id }) {
                            StudioNotice(text: pack.stickerIDs.count >= 3 ? L10n.text("Tap Add in the WhatsApp preview. The final confirmation happens in WhatsApp.") : L10n.text("Your draft pack is saved. Add %d more stickers to export it.", 3 - pack.stickerIDs.count))
                            if pack.stickerIDs.count >= 3 {
                                Button { export(pack) } label: { Label(L10n.text("Add to WhatsApp"), systemImage: "arrow.up.forward.app").modifier(PrimaryButton()) }.disabled(saving)
                            }
                        } else if let image = images.first {
                            StudioNotice(text: L10n.text("Open a WhatsApp chat and paste into the message field. After sending, tap the sticker to add it to favorites."))
                            Button {
                                Task { do { try await WhatsAppExporter.copy(image, openWhatsApp: true) } catch { self.error = error.localizedDescription } }
                            } label: { Label(L10n.text("Copy and open WhatsApp"), systemImage: "arrow.up.forward.app").modifier(PrimaryButton()) }
                        }
                        if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                        Button(L10n.text("Back to studio")) { onFinished() }.font(.headline).frame(maxWidth: .infinity)
                    }
                    if saving { ProgressView(L10n.text("Preparing…")).frame(maxWidth: .infinity) }
                }.padding(24)
            }.background(StudioTheme.paper).navigationTitle(L10n.text("Finish")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(saved ? L10n.text("Close") : L10n.text("Back")) { if saved { onFinished() } else { dismiss() } }.disabled(saving) } }
                .alert(L10n.text("Notice"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                    Button(L10n.text("OK"), role: .cancel) { error = nil }
                } message: { Text(error ?? "") }
        }.tint(StudioTheme.green).interactiveDismissDisabled(saved || saving)
    }

    private func save() {
        saving = true
        do {
            savedPackID = try library.save(images: images, captions: captions, packID: UUID(uuidString: destination), newPackName: destination == "new" ? name : nil)
            saved = true
        } catch { self.error = error.localizedDescription }
        saving = false
    }

    private func export(_ pack: StickerPack) {
        saving = true
        Task {
            defer { saving = false }
            do { try await WhatsAppExporter.send(pack: pack, library: library); status = L10n.text("WhatsApp opened. Finish adding your pack there.") }
            catch { self.error = error.localizedDescription }
        }
    }
}

#Preview("Editor") {
    let image = ImageProcessor.renderer(size: CGSize(width: 512, height: 512)).image { _ in
        ("🥑" as NSString).draw(at: CGPoint(x: 36, y: 16), withAttributes: [.font: UIFont.systemFont(ofSize: 380)])
    }
    StickerEditorView(session: EditingSession(images: [image, image, image]),
                      library: StickerLibrary(directory: FileManager.default.temporaryDirectory.appendingPathComponent("EditorPreview")))
}
