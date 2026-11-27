import SwiftUI
import ThingsBarCore

struct PopoverView: View {
    let store: TodoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(store.settings.source.name).font(.headline)
                Spacer()
                Text("\(store.visibleItems.count)").foregroundStyle(.secondary)
            }
            .padding(12)
            Divider()
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.red).padding(12)
            }
            if store.visibleItems.isEmpty {
                Text(store.isLoading ? "Loading…" : "Nothing here").foregroundStyle(.secondary).padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(store.visibleItems) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                if let project = store.catalog.projectName(for: item.projectID) {
                                    Text(project).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                    }
                }
                .frame(maxHeight: 360)
            }
            Divider()
            HStack {
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .padding(12)
        }
        .frame(width: 340)
    }
}
