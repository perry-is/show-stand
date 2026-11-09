import Foundation
import SwiftData

enum OrientationPreference: String, Codable, CaseIterable, Identifiable {
    case auto, portrait, landscape
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum BusinessType: String, Codable, CaseIterable, Identifiable {
    case products, services, coaching, food, artsCrafts, events
    var id: String { rawValue }

    var label: String {
        switch self {
        case .products: "Products"
        case .services: "Services"
        case .coaching: "Coaching"
        case .food: "Food"
        case .artsCrafts: "Art & Crafts"
        case .events: "Events"
        }
    }

    var symbol: String {
        switch self {
        case .products: "shippingbox"
        case .services: "wrench.and.screwdriver"
        case .coaching: "person.2"
        case .food: "fork.knife"
        case .artsCrafts: "paintpalette"
        case .events: "ticket"
        }
    }
}

enum BoothTheme: String, Codable, CaseIterable, Identifiable {
    case clean, bold, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Where the primary QR sits, as fractions of the display area:
/// `x`/`y` is the card's center (fraction of width/height), `size` is the QR's
/// width as a fraction of the shorter side.
struct QRPlacement: Equatable {
    var x: Double
    var y: Double
    var size: Double
}

@Model
final class Booth {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var logoFilename: String?
    var tagline: String?
    var primaryLink: String = ""
    var intakeLink: String?
    var intakeLabel: String = "Book a deeper conversation"
    /// Empty means "no offer": the display hides it and the button says "Stay in touch".
    var offerText: String = ""
    var accentColor: String = "#1F6FEB"
    /// True once the vendor picks an accent by hand, so a new logo won't replace it.
    var accentOverridden: Bool = false
    var orientationPreference: OrientationPreference = OrientationPreference.auto
    var businessType: BusinessType?
    /// Stored as a plain string: a new non-optional enum column can't be filled in for
    /// booths saved by earlier versions, and SwiftData crashes reading it.
    var themeRaw: String = BoothTheme.clean.rawValue
    var backgroundFilename: String?
    var backgroundFills: Bool = true
    var backgroundDim: Double = 0.35
    // QR placement per orientation; nil means the default layout.
    var qrPortraitX: Double?
    var qrPortraitY: Double?
    var qrPortraitSize: Double?
    var qrLandscapeX: Double?
    var qrLandscapeY: Double?
    var qrLandscapeSize: Double?
    @Relationship(deleteRule: .cascade, inverse: \Lead.booth) var leads: [Lead] = []

    init(name: String, logoFilename: String?, primaryLink: String, offerText: String, orientationPreference: OrientationPreference) {
        self.name = name
        self.logoFilename = logoFilename
        self.primaryLink = primaryLink
        self.offerText = offerText
        self.orientationPreference = orientationPreference
    }

    var theme: BoothTheme {
        get { BoothTheme(rawValue: themeRaw) ?? .clean }
        set { themeRaw = newValue.rawValue }
    }

    var qrPortrait: QRPlacement? {
        get {
            guard let x = qrPortraitX, let y = qrPortraitY, let size = qrPortraitSize else { return nil }
            return QRPlacement(x: x, y: y, size: size)
        }
        set {
            qrPortraitX = newValue?.x
            qrPortraitY = newValue?.y
            qrPortraitSize = newValue?.size
        }
    }

    var qrLandscape: QRPlacement? {
        get {
            guard let x = qrLandscapeX, let y = qrLandscapeY, let size = qrLandscapeSize else { return nil }
            return QRPlacement(x: x, y: y, size: size)
        }
        set {
            qrLandscapeX = newValue?.x
            qrLandscapeY = newValue?.y
            qrLandscapeSize = newValue?.size
        }
    }
}

@Model
final class Lead {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var name: String = ""
    var email: String = ""
    var phone: String?
    var booth: Booth?

    init(name: String, email: String, phone: String?) {
        self.name = name
        self.email = email
        self.phone = phone
    }
}
