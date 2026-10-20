import SwiftUI

/// Sidebar listing installed fonts, library folders and smart sources; accepts dropped folders.
struct SidebarView: View {
    @EnvironmentObject var store: FontStore
    @State private var dropTargeted = false

    var body: some View {
        List(selection: $store.sidebarSelection) {
            Section("Fonts") {
                HStack {
                    Label("All Installed", systemImage: "internaldrive")
                    Spacer()
                    if store.scanningInstalled { ProgressView().controlSize(.small) }
                }
                .tag(SidebarItem.installed)
                .contextMenu { Button("Rescan") { store.scanInstalled() } }
            }
            Section("Libraries") {
                ForEach(store.libraries) { lib in
                    LibraryRow(library: lib).tag(SidebarItem.library(lib.id))
                        .contextMenu {
                            Button("Rescan") { store.scan(lib) }
                            Button("Reveal in Finder") { store.revealLibrary(lib.id) }
                            Divider()
                            Button("Remove Library", role: .destructive) { store.removeLibrary(lib.id) }
                        }
                }
                Button { store.presentAddLibraryPanel() } label: { Label("Add Library…", systemImage: "plus") }
                    .buttonStyle(.borderless)
            }
            Section("Smart") {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Activated", systemImage: "bolt.fill")
                    if store.sessionOnlyCount > 0 {
                        Text("\(store.sessionOnlyCount) session-only, end at logout")
                            .font(.caption2).foregroundStyle(.secondary).padding(.leading, 24)
                    }
                }
                .tag(SidebarItem.activated)
                Label("Favorites", systemImage: "star.fill").tag(SidebarItem.favorites)
                Label("Duplicates", systemImage: "square.on.square").tag(SidebarItem.duplicates)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2).padding(4)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.addLibraries(urls)
        } isTargeted: { dropTargeted = $0 }
        .safeAreaInset(edge: .bottom) {
            Button { DonateLink.open() } label: {
                Label("Support / Donate ❤️", systemImage: "heart").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(10)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    }
}

/// A library folder row with font count, scan progress and stale-bookmark state.
private struct LibraryRow: View {
    @EnvironmentObject var store: FontStore
    let library: FontLibrary

    var body: some View {
        HStack {
            Label(library.name, systemImage: store.staleLibraries.contains(library.id)
                  ? "exclamationmark.triangle.fill" : "folder")
                .help(library.path)
            Spacer()
            if let progress = store.scanProgress[library.id] {
                ProgressView(value: progress).progressViewStyle(.circular).controlSize(.small)
            } else {
                Text("\(Set(store.records.filter { $0.libraryID == library.id }.map(\.family)).count)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// Opens the project's donation page.
enum DonateLink {
    static func open() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
