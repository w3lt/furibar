import AppKit
import SwiftUI
import FuribarCore

/// Raw values, traffic log and a raw sender. This is how the guessed parts of the protocol
/// (battery and firmware layouts, find-device sides) get checked against real earbuds.
struct DiagnosticsContent: View {
    let session: DeviceSession
    @State private var payloadText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle(text: "Reported values")
            if session.state.raw.isEmpty {
                Text("Nothing reported yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                VStack(spacing: 3) {
                    ForEach(session.state.raw.keys.sorted(), id: \.self) { type in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(type.description)  \(type.name)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Hex.string(session.state.raw[type] ?? []))
                                .font(.system(size: 10, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.trailing, 4)
                }
                .frame(height: 96)
            }

            CardTitle(text: "Traffic")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(session.log.suffix(80)) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(arrow(entry.direction))
                                    .foregroundStyle(color(entry.direction))
                                Text(entry.text)
                                    .foregroundStyle(entry.direction == .note ? .secondary : .primary)
                            }
                            .font(.system(size: 9.5, design: .monospaced))
                            .textSelection(.enabled)
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .onChange(of: session.log.count) {
                    if let last = session.log.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            HStack(spacing: 6) {
                TextField("Raw payload, e.g. FA 0C", text: $payloadText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .onSubmit(sendRaw)
                Button("Send", action: sendRaw)
                    .disabled(Hex.parse(payloadText) == nil)
            }
            Text("Sent as-is inside a frame. Reads (FA …) are safe; writes change the earbuds.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Chip(title: "Read All Again", symbol: "arrow.clockwise", selected: false) { session.start() }
                Chip(title: "Copy Log", symbol: "doc.on.doc", selected: false, action: copyLog)
            }
        }
    }

    private func sendRaw() {
        guard let payload = Hex.parse(payloadText) else { return }
        session.sendRaw(payload)
    }

    private func copyLog() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        var lines = ["Furibar diagnostics", "Reported values:"]
        for type in session.state.raw.keys.sorted() {
            lines.append("  \(type.description) \(type.name): \(Hex.string(session.state.raw[type] ?? []))")
        }
        lines.append("Traffic:")
        for entry in session.log {
            lines.append("  \(formatter.string(from: entry.date)) \(arrow(entry.direction)) \(entry.text)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    private func arrow(_ d: LogEntry.Direction) -> String {
        switch d {
        case .sent: "→"
        case .received: "←"
        case .note: "•"
        }
    }

    private func color(_ d: LogEntry.Direction) -> Color {
        switch d {
        case .sent: Theme.hydro
        case .received: .green
        case .note: .secondary
        }
    }
}
