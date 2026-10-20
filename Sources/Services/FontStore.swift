import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Central app state: libraries, scanned fonts, activation, favorites and the on-disk cache.
@MainActor
final class FontStore: ObservableObject {
    @Published var libraries: [FontLibrary] = []
    @Published var records: [FontRecord] = []
    @Published var installed: [FontRecord] = []
    /// Activated library files: path → `true` when persistent, `false` when session-only.
    @Published var activeFiles: [String: Bool] = [:]
    @Published var favorites: Set<String> = []
    @Published var scanProgress: [UUID: Double] = [:]
    @Published var staleLibraries: Set<UUID> = []
    @Published var issue: ActivationIssue?
    @Published var scanningInstalled = false

    @Published var sidebarSelection: SidebarItem? {
        didSet { if oldValue != sidebarSelection { selectedFamily = nil } }
    }
    @Published var selectedFamily: String? {
        didSet { if oldValue != selectedFamily { selectedFaceID = nil } }
    }
    @Published var selectedFaceID: String?
    @Published var searchText = ""
    @Published var sampleText: String
    @Published var previewSize: Double
    @Published var persistentScope = false
    @Published var searchFocusToken = 0

    private var watchers: [UUID: FolderWatcher] = [:]
    private let defaults = UserDefaults.standard

    private struct Cache: Codable { var records: [FontRecord]; var installed: [FontRecord] }

    private var cacheURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("FontToggleShelf/cache.json")
    }

    init() {
        sampleText = defaults.string(forKey: "defaultSampleText") ?? "Handgloves & Quartz 0123"
        let size = defaults.double(forKey: "defaultSize")
        previewSize = size > 0 ? size : 28
        if let data = defaults.data(forKey: "libraries"),
           let libs = try? JSONDecoder().decode([FontLibrary].self, from: data) {
            libraries = libs
        }
        favorites = Set(defaults.stringArray(forKey: "favorites") ?? [])
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let cache = try? JSONDecoder().decode(Cache.self, from: data) {
            records = cache.records.filter { r in libraries.contains { $0.id == r.libraryID } }
            installed = cache.installed
        }
        sidebarSelection = libraries.first.map { .library($0.id) }
        refreshActivationState()
        for lib in libraries { scan(lib) }
        if installed.isEmpty { scanInstalled() }
    }

    // MARK: Derived data

    var duplicateNames: Set<String> {
        var paths: [String: Set<String>] = [:]
        for r in records + installed where !r.postScriptName.isEmpty { paths[r.postScriptName, default: []].insert(r.path) }
        return Set(paths.filter { $0.value.count > 1 }.keys)
    }

    var sessionOnlyCount: Int { activeFiles.values.filter { !$0 }.count }

    var currentFamilies: [FontFamily] {
        let base: [FontRecord]
        switch sidebarSelection {
        case .installed: base = installed
        case .library(let id): base = records.filter { $0.libraryID == id }
        case .activated: base = records.filter { activeFiles[$0.path] != nil }
        case .favorites: base = (records + installed).filter { favorites.contains($0.postScriptName) }
        case .duplicates:
            let names = duplicateNames
            base = (records + installed).filter { names.contains($0.postScriptName) }
        case nil: base = []
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? base : base.filter {
            $0.family.localizedCaseInsensitiveContains(query) || $0.style.localizedCaseInsensitiveContains(query)
                || $0.postScriptName.localizedCaseInsensitiveContains(query)
        }
        return Dictionary(grouping: filtered, by: \.family)
            .map { FontFamily(name: $0.key, faces: $0.value.sorted { $0.style < $1.style }) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var selectedFamilyValue: FontFamily? {
        guard let name = selectedFamily else { return nil }
        return currentFamilies.first { $0.name == name }
    }

    var selectedFace: FontRecord? {
        guard let family = selectedFamilyValue else { return nil }
        return family.faces.first { $0.id == selectedFaceID } ?? family.representative
    }

    func isActive(_ face: FontRecord) -> Bool { activeFiles[face.path] != nil }

    func isActive(_ family: FontFamily) -> Bool {
        let valid = family.faces.filter { !$0.isInstalled && $0.error == nil }
        return !valid.isEmpty && valid.allSatisfy(isActive)
    }

    func library(_ id: UUID) -> FontLibrary? { libraries.first { $0.id == id } }

    // MARK: Libraries

    func presentAddLibraryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.folder]
        panel.prompt = "Add Library"
        if panel.runModal() == .OK { addLibraries(panel.urls) }
    }

    /// Adds dropped or picked folders; non-folders are ignored. Returns whether anything was added.
    @discardableResult
    func addLibraries(_ urls: [URL]) -> Bool {
        var added = false
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !libraries.contains(where: { $0.path == url.standardizedFileURL.path }),
                  let bookmark = makeBookmark(url) else { continue }
            let lib = FontLibrary(id: UUID(), name: url.lastPathComponent, path: url.standardizedFileURL.path, bookmark: bookmark)
            libraries.append(lib)
            sidebarSelection = .library(lib.id)
            scan(lib)
            added = true
        }
        saveLibraries()
        return added
    }

    func removeLibrary(_ id: UUID) {
        let files = Set(records.filter { $0.libraryID == id }.map(\.path))
        let sessionFiles = files.filter { activeFiles[$0] == false }
        Task {
            for path in sessionFiles {
                _ = await FontActivator.unregister(URL(fileURLWithPath: path), persistent: false)
                activeFiles[path] = nil
            }
            saveActivation()
        }
        watchers[id] = nil
        libraries.removeAll { $0.id == id }
        records.removeAll { $0.libraryID == id }
        staleLibraries.remove(id)
        if sidebarSelection == .library(id) { sidebarSelection = libraries.first.map { .library($0.id) } }
        saveLibraries()
        saveCache()
    }

    func relocate(_ id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Relocate"
        guard panel.runModal() == .OK, let url = panel.url, let bookmark = makeBookmark(url),
              let index = libraries.firstIndex(where: { $0.id == id }) else { return }
        libraries[index].bookmark = bookmark
        libraries[index].path = url.standardizedFileURL.path
        libraries[index].name = url.lastPathComponent
        staleLibraries.remove(id)
        saveLibraries()
        scan(libraries[index])
    }

    func revealLibrary(_ id: UUID) {
        guard let lib = library(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lib.path)])
    }

    func rescanSelection() {
        switch sidebarSelection {
        case .installed: scanInstalled()
        case .library(let id): if let lib = library(id) { scan(lib) }
        default: libraries.forEach(scan)
        }
    }

    private func makeBookmark(_ url: URL) -> Data? {
        (try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData())
    }

    /// Resolves a library bookmark, refreshing it if it went stale but the folder is still reachable.
    private func resolve(_ lib: FontLibrary) -> URL? {
        var stale = false
        let url = (try? URL(resolvingBookmarkData: lib.bookmark, options: .withSecurityScope,
                            relativeTo: nil, bookmarkDataIsStale: &stale))
            ?? (try? URL(resolvingBookmarkData: lib.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale))
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        if stale || url.standardizedFileURL.path != lib.path,
           let index = libraries.firstIndex(where: { $0.id == lib.id }) {
            let access = url.startAccessingSecurityScopedResource()
            if let fresh = makeBookmark(url) { libraries[index].bookmark = fresh }
            if access { url.stopAccessingSecurityScopedResource() }
            libraries[index].path = url.standardizedFileURL.path
            saveLibraries()
        }
        return url
    }

    // MARK: Scanning

    func scan(_ lib: FontLibrary) {
        guard scanProgress[lib.id] == nil else { return }
        guard let url = resolve(lib) else {
            staleLibraries.insert(lib.id)
            watchers[lib.id] = nil
            return
        }
        staleLibraries.remove(lib.id)
        let id = lib.id
        scanProgress[id] = 0
        Task {
            let access = url.startAccessingSecurityScopedResource()
            if watchers[id] == nil {
                watchers[id] = FolderWatcher(url: url) { [weak self] in
                    Task { @MainActor in
                        guard let self, let lib = self.library(id) else { return }
                        self.scan(lib)
                    }
                }
            }
            let collected = await scanFiles(in: [url], libraryID: id) { [weak self] in self?.scanProgress[id] = $0 }
            if access { url.stopAccessingSecurityScopedResource() }
            scanProgress[id] = nil
            guard libraries.contains(where: { $0.id == id }) else { return }
            for path in Set(collected.map(\.path)) { PreviewFontCache.shared.invalidate(path: path) }
            records.removeAll { $0.libraryID == id }
            records += collected
            refreshActivationState()
            saveCache()
        }
    }

    func scanInstalled() {
        guard !scanningInstalled else { return }
        scanningInstalled = true
        Task {
            installed = await scanFiles(in: FontScanner.installedFolders, libraryID: nil) { _ in }
            scanningInstalled = false
            saveCache()
        }
    }

    /// Enumerates and parses files in background batches, reporting progress between batches.
    private func scanFiles(in folders: [URL], libraryID: UUID?, progress: @escaping (Double) -> Void) async -> [FontRecord] {
        let files = await Task.detached(priority: .userInitiated) {
            folders.flatMap { FontScanner.fontFiles(in: $0) }
        }.value
        var collected: [FontRecord] = []
        let batch = 50
        for start in stride(from: 0, to: files.count, by: batch) {
            let chunk = Array(files[start..<min(start + batch, files.count)])
            collected += await Task.detached(priority: .userInitiated) {
                chunk.flatMap { FontScanner.records(for: $0, libraryID: libraryID) }
            }.value
            progress(Double(min(start + batch, files.count)) / Double(files.count))
        }
        return collected
    }

    // MARK: Activation

    /// Derives activation from CoreText (does the PostScript name resolve to our file?), with the stored set as fallback.
    func refreshActivationState() {
        let stored = defaults.dictionary(forKey: "activeFiles") as? [String: Bool] ?? [:]
        var result: [String: Bool] = [:]
        var checked: Set<String> = []
        for r in records where r.error == nil && !checked.contains(r.path) {
            checked.insert(r.path)
            if FontActivator.registeredURL(for: r.postScriptName)?.path == r.path {
                result[r.path] = stored[r.path] ?? false
            } else if stored[r.path] == true {
                result[r.path] = true
            }
        }
        activeFiles = result
        saveActivation()
    }

    /// Activates or deactivates every file behind `faces`. Installed and broken fonts are skipped.
    func setActive(_ faces: [FontRecord], _ on: Bool) {
        let targets = Dictionary(grouping: faces.filter { !$0.isInstalled && $0.error == nil }, by: \.path)
        let persistent = persistentScope
        issue = nil
        Task {
            for (path, facesInFile) in targets {
                let url = URL(fileURLWithPath: path)
                if on {
                    guard activeFiles[path] == nil else { continue }
                    let errors = await FontActivator.register(url, persistent: persistent)
                    if let error = errors.first {
                        let conflict = FontActivator.isDuplicateNameError(error)
                            ? facesInFile.lazy.compactMap { FontActivator.registeredURL(for: $0.postScriptName) }.first : nil
                        issue = ActivationIssue(
                            path: path,
                            message: conflict != nil
                                ? "A font with the same PostScript name is already active from another file."
                                : error.localizedDescription,
                            conflictingURL: conflict)
                    } else {
                        activeFiles[path] = persistent
                    }
                } else if let wasPersistent = activeFiles[path] {
                    let errors = await FontActivator.unregister(url, persistent: wasPersistent)
                    if let error = errors.first {
                        issue = ActivationIssue(path: path, message: error.localizedDescription, conflictingURL: nil)
                    } else {
                        activeFiles[path] = nil
                    }
                }
            }
            saveActivation()
        }
    }

    func toggle(face: FontRecord, in family: FontFamily) {
        let wholeFamily = defaults.bool(forKey: "activateWholeFamily")
        let on = !isActive(face)
        setActive(on && wholeFamily ? family.faces : [face], on)
    }

    func toggle(family: FontFamily) { setActive(family.faces, !isActive(family)) }

    /// ⇧⌘A: toggles the selected style if one was picked, otherwise the whole selected family.
    func toggleSelection() {
        guard let family = selectedFamilyValue else { return }
        if selectedFaceID != nil, let face = selectedFace { toggle(face: face, in: family) } else { toggle(family: family) }
    }

    // MARK: Favorites

    func toggleFavorite(_ face: FontRecord) {
        guard !face.postScriptName.isEmpty else { return }
        if favorites.contains(face.postScriptName) { favorites.remove(face.postScriptName) } else { favorites.insert(face.postScriptName) }
        defaults.set(Array(favorites), forKey: "favorites")
    }

    func toggleFavoriteSelection() { if let face = selectedFace { toggleFavorite(face) } }

    // MARK: Persistence

    private func saveLibraries() {
        if let data = try? JSONEncoder().encode(libraries) { defaults.set(data, forKey: "libraries") }
    }

    private func saveActivation() { defaults.set(activeFiles, forKey: "activeFiles") }

    private func saveCache() {
        guard let url = cacheURL, let data = try? JSONEncoder().encode(Cache(records: records, installed: installed)) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
