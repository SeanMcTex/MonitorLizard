import SwiftUI

private struct ScrollViewHoveredKey: EnvironmentKey {
    // Default true so rows outside the scroll view context don't have their hover cleared.
    static let defaultValue = true
}

extension EnvironmentValues {
    var scrollViewHovered: Bool {
        get { self[ScrollViewHoveredKey.self] }
        set { self[ScrollViewHoveredKey.self] = newValue }
    }
}

extension ReviewDecision {
    var color: Color {
        switch self {
        case .approved:         return .green
        case .changesRequested: return .red
        case .reviewRequired:   return .secondary
        }
    }
}

extension NonBlockingCheckState {
    var color: Color {
        switch self {
        case .failed, .waitingForApproval:
            return .orange.opacity(0.85)
        case .running, .queued, .pending:
            return .blue.opacity(0.85)
        case .passed:
            return .green.opacity(0.85)
        }
    }
}

extension PRStackReadiness {
    var color: Color {
        switch status {
        case .allReady, .readyToAdvance: return .green
        case .blocked:                   return .orange
        case .unknown:                   return .secondary
        }
    }
}

struct PRRowView: View {
    let pr: PullRequest

    /// Where this PR sits in its stack, when it renders as a part inside a stack
    /// block. Stack parts use a one-line layout so long stacks stay scannable.
    let stackContext: PRListRow.StackRowContext?

    @EnvironmentObject var viewModel: PRMonitorViewModel
    @Environment(\.scrollViewHovered) private var scrollViewHovered

    @State private var isHovering = false

    private var isStackPart: Bool { stackContext != nil }

    init(pr: PullRequest, stackContext: PRListRow.StackRowContext? = nil) {
        self.pr = pr
        self.stackContext = stackContext
    }

    nonisolated static func daysSinceUpdate(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let updateDay = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: updateDay, to: today).day ?? 0
    }

    private var daysSinceUpdate: Int {
        PRRowView.daysSinceUpdate(from: pr.updatedAt)
    }

    /// Dimming for text content of stack parts the viewer already approved, so
    /// unreviewed parts stand out. Badges and status icons stay full-color.
    private var approvedRowTextOpacity: Double {
        pr.isApprovedByViewer ? 0.55 : 1
    }

    /// Green seal marking PRs the authenticated viewer has already approved.
    /// Icon-only so it never pushes the row's text into wrapping; the caller
    /// picks the font size to fit its layout.
    private func viewerApprovedSeal(font: Font, help: String) -> some View {
        Image(systemName: "checkmark.seal.fill")
            .font(font)
            .foregroundColor(.green)
            .fixedSize()
            .help(help)
    }

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

    private var daysSinceUpdateText: String {
        if daysSinceUpdate == 0 {
            return "updated today \(pr.updatedAt.formatted(.dateTime.hour().minute()))"
        } else if daysSinceUpdate == 1 {
            return "updated 1 day ago"
        } else {
            return "updated \(daysSinceUpdate) days ago"
        }
    }

    private var failingChecks: [StatusCheck] {
        pr.statusChecks.filter { check in
            !check.isNonBlocking && (check.status == .failure || check.status == .error)
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
            } else if let systemImageName = pr.buildStatus.systemImageName {
                Image(systemName: systemImageName)
                    .foregroundColor(pr.buildStatus.color)
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
        Group {
            if let stackContext {
                HStack(spacing: 12) {
                    compactBody(stackContext)
                    PRRowActions(pr: pr, isHovering: isHovering, onOpen: openPRURL)
                }
            } else {
                fullBody
            }
        }
        .padding(.leading, isStackPart ? 36 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, isStackPart ? 6 : 10)
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
        .onChange(of: scrollViewHovered) {
            if !scrollViewHovered && isHovering { isHovering = false }
        }
        .onTapGesture {
            openPRURL()
        }
    }

    /// Two compact lines per stack part: position, number, title, and state, then the
    /// branch and labels. The stack's identity and blocking state live in the block
    /// header instead of on every row.
    private func compactBody(_ context: PRListRow.StackRowContext) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("\(context.position)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
                    .help("Part \(context.position) of \(context.size)")

                if pr.isApprovedByViewer {
                    viewerApprovedSeal(font: .system(size: 10), help: "You approved this part")
                }

                if context.isBlocking {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .help(context.blockingReason.map { reason in
                            "Blocks the rest of the stack from advancing — \(reason)"
                        } ?? "Blocks the rest of the stack from advancing")
                }

                Text("#\(pr.number, format: .number.grouping(.never))")
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Companions are someone else's PRs fetched to complete a stack,
                // so the row shows who authored them.
                if viewModel.isStackCompanion(pr) {
                    Text("@\(pr.author.login)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(pr.displayTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(approvedRowTextOpacity)

                if pr.isDraft {
                    Text("DRAFT")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.8))
                        .cornerRadius(3)
                }

                Spacer(minLength: 4)

                HStack(spacing: 4) {
                    compactStatusIcon
                    Text(pr.buildStatus.displayName)
                        .font(.caption)
                        .foregroundColor(pr.buildStatus.color)
                        .opacity(approvedRowTextOpacity)
                }
            }

            if !pr.headRefName.isEmpty || !pr.labels.isEmpty {
                HStack(spacing: 6) {
                    if !pr.headRefName.isEmpty {
                        Image(systemName: "arrow.branch")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .opacity(approvedRowTextOpacity)

                        Text(pr.headRefName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .opacity(approvedRowTextOpacity)
                    }

                    ForEach(pr.labels) { label in
                        let bgColor = Color(hex: label.color)
                        Text(label.name)
                            .font(.system(size: 9))
                            .foregroundColor(bgColor.contrastingTextColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(bgColor)
                            .cornerRadius(3)
                            .opacity(approvedRowTextOpacity)
                    }
                }
            }
        }
        .help(context.helpText)
        .accessibilityLabel("Stack part \(context.position) of \(context.size), PR \(pr.number), \(pr.buildStatus.displayName)\(pr.isApprovedByViewer ? ", approved by you" : "")")
    }

    private var compactStatusIcon: some View {
        Group {
            if pr.buildStatus == .pending {
                Image(systemName: "gear")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            } else if let systemImageName = pr.buildStatus.systemImageName {
                Image(systemName: systemImageName)
                    .font(.system(size: 10))
                    .foregroundColor(pr.buildStatus.color)
            } else {
                Text(pr.buildStatus.icon)
                    .font(.system(size: 10))
            }
        }
    }

    private var fullBody: some View {
        HStack(spacing: 12) {
            statusIconsColumn

            VStack(alignment: .leading, spacing: 4) {
                // PR Title
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pr.displayTitle)
                        .font(.body)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if pr.isApprovedByViewer {
                        viewerApprovedSeal(font: .body, help: "You approved this PR")
                    }
                }

                // Repo and PR number
                HStack(spacing: 4) {
                    Text(pr.repository.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("#\(pr.number, format: .number.grouping(.never))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Draft badge
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

                }

                // Branch name
                if !pr.headRefName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.branch")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(pr.headRefName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                // Build status text with days since update
                HStack(spacing: 4) {
                    Text(pr.buildStatus.displayName)
                        .font(.caption2)
                        .foregroundColor(pr.buildStatus.color)

                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("(\(daysSinceUpdateText))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let summary = pr.nonBlockingCheckSummary {
                    HStack(spacing: 4) {
                        Text("Non-blocking:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(summary.segments) { segment in
                            Text(segment.text + (segment.id == summary.segments.last?.id ? "" : ","))
                                .font(.caption2)
                                .foregroundStyle(segment.state.color)
                        }
                    }
                    .lineLimit(1)
                    .help("These checks do not block merging.")
                }

                // Labels
                if !pr.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(pr.labels) { label in
                            let bgColor = Color(hex: label.color)
                            Text(label.name)
                                .font(.caption2)
                                .foregroundColor(bgColor.contrastingTextColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(bgColor)
                                .cornerRadius(3)
                        }
                    }
                }

                // Failing checks (only shown when checks fail)
                if !failingChecks.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Failed checks:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

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

            Spacer()

            PRRowActions(pr: pr, isHovering: isHovering, onOpen: openPRURL)
        }
    }
}

/// The per-PR action column: watch, open, copy link, rename, and remove for pinned
/// PRs. Shared by full rows and stacked part rows; the buttons reveal on hover.
private struct PRRowActions: View {
    let pr: PullRequest
    let isHovering: Bool
    let onOpen: () -> Void

    @EnvironmentObject var viewModel: PRMonitorViewModel

    private var watchHelpText: String {
        let memberCount = viewModel.stackMemberCount(for: pr)
        if pr.isWatched {
            return memberCount > 1 ? "Stop watching this stack (\(memberCount) PRs)" : "Stop watching this PR"
        }
        return memberCount > 1 ? "Watch this stack (\(memberCount) PRs)" : "Watch this PR for completion"
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

    private func removeFromOtherPRs() {
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
    }

    var body: some View {
        // 2x2 grid: [Watch, Open] / [Delete, Copy, Rename]
        // Always occupies space; opacity controls visibility.
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    // Watch - fixed cell; unstacked PRs without checks stay hidden
                    if pr.hasStatusChecks || pr.stack != nil {
                        Button(action: { viewModel.toggleWatch(for: pr) }) {
                            Image(systemName: pr.isWatched ? "eye.fill" : "eye")
                                .font(.system(size: 13))
                                .foregroundColor(pr.isWatched ? .blue : .gray)
                        }
                        .buttonStyle(.plain)
                        .help(watchHelpText)
                        .opacity(isHovering || pr.isWatched ? 1.0 : 0.0)
                        .frame(width: 16, height: 16)
                    } else {
                        Color.clear.frame(width: 16, height: 16)
                    }

                    // Open in browser
                    Button(action: onOpen) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 13))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help("Open in GitHub")
                    .opacity(isHovering ? 1.0 : 0.0)
                    .frame(width: 16, height: 16)
                }
                .frame(width: 64, alignment: .trailing)

                // Bottom row: Delete (pinned Other PRs only) + Copy Link + Rename
                HStack(spacing: 8) {
                    if pr.type == .other && viewModel.isPinnedPR(pr) {
                        Button(action: removeFromOtherPRs) {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove from Other PRs")
                        .opacity(isHovering ? 1.0 : 0.0)
                        .frame(width: 16, height: 16)
                    }

                    Button(action: {
                        viewModel.copyPRLink(for: pr)
                    }) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.copiedPRID == pr.id ? "Copied!" : "Copy PR link")
                    .opacity(isHovering ? 1.0 : 0.0)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Text("Copied")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.75))
                            .cornerRadius(4)
                            .fixedSize()
                            .offset(y: 22)
                            .opacity(viewModel.copiedPRID == pr.id ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.15), value: viewModel.copiedPRID),
                        alignment: .bottom
                    )

                    Button(action: showRenameDialog) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                            .foregroundColor(pr.customName != nil ? .blue : .gray)
                    }
                    .buttonStyle(.plain)
                    .help(pr.customName != nil ? "Edit custom name" : "Set custom name")
                    .opacity(isHovering ? 1.0 : 0.0)
                    .frame(width: 16, height: 16)
                }
                .frame(width: 64, alignment: .trailing)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 64, alignment: .trailing) // Fixed width: fits 3-icon row (Other PRs)
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
