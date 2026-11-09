import SwiftUI

/// Draws the public booth screen. The live display uses it as is; the layout editor turns on
/// `editing`, which lets the vendor move and resize the QR card. The button and lock never move.
struct BoothCanvas: View {
    let look: BoothLook
    @Binding var portraitQR: QRPlacement?
    @Binding var landscapeQR: QRPlacement?
    var editing = false
    var drift: CGSize = .zero
    var onButton: () -> Void = {}
    var onLock: () -> Void = {}

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var moveStart: CGPoint?
    @State private var sizeStart: CGFloat?
    @State private var guides: [CanvasGeometry.Guide] = []

    var body: some View {
        let palette = look.palette
        ZStack {
            background(palette)
            GeometryReader { geo in
                let size = geo.size
                let landscape = size.width > size.height
                let geometry = CanvasGeometry(size: size,
                                              wide: landscape || horizontalSizeClass == .regular,
                                              hasIntake: look.intakeLink != nil)
                let placement = landscape ? $landscapeQR : $portraitQR
                let card = geometry.card(for: placement.wrappedValue)

                ZStack(alignment: .topLeading) {
                    content(geometry, palette: palette, reserveQR: placement.wrappedValue == nil ? card.qr : nil)
                    QRCard(link: look.primaryLink, qr: card.qr)
                        .gesture(moveGesture(geometry, placement), including: editing ? .all : .none)
                        .simultaneousGesture(pinchGesture(geometry, placement), including: editing ? .all : .none)
                        .position(card.center)
                    leaveInfoButton(geometry.buttonRect, palette: palette)
                    lockButton(geometry.lockRect, palette: palette)
                    if editing {
                        editOverlay(geometry, card: card, placement: placement)
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .offset(drift)
        }
        .environment(\.colorScheme, palette.scheme)
        .sensoryFeedback(.impact(weight: .light), trigger: guides) { old, new in !new.isEmpty && new != old }
    }

    // MARK: Background

    private func background(_ palette: ThemePalette) -> some View {
        ZStack {
            palette.background
            if let image = look.background {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: look.backgroundFills ? .fill : .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // A little overscan so drift never reveals an edge.
                        .scaleEffect(look.backgroundFills ? 1.04 : 1)
                        .offset(drift)
                        .clipped()
                }
                palette.background.opacity(look.backgroundDim)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Brand, offer, intake

    /// Everything except the QR card, button and lock. When the QR is in its default spot,
    /// `reserveQR` keeps room for it so the text flows around it.
    @ViewBuilder
    private func content(_ geometry: CanvasGeometry, palette: ThemePalette, reserveQR: CGFloat?) -> some View {
        let size = geometry.size
        if geometry.wide {
            let rightColumn = max(geometry.buttonRect.width, reserveQR.map { CanvasGeometry.cardSize($0).width } ?? 0)
            HStack(alignment: .top, spacing: geometry.padding) {
                VStack(alignment: .leading, spacing: 0) {
                    brand(palette, logoHeight: min(size.height * 0.16, 140), alignment: .leading)
                    Spacer(minLength: 12)
                    if look.hasOffer { offer(palette, alignment: .leading) }
                    Spacer(minLength: 12)
                    if let intake = look.intakeLink {
                        intakeRow(intake, palette: palette, qr: min(110, size.height * 0.2))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Color.clear.frame(width: rightColumn)
            }
            .padding(geometry.padding)
        } else {
            VStack(spacing: 0) {
                brand(palette, logoHeight: min(size.height * 0.1, 96), alignment: .center)
                Spacer(minLength: 12)
                if look.hasOffer { offer(palette, alignment: .center) }
                Spacer(minLength: 12)
                VStack(spacing: CanvasGeometry.spacing) {
                    if let reserveQR {
                        Color.clear.frame(height: CanvasGeometry.cardSize(reserveQR).height)
                    }
                    if let intake = look.intakeLink {
                        intakeRow(intake, palette: palette, qr: 88)
                            .frame(height: CanvasGeometry.intakeRowHeight)
                    }
                    Color.clear.frame(height: CanvasGeometry.buttonHeight)
                }
            }
            .padding([.horizontal, .top], geometry.padding)
            .padding(.bottom, geometry.buttonBottomInset)
        }
    }

    private func brand(_ palette: ThemePalette, logoHeight: CGFloat, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            if let logo = look.logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: logoHeight)
            }
            Text(look.name)
                .font(.title.bold())
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let tagline = look.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.title3)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private func offer(_ palette: ThemePalette, alignment: HorizontalAlignment) -> some View {
        Text(look.offerText)
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .foregroundStyle(palette.offer)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .lineLimit(3)
            .minimumScaleFactor(0.4)
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }

    private func intakeRow(_ link: String, palette: ThemePalette, qr: CGFloat) -> some View {
        HStack(spacing: 12) {
            QRView(link: link, size: qr)
                .shadow(color: .black.opacity(0.1), radius: 4, y: 1)
            Text(look.intakeLabel)
                .font(.headline)
                .foregroundStyle(palette.text)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: Fixed controls

    private func leaveInfoButton(_ rect: CGRect, palette: ThemePalette) -> some View {
        Button(action: onButton) {
            Text(look.buttonTitle)
                .font(.title3.weight(.bold))
                .foregroundStyle(palette.buttonText)
                .frame(width: rect.width, height: rect.height)
                .background(palette.buttonFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!editing)
        .position(x: rect.midX, y: rect.midY)
    }

    private func lockButton(_ rect: CGRect, palette: ThemePalette) -> some View {
        Button(action: onLock) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(palette.secondary)
                .opacity(0.35)
                .frame(width: rect.width, height: rect.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!editing)
        .accessibilityLabel("Vendor area")
        .position(x: rect.midX, y: rect.midY)
    }

    // MARK: Editing

    private func editOverlay(_ geometry: CanvasGeometry, card: (center: CGPoint, qr: CGFloat),
                             placement: Binding<QRPlacement?>) -> some View {
        let size = geometry.size
        let rect = CanvasGeometry.cardRect(center: card.center, qr: card.qr)
        let atMinimum = card.qr <= geometry.minQR + 0.5
        let feet = geometry.scanFeet(card.qr)
        return ZStack(alignment: .topLeading) {
            ForEach(guides, id: \.self) { guide in
                Rectangle()
                    .fill(Color.cyan)
                    .frame(width: guide.vertical ? 1.5 : size.width, height: guide.vertical ? size.height : 1.5)
                    .position(x: guide.vertical ? guide.position : size.width / 2,
                              y: guide.vertical ? size.height / 2 : guide.position)
            }
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                .frame(width: rect.width + 8, height: rect.height + 8)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
            Text(atMinimum ? "Scans from about \(feet, specifier: "%.1f") ft · minimum size"
                           : "Scans from about \(feet, specifier: "%.1f") ft")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75), in: Capsule())
                .fixedSize()
                // Above the card when there's room; otherwise over its top padding.
                .position(x: rect.midX, y: rect.minY > 44 ? rect.minY - 22 : rect.minY + 20)
                .allowsHitTesting(false)
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(Color.white, in: Circle())
                .overlay(Circle().stroke(Color.cyan, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .frame(width: 52, height: 52)
                .contentShape(Rectangle())
                .gesture(handleGesture(geometry, placement))
                // Stay fully on screen when the card reaches the edge.
                .position(x: min(rect.maxX, size.width - 20), y: min(rect.maxY, size.height - 20))
                .accessibilityLabel("Resize QR code")
        }
    }

    private func moveGesture(_ geometry: CanvasGeometry, _ placement: Binding<QRPlacement?>) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let current = geometry.card(for: placement.wrappedValue)
                let start = moveStart ?? current.center
                if moveStart == nil { moveStart = start }
                let proposed = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                let snapped = geometry.snap(center: proposed, qr: current.qr)
                let resolved = geometry.resolve(center: snapped.center, qr: current.qr)
                // If the card had to be pushed (edge, button), the snap lines no longer apply.
                guides = resolved.center == snapped.center ? snapped.guides : []
                placement.wrappedValue = geometry.placement(center: resolved.center, qr: resolved.qr)
            }
            .onEnded { _ in
                moveStart = nil
                guides = []
            }
    }

    private func pinchGesture(_ geometry: CanvasGeometry, _ placement: Binding<QRPlacement?>) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let current = geometry.card(for: placement.wrappedValue)
                let start = sizeStart ?? current.qr
                if sizeStart == nil { sizeStart = start }
                resize(to: start * value.magnification, around: current.center, geometry, placement)
            }
            .onEnded { _ in sizeStart = nil }
    }

    /// Dragging the corner handle out grows the card around its center.
    private func handleGesture(_ geometry: CanvasGeometry, _ placement: Binding<QRPlacement?>) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let current = geometry.card(for: placement.wrappedValue)
                let start = sizeStart ?? current.qr
                if sizeStart == nil { sizeStart = start }
                let delta = (value.translation.width + value.translation.height) * 0.9
                resize(to: start + delta, around: current.center, geometry, placement)
            }
            .onEnded { _ in sizeStart = nil }
    }

    private func resize(to qr: CGFloat, around center: CGPoint, _ geometry: CanvasGeometry,
                        _ placement: Binding<QRPlacement?>) {
        let resolved = geometry.resolve(center: center, qr: qr)
        placement.wrappedValue = geometry.placement(center: resolved.center, qr: resolved.qr)
    }
}

/// The QR on its white card: fixed minimum padding as a quiet zone, caption underneath.
/// Its size always matches `CanvasGeometry.cardSize`.
struct QRCard: View {
    let link: String
    let qr: CGFloat

    var body: some View {
        let pad = CanvasGeometry.cardPadding(qr)
        VStack(spacing: 0) {
            Group {
                if let image = QRCode.image(for: link) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: qr, height: qr)
            Text("Scan with your phone camera")
                .font(.system(size: CanvasGeometry.captionFontSize(qr), weight: .medium))
                .foregroundStyle(Color(white: 0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: qr, height: CanvasGeometry.captionHeight(qr))
        }
        .padding(pad)
        .background(Color.white, in: RoundedRectangle(cornerRadius: pad))
        // Without this the shadow is drawn around each piece inside the card.
        .compositingGroup()
        .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("QR code. Scan with your phone camera")
    }
}

/// Full-screen "Edit layout" mode, opened from Go Live and Edit Booth. Edits the bindings
/// directly; the caller saves them along with its other changes.
struct LayoutEditorView: View {
    let look: BoothLook
    let orientation: OrientationPreference
    @Binding var portraitQR: QRPlacement?
    @Binding var landscapeQR: QRPlacement?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            BoothCanvas(look: look, portraitQR: $portraitQR, landscapeQR: $landscapeQR, editing: true)
                // In landscape the default QR is on the right, so keep the toolbar left.
                .overlay(alignment: landscape ? .topLeading : .top) { toolbar(landscape: landscape) }
        }
        .onAppear { Orientation.apply(orientation) }
        .onDisappear { Orientation.apply(nil) }
    }

    private func toolbar(landscape: Bool) -> some View {
        VStack(spacing: 6) {
            HStack {
                Button("Reset layout") {
                    withAnimation(.snappy) {
                        if landscape { landscapeQR = nil } else { portraitQR = nil }
                    }
                }
                .disabled((landscape ? landscapeQR : portraitQR) == nil)
                Spacer()
                Button("Done") { dismiss() }
                    .bold()
            }
            Text(orientation == .auto
                 ? "Editing the \(landscape ? "landscape" : "portrait") layout. Rotate to edit the other."
                 : "Drag to move. Pinch or drag the corner to resize.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .environment(\.colorScheme, .light)
        .frame(maxWidth: 520)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
