import Foundation

/// Only the newest import for a source may publish a result. Restoring a
/// configuration invalidates all previous tickets, including delayed failures.
struct ChannelImportState {
    struct Ticket {
        fileprivate let sourceID: String
        fileprivate let requestID: UUID
        fileprivate let generation: UUID
    }
    private var generation = UUID()
    private var requests: [String: UUID] = [:]
    var isLoading: Bool { !requests.isEmpty }

    mutating func begin(sourceID: String) -> Ticket {
        let id = UUID()
        requests[sourceID] = id
        return Ticket(sourceID: sourceID, requestID: id, generation: generation)
    }
    func accepts(_ ticket: Ticket) -> Bool {
        ticket.generation == generation && requests[ticket.sourceID] == ticket.requestID
    }
    mutating func finish(_ ticket: Ticket) {
        if accepts(ticket) { requests.removeValue(forKey: ticket.sourceID) }
    }
    mutating func cancel(sourceID: String) { requests.removeValue(forKey: sourceID) }
    mutating func invalidate() { generation = UUID(); requests.removeAll() }
}
