import SwiftUI

/// App entry point: main three-column window, Settings, and menu commands with keyboard shortcuts.
@main
struct FontToggleShelfApp: App {
    @StateObject private var store = FontStore()

    var body: some Scene {
        WindowGroup("FontToggleShelf") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .textEditing) {
                Button("Find Fonts") { store.searchFocusToken += 1 }.keyboardShortcut("f")
            }
            CommandMenu("Fonts") {
                Button("Add Library…") { store.presentAddLibraryPanel() }.keyboardShortcut("o")
                Button("Rescan") { store.rescanSelection() }.keyboardShortcut("r")
                Divider()
                Button("Toggle Activation") { store.toggleSelection() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Button("Toggle Favorite") { store.toggleFavoriteSelection() }.keyboardShortcut("d")
            }
            CommandGroup(replacing: .help) {
                Button("Support / Donate ❤️") { DonateLink.open() }
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Main window: sidebar, family list and detail, with the preview controls in the toolbar.
struct ContentView: View {
    @EnvironmentObject var store: FontStore
    @AppStorage("gridMode") private var gridMode = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } content: {
            FontListView()
                .navigationSplitViewColumnWidth(min: 340, ideal: 480)
        } detail: {
            DetailView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 420)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                TextField("Search", text: $store.searchText, prompt: Text("Search fonts"))
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .frame(width: 150)
                Picker("View", selection: $gridMode) {
                    Image(systemName: "list.bullet").tag(false)
                    Image(systemName: "square.grid.2x2").tag(true)
                }
                .pickerStyle(.segmented)
                .help("List or grid")
                TextField("Sample text", text: $store.sampleText, prompt: Text("Type sample text"))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 170)
                Slider(value: $store.previewSize, in: 8...120)
                    .frame(width: 110)
                    .help("Preview size: \(Int(store.previewSize)) pt")
                Button { store.presentAddLibraryPanel() } label: { Label("Add Library", systemImage: "folder.badge.plus") }
                    .help("Add a folder of fonts")
            }
        }
        .onChange(of: store.searchFocusToken) { _, _ in searchFocused = true }
    }
}
