import Foundation

/// A pull request's membership in a GitHub stack: a series of open PRs where each
/// PR targets the branch of the PR below it.
struct PRStackInfo: Hashable, Codable {
    /// Stable identifier of the stack (GitHub GraphQL node ID).
    let id: String

    /// A number uniquely identifying the stack within its repository.
    let number: Int

    /// The total number of pull requests in the stack.
    let size: Int

    /// This pull request's position in the stack, where 1 is closest to the base branch.
    let position: Int

    /// Positions in this stack whose pull request has already merged, as reported
    /// by the stack entries lookup. Nil until the app has looked the stack up.
    /// GitHub keeps merged pull requests in the stack, so their rows never show up
    /// in the user's own searches and the positions stay occupied.
    var mergedPositions: [Int]?

    /// Tooltip explaining where this PR sits in the merge order.
    var helpText: String {
        let header = "Stack #\(number), part \(position) of \(size)"
        return position == 1
            ? "\(header). Merge this one first."
            : "\(header). Merge after part \(position - 1)."
    }
}

/// One part of a stack that is visible in a section.
struct PRStackPart: Hashable {
    let position: Int
    let number: Int
}

/// The row that introduces a stack block: identity and state for the whole stack,
/// so the information is not repeated on every part row.
struct PRStackHeader: Hashable, Identifiable {
    let stackID: String
    let number: Int
    let size: Int

    /// The stack's parts that are visible in this section, ascending by position.
    let visibleParts: [PRStackPart]

    let readiness: PRStackReadiness

    var id: String { "stack-\(stackID)" }

    /// The part to work on next, when its position can be named unambiguously:
    /// every position below it is either visible or already merged.
    var startPart: PRStackPart? {
        PRStackOrdering.nextPart(visibleParts: visibleParts, landedPositions: readiness.landedPositions)
    }

    /// One-line state summary shown next to the stack number.
    var summary: String {
        let state: String
        switch readiness.status {
        case .allReady:
            state = readiness.allReadyText
        case .readyToAdvance:
            if let startPart {
                state = "Ready to merge — start with #\(startPart.number)"
            } else {
                state = "Ready to merge"
            }
        case .blocked(let blocker):
            state = "Blocked by part \(blocker.position) (#\(blocker.number)) — \(blocker.reason)"
        case .unknown:
            let visibleCount = "\(visibleParts.count) of \(size) parts in your lists"
            if let blocker = readiness.blockingPart {
                state = "\(visibleCount) · Visible part \(blocker.position) (#\(blocker.number)) blocked — \(blocker.reason)"
            } else {
                state = visibleCount
            }
        }
        guard let landedText = readiness.landedText else { return state }
        return "\(landedText) · \(state)"
    }

    /// Tooltip listing the parts the app can see.
    var helpText: String {
        let parts = visibleParts
            .map { "#\($0.number) (\($0.position)/\(size))" }
            .joined(separator: ", ")
        var text = "Stack #\(number) — \(size) parts. Visible here: \(parts)."
        if let readinessText = readiness.helpText {
            text += " \(readinessText)"
        }
        return text
    }
}

/// Identifies a stack that has become ready to merge, with enough context for a
/// notification.
struct ReadyStack: Hashable {
    let id: String
    let number: Int
    let size: Int

    /// True when every part of the stack is visible and ready; false when only the
    /// lowest part is known to be ready.
    let allReady: Bool

    /// Position of the part to merge next, when it can be named unambiguously:
    /// every position below it is either visible or already merged. Nil when a
    /// lower position is neither, so the part that comes next cannot be known.
    let nextPartPosition: Int?

    /// Positions already merged, when the stack lookup reported them.
    let landedPositions: Set<Int>
}

/// What the app can say about a stack's readiness to merge, based on the parts it
/// can see. A stack can only advance from its lowest unmerged part, so `status`
/// follows that part when every lower position is known merged, and stays ready
/// even when parts above it are not. `blockingPart`
/// names the lowest blocked visible part — the one everything above it is waiting
/// on — whenever one is visible. Drafts count as blocked: a draft cannot merge
/// even when its checks are green, so a draft member blocks with reason "draft".
struct PRStackReadiness: Hashable {
    enum Status: Hashable {
        /// Every part of the stack is visible and ready to merge.
        case allReady
        /// The lowest part is ready, so merging can start.
        case readyToAdvance
        /// A specific part is not ready, and everything above it waits.
        case blocked(PRStackBlocker)
        /// Not enough of the stack is visible to judge.
        case unknown
    }

    struct PRStackBlocker: Hashable {
        let position: Int
        let number: Int
        let reason: String
    }

    let status: Status
    let size: Int

    /// Positions already merged, when the stack lookup reported them.
    let landedPositions: Set<Int>

    /// The lowest blocked visible part: the one everything above it is waiting
    /// on, whether or not the stack can advance past its lowest part. A draft
    /// part is blocked with reason "draft".
    let blockingPart: PRStackBlocker?

    init(
        status: Status,
        size: Int,
        landedPositions: Set<Int> = [],
        blockingPart: PRStackBlocker? = nil
    ) {
        self.status = status
        self.size = size
        self.landedPositions = landedPositions
        self.blockingPart = blockingPart
    }

    /// True when the lowest unmerged part is ready, whether or not the parts above
    /// it are.
    var isReadyToAdvance: Bool {
        switch status {
        case .allReady, .readyToAdvance: return true
        case .blocked, .unknown: return false
        }
    }

    /// "Part 1 merged" / "Parts 1, 2 merged", or nil when nothing has merged.
    var landedText: String? {
        let positions = landedPositions.sorted()
        guard !positions.isEmpty else { return nil }
        if positions.count == 1 {
            return "Part \(positions[0]) merged"
        }
        return "Parts \(positions.map(String.init).joined(separator: ", ")) merged"
    }

    /// The all-ready state phrase shared by `PRStackHeader.summary` and
    /// `helpText`, without end punctuation; each caller appends its own.
    var allReadyText: String {
        landedPositions.isEmpty
            ? "All \(size) parts are ready to merge"
            : "All remaining parts are ready to merge"
    }

    /// One-line explanation for tooltips, or nil when neither readiness nor a
    /// visible blocker can be identified.
    var helpText: String? {
        var state: String
        switch status {
        case .allReady:
            state = "\(allReadyText)."
        case .readyToAdvance:
            state = landedPositions.isEmpty
                ? "Part 1 is ready to merge."
                : "The next part is ready to merge."
            // The stack can advance, but a blocked part above the lowest one
            // still decides what happens next, so it is named here too.
            if let blockingPart {
                state += " Waiting on part \(blockingPart.position) of \(size) (\(blockingPart.reason))."
            }
        case .blocked(let blocker):
            state = "Waiting on part \(blocker.position) of \(size) (\(blocker.reason))."
        case .unknown:
            guard let blockingPart else { return nil }
            state = "Readiness unknown; visible part \(blockingPart.position) of \(size) (#\(blockingPart.number)) is blocked (\(blockingPart.reason))."
        }
        guard let landedText else { return state }
        return "\(landedText). \(state)"
    }
}

/// A row in a section: a stack block's header, or a PR.
enum PRListRow: Identifiable, Hashable {
    case stackHeader(PRStackHeader)
    case pr(PullRequest, StackRowContext?)

    /// Where a PR sits when it is rendered as a part inside a stack block.
    struct StackRowContext: Hashable {
        let position: Int
        let size: Int
        /// True when this part is the one everything above it is waiting on.
        let isBlocking: Bool
        /// Why the blocking part holds the stack back, when a blocked part is
        /// visible; nil when no blocked part is visible. A `var` with a default
        /// so the memberwise initializer keeps accepting call sites that omit it.
        var blockingReason: String? = nil
        let helpText: String
    }

    var id: String {
        switch self {
        case .stackHeader(let header): return header.id
        case .pr(let pr, _): return pr.id
        }
    }

    /// The PR this row shows, or nil for a stack header.
    var pr: PullRequest? {
        guard case .pr(let pr, _) = self else { return nil }
        return pr
    }
}

enum PRStackOrdering {
    /// Rows for a section: PRs without a stack stay as they are, and each stack
    /// becomes one block — a header followed by its visible parts in merge order,
    /// part 1 (the one closest to the base branch) first.
    ///
    /// A block is emitted at its first member's occurrence in `prs`. Members that
    /// share a stack position are emitted in unspecified order, since `sorted(by:)`
    /// is not guaranteed to be stable. Collapsed stacks emit only their header.
    static func rows(from prs: [PullRequest], collapsedStackIDs: Set<String> = []) -> [PRListRow] {
        var membersByStack: [String: [PullRequest]] = [:]
        for pr in prs {
            guard let stack = pr.stack else { continue }
            membersByStack[stack.id, default: []].append(pr)
        }

        var emittedStacks: Set<String> = []
        var rows: [PRListRow] = []

        for pr in prs {
            guard let stack = pr.stack,
                  let members = membersByStack[stack.id] else {
                rows.append(.pr(pr, nil))
                continue
            }
            guard emittedStacks.insert(stack.id).inserted else { continue }

            let readiness = readiness(of: members, stackSize: stack.size)
            let visibleParts = members
                .compactMap { member -> PRStackPart? in
                    guard let memberStack = member.stack else { return nil }
                    return PRStackPart(position: memberStack.position, number: member.number)
                }
                .sorted { $0.position < $1.position }

            rows.append(.stackHeader(PRStackHeader(
                stackID: stack.id,
                number: stack.number,
                size: stack.size,
                visibleParts: visibleParts,
                readiness: readiness
            )))

            guard !collapsedStackIDs.contains(stack.id) else { continue }

            let ordered = members.sorted {
                ($0.stack?.position ?? 0) < ($1.stack?.position ?? 0)
            }
            for member in ordered {
                guard let memberStack = member.stack else { continue }
                let isBlocking = readiness.blockingPart?.number == member.number
                let helpText = [memberStack.helpText, readiness.helpText]
                    .compactMap { $0 }
                    .joined(separator: " ")
                rows.append(.pr(member, PRListRow.StackRowContext(
                    position: memberStack.position,
                    size: memberStack.size,
                    isBlocking: isBlocking,
                    blockingReason: isBlocking ? readiness.blockingPart?.reason : nil,
                    helpText: helpText
                )))
            }
        }

        return rows
    }

    /// Readiness of a stack from the parts the app can see. A stack advances from
    /// its lowest unmerged part. The lowest visible member decides whether merging
    /// can start only when every position below it is known merged; a blocked part
    /// above it only names what comes next, through `blockingPart`. A draft member
    /// counts as blocked with reason "draft" even when its checks are green.
    static func readiness(of members: [PullRequest], stackSize: Int) -> PRStackReadiness {
        func isBlocked(_ member: PullRequest) -> Bool {
            member.isMergeBlocked || member.isDraft
        }
        func blockReason(_ member: PullRequest) -> String {
            member.isDraft ? "draft" : member.mergeBlockReason ?? "not ready"
        }

        let ordered = members.sorted {
            ($0.stack?.position ?? 0) < ($1.stack?.position ?? 0)
        }
        // Merged parts stay in the stack but never appear in the user's searches,
        // so their positions count as satisfied rather than missing.
        let landed = Set(members.compactMap { $0.stack?.mergedPositions }.first ?? [])
        let accounted = Set(ordered.compactMap { $0.stack?.position }).union(landed)

        // The lowest blocked visible part, whether or not it holds the whole
        // stack back: it is what everything above it is waiting on.
        let blockingPart = ordered.first(where: isBlocked).map { member in
            PRStackReadiness.PRStackBlocker(
                position: member.stack?.position ?? 0,
                number: member.number,
                reason: blockReason(member)
            )
        }

        guard let lowest = ordered.first,
              Set(1..<(lowest.stack?.position ?? 1)).isSubset(of: landed) else {
            return PRStackReadiness(
                status: .unknown,
                size: stackSize,
                landedPositions: landed,
                blockingPart: blockingPart
            )
        }

        // Only the part at the known merge frontier can hold the stack back.
        if isBlocked(lowest), let blockingPart {
            return PRStackReadiness(
                status: .blocked(blockingPart),
                size: stackSize,
                landedPositions: landed,
                blockingPart: blockingPart
            )
        }

        let status: PRStackReadiness.Status =
            accounted.count == stackSize && blockingPart == nil
                ? .allReady
                : .readyToAdvance
        return PRStackReadiness(
            status: status,
            size: stackSize,
            landedPositions: landed,
            blockingPart: blockingPart
        )
    }

    /// The part to merge next, when it can be named unambiguously: the lowest
    /// visible part whose lower positions are all either visible or already
    /// merged. Nil when a lower position is neither, so the part that comes next
    /// cannot be known from what is visible.
    static func nextPart(visibleParts: [PRStackPart], landedPositions: Set<Int>) -> PRStackPart? {
        guard let lowest = visibleParts.min(by: { $0.position < $1.position }) else { return nil }
        let lowerPositions = Set(1..<lowest.position)
        let accounted = landedPositions.union(visibleParts.map(\.position))
        return lowerPositions.isSubset(of: accounted) ? lowest : nil
    }

    /// Stacks whose lowest part has just become ready to merge.
    ///
    /// - Parameter previouslyReady: Stack ids that were ready at the previous call.
    /// - Returns: The stacks that are newly ready, and the ids to pass as
    ///   `previouslyReady` next time.
    static func readinessTransitions(
        previouslyReady: Set<String>,
        prs: [PullRequest]
    ) -> (newlyReady: [ReadyStack], readyStackIDs: Set<String>) {
        var membersByStack: [String: [PullRequest]] = [:]
        var stackNumbers: [String: Int] = [:]
        var stackSizes: [String: Int] = [:]
        for pr in prs {
            guard let stack = pr.stack else { continue }
            membersByStack[stack.id, default: []].append(pr)
            stackNumbers[stack.id] = stack.number
            stackSizes[stack.id] = stack.size
        }

        var readyStackIDs: Set<String> = []
        var newlyReady: [ReadyStack] = []

        for (stackID, members) in membersByStack {
            let stackSize = stackSizes[stackID] ?? members.count
            let readiness = readiness(of: members, stackSize: stackSize)
            guard readiness.isReadyToAdvance else { continue }

            readyStackIDs.insert(stackID)
            guard !previouslyReady.contains(stackID) else { continue }

            let visibleParts = members.compactMap { member -> PRStackPart? in
                guard let stack = member.stack else { return nil }
                return PRStackPart(position: stack.position, number: member.number)
            }
            newlyReady.append(ReadyStack(
                id: stackID,
                number: stackNumbers[stackID] ?? 0,
                size: stackSize,
                allReady: readiness.status == .allReady,
                nextPartPosition: nextPart(
                    visibleParts: visibleParts,
                    landedPositions: readiness.landedPositions
                )?.position,
                landedPositions: readiness.landedPositions
            ))
        }

        return (newlyReady.sorted { $0.number < $1.number }, readyStackIDs)
    }
}
