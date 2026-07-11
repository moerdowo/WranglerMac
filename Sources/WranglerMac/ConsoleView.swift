import SwiftUI

/// Audit log: every wrangler command WranglerMac ran, with its output. Builds
/// trust and doubles as a learning aid ("what command did that button run?").
struct ConsoleView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: ConsoleEntry.ID?

    var body: some View {
        Group {
            if model.console.isEmpty {
                ContentUnavailableView("No commands yet", systemImage: "terminal",
                                       description: Text("Every wrangler command WranglerMac runs shows up here."))
            } else {
                List(model.console, selection: $selection) { entry in
                    DisclosureGroup {
                        RawOutputView(text: entry.output)
                            .frame(minHeight: 60, maxHeight: 260)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(entry.ok ? .green : .red)
                            Text(entry.command)
                                .font(.system(.callout, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            Text(entry.date, style: .time)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Console")
    }
}
