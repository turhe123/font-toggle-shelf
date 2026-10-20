import AppKit
import CoreText
import SwiftUI

/// Finds font files on disk and reads their metadata with CoreText.
enum FontScanner {
    static let extensions: Set<String> = ["ttf", "otf", "ttc", "dfont"]

    static let installedFolders: [URL] = [
        URL(fileURLWithPath: "/System/Library/Fonts"),
        URL(fileURLWithPath: "/Library/Fonts"),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Fonts"),
    ]

    /// Recursively lists font files below `folder` (woff/woff2 and other types are ignored).
    static func fontFiles(in folder: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var result: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if extensions.contains(url.pathExtension.lowercased()) { result.append(url) }
        }
        return result
    }

    /// Reads every face in a font file. Unreadable files produce a single record carrying an error.
    static func records(for url: URL, libraryID: UUID?) -> [FontRecord] {
        let path = url.standardizedFileURL.path
        let format = formatName(url.pathExtension)
        let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
        guard !descriptors.isEmpty else {
            return [FontRecord(path: path, index: 0, family: url.deletingPathExtension().lastPathComponent,
                               style: "—", postScriptName: "", format: format, glyphCount: 0,
                               error: "CoreText could not read this file. It may be corrupt or in an unsupported format.",
                               libraryID: libraryID)]
        }
        return descriptors.enumerated().map { index, descriptor in
            let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
            return FontRecord(
                path: path, index: index,
                family: string(descriptor, kCTFontFamilyNameAttribute) ?? url.deletingPathExtension().lastPathComponent,
                style: string(descriptor, kCTFontStyleNameAttribute) ?? "Regular",
                postScriptName: string(descriptor, kCTFontNameAttribute) ?? "",
                format: format, glyphCount: CTFontGetGlyphCount(font), error: nil, libraryID: libraryID)
        }
    }

    private static func string(_ descriptor: CTFontDescriptor, _ key: CFString) -> String? {
        CTFontDescriptorCopyAttribute(descriptor, key) as? String
    }

    private static func formatName(_ ext: String) -> String {
        switch ext.lowercased() {
        case "ttf": return "TrueType"
        case "otf": return "OpenType (CFF)"
        case "ttc": return "TrueType Collection"
        case "dfont": return "Data-fork Suitcase"
        default: return ext.uppercased()
        }
    }
}

/// Registers and unregisters font files with the CoreText font manager.
enum FontActivator {
    /// Errors that mean "already in the desired state" and are treated as success.
    private static let benignCodes: Set<Int> = [
        CTFontManagerError.alreadyRegistered.rawValue, CTFontManagerError.notRegistered.rawValue,
    ]

    static func register(_ url: URL, persistent: Bool) async -> [NSError] {
        await withCheckedContinuation { continuation in
            var collected: [NSError] = []
            var resumed = false
            CTFontManagerRegisterFontURLs([url] as CFArray, persistent ? .persistent : .session, true) { errors, done in
                collected += (errors as NSArray).compactMap { $0 as? NSError }
                if done && !resumed {
                    resumed = true
                    continuation.resume(returning: collected.filter { !benignCodes.contains($0.code) })
                }
                return true
            }
        }
    }

    static func unregister(_ url: URL, persistent: Bool) async -> [NSError] {
        await withCheckedContinuation { continuation in
            var collected: [NSError] = []
            var resumed = false
            CTFontManagerUnregisterFontURLs([url] as CFArray, persistent ? .persistent : .session) { errors, done in
                collected += (errors as NSArray).compactMap { $0 as? NSError }
                if done && !resumed {
                    resumed = true
                    continuation.resume(returning: collected.filter { !benignCodes.contains($0.code) })
                }
                return true
            }
        }
    }

    /// The file that currently provides `postScriptName` system-wide, if any.
    static func registeredURL(for postScriptName: String) -> URL? {
        guard !postScriptName.isEmpty else { return nil }
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        guard (CTFontCopyPostScriptName(font) as String) == postScriptName else { return nil }
        return (CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL)?.standardizedFileURL
    }

    static func isDuplicateNameError(_ error: NSError) -> Bool {
        error.code == CTFontManagerError.duplicatedName.rawValue
    }
}

/// Creates in-process preview fonts straight from file URLs, so unactivated fonts still render.
@MainActor
final class PreviewFontCache {
    static let shared = PreviewFontCache()
    private var descriptors: [String: [CTFontDescriptor]] = [:]

    func font(for record: FontRecord, size: CGFloat) -> Font? {
        guard record.error == nil else { return nil }
        let list: [CTFontDescriptor]
        if let cached = descriptors[record.path] {
            list = cached
        } else {
            list = (CTFontManagerCreateFontDescriptorsFromURL(record.url as CFURL) as? [CTFontDescriptor]) ?? []
            descriptors[record.path] = list
        }
        guard record.index < list.count else { return nil }
        return Font(CTFontCreateWithFontDescriptor(list[record.index], size, nil))
    }

    func invalidate(path: String) { descriptors[path] = nil }
}

/// Watches a folder with a DispatchSource and calls back after a short debounce.
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init?(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            self?.pending?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self?.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    deinit {
        pending?.cancel()
        source?.cancel()
    }
}
