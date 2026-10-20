import Foundation

/// One font face read from a file on disk (a .ttc/.dfont file can yield several faces).
struct FontRecord: Codable, Identifiable, Hashable {
    let path: String
    let index: Int
    let family: String
    let style: String
    let postScriptName: String
    let format: String
    let glyphCount: Int
    let error: String?
    /// `nil` means the face belongs to an installed (read-only) system or user font.
    let libraryID: UUID?

    var id: String { "\(path)#\(index)" }
    var url: URL { URL(fileURLWithPath: path) }
    var isInstalled: Bool { libraryID == nil }
}

/// A user-chosen folder of fonts, persisted as a security-scoped bookmark.
struct FontLibrary: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: String
    var bookmark: Data
}

/// Faces grouped under one family name for the content column.
struct FontFamily: Identifiable, Hashable {
    let name: String
    let faces: [FontRecord]

    var id: String { name }
    /// The face used for the one-line preview: Regular if present, otherwise the first one.
    var representative: FontRecord? {
        faces.first { ["regular", "roman", "book"].contains($0.style.lowercased()) && $0.error == nil }
            ?? faces.first { $0.error == nil } ?? faces.first
    }
}

/// Sources listed in the sidebar.
enum SidebarItem: Hashable {
    case installed
    case library(UUID)
    case activated
    case favorites
    case duplicates
}

/// A failed activation, shown inline in the detail pane.
struct ActivationIssue: Identifiable {
    let id = UUID()
    let path: String
    let message: String
    let conflictingURL: URL?
}
