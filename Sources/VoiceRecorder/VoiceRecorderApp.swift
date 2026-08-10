import SwiftUI

@main
struct VoiceRecorderApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Record / Stop") { model.toggleRecording() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}

/// Shared formatting helpers.
enum Format {
    static func duration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func timer(_ t: TimeInterval) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let hundredths = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    static func time(_ date: Date) -> String {
        let cal = Calendar.current
        let formatter = DateFormatter()
        if cal.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}
