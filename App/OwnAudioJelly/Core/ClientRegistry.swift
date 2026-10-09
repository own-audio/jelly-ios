import Foundation
import JellyfinKit

/// The connected servers' clients, reachable from the engine's background resolver as well as
/// from the UI.
actor ClientRegistry {
    private var clients: [UUID: JellyfinClient] = [:]

    func set(_ clients: [UUID: JellyfinClient]) {
        self.clients = clients
    }

    func client(for serverId: UUID) -> JellyfinClient? {
        clients[serverId]
    }

    /// The stream URL for one of our composite track ids.
    func streamURL(trackId: String) throws -> URL {
        guard let (serverId, songId) = TrackID.parse(trackId), let client = clients[serverId] else {
            throw URLError(.badURL)
        }
        return client.streamURL(songId: songId)
    }
}
