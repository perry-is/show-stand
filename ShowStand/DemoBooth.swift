import SwiftUI
import SwiftData

/// A fictional example booth for demos and screenshots.
///
/// Launch arguments (set them in the "ShowStand Demo" scheme, or with `simctl launch`):
/// - `-demo`         replace whatever is saved with the example booth and its sample leads
/// - `-demoForm`     open the visitor form over the display (DEBUG builds only)
/// - `-demoVendor`   open the vendor area without Face ID (DEBUG builds only)
/// - `-demoLandscape` start the example booth in landscape
/// - `-demoTheme dark` pick the theme (clean, bold or dark)
///
/// Everything here is made up: the business, the people and the example.com addresses.
/// Like the rest of the app, it makes no network calls.
enum DemoBooth {
    private static let arguments = ProcessInfo.processInfo.arguments

    static var requested: Bool { arguments.contains("-demo") }

    #if DEBUG
    static var opensForm: Bool { arguments.contains("-demoForm") }
    static var opensVendor: Bool { arguments.contains("-demoVendor") }
    #else
    static let opensForm = false
    static let opensVendor = false
    #endif

    /// Wipes saved booths and leads, then inserts the example. Only runs with `-demo`.
    @MainActor static func seedIfRequested(_ context: ModelContext) {
        guard requested else { return }
        for booth in (try? context.fetch(FetchDescriptor<Booth>())) ?? [] {
            ImageStore.delete(booth.logoFilename)
            ImageStore.delete(booth.backgroundFilename)
            context.delete(booth)
        }

        let booth = Booth(
            name: "Harbor & Pine Candle Co.",
            logoFilename: logoImage().flatMap { ImageStore.save($0) },
            primaryLink: "https://example.com/harbor-and-pine",
            offerText: "Get our free scent guide + 10% off",
            orientationPreference: arguments.contains("-demoLandscape") ? .landscape : .auto
        )
        booth.tagline = "Hand-poured soy candles from the coast"
        booth.businessType = .products
        booth.accentColor = "#C2410C"
        booth.accentOverridden = true
        booth.theme = argument(after: "-demoTheme").flatMap(BoothTheme.init(rawValue:)) ?? .dark
        booth.intakeLink = "https://example.com/harbor-and-pine/wholesale"
        booth.intakeLabel = "Wholesale inquiries"
        context.insert(booth)

        let now = Date()
        for (index, sample) in sampleLeads.enumerated() {
            let lead = Lead(name: sample.name, email: sample.email, phone: sample.phone)
            lead.createdAt = now.addingTimeInterval(-Double(index) * 23 * 60 - 7 * 60)
            lead.booth = booth
            context.insert(lead)
        }
        try? context.save()
    }

    private static func argument(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static let sampleLeads: [(name: String, email: String, phone: String?)] = [
        ("Dana Whitfield", "dana.whitfield@example.com", "(555) 014-2231"),
        ("Marcus Ortega", "marcus.o@example.com", nil),
        ("Priya Raman", "priya.raman@example.com", "(555) 019-8870"),
        ("Lee, Jordan", "jordan.lee@example.com", nil),
        ("Sofia Brennan", "sofia@example.com", "(555) 012-4409"),
        ("Theo Nakamura", "theo.nakamura@example.com", nil),
        ("Hannah Cole", "hcole@example.com", "(555) 017-3352"),
        ("Andre Baptiste", "andre.b@example.com", nil),
        ("Mia Kowalski", "mia.kowalski@example.com", nil),
    ]

    /// Draws the example logo instead of shipping an image file.
    @MainActor private static func logoImage() -> UIImage? {
        let renderer = ImageRenderer(content: DemoLogo().frame(width: 512, height: 512))
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// The fictional Harbor & Pine mark: a candle flame over a wave, in a warm circle.
private struct DemoLogo: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(hex: "#1C2B33"))
            Circle().strokeBorder(Color(hex: "#E9B872"), lineWidth: 14).padding(22)
            VStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 130, weight: .regular))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FBD38D"), Color(hex: "#C2410C")],
                                                    startPoint: .top, endPoint: .bottom))
                Image(systemName: "water.waves")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Color(hex: "#7FB7BE"))
                Text("HARBOR & PINE")
                    .font(.system(size: 30, weight: .heavy, design: .serif))
                    .tracking(2)
                    .foregroundStyle(Color(hex: "#F4EDE1"))
            }
        }
    }
}
