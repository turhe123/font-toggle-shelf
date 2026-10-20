import SwiftUI

/// Detail column: metadata, longer samples and per-style activation for the selected family.
struct DetailView: View {
    @EnvironmentObject var store: FontStore

    private let paragraph = """
        Typography is the craft of arranging type to make written language legible, readable and \
        appealing when displayed. Good type sets a tone, guides the eye and disappears into the reading.
        """
    private let pangram = "The quick brown fox jumps over the lazy dog"
    private let digits = "0123456789  !?&@#%$€£ ()[]{} .,;:'\"-–— /\\*+=<>"

    var body: some View {
        if let family = store.selectedFamilyValue, let face = store.selectedFace {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(family.name).font(.largeTitle.bold()).textSelection(.enabled)
                    if family.faces.count > 1 {
                        Picker("Style", selection: Binding(get: { face.id }, set: { store.selectedFaceID = $0 })) {
                            ForEach(family.faces) { Text($0.style).tag($0.id) }
                        }
                        .frame(maxWidth: 320)
                    }
                    actions(face, family)
                    if let issue = store.issue, family.faces.contains(where: { $0.path == issue.path }) {
                        issueBanner(issue)
                    }
                    if face.error != nil {
                        PreviewText(face: face, text: "", size: 14)
                    } else {
                        PreviewText(face: face, text: paragraph, size: max(14, store.previewSize * 0.6))
                        PreviewText(face: face, text: pangram, size: 24)
                        PreviewText(face: face, text: digits, size: 20)
                    }
                    Divider()
                    info(face)
                    Divider()
                    stylesList(family)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("No Font Selected", systemImage: "textformat.alt",
                                   description: Text("Pick a family to see its styles and details."))
        }
    }

    @ViewBuilder private func actions(_ face: FontRecord, _ family: FontFamily) -> some View {
        HStack(spacing: 12) {
            if face.isInstalled {
                Label("Installed font (read only)", systemImage: "lock").foregroundStyle(.secondary)
            } else {
                Button(store.isActive(face) ? "Deactivate" : "Activate") { store.toggle(face: face, in: family) }
                    .buttonStyle(.borderedProminent)
                    .tint(store.isActive(face) ? .gray : .green)
                    .disabled(face.error != nil)
                Toggle("Persistent", isOn: $store.persistentScope)
                    .help("Keep newly activated fonts active after restart instead of only until logout")
                if let persistent = store.activeFiles[face.path] {
                    Text(persistent ? "Persistent" : "Session only")
                        .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                }
            }
            Spacer()
            Button { store.toggleFavorite(face) } label: {
                Image(systemName: store.favorites.contains(face.postScriptName) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
            .help("Favorite")
            .disabled(face.postScriptName.isEmpty)
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([face.url]) }
        }
    }

    private func issueBanner(_ issue: ActivationIssue) -> some View {
        HStack {
            Image(systemName: "exclamationmark.octagon.fill").foregroundStyle(.red)
            Text(issue.message).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let other = issue.conflictingURL {
                Button("Reveal Other File") { NSWorkspace.shared.activateFileViewerSelecting([other]) }
            }
            Button { store.issue = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
    }

    private func info(_ face: FontRecord) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            row("Family", face.family)
            row("Style", face.style)
            row("PostScript", face.postScriptName.isEmpty ? "—" : face.postScriptName)
            row("Format", face.format)
            row("Glyphs", "\(face.glyphCount) (missing characters render with fallback glyphs)")
            row("File", face.path)
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    private func stylesList(_ family: FontFamily) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Styles").font(.headline)
            ForEach(family.faces) { face in
                HStack {
                    Circle().fill(store.isActive(face) ? Color.green : .clear).frame(width: 8, height: 8)
                    Text(face.style).frame(width: 130, alignment: .leading).lineLimit(1)
                    PreviewText(face: face, text: store.sampleText, size: 18).lineLimit(1)
                    Spacer()
                    if !face.isInstalled && face.error == nil {
                        Toggle("", isOn: Binding(get: { store.isActive(face) },
                                                 set: { _ in store.toggle(face: face, in: family) }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.mini)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { store.selectedFaceID = face.id }
            }
        }
    }
}
