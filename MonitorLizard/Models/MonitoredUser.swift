import Foundation

struct IgnoredCheckRule: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var pattern: String        // glob: "codecov/*", "DCO"
    var repository: String     // "owner/repo" or "*" for all repos

    func matches(checkName: String, repo: String) -> Bool {
        let repoMatches = repository == "*" || repository == repo
        guard repoMatches else { return false }
        return globMatch(pattern: pattern, string: checkName)
    }
}

struct MonitoredUser: Codable, Identifiable, Equatable {
    var id: UUID
    var username: String          // "@me" or any GitHub username
    var displayName: String?      // optional label for segment control
    var ignoredRepos: [String]    // ["owner/repo", ...]
    var ignoredChecks: [IgnoredCheckRule]

    var label: String {
        displayName ?? (username == "@me" ? "@me" : username)
    }

    var isMe: Bool { username == "@me" }

    static func defaultMe() -> MonitoredUser {
        MonitoredUser(
            id: UUID(),
            username: "@me",
            displayName: nil,
            ignoredRepos: [],
            ignoredChecks: []
        )
    }
}

/// Simple glob matching supporting only `*` wildcard.
/// `*` matches any sequence of characters.
/// Example: "codecov/*" matches "codecov/patch", "codecov/project".
func globMatch(pattern: String, string: String) -> Bool {
    let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 1 {
        return pattern == string
    }

    var remaining = string[...]
    for (i, part) in parts.enumerated() {
        if part.isEmpty { continue }
        guard let range = remaining.range(of: part) else { return false }
        if i == 0 && range.lowerBound != remaining.startIndex { return false }
        remaining = remaining[range.upperBound...]
    }
    if let last = parts.last, !last.isEmpty {
        return string.hasSuffix(last)
    }
    return true
}
