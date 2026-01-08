import SwiftUI

enum BuildStatus: String, Codable, Hashable {
    case pending
    case success
    case failure
    case error
    case unknown

    var icon: String {
        switch self {
        case .success: return "✅"
        case .failure: return "❌"
        case .error: return "⚠️"
        case .pending: return "🔄"
        case .unknown: return "❓"
        }
    }

    var color: Color {
        switch self {
        case .success: return .green
        case .failure: return .red
        case .error: return .orange
        case .pending: return .blue
        case .unknown: return .gray
        }
    }

    var displayName: String {
        switch self {
        case .success: return "Success"
        case .failure: return "Failed"
        case .error: return "Error"
        case .pending: return "Pending"
        case .unknown: return "Unknown"
        }
    }
}
