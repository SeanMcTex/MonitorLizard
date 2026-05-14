import SwiftUI

enum BuildStatus: String, Codable, Hashable, CaseIterable {
    case conflict
    case notStarted
    case pending
    case success
    case failure
    case error
    case unknown
    case inactive

    var icon: String {
        switch self {
        case .conflict: return "❗"
        case .notStarted: return "🛑"
        case .success: return "✅"
        case .failure: return "❌"
        case .error: return "⚠️"
        case .pending: return "🔄"
        case .unknown: return "❓"
        case .inactive: return "⏳"
        }
    }

    var systemImageName: String? {
        switch self {
        case .notStarted: return "play.slash"
        case .pending: return "gear"
        case .success: return "gear.badge.checkmark"
        case .failure, .error: return "gear.badge.xmark"
        case .conflict, .unknown, .inactive: return nil
        }
    }

    var color: Color {
        switch self {
        case .conflict: return .purple
        case .notStarted: return .gray
        case .success: return .green
        case .failure: return .red
        case .error: return .orange
        case .pending: return .blue
        case .unknown: return .gray
        case .inactive: return .orange
        }
    }

    var displayName: String {
        switch self {
        case .conflict: return "Merge Conflict"
        case .notStarted: return "Not started"
        case .success: return "Success"
        case .failure: return "Failed"
        case .error: return "Error"
        case .pending: return "Pending"
        case .unknown: return "Unknown"
        case .inactive: return "Inactive"
        }
    }
}
