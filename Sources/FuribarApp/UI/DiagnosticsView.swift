import AppKit
import SwiftUI
import FuribarCore

/// Raw values, traffic, connection events and a raw sender. This is how the guessed parts of the
/// protocol (battery and firmware layouts, find-device sides) get checked against real earbuds,
/// and how a failed connection gets explained.
struct DiagnosticsContent: View {
    /// Nil while not connected: then only the connection events and the last session's traffic show.
    let session: DeviceSession?
    @Environment(ConnectionManager.self) private var manager
    @State private var payloadText = ""

    private var traffic: [LogEntry] { session?.log ?? manager.previousTraffic }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session {
                CardTitle(text: "Reported values")
                ReportedValues(state: session.state)
            }

            CardTitle(text: "Connection")
            LogList(entries: manager.events, height: session == nil ? 140 : 70)

            if !traffic.isEmpty {
                CardTitle(text: session == nil ? "Traffic from the last connection" : "Traffic")
                LogList(entries: traffic, height: 120)
            }

            if let session {
                HStack(spacing: 6) {
                    TextField("Raw payload, e.g. FA 0C", text: $payloadText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit { sendRaw(session) }
                    Button("Send") { sendRaw(session) }
                        .disabled(parsedPayload == nil)
                }
                Text("Sent as-is inside a frame. Reads (FA …) are safe; writes change the earbuds.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if let session {
                    Chip(title: "Read All Again", symbol: "arrow.clockwise", selected: false) { session.start() }
                }
                Chip(title: "Copy Log", symbol: "doc.on.doc", selected: false, action: copyLog)
            }
        }
    }

    /// The typed payload, if it's valid hex that fits in one frame.
    private var parsedPayload: [UInt8]? {
        guard let payload = Hex.parse(payloadText), payload.count <= FrameEncoder.maxPayloadLength else { return nil }
        return payload
    }

    private func sendRaw(_ session: DeviceSession) {
        guard let payload = parsedPayload else { return }
        session.sendRaw(payload)
    }

    private func copyLog() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        func lines(_ entries: [LogEntry]) -> [String] {
            entries.map { "  \(formatter.string(from: $0.date)) \(LogList.arrow($0.direction)) \($0.text)" }
        }
        var out = ["Furibar diagnostics", "Status: \(manager.status), transport: \(manager.transport?.rawValue ?? "none")"]
        if let session {
            out.append("Reported values:")
            for type in session.state.raw.keys.sorted() {
                out.append("  \(type.description) \(type.name): \(Hex.string(session.state.raw[type] ?? []))")
            }
        }
        out.append("Connection:")
        out += lines(manager.events)
        out.append(session == nil ? "Traffic from the last connection:" : "Traffic:")
        out += lines(traffic)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out.joined(separator: "\n"), forType: .string)
    }
}

private struct ReportedValues: View {
    let state: DeviceState

    var body: some View {
        if state.raw.isEmpty {
            Text("Nothing reported yet.").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(state.raw.keys.sorted(), id: \.self) { type in
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(type.description)  \(type.name)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(Hex.string(state.raw[type] ?? []))
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
    }
}

/// A scrolling list of log lines that follows the newest one.
private struct LogList: View {
    let entries: [LogEntry]
    let height: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(entries.suffix(80)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(Self.arrow(entry.direction))
                                .foregroundStyle(Self.color(entry.direction))
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
            .frame(height: height)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            // Keyed on the last entry, not the count: the count stops changing once the log is full.
            .onChange(of: entries.last?.id) {
                if let last = entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    static func arrow(_ d: LogEntry.Direction) -> String {
        switch d {
        case .sent: "→"
        case .received: "←"
        case .note: "•"
        }
    }

    static func color(_ d: LogEntry.Direction) -> Color {
        switch d {
        case .sent: Theme.hydro
        case .received: .green
        case .note: .secondary
        }
    }
}
