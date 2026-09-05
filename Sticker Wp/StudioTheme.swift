import SwiftUI

enum StudioTheme {
    static let ink = adaptive(light: UIColor(red: 0.10, green: 0.17, blue: 0.14, alpha: 1), dark: UIColor(red: 0.92, green: 0.96, blue: 0.93, alpha: 1))
    static let green = adaptive(light: UIColor(red: 0.16, green: 0.39, blue: 0.29, alpha: 1), dark: UIColor(red: 0.65, green: 0.87, blue: 0.72, alpha: 1))
    static let forest = Color(red: 0.16, green: 0.39, blue: 0.29)
    static let onLime = Color(red: 0.10, green: 0.17, blue: 0.14)
    static let lime = Color(red: 0.82, green: 0.94, blue: 0.43)
    static let paper = adaptive(light: UIColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1), dark: UIColor(red: 0.07, green: 0.09, blue: 0.08, alpha: 1))
    static let surface = adaptive(light: .white, dark: UIColor(red: 0.13, green: 0.17, blue: 0.15, alpha: 1))
    static let checker = adaptive(light: UIColor.black.withAlphaComponent(0.035), dark: UIColor.white.withAlphaComponent(0.06))

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? dark : light })
    }
}

struct PrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.headline).frame(maxWidth: .infinity).padding(.vertical, 17)
            .foregroundStyle(.white).background(StudioTheme.forest, in: RoundedRectangle(cornerRadius: 19))
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 16
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(StudioTheme.surface))
            for row in 0..<Int(ceil(size.height / step)) {
                for column in 0..<Int(ceil(size.width / step)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step, height: step)), with: .color(StudioTheme.checker))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct StickerThumbnail: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(StudioTheme.surface)
            if let image { Image(uiImage: image).resizable().scaledToFit().padding(8) }
            else { Image(systemName: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
        }.aspectRatio(1, contentMode: .fit)
    }
}

struct StudioNotice: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.footnote).foregroundStyle(StudioTheme.green)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(StudioTheme.green.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }
}
