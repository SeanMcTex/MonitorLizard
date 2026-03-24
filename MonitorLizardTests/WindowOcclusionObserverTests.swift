import Testing
import AppKit
@testable import MonitorLizard

@MainActor
struct WindowOcclusionObserverTests {

    // MARK: Helpers

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
    }

    private func makeTrackingView(onChange: @escaping (Bool) -> Void) -> WindowOcclusionObserver.TrackingView {
        WindowOcclusionObserver.TrackingView(onChange: onChange)
    }

    // MARK: Observer registration

    @Test func observerRegistersOnWindowAttach() throws {
        let window = makeWindow()
        var received: [Bool] = []
        let view = makeTrackingView { received.append($0) }

        window.contentView = view
        // viewDidMoveToWindow fires synchronously when added to a window.
        // The initial-state async dispatch has not yet run, but the observer
        // should be registered for future notifications.
        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        // Notification is posted synchronously on the main queue observer,
        // so received should have one entry (window.occlusionState may or
        // may not be .visible in an offscreen test window, but onChange fired).
        #expect(received.count == 1)
    }

    @Test func observerDeregistersOnWindowDetach() {
        let window = makeWindow()
        var received: [Bool] = []
        let view = makeTrackingView { received.append($0) }

        window.contentView = view
        window.contentView = nil  // triggers viewDidMoveToWindow with window == nil

        let countAfterDetach = received.count
        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        // No additional calls after detach.
        #expect(received.count == countAfterDetach)
    }

    @Test func onChangeUpdatedAfterViewReuse() {
        let window = makeWindow()
        var firstCount = 0
        var secondCount = 0

        let view = makeTrackingView { _ in firstCount += 1 }
        window.contentView = view

        // Simulate updateNSView replacing the closure (as SwiftUI does on re-render).
        view.onChange = { _ in secondCount += 1 }

        NotificationCenter.default.post(
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }
}
