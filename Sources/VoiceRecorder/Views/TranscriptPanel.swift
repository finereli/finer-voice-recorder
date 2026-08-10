import SwiftUI

/// Shows the transcript for a recording. Language is chosen from a compact
/// popup menu (with an "Automatic" option); direction is derived from the text
/// so Hebrew/Arabic flow right-to-left on their own. Copy and export live here.
struct TranscriptPanel: View {
    @EnvironmentObject var model: AppModel
    let recording: Recording

    @State private var language: String = autoLanguageCode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            transcriptBody
        }
        .frame(maxHeight: .infinity)
        .onAppear { language = recording.languageCode ?? model.preferredLanguage }
        .onChange(of: recording.id) { _ in
            language = recording.languageCode ?? model.preferredLanguage
        }
        // Keep the menu in sync after auto-detect resolves to a real language.
        .onChange(of: recording.languageCode) { newCode in
            if let newCode { language = newCode }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble").foregroundStyle(.secondary)
            Text("Transcript").font(.system(size: 13, weight: .semibold))

            Spacer()

            languageMenu

            IconButton(system: "doc.on.doc", help: "Copy transcript") {
                model.copyTranscript(recording)
            }
            .disabled(!hasTranscript)

            IconButton(system: "square.and.arrow.up", help: "Export transcript to a file") {
                model.exportTranscript(recording)
            }
            .disabled(!hasTranscript)

            if model.transcriber.isTranscribing {
                ProgressView().controlSize(.small)
                IconButton(system: "xmark.circle.fill", help: "Cancel") {
                    model.transcriber.cancel()
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 10)
    }

    /// QuickTime-style popup: a subtle pill you click to reveal the menu.
    private var languageMenu: some View {
        Menu {
            Button { choose(autoLanguageCode) } label: {
                menuRow("Automatic", selected: language == autoLanguageCode)
            }
            Divider()
            ForEach(model.transcriber.availableLanguages) { lang in
                Button { choose(lang.id) } label: {
                    menuRow(lang.name, selected: language == lang.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe").font(.system(size: 11))
                Text(model.transcriber.name(for: language))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .noFocusRing()
        .pointingHandCursor()
        .disabled(model.transcriber.isTranscribing)
        .help("Transcription language")
    }

    @ViewBuilder
    private func menuRow(_ title: String, selected: Bool) -> some View {
        if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func choose(_ code: String) {
        language = code
        // Choosing a language (re-)transcribes in it immediately.
        model.retranscribe(recording, language: code)
    }

    // MARK: - Body

    private var transcriptBody: some View {
        ScrollView {
            Text(displayText)
                .font(.system(size: 14))
                .textSelection(.enabled)
                // Align to the natural start side and let layoutDirection pick
                // which side that is: leading == right in an RTL context.
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .foregroundStyle(hasTranscript ? .primary : .secondary)
                .padding(.horizontal, 30)
                .padding(.bottom, 20)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Derived

    private var hasTranscript: Bool {
        !(recording.transcript ?? "").isEmpty
    }

    private var displayText: String {
        if model.transcriber.isTranscribing && !model.transcriber.progressText.isEmpty {
            return model.transcriber.progressText
        }
        if let t = recording.transcript, !t.isEmpty { return t }
        if model.transcriber.isTranscribing { return "Transcribing…" }
        return model.transcriber.authorized
            ? "No transcript yet. Pick a language to transcribe."
            : "Grant speech-recognition permission to transcribe."
    }

    /// Direction follows the actual characters, not the chosen language.
    private var isRTL: Bool { TextDirection.isRTL(displayText) }
}

/// A borderless toolbar-style icon button.
struct IconButton: View {
    let system: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 13))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
