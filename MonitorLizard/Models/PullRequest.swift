import Foundation

struct PullRequest: Identifiable, Hashable {
    let number: Int
    let title: String
    let repository: RepositoryInfo
    let url: String
    let author: Author
    let headRefName: String
    let updatedAt: Date
    var buildStatus: BuildStatus
    var isWatched: Bool
    let labels: [Label]

    var id: String {
        "\(repository.nameWithOwner)#\(number)"
    }

    struct RepositoryInfo: Hashable {
        let name: String
        let nameWithOwner: String
    }

    struct Author: Hashable {
        let login: String
    }

    struct Label: Hashable, Identifiable {
        let id: String
        let name: String
        let color: String
    }
}

// Response structures for parsing gh CLI JSON output
struct GHPRSearchResponse: Codable {
    let number: Int
    let title: String
    let repository: Repository
    let url: String
    let author: Author
    let updatedAt: String
    let labels: [Label]

    struct Repository: Codable {
        let name: String
        let nameWithOwner: String
    }

    struct Author: Codable {
        let login: String
    }

    struct Label: Codable {
        let id: String
        let name: String
        let color: String
    }
}

struct GHPRDetailResponse: Codable {
    let headRefName: String
    let statusCheckRollup: [StatusCheck]?

    struct StatusCheck: Codable {
        let name: String?
        let context: String?
        let status: String?
        let state: String?
        let conclusion: String?
        let __typename: String

        private enum CodingKeys: String, CodingKey {
            case name, context, status, state, conclusion, __typename
        }
    }
}
