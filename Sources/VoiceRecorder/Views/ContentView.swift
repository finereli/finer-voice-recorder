import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Device selection is a top-level, always-visible band.
            DeviceBar()
            Divider()

            NavigationSplitView {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            } detail: {
                DetailView()
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }),
               actions: { Button("OK", role: .cancel) {} },
               message: { Text(model.errorMessage ?? "") })
    }
}
