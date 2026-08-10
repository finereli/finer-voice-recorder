import SwiftUI

/// Shows the transcript for a recording with a language picker and controls to
/// (re-)transcribe. Renders right-to-left for languages like Hebrew and Arabic.
struct TranscriptPanel: View {
    @EnvironmentObject var model: AppModel
    let recording: Recording

    @State private var language: String = "he-IL"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                Text("Transcript").font(.system(size: 13, weight: .semibold))

                Spacer()

                Picker("", selection: $language) {
                    ForEach(model.transcriber.availableLanguages) { lang in
                        Text(lang.name).tag(lang.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                if model.transcriber.isTranscribing {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { model.transcriber.cancel() }
                } else {
                    Button(recording.transcript == nil ? "Transcribe" : "Re-transcribe") {
                        model.retranscribe(recording, language: language)
                    }
                    .disabled(!model.transcriber.authorized)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 10)

            ScrollView {
                Text(transcriptText)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                    .multilineTextAlignment(isRTL ? .trailing : .leading)
                    .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                    .foregroundStyle(recording.transcript == nil ? .secondary : .primary)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxHeight: .infinity)
        .onAppear { language = recording.languageCode ?? model.preferredLanguage }
        .onChange(of: recording.id) { _ in
            language = recording.languageCode ?? model.preferredLanguage
        }
    }

    private var transcriptText: String {
        if model.transcriber.isTranscribing && !model.transcriber.progressText.isEmpty {
            return model.transcriber.progressText
        }
        if let t = recording.transcript, !t.isEmpty { return t }
        if model.transcriber.isTranscribing { return "Transcribing…" }
        return model.transcriber.authorized
            ? "No transcript yet. Pick a language and press Transcribe."
            : "Grant speech-recognition permission to transcribe."
    }

    private var isRTL: Bool {
        language.hasPrefix("he") || language.hasPrefix("ar") || language.hasPrefix("fa")
    }
}
