import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    @EnvironmentObject var viewModel: PRMonitorViewModel

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                if pr.buildStatus == .pending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(pr.buildStatus.icon)
                        .font(.title2)
                }
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                // PR Title
                Text(pr.title)
                    .font(.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Repo and PR number
                HStack(spacing: 4) {
                    Text(pr.repository.name)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("#\(pr.number)")
                        .font(.caption)
                        .foregroundColor(.secondary)
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

                // Build status text
                Text(pr.buildStatus.displayName)
                    .font(.caption2)
                    .foregroundColor(pr.buildStatus.color)

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
            }

            Spacer()

            // Action buttons - always present but only visible on hover or if watched
            HStack(spacing: 8) {
                // Watch button
                Button(action: {
                    viewModel.toggleWatch(for: pr)
                }) {
                    Image(systemName: pr.isWatched ? "eye.fill" : "eye")
                        .foregroundColor(pr.isWatched ? .blue : .gray)
                }
                .buttonStyle(.plain)
                .help(pr.isWatched ? "Stop watching this PR" : "Watch this PR for completion")
                .opacity(isHovering || pr.isWatched ? 1.0 : 0.0)

                // Open in browser button
                Button(action: {
                    if let url = URL(string: pr.url) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
                .help("Open in GitHub")
                .opacity(isHovering ? 1.0 : 0.0)
            }
            .frame(width: 60) // Fixed width to prevent layout shift
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovering ? Color.gray.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            if let url = URL(string: pr.url) {
                NSWorkspace.shared.open(url)
            }
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
