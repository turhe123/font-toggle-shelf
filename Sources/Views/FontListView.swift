import SwiftUI

/// Content column: font families of the selected source as a list or grid, plus empty states.
struct FontListView: View {
    @EnvironmentObject var store: FontStore
    @AppStorage("gridMode") private var gridMode = false

    var body: some View {
        let families = store.currentFamilies
        Group {
            if store.libraries.isEmpty && store.sidebarSelection == nil {
                DropZone()
            } else if case .library(let id) = store.sidebarSelection, store.staleLibraries.contains(id) {
                ContentUnavailableView {
                    Label("Folder not found", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("This library's folder was moved or deleted.")
                } actions: {
                    Button("Relocate…") { store.relocate(id) }
                }
            } else if families.isEmpty {
                emptyState
            } else if gridMode {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                        ForEach(families) { family in
                            FamilyCard(family: family, selected: store.selectedFamily == family.name)
                                .onTapGesture { store.selectedFamily = family.name }
                        }
                    }
                    .padding()
                }
            } else {
                List(families, selection: $store.selectedFamily) { family in
                    FamilyRow(family: family).tag(family.name)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if store.sidebarSelection == .activated && store.sessionOnlyCount > 0 {
                Text("Session-only activations (no Persistent badge) are removed when you log out.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(6).background(.bar)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if !store.searchText.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else if case .library(let id) = store.sidebarSelection {
            if store.scanProgress[id] != nil {
                ProgressView("Scanning…")
            } else {
                ContentUnavailableView("No font files found in this folder", systemImage: "textformat",
                                       description: Text("Looking for .ttf, .otf, .ttc and .dfont files."))
            }
        } else if store.sidebarSelection == nil {
            ContentUnavailableView("Select a source", systemImage: "sidebar.left")
        } else {
            ContentUnavailableView("Nothing here yet", systemImage: "tray")
        }
    }
}

/// Large dashed drop target shown before any library exists.
private struct DropZone: View {
    @EnvironmentObject var store: FontStore
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.plus").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Drop a folder of fonts here or click Add Library").font(.title3)
            Button("Add Library…") { store.presentAddLibraryPanel() }.controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(targeted ? Color.accentColor : .secondary, style: StrokeStyle(lineWidth: 2, dash: [8, 6])))
        .padding(30)
        .dropDestination(for: URL.self) { urls, _ in store.addLibraries(urls) } isTargeted: { targeted = $0 }
    }
}

/// A list row: family name on the left, live preview on the right, activation switch.
private struct FamilyRow: View {
    @EnvironmentObject var store: FontStore
    let family: FontFamily

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(store.isActive(family) ? Color.green : .clear).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(family.name).lineLimit(1)
                Text("\(family.faces.count) style\(family.faces.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 170, alignment: .leading)
            PreviewText(face: family.representative, text: store.sampleText, size: store.previewSize)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !(family.representative?.isInstalled ?? true) {
                Toggle("", isOn: Binding(get: { store.isActive(family) }, set: { _ in store.toggle(family: family) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A grid card used in grid mode.
private struct FamilyCard: View {
    @EnvironmentObject var store: FontStore
    let family: FontFamily
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(family.name).font(.caption).lineLimit(1)
                Spacer()
                if store.isActive(family) { Circle().fill(.green).frame(width: 8, height: 8) }
            }
            PreviewText(face: family.representative, text: store.sampleText, size: store.previewSize)
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
    }
}

/// Renders text in a font face, or a warning with the CoreText error for unreadable files.
struct PreviewText: View {
    let face: FontRecord?
    let text: String
    let size: Double

    var body: some View {
        if let face, let error = face.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout)
        } else if let face, let font = PreviewFontCache.shared.font(for: face, size: size) {
            Text(text.isEmpty ? face.family : text).font(font)
        } else {
            Text("Preview unavailable").foregroundStyle(.secondary)
        }
    }
}
