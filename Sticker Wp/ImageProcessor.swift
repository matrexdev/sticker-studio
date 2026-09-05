import UIKit
import Vision
import CoreImage
import ImageIO
import libwebp

struct StickerStyle {
    var scale: Double = 0.88
    var rotation: Double = 0
    var text = ""
    var textSize: Double = 48
    var textY: Double = 0.8
    var textColor: UIColor = .white
    var outline = true
}

enum ImageProcessor {
    static func renderer(size: CGSize) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    static func importImage(_ data: Data) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw StudioError.message(L10n.text("This file could not be opened as a photo.")) }
        return UIImage(cgImage: cg)
    }

    static func normalized(_ image: UIImage, maxSide: CGFloat = 1600) -> UIImage {
        let ratio = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: max(1, image.size.width * ratio), height: max(1, image.size.height * ratio))
        return renderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    static func render(_ image: UIImage, style: StickerStyle, side: CGFloat = 512) -> UIImage {
        renderer(size: CGSize(width: side, height: side)).image { context in
            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: side / 2, y: side / 2)
            cg.rotate(by: style.rotation * .pi / 180)
            let ratio = side * style.scale / max(image.size.width, image.size.height)
            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            image.draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            cg.restoreGState()
            let text = style.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                paragraph.lineBreakMode = .byWordWrapping
                let font = UIFont.systemFont(ofSize: style.textSize * side / 512, weight: .heavy)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: style.textColor,
                    .strokeColor: UIColor.black, .strokeWidth: style.outline ? -5.0 : 0.0,
                    .paragraphStyle: paragraph
                ]
                let width = side - 32 * side / 512
                let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: side), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
                let height = min(side, ceil(bounds.height))
                let y = max(0, min(side - height, side * style.textY - height / 2))
                (text as NSString).draw(in: CGRect(x: (side - width) / 2, y: y, width: width, height: height), withAttributes: attributes)
            }
        }
    }

    static func removeBackground(from data: Data) throws -> Data {
        guard let image = CIImage(data: data) else { throw StudioError.message(L10n.text("Could not process the photo.")) }
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw StudioError.message(L10n.text("No clear subject found. Try a clearer photo or use the crop tool."))
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
        let output = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(output, from: output.extent), let data = UIImage(cgImage: cg).pngData() else {
            throw StudioError.message(L10n.text("Could not remove the background. Please try again."))
        }
        return data
    }

    static func crop(_ image: UIImage, zoom: CGFloat, offset: CGSize) -> UIImage {
        let side: CGFloat = 1200
        let ratio = side / min(image.size.width, image.size.height) * zoom
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return renderer(size: CGSize(width: side, height: side)).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2 + offset.width * side,
                                  y: (side - size.height) / 2 + offset.height * side,
                                  width: size.width, height: size.height))
        }
    }

    static func webP(from image: UIImage) throws -> Data {
        guard let cg = image.cgImage, cg.width == 512, cg.height == 512 else {
            throw StudioError.message(L10n.text("WhatsApp stickers must be 512 × 512 pixels."))
        }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw StudioError.message(L10n.text("Could not allocate image memory for WebP.")) }
        // libwebp expects straight alpha; CGContext supplies premultiplied alpha.
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[i + 3])
            if alpha > 0 && alpha < 255 {
                for channel in 0..<3 { pixels[i + channel] = UInt8(min(255, (Int(pixels[i + channel]) * 255 + alpha / 2) / alpha)) }
            }
        }
        for quality: Float in [95, 85, 75, 60, 45, 30, 15, 5] {
            var output: UnsafeMutablePointer<UInt8>?
            let count = pixels.withUnsafeBufferPointer {
                WebPEncodeRGBA($0.baseAddress, Int32(width), Int32(height), Int32(width * 4), quality, &output)
            }
            guard count > 0, let output else { throw StudioError.message(L10n.text("Could not create the WebP file.")) }
            let data = Data(bytes: output, count: count)
            WebPFree(output)
            if data.count <= 100 * 1024 { return data }
        }
        throw StudioError.message(L10n.text("This image could not fit within 100 KB. Simplify it and try again."))
    }
}
