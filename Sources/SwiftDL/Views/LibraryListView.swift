import SwiftUI

struct LibraryListView: View {
    @Environment(LibraryManager.self) private var libraryManager

    @State private var itemToDelete: LibraryItem?
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader

            Divider()

            if libraryManager.items.isEmpty {
                ContentUnavailableView(
                    "No Downloaded Files",
                    systemImage: "folder",
                    description: Text("Downloaded videos will appear here")
                )
                .frame(minHeight: 120)
            } else {
                List(libraryManager.items) { item in
                    LibraryRowView(item: item)
                        .contextMenu {
                            Button {
                                libraryManager.openItem(item)
                            } label: {
                                Label("Open in Player", systemImage: "play.circle")
                            }

                            Button {
                                libraryManager.showInFinder(item)
                            } label: {
                                Label("Show in Finder", systemImage: "folder")
                            }

                            Divider()

                            Button(role: .destructive) {
                                confirmDelete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                confirmDelete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .alert(
            "Delete File",
            isPresented: $showDeleteAlert,
            presenting: itemToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                libraryManager.deleteItem(item)
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text("\"\(item.fileName)\" will be permanently deleted from disk.")
        }
    }

    private var sectionHeader: some View {
        HStack {
            Label("Library", systemImage: "folder.fill")
                .font(.headline)
            Spacer()
            if !libraryManager.items.isEmpty {
                Text("\(libraryManager.items.count) file\(libraryManager.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 8)
    }

    private func confirmDelete(_ item: LibraryItem) {
        itemToDelete = item
        showDeleteAlert = true
    }
}
