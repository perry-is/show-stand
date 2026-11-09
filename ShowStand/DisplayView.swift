import Combine
import SwiftUI

/// The public booth screen.
struct DisplayView: View {
    let booth: Booth
    let onUnlock: () -> Void

    @State private var showForm = false
    @State private var drift: CGSize = .zero
    @State private var showPasscodeNeeded = false

    /// Every few minutes the whole layout eases a few points to avoid OLED burn-in.
    private let driftTimer = Timer.publish(every: 180, on: .main, in: .common).autoconnect()

    var body: some View {
        BoothCanvas(look: booth.look,
                    portraitQR: .constant(booth.qrPortrait),
                    landscapeQR: .constant(booth.qrLandscape),
                    drift: drift,
                    onButton: { showForm = true },
                    onLock: unlock)
            .sheet(isPresented: $showForm) {
                VisitorFormView(booth: booth)
            }
            .onReceive(driftTimer) { _ in
                withAnimation(.easeInOut(duration: 20)) { drift = nextDrift() }
            }
            .alert("Set a device passcode", isPresented: $showPasscodeNeeded) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your leads are protected by Face ID, Touch ID, or the device passcode. Turn on a passcode in Settings to open them.")
            }
    }

    private func unlock() {
        Task {
            switch await VendorAuth.authenticate() {
            case .success: onUnlock()
            case .failed: break
            case .unavailable: showPasscodeNeeded = true
            }
        }
    }

    private func nextDrift() -> CGSize {
        let limit: CGFloat = 8
        func step(_ value: CGFloat) -> CGFloat {
            min(limit, max(-limit, value + .random(in: -3...3)))
        }
        return CGSize(width: step(drift.width), height: step(drift.height))
    }
}
