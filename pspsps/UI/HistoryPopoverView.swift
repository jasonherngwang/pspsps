import SwiftUI

struct HistoryPopoverView: View {
    @ObservedObject var history: TranscriptHistory
    let textPaster: TextPaster

    @State private var searchQuery = ""

    private var filteredEntries: [TranscriptEntry] {
        history.search(query: searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search history", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if filteredEntries.isEmpty {
                Text(searchQuery.isEmpty ? "No history yet" : "No results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        HistoryEntryRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                textPaster.paste(entry.text)
                            }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            history.delete(id: filteredEntries[index].id)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 320, height: 400)
    }
}

private struct HistoryEntryRow: View {
    let entry: TranscriptEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.text.prefix(120).description)
                .lineLimit(2)
                .font(.body)
            HStack(spacing: 6) {
                Text(entry.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let app = entry.sourceApp {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(app)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, 2)
    }
}
