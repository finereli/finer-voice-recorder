import Foundation

/// A single recording plus its metadata and (optional) transcript.
struct Recording: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var fileName: String          // relative to the recordings directory
    var createdAt: Date
    var duration: TimeInterval
    var transcript: String?
    var languageCode: String?
    var isFavorite: Bool

    init(id: UUID = UUID(), title: String, fileName: String, createdAt: Date = Date(),
         duration: TimeInterval, transcript: String? = nil, languageCode: String? = nil,
         isFavorite: Bool = false) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.createdAt = createdAt
        self.duration = duration
        self.transcript = transcript
        self.languageCode = languageCode
        self.isFavorite = isFavorite
    }
}
