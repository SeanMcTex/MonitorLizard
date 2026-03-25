import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    @EnvironmentObject var viewModel: PRMonitorViewModel

    @State private var isHovering = false

    private func openPRURL() {
        // Close the menu bar extra by ordering out all panels
        NSApp.windows.forEach { window in
            if window is NSPanel {
                window.orderOut(nil)
            }
        }

        // Open the URL
        if let url = URL(string: pr.url) {
            NSWorkspace.shared.open(url)
        }
    }

    private var updatedAgoText: String {
        let seconds = Int(Date().timeIntervalSince(pr.updatedAt))
        if seconds < 60 {
            return "just updated"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return minutes == 1 ? "updated 1 minute ago" : "updated \(minutes) minutes ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return hours == 1 ? "updated 1 hour ago" : "updated \(hours) hours ago"
        } else {
            let days = seconds / 86400
            return days == 1 ? "updated 1 day ago" : "updated \(days) days ago"
        }
    }

    private var buildStatusText: String {
        if pr.buildStatus == .pending {
            let pendingCount = pr.statusChecks.filter { $0.status == .pending }.count
            return pendingCount > 0 ? "\(pendingCount) checks pending" : pr.buildStatus.displayName
        }
        if pr.buildStatus == .failure || pr.buildStatus == .error {
            let pendingCount = pr.statusChecks.filter { $0.status == .pending }.count
            return pendingCount > 0 ? "\(pr.buildStatus.displayName) (\(pendingCount) pending)" : pr.buildStatus.displayName
        }
        return pr.buildStatus.displayName
    }

    private var pendingChecksTooltipLines: [InstantTooltip.Line] {
        guard pr.buildStatus == .pending || pr.buildStatus == .failure || pr.buildStatus == .error else { return [] }
        return pr.statusChecks
            .filter { $0.status == .pending }
            .map { check in
            InstantTooltip.Line(icon: check.status.icon, text: check.name)
        }
    }

    private var failingChecks: [StatusCheck] {
        pr.statusChecks.filter { check in
            check.status == .failure || check.status == .error
        }
    }

    private func showRenameDialog() {
        NSApp.windows.forEach { window in
            if window is NSPanel { window.orderOut(nil) }
        }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Custom Display Name"
            alert.informativeText = "Enter a name to override the GitHub title, or clear it to restore the original."
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
            field.stringValue = pr.customName ?? ""
            field.placeholderString = pr.title
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            if pr.customName != nil {
                alert.addButton(withTitle: "Reset to GitHub Title")
            }
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                viewModel.renamePR(pr, to: name.isEmpty ? nil : name)
            case .alertThirdButtonReturn:
                viewModel.renamePR(pr, to: nil)
            default:
                break
            }
        }
    }

    private func openCheckURL(_ urlString: String?) {
        guard let urlString = urlString,
              let url = URL(string: urlString) else {
            return
        }

        // Close menu bar panels
        NSApp.windows.forEach { window in
            if window is NSPanel {
                window.orderOut(nil)
            }
        }

        NSWorkspace.shared.open(url)
    }

    private let iconColumnWidth: CGFloat = 30

    private var buildStatusIcon: some View {
        Group {
            if pr.buildStatus == .pending {
                if #available(macOS 15.0, *) {
                    Image(systemName: "gear")
                        .foregroundColor(.gray)
                        .font(.title2)
                        .symbolEffect(.rotate.byLayer, options: .repeat(.continuous))
                } else {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            } else if pr.buildStatus == .success {
                Image(systemName: "gear.badge.checkmark")
                    .foregroundColor(.green)
                    .font(.title2)
            } else if pr.buildStatus == .failure || pr.buildStatus == .error {
                Image(systemName: "gear.badge.xmark")
                    .foregroundColor(.red)
                    .font(.title2)
            } else {
                Text(pr.buildStatus.icon)
                    .font(.title2)
            }
        }
    }

    private var statusIconsColumn: some View {
        VStack(spacing: 8) {
            // Review indicator (for PRs awaiting review)
            if pr.type == .reviewing {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundColor(.blue)
                    .font(.title2)
                    .help("Awaiting your review")
                    .frame(width: iconColumnWidth, height: 24)
            }

            // Build status icon
            buildStatusIcon
                .frame(width: iconColumnWidth, height: 24)

            if let decision = pr.reviewDecision {
                Image(systemName: decision.systemImageName)
                    .foregroundColor(decision.color)
                    .font(.title2)
                    .help(decision.helpText)
                    .offset(x: 2)
                    .frame(width: iconColumnWidth, height: 24)
            }
        }
        .frame(width: iconColumnWidth)
    }

    var body: some View {
        HStack(spacing: 12) {
            statusIconsColumn

            VStack(alignment: .leading, spacing: 4) {
                // PR Title
                Text(pr.displayTitle)
                    .font(.body)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Repo, PR number, branch
                HStack(spacing: 4) {
                    Text(pr.repository.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("#\(pr.number)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if pr.isDraft {
                        Text("DRAFT")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.8))
                            .cornerRadius(3)
                    }

                    if !pr.headRefName.isEmpty {
                        Image(systemName: "arrow.branch")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(pr.headRefName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Labels
                if !pr.labels.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(pr.labels) { label in
                            let bgColor = Color(hex: label.color)
                            Text(label.name)
                                .font(.caption2)
                                .foregroundColor(bgColor.contrastingTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(bgColor)
                                .cornerRadius(3)
                                .fixedSize()
                        }
                    }
                }

                // Build status text with days since update
                HStack(spacing: 4) {
                    Text(buildStatusText)
                        .font(.caption2)
                        .foregroundColor(pr.buildStatus.color)
                        .overlay {
                            if !pendingChecksTooltipLines.isEmpty {
                                InstantTooltip(lines: pendingChecksTooltipLines)
                            }
                        }

                    if pr.ignoredCheckCount > 0 {
                        Text("(\(pr.ignoredCheckCount) ignored)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(updatedAgoText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Failing checks (only shown when checks fail)
                if !failingChecks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(failingChecks) { check in
                            Button(action: {
                                openCheckURL(check.detailsUrl)
                            }) {
                                HStack(spacing: 4) {
                                    Text(check.status.icon)
                                        .font(.caption)
                                    Text(check.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Open \(check.name) details")
                        }
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)

            // Action buttons - vertical strip at right edge.
            // Always rendered with fixed width to reserve space and
            // prevent layout shifts (title/tags rewrapping) on hover.
            VStack(spacing: 4) {
                if pr.hasStatusChecks {
                    Button(action: { viewModel.toggleWatch(for: pr) }) {
                        Image(systemName: pr.isWatched ? "eye.fill" : "eye")
                            .foregroundColor(pr.isWatched ? .blue : .gray)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help(pr.isWatched ? "Stop watching this PR" : "Watch this PR for completion")
                    .opacity(isHovering || pr.isWatched ? 1.0 : 0.0)
                    .frame(width: 16, height: 16)
                }

                Button(action: openPRURL) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Open in GitHub")
                .opacity(isHovering ? 1.0 : 0.0)
                .frame(width: 16, height: 16)

                if pr.type == .other {
                    Button(action: {
                        NSApp.windows.forEach { window in
                            if window is NSPanel { window.orderOut(nil) }
                        }
                        DispatchQueue.main.async {
                            let alert = NSAlert()
                            alert.messageText = "Remove from Other PRs?"
                            alert.informativeText = "\"\(pr.displayTitle)\" will be removed from Other PRs."
                            alert.addButton(withTitle: "Remove")
                            alert.addButton(withTitle: "Cancel")
                            alert.alertStyle = .warning
                            if alert.runModal() == .alertFirstButtonReturn {
                                viewModel.removeOtherPR(pr)
                            }
                        }
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Other PRs")
                    .opacity(isHovering ? 1.0 : 0.0)
                    .frame(width: 16, height: 16)
                }

                Button(action: showRenameDialog) {
                    Image(systemName: "pencil")
                        .foregroundColor(pr.customName != nil ? .blue : .gray)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(pr.customName != nil ? "Edit custom name" : "Set custom name")
                .opacity(isHovering ? 1.0 : 0.0)
                .frame(width: 16, height: 16)
            }
            .frame(width: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        // Use onContinuousHover instead of onHover to avoid an infinite
        // SwiftUI update loop. During scrolling, LazyVStack recycles views,
        // which can rapid-fire .onHover events. Each event sets @State,
        // triggering a view update that causes more recycling and more hover
        // events, freezing the app in AG::Graph::UpdateStack::update.
        // The guards prevent redundant state writes from triggering updates.
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if !isHovering { isHovering = true }
            case .ended:
                if isHovering { isHovering = false }
            }
        }
        .onTapGesture {
            openPRURL()
        }
    }
}

/// An NSViewRepresentable that sets an instant tooltip on the parent view.
/// Unlike SwiftUI's `.help()`, this shows immediately on hover and works
/// even when the app is not focused (menu bar / floating window).
struct InstantTooltip: NSViewRepresentable {
    struct Line {
        let icon: String
        let text: String
    }

    let lines: [Line]

    func makeNSView(context: Context) -> TooltipView {
        TooltipView(lines: lines)
    }

    func updateNSView(_ nsView: TooltipView, context: Context) {
        nsView.updateTooltip(lines)
    }

    class TooltipView: NSView {
        private var lines: [Line]
        private var trackingArea: NSTrackingArea?
        private var tooltipWindow: NSWindow?
        private var scrollObserver: NSObjectProtocol?

        init(lines: [Line]) {
            self.lines = lines
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        func updateTooltip(_ lines: [Line]) {
            self.lines = lines
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area = trackingArea {
                removeTrackingArea(area)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateScrollObserver()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            updateScrollObserver()
        }

        override func mouseEntered(with event: NSEvent) {
            showTooltip()
        }

        override func mouseExited(with event: NSEvent) {
            hideTooltip()
        }

        override func removeFromSuperview() {
            removeScrollObserver()
            hideTooltip()
            super.removeFromSuperview()
        }

        deinit {
            removeScrollObserver()
        }

        private func showTooltip() {
            guard !lines.isEmpty else { return }
            hideTooltip()

            let padding: CGFloat = 6
            let rowSpacing: CGFloat = 3
            let iconFont = NSFont(name: "Apple Color Emoji", size: NSFont.smallSystemFontSize) ?? .systemFont(ofSize: NSFont.smallSystemFontSize)
            let textFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)

            let rows = lines.map { line -> NSView in
                let iconLabel = NSTextField(labelWithString: line.icon)
                iconLabel.font = iconFont
                iconLabel.backgroundColor = .clear

                let textLabel = NSTextField(labelWithString: line.text)
                textLabel.font = textFont
                textLabel.textColor = .labelColor
                textLabel.backgroundColor = .clear

                let row = NSStackView(views: [iconLabel, textLabel])
                row.orientation = .horizontal
                row.alignment = .firstBaseline
                row.spacing = 6
                return row
            }

            let stack = NSStackView(views: rows)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = rowSpacing
            stack.edgeInsets = NSEdgeInsets(top: padding, left: padding, bottom: padding, right: padding)
            stack.layoutSubtreeIfNeeded()

            let fittingSize = stack.fittingSize
            let contentSize = NSSize(width: fittingSize.width, height: fittingSize.height)

            let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
            contentView.wantsLayer = true
            contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            contentView.layer?.borderColor = NSColor.separatorColor.cgColor
            contentView.layer?.borderWidth = 0.5
            contentView.layer?.cornerRadius = 4
            stack.frame = contentView.bounds
            stack.autoresizingMask = [.width, .height]
            contentView.addSubview(stack)

            let screenPoint = window?.convertPoint(toScreen: convert(NSPoint(x: bounds.midX, y: bounds.maxY), to: nil)) ?? .zero
            let origin = NSPoint(
                x: screenPoint.x - contentSize.width / 2,
                y: screenPoint.y + 4
            )

            let tipWindow = NSWindow(
                contentRect: NSRect(origin: origin, size: contentSize),
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            tipWindow.isOpaque = false
            tipWindow.backgroundColor = .clear
            tipWindow.level = .floating
            tipWindow.contentView = contentView
            tipWindow.orderFront(nil)
            tooltipWindow = tipWindow
        }

        private func hideTooltip() {
            tooltipWindow?.orderOut(nil)
            tooltipWindow = nil
        }

        private func updateScrollObserver() {
            removeScrollObserver()
            guard let clipView = enclosingScrollView()?.contentView else { return }
            clipView.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self] _ in
                self?.hideTooltipIfMouseLeftBounds()
            }
        }

        private func removeScrollObserver() {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
        }

        private func hideTooltipIfMouseLeftBounds() {
            guard tooltipWindow != nil, let window else { return }
            let mouseLocationInWindow = window.mouseLocationOutsideOfEventStream
            let mouseLocationInView = convert(mouseLocationInWindow, from: nil)
            if !bounds.contains(mouseLocationInView) {
                hideTooltip()
            }
        }

        private func enclosingScrollView() -> NSScrollView? {
            var currentView = superview
            while let view = currentView {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }
                currentView = view.superview
            }
            return nil
        }
    }
}

/// A simple wrapping flow layout that places children left-to-right,
/// moving to the next row when a child would exceed the available width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    var contrastingTextColor: Color {
        // Convert to NSColor to get RGB components
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else {
            return .white
        }

        let red = nsColor.redComponent
        let green = nsColor.greenComponent
        let blue = nsColor.blueComponent

        // Calculate relative luminance using WCAG formula
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue

        // Use black text for light backgrounds, white for dark
        return luminance > 0.5 ? .black : .white
    }
}
