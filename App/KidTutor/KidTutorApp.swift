import SwiftUI

@main
struct KidTutorApp: App {
    @State private var model = AppModel()

    init() {
        KidFont.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

/// The child's home screen; the Phase 0 handwriting tools live behind the grown-ups gear.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HomeView()
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
