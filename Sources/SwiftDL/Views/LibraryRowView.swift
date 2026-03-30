import SwiftUI

struct LibraryRowView: View {
    let item: LibraryItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film")
                .foregroundStyle(Color.accentColor)
                .imageScale(.large)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.body)

                HStack(spacing: 4) {
                    Text(item.fileSize.formattedFileSize)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(item.dateModified.relativeFormatted)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}
