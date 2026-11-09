import SwiftUI
import CoreImage

/// Everything the display needs to draw a booth, as plain values. The live display builds
/// it from the saved `Booth`; setup and Edit Booth build it from unsaved edits so the
/// layout editor previews exactly what visitors will see.
struct BoothLook {
    var name: String
    var tagline: String?
    var logo: UIImage?
    var offerText: String
    var primaryLink: String
    var intakeLink: String?
    var intakeLabel: String
    var accentHex: String
    var theme: BoothTheme
    var background: UIImage?
    var backgroundFills: Bool
    var backgroundDim: Double

    var hasOffer: Bool { !offerText.trimmingCharacters(in: .whitespaces).isEmpty }
    var buttonTitle: String { hasOffer ? "Leave your info" : "Stay in touch" }
    var accent: Color { Color(hex: accentHex) }
    var palette: ThemePalette { ThemePalette(theme: theme, accent: accent) }
}

extension Booth {
    var look: BoothLook {
        BoothLook(
            name: name,
            tagline: tagline,
            logo: ImageStore.load(logoFilename),
            offerText: offerText,
            primaryLink: primaryLink,
            intakeLink: (intakeLink?.isEmpty ?? true) ? nil : intakeLink,
            intakeLabel: intakeLabel,
            accentHex: accentColor,
            theme: theme,
            background: ImageStore.load(backgroundFilename),
            backgroundFills: backgroundFills,
            backgroundDim: backgroundDim
        )
    }
}

// MARK: - Themes

struct ThemePalette {
    let background: Color
    let text: Color
    let secondary: Color
    let offer: Color
    let buttonFill: Color
    let buttonText: Color
    let scheme: ColorScheme

    init(theme: BoothTheme, accent: Color) {
        switch theme {
        case .clean:
            background = .white
            text = .black
            secondary = Color(white: 0.4)
            offer = accent
            buttonFill = accent
            buttonText = accent.readableForeground
            scheme = .light
        case .bold:
            let foreground = accent.readableForeground
            background = accent
            text = foreground
            secondary = foreground.opacity(0.75)
            offer = foreground
            buttonFill = foreground
            buttonText = accent
            scheme = accent.isLight ? .light : .dark
        case .dark:
            background = Color(white: 0.06)
            text = .white
            secondary = Color(white: 0.65)
            offer = accent
            buttonFill = accent
            buttonText = accent.readableForeground
            scheme = .dark
        }
    }
}

// MARK: - Physical size

enum DeviceScreen {
    /// Estimated points per inch. iOS doesn't expose screen density, so this uses the device
    /// class and screen size: 3x iPhones ≈ 460 ppi (153 pt/in), 2x iPhones and iPad mini
    /// ≈ 326 ppi (163 pt/in), other iPads ≈ 264 ppi (132 pt/in).
    static var pointsPerInch: CGFloat {
        let screen = UIScreen.main
        let shortSide = min(screen.bounds.width, screen.bounds.height)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return shortSide <= 744 ? 163 : 132
        }
        return screen.scale >= 3 ? 153 : 163
    }

    /// Rule of thumb: a QR scans from about 10× its width.
    static func scanFeet(qrWidth: CGFloat, pointsPerInch: CGFloat = pointsPerInch) -> Double {
        Double(qrWidth / pointsPerInch * 10 / 12)
    }
}

// MARK: - Display geometry

/// Fixed positions (button, lock), QR size limits, the default QR spot, and the rules that
/// keep a moved QR on screen and clear of the button and lock. All in the display's points.
struct CanvasGeometry {
    let size: CGSize
    let wide: Bool
    let hasIntake: Bool
    var pointsPerInch: CGFloat = DeviceScreen.pointsPerInch

    static let spacing: CGFloat = 14
    static let buttonHeight: CGFloat = 58
    static let intakeRowHeight: CGFloat = 88
    /// Keep the QR card this far from the screen edges and from the button and lock.
    static let inset: CGFloat = 8
    static let snapDistance: CGFloat = 10

    var padding: CGFloat { wide ? min(48, size.height * 0.06) : 24 }
    var shortSide: CGFloat { min(size.width, size.height) }

    /// Space under the button: enough that the corner lock never sits underneath it.
    var buttonBottomInset: CGFloat { max(padding, lockRect.height + 6) }

    var buttonRect: CGRect {
        let h = Self.buttonHeight
        let y = size.height - buttonBottomInset - h
        if wide {
            let w = min(360, size.width * 0.38)
            return CGRect(x: size.width - padding - w, y: y, width: w, height: h)
        }
        let w = min(size.width - padding * 2, 420)
        return CGRect(x: (size.width - w) / 2, y: y, width: w, height: h)
    }

    var lockRect: CGRect { CGRect(x: size.width - 44, y: size.height - 44, width: 44, height: 44) }

    // MARK: QR card metrics (the QR plus its white card and caption)

    static func cardPadding(_ qr: CGFloat) -> CGFloat { max(16, qr * 0.07) }
    static func captionFontSize(_ qr: CGFloat) -> CGFloat { min(17, max(11, qr * 0.06)) }
    static func captionHeight(_ qr: CGFloat) -> CGFloat { (captionFontSize(qr) * 1.3).rounded(.up) + 6 }
    static func cardSize(_ qr: CGFloat) -> CGSize {
        let pad = cardPadding(qr)
        return CGSize(width: qr + pad * 2, height: qr + captionHeight(qr) + pad * 2)
    }

    /// Largest QR whose card fits in `box`.
    static func largestQR(fitting box: CGSize) -> CGFloat {
        var low: CGFloat = 0, high = max(box.width, box.height)
        for _ in 0..<24 {
            let mid = (low + high) / 2
            let card = cardSize(mid)
            if card.width <= box.width && card.height <= box.height { low = mid } else { high = mid }
        }
        return low.rounded(.down)
    }

    /// The card must fit across the screen and above the button.
    var maxQR: CGFloat {
        Self.largestQR(fitting: CGSize(width: size.width - Self.inset * 2,
                                       height: buttonRect.minY - Self.spacing - Self.inset))
    }

    /// About a 1 ft scan distance (1.2 in wide), unless the screen can't fit that.
    var minQR: CGFloat { min(1.2 * pointsPerInch, maxQR) }

    func scanFeet(_ qr: CGFloat) -> Double { DeviceScreen.scanFeet(qrWidth: qr, pointsPerInch: pointsPerInch) }

    // MARK: Default spot

    /// Phone portrait: centered above the button (and the intake row, if any).
    /// Wide: right column, just above the button.
    var defaultCard: (center: CGPoint, qr: CGFloat) {
        if wide {
            let bottom = buttonRect.minY - Self.spacing
            let ideal = min(size.width * 0.42,
                            Self.largestQR(fitting: CGSize(width: size.width * 0.45, height: bottom - padding)))
            let qr = min(max(ideal, minQR), maxQR)
            let card = Self.cardSize(qr)
            return (CGPoint(x: size.width - padding - card.width / 2, y: bottom - card.height / 2), qr)
        }
        let intakeBlock = hasIntake ? Self.intakeRowHeight + Self.spacing : 0
        let bottom = buttonRect.minY - Self.spacing - intakeBlock
        // Leave roughly 230 pt above for the brand and offer.
        let ideal = min(size.width * 0.72,
                        Self.largestQR(fitting: CGSize(width: size.width - padding * 2, height: bottom - padding - 230)))
        let qr = min(max(ideal, minQR), maxQR)
        let card = Self.cardSize(qr)
        return (CGPoint(x: size.width / 2, y: bottom - card.height / 2), qr)
    }

    // MARK: Converting and constraining

    func card(for placement: QRPlacement?) -> (center: CGPoint, qr: CGFloat) {
        guard let placement else { return defaultCard }
        return resolve(center: CGPoint(x: placement.x * size.width, y: placement.y * size.height),
                       qr: placement.size * shortSide)
    }

    func placement(center: CGPoint, qr: CGFloat) -> QRPlacement {
        QRPlacement(x: center.x / size.width, y: center.y / size.height, size: qr / shortSide)
    }

    static func cardRect(center: CGPoint, qr: CGFloat) -> CGRect {
        let card = cardSize(qr)
        return CGRect(x: center.x - card.width / 2, y: center.y - card.height / 2, width: card.width, height: card.height)
    }

    /// Clamps size to [minQR, maxQR], keeps the card on screen, and lifts it above the
    /// button and lock if it would cover them (both sit at the bottom, so up is always free).
    func resolve(center: CGPoint, qr proposed: CGFloat) -> (center: CGPoint, qr: CGFloat) {
        let qr = min(max(proposed, minQR), maxQR)
        let card = Self.cardSize(qr)
        let inset = Self.inset
        var c = center
        c.x = min(max(c.x, inset + card.width / 2), size.width - inset - card.width / 2)
        c.y = min(max(c.y, inset + card.height / 2), size.height - inset - card.height / 2)
        for zone in [buttonRect, lockRect].map({ $0.insetBy(dx: -inset, dy: -inset) }) {
            if Self.cardRect(center: c, qr: qr).intersects(zone) {
                c.y = zone.minY - card.height / 2
            }
        }
        return (c, qr)
    }

    // MARK: Snapping

    struct Guide: Hashable {
        let vertical: Bool
        let position: CGFloat
    }

    /// Snaps the card's center to the center line and thirds, or its edges to the screen
    /// edges, when within `snapDistance`. Returns the guides to draw.
    func snap(center: CGPoint, qr: CGFloat) -> (center: CGPoint, guides: [Guide]) {
        let card = Self.cardSize(qr)
        let inset = Self.inset
        var result = center
        var guides: [Guide] = []

        // (target value for the card center, line to draw)
        let xTargets: [(CGFloat, CGFloat)] = [
            (size.width / 2, size.width / 2),
            (size.width / 3, size.width / 3),
            (size.width * 2 / 3, size.width * 2 / 3),
            (inset + card.width / 2, inset),
            (size.width - inset - card.width / 2, size.width - inset),
        ]
        let yTargets: [(CGFloat, CGFloat)] = [
            (size.height / 2, size.height / 2),
            (size.height / 3, size.height / 3),
            (size.height * 2 / 3, size.height * 2 / 3),
            (inset + card.height / 2, inset),
            (size.height - inset - card.height / 2, size.height - inset),
        ]
        if let best = xTargets.min(by: { abs($0.0 - center.x) < abs($1.0 - center.x) }),
           abs(best.0 - center.x) <= Self.snapDistance {
            result.x = best.0
            guides.append(Guide(vertical: true, position: best.1))
        }
        if let best = yTargets.min(by: { abs($0.0 - center.y) < abs($1.0 - center.y) }),
           abs(best.0 - center.y) <= Self.snapDistance {
            result.y = best.0
            guides.append(Guide(vertical: false, position: best.1))
        }
        return (result, guides)
    }
}

// MARK: - Logo color

enum LogoColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    /// The most common clearly colored pixel group in the logo, as a hex string.
    /// Ignores transparent, near-white, near-black, and gray pixels; nil if nothing is left.
    static func dominantHex(in image: UIImage) -> String? {
        guard let input = CIImage(image: image) else { return nil }
        let side: CGFloat = 48
        let scale = side / max(input.extent.width, input.extent.height)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let width = Int(small.extent.width.rounded(.up)), height = Int(small.extent.height.rounded(.up))
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        context.render(small, toBitmap: &pixels, rowBytes: width * 4,
                       bounds: CGRect(x: small.extent.minX, y: small.extent.minY, width: CGFloat(width), height: CGFloat(height)),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        // Bucket by 3 bits per channel; remember sums to average each bucket.
        var counts = [Int](repeating: 0, count: 512)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 512)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3])
            guard a > 128 else { continue }
            // Rendered pixels are premultiplied.
            let r = Double(pixels[i]) / a, g = Double(pixels[i + 1]) / a, b = Double(pixels[i + 2]) / a
            let maxC = max(r, g, b), minC = min(r, g, b)
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC
            guard saturation > 0.25, maxC > 0.15, maxC < 0.99 || saturation > 0.4 else { continue }
            let key = (Int(min(r, 1) * 7.99) << 6) | (Int(min(g, 1) * 7.99) << 3) | Int(min(b, 1) * 7.99)
            counts[key] += 1
            sums[key].0 += r; sums[key].1 += g; sums[key].2 += b
        }
        guard let best = counts.indices.max(by: { counts[$0] < counts[$1] }), counts[best] > 0 else { return nil }
        let n = Double(counts[best])
        func byte(_ v: Double) -> Int { Int((min(max(v / n, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(sums[best].0), byte(sums[best].1), byte(sums[best].2))
    }
}
