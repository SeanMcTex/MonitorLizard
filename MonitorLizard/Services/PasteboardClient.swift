import Dependencies
import AppKit

protocol PasteboardClient: Sendable {
    func copy(_ string: String)
    func read() -> String?
}

final class LivePasteboardClient: PasteboardClient, @unchecked Sendable {
    func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }
}

final class TestPasteboardClient: PasteboardClient, @unchecked Sendable {
    private var contents: String?

    func copy(_ string: String) {
        contents = string
    }

    func read() -> String? {
        contents
    }
}