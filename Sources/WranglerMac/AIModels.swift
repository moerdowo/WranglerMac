import SwiftUI

/// AI Models list — like the generic list, but each model opens a playground
/// that runs inference via the Cloudflare AI API.
struct AIModelsView: View {
    @Environment(AppModel.self) private var model
    @State private var items: [GenericItem] = []
    @State private var loading = true
    private let type = CFResources.aiModels

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    LoadingMatrix(caption: "LOADING AI MODELS", tint: type.tint)
                } else if items.isEmpty {
                    ContentUnavailableView("No models", systemImage: type.icon)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("AI Models").font(.title3).bold()
                                Spacer()
                                Text("^[\(items.count) model](inflect: true)").font(.callout).foregroundStyle(.secondary)
                            }.padding(.bottom, 2)
                            ForEach(items) { item in
                                NavigationLink(value: item) {
                                    ResourceCard(icon: "sparkles", tint: type.tint, title: item.title,
                                                 subtitle: item.subtitle, monospacedSubtitle: false)
                                }.buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: 640).frame(maxWidth: .infinity).padding(.horizontal, 28).padding(.vertical, 22)
                    }
                }
            }
            .background(.background)
            .navigationTitle("AI Models")
            .navigationDestination(for: GenericItem.self) { AIModelPlayground(item: $0) }
            .toolbar { ToolbarItem(placement: .primaryAction) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") } } }
            .task { if loading { await load() } }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        let r = await model.exec(["ai", "models", "list"])
        items = parseGenericItems(r.stdout, type: type)
    }
}

struct AIModelPlayground: View {
    @Environment(AppModel.self) private var model
    let item: GenericItem

    @State private var body_ = ""
    @State private var response = ""
    @State private var extracted: String?
    @State private var running = false
    @State private var error: String?

    private var task: String { item.subtitle ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                SectionBox(title: "Request", systemImage: "chevron.left.forwardslash.chevron.right") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("POST /ai/run/\(item.id)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        TextEditor(text: $body_)
                            .font(.system(.callout, design: .monospaced))
                            .frame(height: 120)
                            .padding(6)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                        HStack {
                            Spacer()
                            Button { Task { await run() } } label: {
                                if running { Text("Running…") } else { Label("Run", systemImage: "play.fill") }
                            }
                            .buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                            .disabled(running || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
                if let extracted {
                    SectionBox(title: "Response", systemImage: "text.bubble") {
                        Text(extracted).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !response.isEmpty {
                    SectionBox(title: extracted == nil ? "Response" : "Raw JSON", systemImage: "curlybraces") {
                        ScrollView(.horizontal) {
                            Text(response).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 260)
                    }
                }
            }
            .frame(maxWidth: 700).frame(maxWidth: .infinity).padding(24)
        }
        .navigationTitle(item.title)
        .navigationSubtitle("AI model")
        .onAppear { if body_.isEmpty { body_ = defaultBody() } }
    }

    private var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0xF7B733), Color(hex: 0xF39C12)], startPoint: .top, endPoint: .bottom))
                .frame(width: 52, height: 52)
                .overlay(Image(systemName: "sparkles").foregroundStyle(.white).font(.title2))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.title3).bold().textSelection(.enabled).lineLimit(1)
                if !task.isEmpty { Text(task).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
    }

    private func defaultBody() -> String {
        let t = task.lowercased()
        if t.contains("embedding") { return "{\n  \"text\": [\"Hello, world!\"]\n}" }
        if t.contains("text-to-image") || t.contains("image") && !t.contains("image-to") { return "{\n  \"prompt\": \"a friendly robot waving\"\n}" }
        if t.contains("classification") { return "{\n  \"text\": \"I absolutely love this!\"\n}" }
        if t.contains("translation") { return "{\n  \"text\": \"Hello\",\n  \"source_lang\": \"en\",\n  \"target_lang\": \"es\"\n}" }
        if t.contains("speech") || t.contains("automatic speech") { return "{\n  \"audio\": []\n}" }
        // default: chat / text generation
        return "{\n  \"messages\": [\n    { \"role\": \"user\", \"content\": \"Tell me a fun fact about the ocean.\" }\n  ]\n}"
    }

    private func run() async {
        running = true; defer { running = false }
        response = ""; extracted = nil; error = nil
        guard let account = model.activeAccountID, let token = await model.freshToken() else {
            error = "Not signed in."; return
        }
        do {
            let out = try await CloudflareAPI.runAI(account: account, model: item.id, body: body_, token: token)
            response = out
            extracted = extractText(out)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Pull the human-readable text out of a text-generation response.
    private func extractText(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = obj["result"] as? [String: Any] else { return nil }
        if let r = result["response"] as? String { return r }
        if let translated = result["translated_text"] as? String { return translated }
        return nil
    }
}
