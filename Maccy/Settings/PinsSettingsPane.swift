import SwiftUI

struct PinsSettingsPane: View {
  @Environment(AppState.self) private var appState
  @State private var selection: UUID?

  private var items: [HistoryItemDecorator] {
    appState.history.pinnedItems
  }

  var body: some View {
    VStack(alignment: .leading) {
      Table(items, selection: $selection) {
        TableColumn(Text("Key", tableName: "PinsSettings")) { item in
          Button {
            appState.history.togglePin(item)
          } label: {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
          }
          .buttonStyle(.plain)
          .help("取消固定")
        }
        .width(60)

        TableColumn(Text("Application", tableName: "PreviewItemView")) { item in
          Text(item.application ?? "")
        }

        TableColumn(Text("Content", tableName: "PinsSettings")) { item in
          Text(item.title)
            .lineLimit(1)
        }
      }
      .onDeleteCommand {
        guard let selection,
              let item = appState.history.items.first(where: { $0.id == selection }) else {
          return
        }

        appState.history.delete(item)
      }

      Text("固定项只保留快速粘贴能力；旧版按键别名和内容编辑已删除。")
        .foregroundStyle(.gray)
        .controlSize(.small)
    }
    .frame(minWidth: 500, minHeight: 400)
    .padding()
    .task {
      try? await appState.history.load()
    }
  }
}

#Preview {
  PinsSettingsPane()
    .environment(AppState.shared)
}
