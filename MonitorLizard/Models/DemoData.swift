import Foundation

enum DemoData {
    static let samplePullRequests: [PullRequest] = [
        // REVIEWING PRs (2 total)

        // 1. SUCCESS - Reviewing PR
        PullRequest(
            number: 267,
            title: "Update cat ear tufts measurement guidelines",
            repository: PullRequest.RepositoryInfo(
                name: "cat-show-tracker",
                nameWithOwner: "feline-federation/cat-show-tracker"
            ),
            url: "https://github.com/feline-federation/cat-show-tracker/pull/267",
            author: PullRequest.Author(login: "judge-whiskers"),
            headRefName: "docs/ear-tuft-standards",
            updatedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            buildStatus: .success,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "1", name: "documentation", color: "0075ca")
            ],
            type: .reviewing,
            isDraft: false
        ),

        // 2. PENDING - Reviewing PR
        PullRequest(
            number: 203,
            title: "Refactor Persian cat coat quality scoring system",
            repository: PullRequest.RepositoryInfo(
                name: "cat-show-tracker",
                nameWithOwner: "feline-federation/cat-show-tracker"
            ),
            url: "https://github.com/feline-federation/cat-show-tracker/pull/203",
            author: PullRequest.Author(login: "cat-judge-marie"),
            headRefName: "refactor/persian-scoring",
            updatedAt: Date().addingTimeInterval(-1800), // 30 minutes ago
            buildStatus: .pending,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "2", name: "refactoring", color: "fbca04")
            ],
            type: .reviewing,
            isDraft: false
        ),

        // AUTHORED PRs (6 total)

        // 3. SUCCESS - Authored PR
        PullRequest(
            number: 421,
            title: "Add temperature monitoring for cave aging rooms",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/421",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "feature/temperature-sensors",
            updatedAt: Date().addingTimeInterval(-3600), // 1 hour ago
            buildStatus: .success,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "3", name: "enhancement", color: "a2eeef")
            ],
            type: .authored,
            isDraft: false
        ),

        // 4. FAILURE - Authored PR
        PullRequest(
            number: 387,
            title: "Implement Camembert ripeness detection algorithm",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/387",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "feature/camembert-ai",
            updatedAt: Date().addingTimeInterval(-7200), // 2 hours ago
            buildStatus: .failure,
            isWatched: true,
            labels: [
                PullRequest.Label(id: "4", name: "bug", color: "d73a4a"),
                PullRequest.Label(id: "5", name: "machine-learning", color: "0e8a16")
            ],
            type: .authored,
            isDraft: false
        ),

        // 5. PENDING - Authored PR
        PullRequest(
            number: 512,
            title: "Update cheese rotation schedule for blue varieties",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/512",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "fix/roquefort-rotation",
            updatedAt: Date().addingTimeInterval(-1800), // 30 minutes ago
            buildStatus: .pending,
            isWatched: true,
            labels: [],
            type: .authored,
            isDraft: false
        ),

        // 6. CONFLICT - Authored PR
        PullRequest(
            number: 445,
            title: "Merge brie and camembert aging profiles",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/445",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "feature/unified-soft-cheese",
            updatedAt: Date().addingTimeInterval(-10800), // 3 hours ago
            buildStatus: .conflict,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "6", name: "needs-rebase", color: "d93f0b")
            ],
            type: .authored,
            isDraft: false
        ),

        // 7. INACTIVE - Authored PR (Draft)
        PullRequest(
            number: 299,
            title: "WIP: Experimental mold detection via computer vision",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/299",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "experiment/cv-mold-detection",
            updatedAt: Date().addingTimeInterval(-345600), // 4 days ago
            buildStatus: .inactive,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "7", name: "experimental", color: "e4e669"),
                PullRequest.Label(id: "8", name: "draft", color: "6f42c1")
            ],
            type: .authored,
            isDraft: true
        ),

        // 8. PENDING - Authored PR (Draft)
        PullRequest(
            number: 498,
            title: "Draft: Parmesan aging time calculator",
            repository: PullRequest.RepositoryInfo(
                name: "cheese-cellar-manager",
                nameWithOwner: "fromagerie/cheese-cellar-manager"
            ),
            url: "https://github.com/fromagerie/cheese-cellar-manager/pull/498",
            author: PullRequest.Author(login: "demo-user"),
            headRefName: "draft/parmesan-calculator",
            updatedAt: Date().addingTimeInterval(-2700), // 45 minutes ago
            buildStatus: .pending,
            isWatched: false,
            labels: [
                PullRequest.Label(id: "9", name: "work-in-progress", color: "d4c5f9")
            ],
            type: .authored,
            isDraft: true
        )
    ]
}
