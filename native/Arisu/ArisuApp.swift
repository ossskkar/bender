import SwiftUI

@main
struct ArisuApp: App {
    @StateObject private var pet = Pet()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            ContentView(pet: pet, live: pet.live, room: pet.room)
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                // The wake lock does not survive a trip to the background, and
                // `onAppear` fires once per launch -- so one switch away from
                // her and the iPad went back to locking itself, which is the
                // whole complaint: he has to unlock it, and a dark screen means
                // he forgets she is there. Re-take it on every return.
                .onChange(of: phase) { _, now in
                    if now == .active { UIApplication.shared.isIdleTimerDisabled = true }
                }
        }
    }
}
