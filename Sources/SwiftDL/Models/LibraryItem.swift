import Foundation

struct LibraryItem: Identifiable {
    let id: UUID = UUID()
    let fileName: String
    let fileURL: URL
    let fileSize: Int64
    let dateModified: Date
}
