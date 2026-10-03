import SwiftUI

/// The row that introduces a stack block. It carries the stack's identity and state
/// once, instead of repeating position chips on every part, and collapses the block.
struct StackHeaderView: View {
    let header: PRStackHeader
    @EnvironmentObject var viewModel: PRMonitorViewModel
    @Environment(\.scrollViewHovered) private var scrollViewHovered

    @State private var isHovering = false

    private var isCollapsed: Bool {
        viewModel.isStackCollapsed(header.stackID)
    }

    private var isWatched: Bool {
        viewModel.isStackWatched(header.stackID)
    }

    private var watchHelpText: String {
        let count = viewModel.stackMemberCount(forStackID: header.stackID)
        if isWatched {
            return "Stop watching this stack (\(count) PRs)"
        }
        return "Watch this stack (\(count) PRs)"
    }

    private var openAllHelpText: String {
        let count = viewModel.stackParts(inStack: header.stackID).count
        return count == 1
            ? "Open the PR in GitHub"
            : "Open all \(count) PRs in GitHub, starting with part 1"
    }

    private func openAllPRs() {
        let parts = viewModel.stackParts(inStack: header.stackID)
        guard !parts.isEmpty else { return }

        // Close the menu bar extra before the browser takes focus
        NSApp.windows.forEach { window in
            if window is NSPanel {
                window.orderOut(nil)
            }
        }

        for pr in parts {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // The padding lives inside the button so the whole strip, including the
            // space around the chevron, is clickable. Backed by a content shape,
            // the hit area stays this size even though the chevron is 10 pt wide.
            Button(action: { viewModel.toggleStackCollapse(header.stackID) }) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 10)

                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 12))
                        .foregroundColor(header.readiness.color)

                    Text("Stack #\(header.number)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(header.summary)
                        .font(.caption)
                        .foregroundColor(summaryColor)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(header.helpText)
            .accessibilityLabel("Stack \(header.number). \(header.summary)")
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint(isCollapsed ? "Expands the stack" : "Collapses the stack")

            // Watch - applies to every known part of the stack
            Button(action: { viewModel.toggleWatchForStack(header.stackID) }) {
                Image(systemName: isWatched ? "eye.fill" : "eye")
                    .font(.system(size: 13))
                    .foregroundColor(isWatched ? .blue : .gray)
            }
            .buttonStyle(.plain)
            .help(watchHelpText)
            .opacity(isHovering || isWatched ? 1.0 : 0.0)
            .frame(width: 16, height: 16)
            .accessibilityLabel(isWatched ? "Stop watching this stack" : "Watch this stack")

            // Open every known part, in merge order
            Button(action: openAllPRs) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
            }
            .buttonStyle(.plain)
            .help(openAllHelpText)
            .opacity(isHovering ? 1.0 : 0.0)
            .frame(width: 16, height: 16)
            .accessibilityLabel("Open all PRs in this stack")
        }
        .padding(.trailing, 12)
        .background(Color.gray.opacity(isHovering ? 0.1 : 0.05))
        .contentShape(Rectangle())
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
    }

    private var summaryColor: Color {
        switch header.readiness.status {
        case .unknown: return .secondary
        default:       return header.readiness.color
        }
    }
}
