import Foundation

struct TrackerEvent: Codable, Identifiable {
    var id: String { messageID }
    let messageID: String
    let detectedAt: Date
    let senderAddress: String
    let subject: String
    let matchedDomains: [String]
}
