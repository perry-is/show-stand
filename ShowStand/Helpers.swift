import SwiftUI
import CoreImage.CIFilterBuiltins
import LocalAuthentication
import PhotosUI
import UniformTypeIdentifiers
import UIKit.UIGestureRecognizerSubclass

// MARK: - QR codes

enum QRCode {
    private static let context = CIContext()
    private static var cache: [String: UIImage] = [:]

    static func image(for string: String) -> UIImage? {
        if let cached = cache[string] { return cached }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache[string] = image
        return image
    }
}

/// Black-on-white QR with a quiet zone, drawn with no interpolation so modules stay crisp.
struct QRView: View {
    let link: String
    let size: CGFloat

    var body: some View {
        let quietZone = size * 0.07
        Group {
            if let image = QRCode.image(for: link) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear
            }
        }
        .padding(quietZone)
        .frame(width: size, height: size)
        .background(Color.white, in: RoundedRectangle(cornerRadius: size * 0.05))
        .accessibilityLabel("QR code")
    }
}

// MARK: - Logo files

enum ImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    private static var directory: URL {
        let dir = URL.applicationSupportDirectory.appending(path: "Logos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downscales and writes the image (PNG keeps logo transparency; JPEG keeps photos small).
    /// Returns the filename to store on the model.
    static func save(_ image: UIImage, maxSide: CGFloat = 1024, jpeg: Bool = false) -> String? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = jpeg ? resized.jpegData(compressionQuality: 0.85) : resized.pngData() else { return nil }
        let filename = UUID().uuidString + (jpeg ? ".jpg" : ".png")
        do {
            try data.write(to: directory.appending(path: filename), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(resized, forKey: filename as NSString)
        return filename
    }

    static func load(_ filename: String?) -> UIImage? {
        guard let filename else { return nil }
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: directory.appending(path: filename).path(percentEncoded: false)) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func delete(_ filename: String?) {
        guard let filename else { return }
        cache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: directory.appending(path: filename))
    }
}

// MARK: - Validation

enum Validate {
    /// Adds `https://` when the vendor leaves the scheme off.
    static func normalizedLink(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil { return trimmed }
        return "https://" + trimmed
    }

    static func isValidLink(_ link: String) -> Bool {
        guard let url = URL(string: link),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return false }
        return true
    }

    static func isValidEmail(_ email: String) -> Bool {
        email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil
    }
}

// MARK: - Colors

extension Color {
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        guard digits.count == 6, Scanner(string: digits).scanHexInt64(&value) else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ c: CGFloat) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    /// True when black text reads better than white on top of this color.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.65
    }

    /// Black or white, whichever reads better on top of this color.
    var readableForeground: Color { isLight ? .black : .white }
}

// MARK: - Orientation lock

enum Orientation {
    static var mask: UIInterfaceOrientationMask = .all

    /// `nil` means "no preference" (setup and vendor area rotate freely).
    @MainActor static func apply(_ preference: OrientationPreference?) {
        let newMask: UIInterfaceOrientationMask
        switch preference {
        case .portrait: newMask = .portrait
        case .landscape: newMask = .landscape
        case .auto, nil: newMask = UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
        }
        guard newMask != mask else { return }
        mask = newMask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            var controller = scene.keyWindow?.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in }
        }
    }
}

// MARK: - Vendor auth

enum VendorAuth {
    enum Result { case success, failed, unavailable }

    /// False when the device has no passcode, which means leads can't be protected.
    static var isPasscodeSet: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Face ID / Touch ID with passcode fallback.
    static func authenticate() async -> Result {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            #if targetEnvironment(simulator)
            return .success // Simulators often have no passcode; real devices never take this path.
            #else
            return .unavailable
            #endif
        }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your leads") ? .success : .failed
        } catch {
            return .failed
        }
    }
}

// MARK: - Idle tracking

/// Idle timeouts. DEBUG builds use short values so they can be tested quickly.
enum Timing {
    #if DEBUG
    static let visitorFormReset: TimeInterval = 10
    static let vendorRelock: TimeInterval = 20
    #else
    static let visitorFormReset: TimeInterval = 60
    static let vendorRelock: TimeInterval = 120
    #endif
}

/// Watches every touch in the window without interfering with it, so the visitor form
/// and vendor area can tell how long the screen has been left alone.
final class ActivityTracker: UIGestureRecognizer {
    private(set) static var lastActivity = Date()

    static func touch() { lastActivity = Date() }

    static var idleSeconds: TimeInterval { Date().timeIntervalSince(lastActivity) }

    @MainActor static func install() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where !(window.gestureRecognizers ?? []).contains(where: { $0 is ActivityTracker }) {
                let tracker = ActivityTracker(target: nil, action: nil)
                tracker.cancelsTouchesInView = false
                tracker.delaysTouchesBegan = false
                tracker.delaysTouchesEnded = false
                window.addGestureRecognizer(tracker)
            }
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        Self.touch()
        state = .failed
    }
}

// MARK: - CSV export

struct LeadsCSV: Transferable {
    struct Row {
        let date: Date
        let name: String
        let email: String
        let phone: String
    }

    let boothName: String
    let rows: [Row]

    var filename: String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleaned = boothName.components(separatedBy: unsafe).joined(separator: "-")
            .trimmingCharacters(in: .whitespaces)
        return "ShowStand-\(cleaned.isEmpty ? "Booth" : cleaned)-\(Self.format(Date(), "yyyy-MM-dd")).csv"
    }

    var text: String {
        var lines = ["Date,Time,Name,Email,Phone"]
        for row in rows {
            lines.append([Self.format(row.date, "yyyy-MM-dd"), Self.format(row.date, "HH:mm"), row.name, row.email, row.phone]
                .map(Self.escape)
                .joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { csv in
            let url = FileManager.default.temporaryDirectory.appending(path: csv.filename)
            // BOM so Excel also reads it as UTF-8; Numbers and Google Sheets ignore it.
            try Data(("\u{FEFF}" + csv.text).utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

// MARK: - Shared views

/// Square logo slot backed by PhotosPicker.
struct LogoPicker: View {
    @Binding var image: UIImage?
    var size: CGFloat = 140
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $item, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(.secondarySystemBackground))
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 34))
                            Text("Add logo")
                                .font(.subheadline.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            if image != nil {
                Button("Remove logo", role: .destructive) {
                    image = nil
                    item = nil
                }
                .font(.footnote)
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    image = picked
                }
            }
        }
    }
}

struct GuidedAccessSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let steps = [
        "Open Settings → Accessibility → Guided Access and turn it on.",
        "Tap Passcode Settings → Set Guided Access Passcode. You can also allow Face ID or Touch ID to end it.",
        "Open Show Stand and go live.",
        "Triple-click the side button (or the Home button) and tap Start.",
        "To finish, triple-click again, enter your passcode, and tap End.",
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(.tint)
                            Text(step)
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Guided Access keeps visitors inside Show Stand. They can't swipe home, open other apps, or see your notifications.")
                }
            }
            .navigationTitle("Guided Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
