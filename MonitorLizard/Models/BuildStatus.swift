import SwiftUI

enum BuildStatus: String, Codable, Hashable {
    case conflict
    case pending
    case success
    case failure
    case error
    case changesRequested
    case unknown
    case inactive

    var icon: String {
        switch self {
        case .conflict: return "❗"
        case .success: return "✅"
        case .failure: return "❌"
        case .error: return "⚠️"
        case .changesRequested: return "🔄"
        case .pending: return "🔄"
        case .unknown: return "❓"
        case .inactive: return "⏳"
        }
    }

    var color: Color {
        switch self {
        case .conflict: return .purple
        case .success: return .green
        case .failure: return .red
        case .error: return .orange
        case .changesRequested: return .orange
        case .pending: return .blue
        case .unknown: return .gray
        case .inactive: return .orange
        }
    }

    var displayName: String {
        switch self {
        case .conflict: return "Merge Conflict"
        case .success: return "Success"
        case .failure: return "Failed"
        case .error: return "Error"
        case .changesRequested: return "Changes Requested"
        case .pending: return "Pending"
        case .unknown: return "Unknown"
        case .inactive: return "Inactive"
        }
    }
}
