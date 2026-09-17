import SwiftUI
import SwiftData

/// Folders sidebar (WP2): All Scripts + user folders, "+ New Folder",
/// rename/delete via context menu. Deleting a folder never deletes its
/// scripts — the relationship delete rule is `.nullify` (SPEC F1/§4).
struct SidebarView: View {
    @Binding var selection: SidebarItem?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.name) private var folders: [Folder]

    @State private var renamingFolderID: UUID?
    @State private var folderPendingDelete: Folder?

    /// "New Folder" prompt: the field is prefilled with the next free
    /// "New Folder N" so accepting the default never produces a duplicate.
    @State private var isNamingNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        List(selection: $selection) {
            Label("All Scripts", systemImage: "doc.on.doc")
                .tag(SidebarItem.allScripts)

            if !folders.isEmpty {
                Section("Folders") {
                    ForEach(folders) { folder in
                        FolderRowView(folder: folder, renamingFolderID: $renamingFolderID)
                            .tag(SidebarItem.folder(folder))
                            .contextMenu {
                                Button {
                                    renamingFolderID = folder.id
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    folderPendingDelete = folder
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("eTeleprompter")
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            newFolderButton
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: isConfirmingFolderDelete,
            titleVisibility: .visible,
            presenting: folderPendingDelete
        ) { folder in
            Button("Delete Folder", role: .destructive) {
                delete(folder)
            }
            Button("Cancel", role: .cancel) {}
        } message: { folder in
            Text("\"\(folder.name)\" will be deleted. Its scripts are kept and will appear under All Scripts.")
        }
        .alert("New Folder", isPresented: $isNamingNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") { createFolder(named: newFolderName) }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Enter a name for the folder.")
        }
    }

    private var newFolderButton: some View {
        Button(action: addFolder) {
            Label("New Folder", systemImage: "folder.badge.plus")
                .font(.body.weight(.medium))
        }
        .buttonStyle(.borderless)
        .padding(12)
    }

    private var isConfirmingFolderDelete: Binding<Bool> {
        Binding(
            get: { folderPendingDelete != nil },
            set: { if !$0 { folderPendingDelete = nil } }
        )
    }

    /// Asks for a name instead of silently inserting "New Folder". Creating
    /// several folders in a row used to yield identical "New Folder" entries.
    private func addFolder() {
        newFolderName = Self.nextFreeFolderName(existing: folders.map(\.name))
        isNamingNewFolder = true
    }

    private func createFolder(named typed: String) {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty
            ? Self.nextFreeFolderName(existing: folders.map(\.name))
            : trimmed
        let folder = Folder(name: name)
        modelContext.insert(folder)
        selection = .folder(folder)
        newFolderName = ""
    }

    /// "New Folder 1", "New Folder 2", … — the first not already in use.
    static func nextFreeFolderName(existing: [String]) -> String {
        let taken = Set(existing)
        var n = 1
        while taken.contains("New Folder \(n)") { n += 1 }
        return "New Folder \(n)"
    }

    private func delete(_ folder: Folder) {
        if renamingFolderID == folder.id {
            renamingFolderID = nil
        }
        if selection == .folder(folder) {
            selection = .allScripts
        }
        // Delete rule is `.nullify`: the folder's scripts survive and revert
        // to "no folder", i.e. they remain visible under All Scripts.
        modelContext.delete(folder)
    }
}
