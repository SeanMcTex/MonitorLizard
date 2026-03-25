import Foundation
import Combine

@MainActor
class RefreshLogger: ObservableObject {
    static let shared = RefreshLogger()

    @Published var logs: String = ""
    private var lines: [String] = []
    private let maxLines = 200

    private init() {}

    func log(_ message: String) {
        let timestamp = Self.formatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        print(line)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        logs = lines.joined(separator: "\n")
    }

    func clear() {
        lines.removeAll()
        logs = ""
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
}
