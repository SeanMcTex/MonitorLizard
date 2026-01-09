import SwiftUI

enum BuildStatus: String, Codable, Hashable {
    case conflict
    case pending
    case success
    case failure
    case error
    case unknown
    case stale

    var icon: String {
        switch self {
        case .conflict: return "❗"
        case .success: return "✅"
        case .failure: return "❌"
        case .error: return "⚠️"
        case .pending: return "🔄"
        case .unknown: return "❓"
        case .stale: return "⏳"
        }
    }

    var color: Color {
        switch self {
        case .conflict: return .purple
        case .success: return .green
        case .failure: return .red
        case .error: return .orange
        case .pending: return .blue
        case .unknown: return .gray
        case .stale: return .orange
        }
    }

    var displayName: String {
        switch self {
        case .conflict: return "Merge Conflict"
        case .success: return "Success"
        case .failure: return "Failed"
        case .error: return "Error"
        case .pending: return "Pending"
        case .unknown: return "Unknown"
        case .stale: return "Stale"
        }
    }
}
