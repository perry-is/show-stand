import Combine
import PhotosUI
import SwiftUI
import SwiftData

/// Behind Face ID / passcode. Re-locks after `Timing.vendorRelock` idle (and on background, see RootView).
struct VendorView: View {
    let booth: Booth
    let onLock: () -> Void

    @Environment(\.modelContext) private var context
    @State private var confirmClear = false
    @State private var editing = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var leads: [Lead] { booth.leads.sorted { $0.createdAt > $1.createdAt } }

    private var csv: LeadsCSV {
        LeadsCSV(boothName: booth.name, rows: leads.map {
            LeadsCSV.Row(date: $0.createdAt, name: $0.name, email: $0.email, phone: $0.phone ?? "")
        })
    }

    var body: some View {
        let leads = leads
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(leads.count)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                        Text(leads.count == 1 ? "lead" : "leads")
                            .foregroundStyle(.secondary)
                    }
                    ShareLink(item: csv, preview: SharePreview(csv.filename)) {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(leads.isEmpty)
                    Button {
                        editing = true
                    } label: {
                        Label("Edit booth", systemImage: "pencil")
                    }
                }

                Section("Leads") {
                    if leads.isEmpty {
                        Text("No leads yet. They'll show up here as visitors fill out the form.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(leads) { lead in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lead.name).font(.headline)
                            Text(lead.email).foregroundStyle(.secondary)
                            Text(lead.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { offsets in
                        offsets.map { leads[$0] }.forEach(context.delete)
                        try? context.save()
                    }
                }

                if !leads.isEmpty {
                    Section {
                        Button("Clear all leads", role: .destructive) { confirmClear = true }
                    }
                }
            }
            .navigationTitle(booth.name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back to display", action: onLock)
                }
            }
            .confirmationDialog("Delete all \(leads.count) leads?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Delete all leads", role: .destructive, action: clearAll)
            } message: {
                Text("Export them first if you need them. This can't be undone.")
            }
            .sheet(isPresented: $editing) {
                EditBoothView(booth: booth)
            }
        }
        .onAppear { ActivityTracker.touch() }
        .onReceive(tick) { _ in
            if ActivityTracker.idleSeconds >= Timing.vendorRelock { onLock() }
        }
    }

    private func clearAll() {
        let all = booth.leads
        booth.leads.removeAll()
        all.forEach(context.delete)
        try? context.save()
    }
}

struct EditBoothView: View {
    let booth: Booth

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var logo: UIImage?
    private let originalLogo: UIImage?
    @State private var background: UIImage?
    private let originalBackground: UIImage?
    @State private var name: String
    @State private var tagline: String
    @State private var businessType: BusinessType?
    @State private var primaryLink: String
    @State private var offerText: String
    @State private var intakeLink: String
    @State private var intakeLabel: String
    @State private var accentHex: String
    @State private var accentOverridden: Bool
    @State private var theme: BoothTheme
    @State private var backgroundFills: Bool
    @State private var backgroundDim: Double
    @State private var portraitQR: QRPlacement?
    @State private var landscapeQR: QRPlacement?
    @State private var orientation: OrientationPreference
    @State private var backgroundItem: PhotosPickerItem?
    @State private var showFileImporter = false
    @State private var showLayoutEditor = false
    @State private var showGuidedAccess = false

    init(booth: Booth) {
        self.booth = booth
        originalLogo = ImageStore.load(booth.logoFilename)
        originalBackground = ImageStore.load(booth.backgroundFilename)
        _logo = State(initialValue: originalLogo)
        _background = State(initialValue: originalBackground)
        _name = State(initialValue: booth.name)
        _tagline = State(initialValue: booth.tagline ?? "")
        _businessType = State(initialValue: booth.businessType)
        _primaryLink = State(initialValue: booth.primaryLink)
        _offerText = State(initialValue: booth.offerText)
        _intakeLink = State(initialValue: booth.intakeLink ?? "")
        _intakeLabel = State(initialValue: booth.intakeLabel)
        _accentHex = State(initialValue: booth.accentColor)
        _accentOverridden = State(initialValue: booth.accentOverridden)
        _theme = State(initialValue: booth.theme)
        _backgroundFills = State(initialValue: booth.backgroundFills)
        _backgroundDim = State(initialValue: booth.backgroundDim)
        _portraitQR = State(initialValue: booth.qrPortrait)
        _landscapeQR = State(initialValue: booth.qrLandscape)
        _orientation = State(initialValue: booth.orientationPreference)
    }

    private var normalizedPrimary: String { Validate.normalizedLink(primaryLink) }
    private var normalizedIntake: String { Validate.normalizedLink(intakeLink) }
    private var primaryValid: Bool { Validate.isValidLink(normalizedPrimary) }
    private var intakeValid: Bool { normalizedIntake.isEmpty || Validate.isValidLink(normalizedIntake) }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && primaryValid && intakeValid
    }

    /// The unsaved edits, so the layout editor previews them.
    private var draftLook: BoothLook {
        BoothLook(name: name.trimmingCharacters(in: .whitespaces),
                  tagline: tagline.trimmingCharacters(in: .whitespaces),
                  logo: logo, offerText: offerText, primaryLink: normalizedPrimary,
                  intakeLink: normalizedIntake.isEmpty ? nil : normalizedIntake,
                  intakeLabel: intakeLabel, accentHex: accentHex, theme: theme,
                  background: background, backgroundFills: backgroundFills, backgroundDim: backgroundDim)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Brand") {
                    LogoPicker(image: $logo, size: 110)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    TextField("Business name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Tagline (optional)", text: $tagline)
                    Picker("What you do", selection: $businessType) {
                        Text("Not set").tag(BusinessType?.none)
                        ForEach(BusinessType.allCases) { Text($0.label).tag(BusinessType?.some($0)) }
                    }
                }

                Section {
                    TextField("yourbusiness.com", text: $primaryLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !primaryValid {
                        Text("Enter a web address, like yourbusiness.com").font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Main QR code link")
                }

                Section {
                    TextField("What visitors get (optional)", text: $offerText, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("Offer")
                } footer: {
                    Text("Leave empty for no offer. The button will say “Stay in touch.”")
                }

                Section {
                    TextField("Link (optional)", text: $intakeLink)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !intakeValid {
                        Text("Enter a web address, or leave it empty").font(.footnote).foregroundStyle(.red)
                    }
                    TextField("Label", text: $intakeLabel)
                } header: {
                    Text("Second QR code")
                } footer: {
                    Text("Shown smaller on the display. Good for your own intake or booking form.")
                }

                Section("Look") {
                    Picker("Theme", selection: $theme) {
                        ForEach(BoothTheme.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ColorPicker("Accent color",
                                selection: Binding(get: { Color(hex: accentHex) },
                                                   set: { accentHex = $0.hexString; accentOverridden = true }),
                                supportsOpacity: false)
                    if let logo, accentOverridden, let logoHex = LogoColor.dominantHex(in: logo) {
                        Button("Use logo color") {
                            accentHex = logoHex
                            accentOverridden = false
                        }
                    }
                    Button {
                        showLayoutEditor = true
                    } label: {
                        Label("Edit layout", systemImage: "qrcode.viewfinder")
                    }
                }

                Section {
                    if let background {
                        Image(uiImage: background)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowSeparator(.hidden)
                    }
                    PhotosPicker(selection: $backgroundItem, matching: .images) {
                        Label(background == nil ? "Choose photo" : "Replace with photo", systemImage: "photo")
                    }
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Choose from Files", systemImage: "folder")
                    }
                    if background != nil {
                        Picker("Fit", selection: $backgroundFills) {
                            Text("Fill").tag(true)
                            Text("Fit").tag(false)
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dim \(Int((backgroundDim * 100).rounded()))%")
                            Slider(value: $backgroundDim, in: 0...0.9)
                        }
                        Button("Remove background", role: .destructive) {
                            background = nil
                            backgroundItem = nil
                        }
                    }
                } header: {
                    Text("Background")
                } footer: {
                    Text("Dim blends the photo toward the theme color so text stays readable.")
                }

                Section("Display") {
                    Picker("Orientation", selection: $orientation) {
                        ForEach(OrientationPreference.allCases) { Text($0.label).tag($0) }
                    }
                    Button("How to use Guided Access") { showGuidedAccess = true }
                }
            }
            .navigationTitle("Edit Booth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            .sheet(isPresented: $showGuidedAccess) { GuidedAccessSheet() }
            .fullScreenCover(isPresented: $showLayoutEditor) {
                LayoutEditorView(look: draftLook, orientation: orientation,
                                 portraitQR: $portraitQR, landscapeQR: $landscapeQR)
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                    background = image
                }
            }
        }
        .onChange(of: [name, tagline, primaryLink, offerText, intakeLink, intakeLabel]) { ActivityTracker.touch() }
        .onChange(of: logo) { _, newLogo in
            guard !accentOverridden, let newLogo, let hex = LogoColor.dominantHex(in: newLogo) else { return }
            accentHex = hex
        }
        .onChange(of: backgroundItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    background = image
                }
            }
        }
    }

    private func save() {
        if logo !== originalLogo {
            ImageStore.delete(booth.logoFilename)
            booth.logoFilename = logo.flatMap { ImageStore.save($0) }
        }
        if background !== originalBackground {
            ImageStore.delete(booth.backgroundFilename)
            booth.backgroundFilename = background.flatMap { ImageStore.save($0, maxSide: 2048, jpeg: true) }
        }
        let trimmedTagline = tagline.trimmingCharacters(in: .whitespaces)
        let trimmedLabel = intakeLabel.trimmingCharacters(in: .whitespaces)
        booth.name = name.trimmingCharacters(in: .whitespaces)
        booth.tagline = trimmedTagline.isEmpty ? nil : trimmedTagline
        booth.businessType = businessType
        booth.primaryLink = normalizedPrimary
        booth.offerText = offerText.trimmingCharacters(in: .whitespaces)
        booth.intakeLink = normalizedIntake.isEmpty ? nil : normalizedIntake
        booth.intakeLabel = trimmedLabel.isEmpty ? "Book a deeper conversation" : trimmedLabel
        booth.accentColor = accentHex
        booth.accentOverridden = accentOverridden
        booth.theme = theme
        booth.backgroundFills = backgroundFills
        booth.backgroundDim = backgroundDim
        booth.qrPortrait = portraitQR
        booth.qrLandscape = landscapeQR
        booth.orientationPreference = orientation
        try? context.save()
        dismiss()
    }
}
