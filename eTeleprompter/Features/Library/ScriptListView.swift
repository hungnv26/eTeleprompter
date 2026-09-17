import SwiftUI
import SwiftData

/// Script list (WP2): rows (title, modified date, word count, reading time),
/// live search over title+content, "+" create, context menu Duplicate/Move/
/// Delete (swipe-to-delete on iPad), sorted by modifiedDate descending.
struct ScriptListView: View {
    var sidebarItem: SidebarItem
    @Binding var selection: Script?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Script.modifiedDate, order: .reverse) private var allScripts: [Script]
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var searchText = ""
    @State private var scriptPendingDelete: Script?

    @State private var isImporting = false
    @State private var importError: String?

    /// Scripts of the selected sidebar item, filtered by the live search
    /// query (case-insensitive substring over title AND content, SPEC F1).
    /// `allScripts` is already sorted modifiedDate-descending; filtering
    /// preserves that order.
    private var visibleScripts: [Script] {
        let inScope: [Script]
        switch sidebarItem {
        case .allScripts:
            inScope = allScripts
        case .folder(let folder):
            inScope = allScripts.filter { $0.folder === folder }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return inScope }
        return inScope.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    private var navigationTitle: String {
        switch sidebarItem {
        case .allScripts: "All Scripts"
        case .folder(let folder): folder.name
        }
    }

    var body: some View {
        Group {
            if visibleScripts.isEmpty {
                emptyState
            } else {
                scriptList
            }
        }
        .searchable(text: $searchText, prompt: "Title or content")
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: addScript) {
                    Label("New Script", systemImage: "plus")
                }
                .help("New Script")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import Script", systemImage: "square.and.arrow.down")
                }
                .help("Import a PDF, Word, text or RTF file as a new script")
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: DocumentTextExtractor.supportedTypes
        ) { result in
            importScript(from: result)
        }
        .alert("Couldn’t Import", isPresented: isShowingImportError) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .confirmationDialog(
            "Delete Script?",
            isPresented: isConfirmingScriptDelete,
            titleVisibility: .visible,
            presenting: scriptPendingDelete
        ) { script in
            Button("Delete Script", role: .destructive) {
                delete(script)
            }
            Button("Cancel", role: .cancel) {}
        } message: { script in
            Text("\"\(script.title)\" will be permanently deleted. This cannot be undone.")
        }
    }

    private var scriptList: some View {
        List(selection: $selection) {
            ForEach(visibleScripts) { script in
                ScriptRowView(script: script)
                    .tag(script)
                    .contextMenu {
                        Button {
                            duplicate(script)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        MoveToFolderMenu(script: script, folders: folders)
                        Divider()
                        Button(role: .destructive) {
                            scriptPendingDelete = script
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                #if os(iOS)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // Not `role: .destructive` — the row must stay put
                        // until the confirmation dialog is answered.
                        Button {
                            scriptPendingDelete = script
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                #endif
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView(
                "No Scripts",
                systemImage: "doc.text",
                description: Text("Tap + to create a script.")
            )
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var isConfirmingScriptDelete: Binding<Bool> {
        Binding(
            get: { scriptPendingDelete != nil },
            set: { if !$0 { scriptPendingDelete = nil } }
        )
    }

    // MARK: - Actions

    /// "+" creates an "Untitled" script (in the selected folder, if any) and
    /// selects it so the editor opens immediately (SPEC F1).
    private func addScript() {
        var folder: Folder?
        if case .folder(let selected) = sidebarItem {
            folder = selected
        }
        let script = Script(folder: folder)
        modelContext.insert(script)
        selection = script
    }

    private var isShowingImportError: Binding<Bool> {
        Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })
    }

    /// Import: a PDF / Word / text file becomes a new script titled after the
    /// file, in the selected folder, and opens in the editor.
    private func importScript(from result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let url):
            do {
                let text = try DocumentTextExtractor.text(from: url)
                var folder: Folder?
                if case .folder(let selected) = sidebarItem { folder = selected }
                let script = Script(title: DocumentTextExtractor.suggestedTitle(for: url),
                                    content: text, folder: folder)
                modelContext.insert(script)
                selection = script
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    /// Duplicate: identical content, Finder-style "<Title> copy" name, same
    /// folder, fresh id/createdDate/modifiedDate (from Script.init).
    private func duplicate(_ script: Script) {
        let title = DuplicateNamer.copyName(
            for: script.title,
            existingTitles: Set(allScripts.map(\.title))
        )
        let copy = Script(title: title, content: script.content, folder: script.folder)
        modelContext.insert(copy)
    }

    private func delete(_ script: Script) {
        if selection == script {
            selection = nil
        }
        modelContext.delete(script)
    }
}
