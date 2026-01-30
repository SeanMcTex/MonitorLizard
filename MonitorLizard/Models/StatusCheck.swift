//
//  StatusCheck.swift
//  MonitorLizard
//
//  Represents an individual status check for a pull request
//

import SwiftUI

enum CheckStatus: String, Codable {
    case pending
    case success
    case failure
    case error
    case skipped

    var icon: String {
        switch self {
        case .pending:
            return "⏳"
        case .success:
            return "✅"
        case .failure:
            return "❌"
        case .error:
            return "⚠️"
        case .skipped:
            return "⊘"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .orange
        case .success:
            return .green
        case .failure:
            return .red
        case .error:
            return .yellow
        case .skipped:
            return .gray
        }
    }
}

struct StatusCheck: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let status: CheckStatus
    let detailsUrl: String?

    init(id: String, name: String, status: CheckStatus, detailsUrl: String?) {
        self.id = id
        self.name = name
        self.status = status
        self.detailsUrl = detailsUrl
    }
}
