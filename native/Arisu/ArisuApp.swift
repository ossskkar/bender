import SwiftUI

@main
struct ArisuApp: App {
    @StateObject private var pet = Pet()
    var body: some Scene {
        WindowGroup {
            ContentView(pet: pet, live: pet.live, room: pet.room)
                .preferredColorScheme(.dark)
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}
