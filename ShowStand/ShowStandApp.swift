import SwiftUI
import SwiftData

@main
struct ShowStandApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Booth.self, Lead.self])
    }
}

/// Only here so the display can lock orientation (see `Orientation`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Orientation.mask
    }
}

/// Decides which screen is showing and owns the "screen-level" side effects:
/// keep-awake, orientation lock, and re-locking the vendor area.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Booth.createdAt) private var booths: [Booth]
    @State private var vendorOpen = false

    var body: some View {
        Group {
            if let booth = booths.first {
                DisplayView(booth: booth, onUnlock: { vendorOpen = true })
                    .fullScreenCover(isPresented: $vendorOpen) {
                        VendorView(booth: booth, onLock: { vendorOpen = false })
                    }
            } else {
                SetupFlow()
            }
        }
        .onAppear {
            ActivityTracker.install()
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { vendorOpen = false }
            if phase == .active { ActivityTracker.install() }
            refresh()
        }
        .onChange(of: vendorOpen) { refresh() }
        .onChange(of: booths.isEmpty) { refresh() }
    }

    private func refresh() {
        let onDisplay = !booths.isEmpty && !vendorOpen
        UIApplication.shared.isIdleTimerDisabled = onDisplay && scenePhase == .active
        Orientation.apply(onDisplay ? booths.first?.orientationPreference : nil)
    }
}
