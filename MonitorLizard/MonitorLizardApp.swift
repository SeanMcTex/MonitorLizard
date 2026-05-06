import AppKit
import Combine
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var retainedDelegate: AppDelegate?

    private var statusItemController: StatusItemController?

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate

        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let isDemoMode = CommandLine.arguments.contains("--demo-mode")
        let viewModel = PRMonitorViewModel(isDemoMode: isDemoMode)
        statusItemController = StatusItemController(viewModel: viewModel)

        _ = UpdateService.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private final class StatusItemController: NSObject, NSPopoverDelegate {
    private static let autosaveName = "MonitorLizard"
    private static let preferredPosition = 300

    private let viewModel: PRMonitorViewModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var warningIconObserver: AnyCancellable?
    private var visibilityObserver: NSKeyValueObservation?
    private var isRestoringVisibility = false

    init(viewModel: PRMonitorViewModel) {
        Self.seedStatusItemDefaults()

        self.viewModel = viewModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        observeViewModel()
        observeVisibility()
    }

    private func configureStatusItem() {
        statusItem.autosaveName = Self.autosaveName
        statusItem.behavior = []
        statusItem.isVisible = true

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "MonitorLizard"

        updateStatusIcon(showWarningIcon: viewModel.showWarningIcon)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: 450, height: 520)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(viewModel)
        )
    }

    private func observeViewModel() {
        warningIconObserver = viewModel.$showWarningIcon
            .receive(on: RunLoop.main)
            .sink { [weak self] showWarningIcon in
                self?.updateStatusIcon(showWarningIcon: showWarningIcon)
            }
    }

    private func observeVisibility() {
        visibilityObserver = statusItem.observe(\.isVisible, options: [.new]) { item, change in
            guard let isVisible = change.newValue else { return }
            print("[StatusItemController] status item visibility changed: \(isVisible)")
            if !isVisible {
                print("[StatusItemController] status item hidden by system; app remains running")
                Task { @MainActor [weak self] in
                    await self?.restoreVisibilityAfterSystemHide()
                }
            }
        }
    }

    private static func seedStatusItemDefaults() {
        let defaults = UserDefaults.standard

        for identity in ["Item-0", autosaveName] {
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(identity)")

            let preferredPositionKey = "NSStatusItem Preferred Position \(identity)"
            if defaults.object(forKey: preferredPositionKey) == nil {
                defaults.set(preferredPosition, forKey: preferredPositionKey)
            }
        }

        defaults.synchronize()
    }

    private func restoreVisibilityAfterSystemHide() async {
        guard !isRestoringVisibility else { return }
        isRestoringVisibility = true
        defer { isRestoringVisibility = false }

        for delay in [200_000_000, 1_000_000_000, 3_000_000_000] as [UInt64] {
            try? await Task.sleep(nanoseconds: delay)

            guard !statusItem.isVisible else { return }
            print("[StatusItemController] requesting status item visibility restore")
            statusItem.isVisible = true
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover(relativeTo: sender)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateStatusIcon(showWarningIcon: Bool) {
        guard let button = statusItem.button else { return }

        let symbolName = showWarningIcon ? "exclamationmark.triangle.fill" : "lizard"
        let fallbackName = showWarningIcon ? NSImage.cautionName : NSImage.applicationIconName
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MonitorLizard")
            ?? NSImage(named: fallbackName)

        image?.isTemplate = true
        button.image = image
        button.contentTintColor = showWarningIcon ? .systemRed : nil
    }
}
