import SwiftUI
import SwiftData

/// First launch: five steps, one job each, then Go Live creates the booth.
struct SetupFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var step = 0
    @State private var logo: UIImage?
    @State private var name = ""
    @State private var businessType: BusinessType?
    @State private var link = ""
    @State private var offer = ""
    @State private var orientation: OrientationPreference = .auto
    @State private var theme: BoothTheme = .clean
    @State private var accentHex = "#1F6FEB"
    @State private var accentOverridden = false
    @State private var portraitQR: QRPlacement?
    @State private var landscapeQR: QRPlacement?
    @State private var showGuidedAccess = false
    @State private var showLayoutEditor = false
    @State private var passcodeSet = true
    @FocusState private var fieldFocused: Bool

    private let stepCount = 5

    private var normalizedLink: String { Validate.normalizedLink(link) }

    private var canContinue: Bool {
        switch step {
        case 0: !name.trimmingCharacters(in: .whitespaces).isEmpty
        case 1: businessType != nil
        case 2: Validate.isValidLink(normalizedLink)
        case 3: !offer.trimmingCharacters(in: .whitespaces).isEmpty
        default: true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                Group {
                    switch step {
                    case 0: logoStep
                    case 1: businessTypeStep
                    case 2: linkStep
                    case 3: offerStep
                    default: goLiveStep
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .id(step)
                .transition(.opacity)
            }
            .scrollDismissesKeyboard(.interactively)

            Button(action: advance) {
                Text(step == stepCount - 1 ? "Go Live" : "Continue")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .disabled(!canContinue)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: 560)
        }
        .sheet(isPresented: $showGuidedAccess) { GuidedAccessSheet() }
        .fullScreenCover(isPresented: $showLayoutEditor) {
            LayoutEditorView(look: draftLook, orientation: orientation,
                             portraitQR: $portraitQR, landscapeQR: $landscapeQR)
        }
        .onChange(of: logo) { _, newLogo in
            // The logo's main color becomes the accent unless they've picked one.
            guard !accentOverridden else { return }
            accentHex = newLogo.flatMap(LogoColor.dominantHex) ?? "#1F6FEB"
        }
        .onAppear { passcodeSet = VendorAuth.isPasscodeSet }
        .onChange(of: scenePhase) { _, phase in
            // Re-check when they come back from Settings.
            if phase == .active { passcodeSet = VendorAuth.isPasscodeSet }
        }
    }

    private var header: some View {
        HStack {
            Button {
                withAnimation { step -= 1 }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .opacity(step > 0 ? 1 : 0)
            .disabled(step == 0)
            Spacer()
            HStack(spacing: 8) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.accentColor : Color(.tertiarySystemFill))
                        .frame(width: index == step ? 22 : 8, height: 8)
                }
            }
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")
            Spacer()
            Label("Back", systemImage: "chevron.left").hidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func advance() {
        guard canContinue else { return }
        if step == 2 { link = normalizedLink }
        if step < stepCount - 1 {
            fieldFocused = false
            withAnimation { step += 1 }
        } else {
            goLive()
        }
    }

    private func skipOffer() {
        offer = ""
        fieldFocused = false
        withAnimation { step += 1 }
    }

    private var draftLook: BoothLook {
        BoothLook(name: name.trimmingCharacters(in: .whitespaces), tagline: nil, logo: logo,
                  offerText: offer, primaryLink: normalizedLink, intakeLink: nil,
                  intakeLabel: "Book a deeper conversation", accentHex: accentHex, theme: theme,
                  background: nil, backgroundFills: true, backgroundDim: 0.35)
    }

    private func goLive() {
        let booth = Booth(
            name: name.trimmingCharacters(in: .whitespaces),
            logoFilename: logo.flatMap { ImageStore.save($0) },
            primaryLink: normalizedLink,
            offerText: offer.trimmingCharacters(in: .whitespaces),
            orientationPreference: orientation
        )
        booth.businessType = businessType
        booth.theme = theme
        booth.accentColor = accentHex
        booth.accentOverridden = accentOverridden
        booth.qrPortrait = portraitQR
        booth.qrLandscape = landscapeQR
        context.insert(booth)
        try? context.save()
    }

    // MARK: Steps

    private var logoStep: some View {
        VStack(spacing: 28) {
            StepTitle(title: "Your brand", subtitle: "Add your logo and business name.")
            VStack(spacing: 6) {
                LogoPicker(image: $logo)
                if logo == nil {
                    Text("Optional — skip if you don't have one handy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            TextField("Business name", text: $name)
                .textContentType(.organizationName)
                .textInputAutocapitalization(.words)
                .submitLabel(.continue)
                .onSubmit(advance)
                .bigField(focus: $fieldFocused)
        }
    }

    private var businessTypeStep: some View {
        VStack(spacing: 28) {
            StepTitle(title: "What do you do?", subtitle: "We'll suggest offers that fit your business.")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(BusinessType.allCases) { type in
                    let selected = businessType == type
                    Button {
                        businessType = type
                    } label: {
                        Label(type.label, systemImage: type.symbol)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(selected ? Color.accentColor : Color(.secondarySystemBackground),
                                        in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }

    private var linkStep: some View {
        VStack(spacing: 28) {
            StepTitle(title: "Where should the QR code go?",
                      subtitle: "Your website, shop, booking page, or link-in-bio.")
            TextField("yourbusiness.com", text: $link)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .onSubmit(advance)
                .bigField(focus: $fieldFocused)
            if Validate.isValidLink(normalizedLink) {
                VStack(spacing: 10) {
                    QRView(link: normalizedLink, size: 200)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
                    Text(normalizedLink)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(.tertiary)
                    .frame(width: 200, height: 200)
                    .overlay(Text("QR preview").foregroundStyle(.secondary))
            }
        }
        .onAppear { fieldFocused = true }
    }

    private var offerStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepTitle(title: "What do visitors get?",
                      subtitle: "Give people a reason to leave their name and email.")
            TextField("Your offer", text: $offer, axis: .vertical)
                .lineLimit(1...3)
                .textInputAutocapitalization(.sentences)
                .bigField(focus: $fieldFocused)
            VStack(spacing: 10) {
                ForEach(businessType?.suggestions ?? OfferSuggestion.general) { suggestion in
                    Button {
                        offer = suggestion.text
                        fieldFocused = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.text)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(suggestion.why)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if offer == suggestion.text {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .multilineTextAlignment(.leading)
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button("Skip — no offer", action: skipOffer)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var goLiveStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepTitle(title: "Ready to go live", subtitle: "Set the screen up the way it'll sit on your table.")
            if !passcodeSet {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Set a device passcode to protect your leads: Settings → Face ID & Passcode (or Touch ID & Passcode).", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("Without one, the lock icon can't keep visitors out of your leads. You can still go live.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Orientation")
                    .font(.headline)
                Picker("Orientation", selection: $orientation) {
                    ForEach(OrientationPreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Auto follows the device. Pick Portrait or Landscape to lock it on a stand.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Look")
                    .font(.headline)
                Picker("Theme", selection: $theme) {
                    ForEach(BoothTheme.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                ColorPicker(logo == nil || accentOverridden ? "Accent color" : "Accent color (from your logo)",
                            selection: Binding(get: { Color(hex: accentHex) },
                                               set: { accentHex = $0.hexString; accentOverridden = true }),
                            supportsOpacity: false)
                Button {
                    showLayoutEditor = true
                } label: {
                    Label("Edit layout", systemImage: "qrcode.viewfinder")
                        .font(.body.weight(.semibold))
                }
                Text("Move and resize the QR code. You can change all of this later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Tip: use Guided Access", systemImage: "lock.shield")
                    .font(.headline)
                Text("It keeps visitors inside Show Stand, so nobody can wander into your other apps.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Show me how") { showGuidedAccess = true }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct OfferSuggestion: Identifiable {
    let text: String
    let why: String
    var id: String { text }

    /// Used when no business type is set (booths made before business types existed).
    static let general = [
        OfferSuggestion(text: "Get our free catalog", why: "Low commitment, works for product vendors"),
        OfferSuggestion(text: "10% off your first order", why: "Gives a reason to act after the show"),
        OfferSuggestion(text: "Enter today's giveaway", why: "Highest sign-ups, lower-quality leads"),
        OfferSuggestion(text: "Free 15-minute consult", why: "Best for coaches and service businesses"),
        OfferSuggestion(text: "Get the slides / resources", why: "Good for speakers and educators"),
    ]
}

extension BusinessType {
    var suggestions: [OfferSuggestion] {
        switch self {
        case .products: [
            OfferSuggestion(text: "Get our free catalog", why: "Low commitment, an easy yes for browsers"),
            OfferSuggestion(text: "10% off your first order", why: "Gives a reason to buy after the show"),
            OfferSuggestion(text: "Early access to new releases", why: "Rewards your biggest fans"),
            OfferSuggestion(text: "Enter today's giveaway", why: "Highest sign-ups, lower-quality leads"),
        ]
        case .services: [
            OfferSuggestion(text: "Free 15-minute consult", why: "A low-risk way to start the conversation"),
            OfferSuggestion(text: "Free quote within 48 hours", why: "Turns interest into a concrete next step"),
            OfferSuggestion(text: "Get our pricing guide", why: "Answers the first question people have"),
            OfferSuggestion(text: "$50 off your first booking", why: "Gives a reason to act after the show"),
        ]
        case .coaching: [
            OfferSuggestion(text: "Free 15-minute discovery call", why: "The natural first step for 1:1 coaching"),
            OfferSuggestion(text: "Get the free workbook", why: "Value up front, no pressure"),
            OfferSuggestion(text: "Join the free 5-day challenge", why: "Builds trust over a few days"),
            OfferSuggestion(text: "Get the slides / resources", why: "Good if you're speaking at the event"),
        ]
        case .food: [
            OfferSuggestion(text: "Free sample with your next order", why: "Brings people back to buy"),
            OfferSuggestion(text: "10% off your first order", why: "Simple, works online or in person"),
            OfferSuggestion(text: "Get our menu and new flavors", why: "Keeps you top of mind"),
            OfferSuggestion(text: "Enter today's giveaway", why: "Highest sign-ups, lower-quality leads"),
        ]
        case .artsCrafts: [
            OfferSuggestion(text: "First look at new pieces", why: "Collectors love early access"),
            OfferSuggestion(text: "10% off your first purchase", why: "Gives a reason to buy after the show"),
            OfferSuggestion(text: "Get our next market dates", why: "Turns browsers into repeat visitors"),
            OfferSuggestion(text: "Enter today's giveaway", why: "Highest sign-ups, lower-quality leads"),
        ]
        case .events: [
            OfferSuggestion(text: "Get early-bird tickets", why: "Rewards people who commit early"),
            OfferSuggestion(text: "Join the guest list", why: "Feels exclusive, easy to say yes"),
            OfferSuggestion(text: "Get the event calendar", why: "Keeps you top of mind all season"),
            OfferSuggestion(text: "Enter to win free tickets", why: "Highest sign-ups, lower-quality leads"),
        ]
        }
    }
}

private struct StepTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Large field whose whole rounded box, padding included, focuses the text field.
    func bigField(focus: FocusState<Bool>.Binding) -> some View {
        font(.title3)
            .focused(focus)
            .padding(16)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
            .onTapGesture { focus.wrappedValue = true }
    }
}
