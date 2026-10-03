import Testing
import Foundation
@testable import MonitorLizard

@MainActor
struct PRStackOrderingTests {

    private func makePR(
        _ number: Int,
        stackID: String = "stack-1",
        stackNumber: Int = 7,
        stackSize: Int = 4,
        position: Int,
        status: BuildStatus = .success,
        reviewDecision: ReviewDecision? = nil,
        mergedPositions: [Int]? = nil
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            buildStatus: status,
            isWatched: false,
            labels: [],
            type: .reviewing,
            isDraft: false,
            statusChecks: [],
            reviewDecision: reviewDecision,
            host: "github.com",
            stack: PRStackInfo(
                id: stackID,
                number: stackNumber,
                size: stackSize,
                position: position,
                mergedPositions: mergedPositions
            )
        )
    }

    private func makeUnstackedPR(_ number: Int) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            buildStatus: .success,
            isWatched: false,
            labels: [],
            type: .reviewing,
            isDraft: false,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com"
        )
    }

    private func header(_ rows: [PRListRow]) -> PRStackHeader? {
        guard case .stackHeader(let header) = rows.first else { return nil }
        return header
    }

    private func positions(_ rows: [PRListRow]) -> [Int] {
        rows.compactMap { $0.pr?.stack?.position }
    }

    @Test func rendersAStackAsOneBlockInMergeOrder() {
        let rows = PRStackOrdering.rows(from: [
            makePR(1, position: 1),
            makePR(3, position: 3),
            makePR(2, position: 2),
            makePR(4, position: 4),
        ])

        #expect(rows.count == 5)
        let header = header(rows)
        #expect(header?.number == 7)
        #expect(header?.size == 4)
        #expect(header?.visibleParts.map(\.number) == [1, 2, 3, 4])
        #expect(rows.compactMap(\.pr).map(\.number) == [1, 2, 3, 4])
        #expect(positions(rows) == [1, 2, 3, 4])
    }

    @Test func leavesUnstackedPRsAsPlainRows() {
        let rows = PRStackOrdering.rows(from: [makeUnstackedPR(10), makeUnstackedPR(11)])

        #expect(rows.count == 2)
        #expect(rows.compactMap(\.pr).map(\.number) == [10, 11])
        for row in rows {
            guard case .pr(_, let context) = row else {
                Issue.record("Expected a plain PR row")
                continue
            }
            #expect(context == nil)
        }
    }

    @Test func keepsAStackTogetherWhenOtherPRsSeparateThem() {
        let rows = PRStackOrdering.rows(from: [
            makeUnstackedPR(10),
            makePR(2, stackSize: 2, position: 2),
            makeUnstackedPR(11),
            makePR(1, stackSize: 2, position: 1),
        ])

        #expect(rows.compactMap(\.pr).map(\.number) == [10, 1, 2, 11])
        guard case .stackHeader = rows[1] else {
            Issue.record("Expected the stack header at index 1")
            return
        }
    }

    @Test func rendersEachStackAsItsOwnBlock() {
        let rows = PRStackOrdering.rows(from: [
            makePR(1, stackID: "a", stackSize: 2, position: 1),
            makePR(3, stackID: "b", stackSize: 2, position: 1),
            makePR(2, stackID: "a", stackSize: 2, position: 2),
            makePR(4, stackID: "b", stackSize: 2, position: 2),
        ])

        #expect(rows.compactMap(\.pr).map(\.number) == [1, 2, 3, 4])
        let headerCount = rows.filter { row in
            if case .stackHeader = row { return true }
            return false
        }.count
        #expect(headerCount == 2)
    }

    @Test func partialStackReportsOnlyTheVisibleParts() {
        // Only positions 3 and 4 of a four-PR stack are visible.
        let rows = PRStackOrdering.rows(from: [
            makePR(3, position: 3),
            makePR(4, position: 4),
        ])

        #expect(rows.compactMap(\.pr).map(\.number) == [3, 4])
        let header = header(rows)
        #expect(header?.visibleParts.map(\.position) == [3, 4])
        #expect(header?.summary == "2 of 4 parts in your lists")
    }

    @Test func singleVisibleStackMemberStillGetsABlock() {
        let rows = PRStackOrdering.rows(from: [makePR(2, position: 2)])

        #expect(rows.count == 2)
        #expect(header(rows)?.visibleParts.map(\.position) == [2])
        guard case .pr(_, let context) = rows[1] else {
            Issue.record("Expected the part row")
            return
        }
        #expect(context?.position == 2)
        #expect(context?.size == 4)
    }

    @Test func collapsedStackEmitsOnlyItsHeader() {
        let prs = [makePR(1, position: 1), makePR(2, position: 2)]

        let rows = PRStackOrdering.rows(from: prs, collapsedStackIDs: ["stack-1"])

        #expect(rows.count == 1)
        #expect(header(rows)?.size == 4)
    }

    @Test func collapsedUnknownStackNamesOnlyItsVisibleBlocker() {
        let rows = PRStackOrdering.rows(from: [
            makePR(3, position: 3, status: .failure, mergedPositions: [1]),
        ], collapsedStackIDs: ["stack-1"])

        #expect(rows.count == 1)
        let header = header(rows)
        #expect(header?.readiness.status == .unknown)
        #expect(header?.startPart == nil)
        #expect(header?.summary == "Part 1 merged · 1 of 4 parts in your lists · Visible part 3 (#3) blocked — failing checks")
        #expect(header?.helpText == "Stack #7 — 4 parts. Visible here: #3 (3/4). Part 1 merged. Readiness unknown; visible part 3 of 4 (#3) is blocked (failing checks).")
    }

    @Test func marksOnlyTheBlockingPart() {
        let rows = PRStackOrdering.rows(from: [
            makePR(1, position: 1, status: .failure),
            makePR(2, position: 2),
        ])

        for row in rows {
            guard case .pr(let pr, let context) = row else { continue }
            #expect(context?.isBlocking == (pr.number == 1))
        }
    }

    @Test func marksTheBlockingUpperPartEvenWhenTheBaseIsReady() {
        let rows = PRStackOrdering.rows(from: [
            makePR(1, position: 1),
            makePR(2, position: 2, status: .failure),
        ])

        for row in rows {
            guard case .pr(let pr, let context) = row else { continue }
            #expect(context?.isBlocking == (pr.number == 2))
        }
    }

    @Test func blockingRowCarriesItsReasonIntoTheRowContext() {
        let rows = PRStackOrdering.rows(from: [
            makePR(1, position: 1),
            makePR(2, position: 2),
            makePR(3, position: 3, status: .failure),
        ])

        for row in rows {
            guard case .pr(let pr, let context) = row else { continue }
            #expect(context?.isBlocking == (pr.number == 3))
            #expect(context?.blockingReason == (pr.number == 3 ? "failing checks" : nil))
            if pr.number == 3 {
                #expect(context?.helpText.contains("Waiting on part 3 of 4 (failing checks).") == true)
            }
        }
    }

    @Test func mergedLowerPartsAreAccountedForInTheHeader() {
        let rows = PRStackOrdering.rows(from: [
            makePR(2, stackSize: 3, position: 2, mergedPositions: [1]),
            makePR(3, stackSize: 3, position: 3, mergedPositions: [1]),
        ])

        #expect(rows.compactMap(\.pr).map(\.number) == [2, 3])
        let header = header(rows)
        #expect(header?.readiness.status == .allReady)
        #expect(header?.visibleParts.map(\.number) == [2, 3])
        #expect(header?.summary == "Part 1 merged · All remaining parts are ready to merge")
    }

    @Test func mergedBaseNamesTheNextPartToMerge() {
        let rows = PRStackOrdering.rows(from: [
            makePR(2, stackSize: 3, position: 2, mergedPositions: [1]),
        ])

        #expect(header(rows)?.summary == "Part 1 merged · Ready to merge — start with #2")
    }

    @Test func mergedLowerPartsAndABlockedPartAreReportedTogether() {
        let rows = PRStackOrdering.rows(from: [
            makePR(2, stackSize: 3, position: 2, status: .failure, mergedPositions: [1]),
            makePR(3, stackSize: 3, position: 3, mergedPositions: [1]),
        ])

        #expect(header(rows)?.summary == "Part 1 merged · Blocked by part 2 (#2) — failing checks")
    }

    @Test func headerSummarizesTheStackState() {
        let blocked = header(PRStackOrdering.rows(from: [
            makePR(1, position: 1, status: .pending),
            makePR(2, position: 2),
        ]))
        #expect(blocked?.summary == "Blocked by part 1 (#1) — checks pending")

        let readyBaseWithPendingUpper = header(PRStackOrdering.rows(from: [
            makePR(1, stackSize: 2, position: 1),
            makePR(2, stackSize: 2, position: 2, status: .pending),
        ]))
        #expect(readyBaseWithPendingUpper?.summary == "Ready to merge — start with #1")

        let ready = header(PRStackOrdering.rows(from: [
            makePR(1, stackSize: 2, position: 1),
            makePR(2, stackSize: 2, position: 2),
        ]))
        #expect(ready?.summary == "All 2 parts are ready to merge")

        let waiting = header(PRStackOrdering.rows(from: [makePR(1, position: 1)]))
        #expect(waiting?.summary == "Ready to merge — start with #1")
    }
}

@MainActor
struct PRStackReadinessTests {

    private func makePR(
        _ number: Int,
        position: Int,
        stackSize: Int,
        status: BuildStatus = .success,
        reviewDecision: ReviewDecision? = nil,
        mergedPositions: [Int]? = nil,
        isDraft: Bool = false
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            buildStatus: status,
            isWatched: false,
            labels: [],
            type: .reviewing,
            isDraft: isDraft,
            statusChecks: [],
            reviewDecision: reviewDecision,
            host: "github.com",
            stack: PRStackInfo(
                id: "stack-1",
                number: 42,
                size: stackSize,
                position: position,
                mergedPositions: mergedPositions
            )
        )
    }

    @Test func readyBaseWithABlockedUpperPartIsReadyToAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 3),
                makePR(2, position: 2, stackSize: 3, status: .failure),
                makePR(3, position: 3, stackSize: 3),
            ],
            stackSize: 3
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == .init(position: 2, number: 2, reason: "failing checks"))
    }

    @Test func pendingBasePartBlocksTheStack() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(1, position: 1, stackSize: 2, status: .pending)],
            stackSize: 2
        )

        #expect(readiness.status == .blocked(.init(position: 1, number: 1, reason: "checks pending")))
    }

    @Test func readyBaseWithChangesRequestedOnAnUpperPartIsReadyToAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 2),
                makePR(2, position: 2, stackSize: 2, reviewDecision: .changesRequested),
            ],
            stackSize: 2
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == .init(position: 2, number: 2, reason: "changes requested"))
    }

    @Test func reviewRequiredOnTheLowestPartBlocksTheStack() {
        // Review required blocks merging just like changes requested: a
        // green-check part still waiting on a review cannot advance the stack.
        let readiness = PRStackOrdering.readiness(
            of: [makePR(1, position: 1, stackSize: 2, reviewDecision: .reviewRequired)],
            stackSize: 2
        )

        #expect(readiness.status == .blocked(.init(position: 1, number: 1, reason: "review required")))
        #expect(!readiness.isReadyToAdvance)
    }

    @Test func readyBaseWithReviewRequiredOnAnUpperPartIsReadyToAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 2),
                makePR(2, position: 2, stackSize: 2, reviewDecision: .reviewRequired),
            ],
            stackSize: 2
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == .init(position: 2, number: 2, reason: "review required"))
    }

    // MARK: - Drafts count as blocked

    @Test func draftLowestPartBlocksTheStack() {
        // A draft cannot merge even with green checks, so a ready-looking draft
        // base must hold the stack back instead of reading as ready.
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 2, isDraft: true),
                makePR(2, position: 2, stackSize: 2),
            ],
            stackSize: 2
        )

        #expect(readiness.status == .blocked(.init(position: 1, number: 1, reason: "draft")))
        #expect(readiness.isReadyToAdvance == false)
    }

    @Test func draftPartAboveAReadyBaseIsTheBlockingPart() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 3),
                makePR(2, position: 2, stackSize: 3, isDraft: true),
                makePR(3, position: 3, stackSize: 3),
            ],
            stackSize: 3
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.blockingPart == .init(position: 2, number: 2, reason: "draft"))
    }

    @Test func draftReasonWinsWhenChecksAlsoFail() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(1, position: 1, stackSize: 2, status: .failure, isDraft: true)],
            stackSize: 2
        )

        #expect(readiness.status == .blocked(.init(position: 1, number: 1, reason: "draft")))
    }

    // MARK: - Readiness help text

    @Test func readyToAdvanceHelpTextNamesTheBlockingUpperPart() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 4),
                makePR(2, position: 2, stackSize: 4),
                makePR(3, position: 3, stackSize: 4, status: .failure),
            ],
            stackSize: 4
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.helpText == "Part 1 is ready to merge. Waiting on part 3 of 4 (failing checks).")
    }

    @Test func blockedAndAllReadyHelpTextsKeepTheirPhrasing() {
        let blocked = PRStackOrdering.readiness(
            of: [makePR(1, position: 1, stackSize: 2, status: .pending)],
            stackSize: 2
        )
        #expect(blocked.helpText == "Waiting on part 1 of 2 (checks pending).")

        let allReady = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 2),
                makePR(2, position: 2, stackSize: 2),
            ],
            stackSize: 2
        )
        #expect(allReady.helpText == "All 2 parts are ready to merge.")
    }

    @Test func allPartsVisibleAndReadyMeansAllReady() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(1, position: 1, stackSize: 2),
                makePR(2, position: 2, stackSize: 2),
            ],
            stackSize: 2
        )

        #expect(readiness.status == .allReady)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.helpText == "All 2 parts are ready to merge.")
    }

    @Test func baseReadyWithMissingPartsMeansReadyToAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(1, position: 1, stackSize: 4)],
            stackSize: 4
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.helpText == "Part 1 is ready to merge.")
    }

    @Test func mergedBaseLetsTheStackAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(2, position: 2, stackSize: 3, mergedPositions: [1]),
                makePR(3, position: 3, stackSize: 3, mergedPositions: [1]),
            ],
            stackSize: 3
        )

        #expect(readiness.status == .allReady)
        #expect(readiness.landedPositions == [1])
        #expect(readiness.landedText == "Part 1 merged")
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.helpText == "Part 1 merged. All remaining parts are ready to merge.")
    }

    @Test func mergedBaseWithMissingUpperPartsIsReadyToAdvance() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(2, position: 2, stackSize: 3, mergedPositions: [1])],
            stackSize: 3
        )

        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
        #expect(readiness.helpText == "Part 1 merged. The next part is ready to merge.")
    }

    @Test func mergedTextListsEveryLandedPosition() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(3, position: 3, stackSize: 3, mergedPositions: [1, 2])],
            stackSize: 3
        )

        #expect(readiness.landedText == "Parts 1, 2 merged")
        #expect(readiness.status == .allReady)
    }

    @Test func unreadyPartWithoutVisibleBaseIsUnknown() {
        let readiness = PRStackOrdering.readiness(
            of: [makePR(2, position: 2, stackSize: 4)],
            stackSize: 4
        )

        #expect(readiness.status == .unknown)
        #expect(!readiness.isReadyToAdvance)
        #expect(readiness.helpText == nil)
    }

    @Test func blockedUpperPartWithoutVisibleBaseIsUnknownButStillNamesTheBlocker() {
        // Position 1 is neither visible nor known-merged, so readiness cannot be
        // judged — but the blocked part stays exposed so its row keeps the
        // blocking marker.
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(2, position: 2, stackSize: 4),
                makePR(3, position: 3, stackSize: 4, status: .failure),
            ],
            stackSize: 4
        )

        #expect(readiness.status == .unknown)
        #expect(!readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == .init(position: 3, number: 3, reason: "failing checks"))
    }

    @Test func blockedLowestVisiblePartWithoutVisibleBaseIsUnknownButStillNamesTheBlocker() {
        // The lowest visible part is blocked, but position 1 is neither visible
        // nor known-merged, so the stack's true lowest part is unknown and
        // readiness cannot be judged. The blocked part stays exposed so its row
        // keeps the blocking marker, and the stack must not read as ready.
        let readiness = PRStackOrdering.readiness(
            of: [
                makePR(2, position: 2, stackSize: 4, status: .failure),
                makePR(3, position: 3, stackSize: 4),
            ],
            stackSize: 4
        )

        #expect(readiness.status == .unknown)
        #expect(!readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == .init(position: 2, number: 2, reason: "failing checks"))
    }

    @Test func unknownMiddlePositionStillMarksABlockedVisibleRow() {
        let rows = PRStackOrdering.rows(from: [
            makePR(3, position: 3, stackSize: 4, status: .failure, mergedPositions: [1]),
        ])

        guard case .stackHeader(let header) = rows.first,
              case .pr(_, let context) = rows.last else {
            Issue.record("Expected a stack header and its visible part")
            return
        }
        #expect(header.readiness.status == .unknown)
        #expect(header.readiness.blockingPart == .init(position: 3, number: 3, reason: "failing checks"))
        #expect(context?.isBlocking == true)
        #expect(context?.blockingReason == "failing checks")
    }
}

@MainActor
struct PRStackReadinessTransitionTests {

    private func makePR(
        _ number: Int,
        position: Int,
        status: BuildStatus,
        stackSize: Int = 2,
        mergedPositions: [Int]? = nil,
        isDraft: Bool = false
    ) -> PullRequest {
        PullRequest(
            number: number,
            title: "PR #\(number)",
            repository: PullRequest.RepositoryInfo(name: "repo", nameWithOwner: "owner/repo"),
            url: "https://github.com/owner/repo/pull/\(number)",
            author: PullRequest.Author(login: "alice"),
            headRefName: "feature/\(number)",
            updatedAt: Date(timeIntervalSince1970: 1_000_000),
            buildStatus: status,
            isWatched: false,
            labels: [],
            type: .reviewing,
            isDraft: isDraft,
            statusChecks: [],
            reviewDecision: nil,
            host: "github.com",
            stack: PRStackInfo(
                id: "stack-1",
                number: 42,
                size: stackSize,
                position: position,
                mergedPositions: mergedPositions
            )
        )
    }

    @Test func reportsAStackOnceWhenItsBaseBecomesReady() {
        let ready = [makePR(1, position: 1, status: .success), makePR(2, position: 2, status: .success)]

        let first = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: ready)
        let second = PRStackOrdering.readinessTransitions(previouslyReady: first.readyStackIDs, prs: ready)

        #expect(first.newlyReady.map(\.number) == [42])
        #expect(first.newlyReady.first?.allReady == true)
        #expect(second.newlyReady.isEmpty)
        #expect(second.readyStackIDs == first.readyStackIDs)
    }

    @Test func reportsAStackOnceWhenItsBaseIsReadyAndAnUpperPartIsBlocked() {
        let readyBase = [
            makePR(1, position: 1, status: .success),
            makePR(2, position: 2, status: .failure),
        ]

        let first = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: readyBase)
        let second = PRStackOrdering.readinessTransitions(previouslyReady: first.readyStackIDs, prs: readyBase)

        #expect(first.newlyReady.count == 1)
        #expect(first.newlyReady.first?.allReady == false)
        #expect(first.newlyReady.first?.nextPartPosition == 1)
        #expect(second.newlyReady.isEmpty)
    }

    @Test func namesTheNextPartWhenLowerPartsHaveMerged() {
        let prs = [makePR(2, position: 2, status: .success, stackSize: 3, mergedPositions: [1])]

        let result = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: prs)

        #expect(result.newlyReady.count == 1)
        #expect(result.newlyReady.first?.allReady == false)
        #expect(result.newlyReady.first?.nextPartPosition == 2)
        #expect(result.newlyReady.first?.landedPositions == [1])
    }

    @Test func doesNotNameTheNextPartWhenAMiddlePositionIsUnknown() {
        // Position 1 has merged and position 3 is green, but position 2 is
        // neither visible nor known-merged: the next position to merge is
        // unknown, so the stack is not ready to advance and must not notify.
        let prs = [makePR(3, position: 3, status: .success, stackSize: 4, mergedPositions: [1])]

        let result = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: prs)

        #expect(result.newlyReady.isEmpty, "a stack whose next position is unknown must not be reported ready")
        #expect(result.readyStackIDs.isEmpty)

        // Direct readiness: the unaccounted merge frontier keeps the stack from
        // reading as ready to advance, and nothing visible is blocked.
        let readiness = PRStackOrdering.readiness(of: prs, stackSize: 4)
        #expect(readiness.status == .unknown)
        #expect(!readiness.isReadyToAdvance)
        #expect(readiness.blockingPart == nil, "part 3 is green, so no visible part is the blocker")
    }

    @Test func readyBaseAdvancesEvenWhenAHigherPositionIsUnknown() {
        // Part 1 is visible and ready and part 3 is green, but part 2 is neither
        // visible nor known-merged. The unknown position sits above the merge
        // frontier (part 1 has not merged yet), so it must not hold the stack
        // back: the stack reports ready, advancing via part 1.
        let prs = [
            makePR(1, position: 1, status: .success, stackSize: 4),
            makePR(3, position: 3, status: .success, stackSize: 4),
        ]

        let result = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: prs)

        #expect(result.newlyReady.count == 1)
        #expect(result.newlyReady.first?.allReady == false)
        #expect(result.newlyReady.first?.nextPartPosition == 1)

        let readiness = PRStackOrdering.readiness(of: prs, stackSize: 4)
        #expect(readiness.status == .readyToAdvance)
        #expect(readiness.isReadyToAdvance)
    }

    @Test func reportsASingleStackAcrossMultipleParts() {
        let ready = [makePR(1, position: 1, status: .success), makePR(2, position: 2, status: .success)]

        let result = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: ready)

        #expect(result.newlyReady.count == 1)
    }

    @Test func doesNotReportAStackWhoseBaseIsNotVisible() {
        let prs = [makePR(2, position: 2, status: .success)]

        let result = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: prs)

        #expect(result.newlyReady.isEmpty)
        #expect(result.readyStackIDs.isEmpty)
    }

    @Test func reportsAgainAfterTheStackRegressesAndRecovers() {
        let ready = [makePR(1, position: 1, status: .success)]
        let blocked = [makePR(1, position: 1, status: .failure)]

        let first = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: ready)
        let regressed = PRStackOrdering.readinessTransitions(previouslyReady: first.readyStackIDs, prs: blocked)
        let recovered = PRStackOrdering.readinessTransitions(previouslyReady: regressed.readyStackIDs, prs: ready)

        #expect(first.newlyReady.count == 1)
        #expect(regressed.newlyReady.isEmpty)
        #expect(recovered.newlyReady.count == 1)
    }

    @Test func aDraftBaseKeepsTheStackUnreadyUntilItIsPublished() {
        // A draft base cannot merge, so the stack must not be reported ready;
        // publishing the same part (checks already green) makes it ready.
        let draftBase = [makePR(1, position: 1, status: .success, isDraft: true)]
        let publishedBase = [makePR(1, position: 1, status: .success)]

        let whileDraft = PRStackOrdering.readinessTransitions(previouslyReady: [], prs: draftBase)
        #expect(whileDraft.newlyReady.isEmpty)
        #expect(whileDraft.readyStackIDs.isEmpty)

        let oncePublished = PRStackOrdering.readinessTransitions(
            previouslyReady: whileDraft.readyStackIDs,
            prs: publishedBase
        )
        #expect(oncePublished.newlyReady.count == 1)
    }
}

@MainActor
struct PRStackInfoTests {

    @Test func labelsFirstStackEntryAsTheOneToMergeFirst() {
        let first = PRStackInfo(id: "stack-1", number: 42, size: 4, position: 1)

        #expect(first.helpText == "Stack #42, part 1 of 4. Merge this one first.")
    }

    @Test func labelsLaterStackEntriesAsFollowingThePreviousPart() {
        let third = PRStackInfo(id: "stack-1", number: 42, size: 4, position: 3)

        #expect(third.helpText == "Stack #42, part 3 of 4. Merge after part 2.")
    }
}

@MainActor
struct StackReadyNotificationContentTests {

    @Test func allReadyStackWithoutLandedPartsListsEveryPart() {
        let stack = ReadyStack(
            id: "ST_1",
            number: 7,
            size: 4,
            allReady: true,
            nextPartPosition: 1,
            landedPositions: []
        )

        let content = NotificationService.stackReadyContent(for: stack)

        #expect(content.title == "✅ Stack ready")
        #expect(content.subtitle == "Stack #7")
        #expect(content.body == "All 4 pull requests in this stack are ready to merge.")
        #expect(content.identifier == "stack-ST_1")
    }

    @Test func allReadyStackWithLandedPartsListsTheRemainder() {
        let stack = ReadyStack(
            id: "ST_1",
            number: 7,
            size: 4,
            allReady: true,
            nextPartPosition: 3,
            landedPositions: [1, 2]
        )

        let content = NotificationService.stackReadyContent(for: stack)

        #expect(content.body == "All remaining parts are ready to merge.")
    }

    @Test func partiallyVisibleStackNamesItsNextPart() {
        let stack = ReadyStack(
            id: "ST_1",
            number: 7,
            size: 3,
            allReady: false,
            nextPartPosition: 2,
            landedPositions: [1]
        )

        let content = NotificationService.stackReadyContent(for: stack)

        #expect(content.body == "Part 2 of 3 is ready to merge.")
    }

    @Test func stackWithoutANamableNextPartDoesNotClaimReadiness() {
        let stack = ReadyStack(
            id: "ST_1",
            number: 7,
            size: 4,
            allReady: false,
            nextPartPosition: nil,
            landedPositions: [1]
        )

        let content = NotificationService.stackReadyContent(for: stack)

        #expect(content.title == "Stack status unknown")
        #expect(content.body == "The next part to merge could not be determined.")
    }
}
