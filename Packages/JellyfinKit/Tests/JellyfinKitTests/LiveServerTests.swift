import Foundation
import Testing

@testable import JellyfinKit

/// Against a real server, skipped unless `JELLYFIN_HOST`, `JELLYFIN_USER` and
/// `JELLYFIN_PASSWORD` are set. Read-only except for a favorite and a playlist, which are put
/// back as they were; no play is counted.
enum LiveServerConfig {
    static let current: (host: URL, user: String, password: String)? = {
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["JELLYFIN_HOST"], let host = JellyfinClient.normalizeHost(raw),
              let user = env["JELLYFIN_USER"], let password = env["JELLYFIN_PASSWORD"]
        else { return nil }
        return (host, user, password)
    }()
}

@Suite("Live server", .serialized, .enabled(if: LiveServerConfig.current != nil))
struct LiveServerTests {

    private static let info = ClientInfo(client: "own.jelly tests", device: "swift test", deviceId: "own-jelly-live-tests", version: "0")

    private func client() async throws -> JellyfinClient {
        let env = try #require(LiveServerConfig.current)
        let session = try await JellyfinClient.signIn(host: env.host, username: env.user, password: env.password, clientInfo: Self.info)
        let api = JellyfinClient(host: env.host, session: session, clientInfo: Self.info)
        // Scope to the first music library, as the app does by default.
        let library = try await api.musicLibraries().first
        return JellyfinClient(host: env.host, session: session, libraryId: library?.id, clientInfo: Self.info)
    }

    @Test("server info and sign-in; a wrong password is refused")
    func signIn() async throws {
        let env = try #require(LiveServerConfig.current)
        let info = try await JellyfinClient.serverInfo(host: env.host)
        #expect(!info.version.isEmpty)
        await #expect(throws: JellyfinClient.JellyfinError.unauthorized) {
            try await JellyfinClient.signIn(host: env.host, username: env.user, password: env.password + "x", clientInfo: Self.info)
        }
        #expect(try await client().checkSession() == .ok)
    }

    @Test("music libraries, artists, every album order, an album with its songs")
    func browse() async throws {
        let api = try await client()
        #expect(try await !api.musicLibraries().isEmpty)
        #expect(try await !api.artists().isEmpty)
        for sort in AlbumSort.allCases where sort != .favorites {
            let albums = try await api.albums(sort, limit: 5)
            #expect(!albums.isEmpty, "\(sort) is empty")
        }
        let album = try #require(try await api.albums(.name, limit: 1).first)
        let loaded = try await api.album(id: album.id)
        #expect(loaded.album.id == album.id)
        #expect(!loaded.songs.isEmpty)
        #expect(loaded.songs.allSatisfy { $0.albumId == album.id && ($0.duration ?? 0) > 0 })
        if let artistId = album.artistId {
            #expect(try await api.albums(artistId: artistId).contains { $0.id == album.id })
        }
    }

    @Test("songs page by page, genres, random songs, search, instant mix")
    func songsAndDiscovery() async throws {
        let api = try await client()
        let first = try await api.songs(limit: 20)
        let second = try await api.songs(limit: 20, offset: 20)
        #expect(first.count == 20)
        #expect(Set(first.map(\.id)).isDisjoint(with: second.map(\.id)))
        let genre = try #require(try await api.genres().first { ($0.songCount ?? 1) > 0 })
        #expect(try await !api.albums(genreId: genre.id).isEmpty)
        #expect(try await api.randomSongs(limit: 10).count == 10)
        let word = String(first[0].title.split(separator: " ").first ?? "a")
        #expect(try await !api.search(word).isEmpty)
        #expect(try await !api.instantMix(itemId: first[0].id, limit: 10).isEmpty)
    }

    @Test("a favorite set and cleared again")
    func favoriteRoundTrip() async throws {
        let api = try await client()
        let song = try #require(try await api.songs(limit: 1, offset: 7).first)
        try await api.setFavorite(song.id, !song.isFavorite)
        #expect(try await api.song(id: song.id).isFavorite == !song.isFavorite)
        try await api.setFavorite(song.id, song.isFavorite)
        #expect(try await api.song(id: song.id).isFavorite == song.isFavorite)
        _ = try await api.favorites()
    }

    @Test("a playlist created, filled, renamed, trimmed and deleted")
    func playlistRoundTrip() async throws {
        let api = try await client()
        let songs = try await api.songs(limit: 3)
        let id = try await api.createPlaylist(name: "own.jelly test", songIds: [songs[0].id])
        do {
            try await api.addToPlaylist(id: id, songIds: [songs[1].id, songs[2].id])
            try await api.renamePlaylist(id: id, to: "own.jelly test renamed")
            var loaded = try await api.playlist(id: id)
            #expect(loaded.songs.map(\.id) == songs.map(\.id))
            #expect(loaded.playlist.name == "own.jelly test renamed")
            let entry = try #require(loaded.songs[1].playlistItemId)
            try await api.removeFromPlaylist(id: id, entryIds: [entry])
            loaded = try await api.playlist(id: id)
            #expect(loaded.songs.map(\.id) == [songs[0].id, songs[2].id])
        } catch {
            try? await api.deletePlaylist(id: id)
            throw error
        }
        try await api.deletePlaylist(id: id)
        #expect(try await !api.playlists().contains { $0.id == id })
    }

    @Test("the stream URL returns audio and covers load without the token")
    func streamAndImages() async throws {
        let api = try await client()
        let song = try #require(try await api.songs(limit: 1).first)
        var request = URLRequest(url: api.streamURL(songId: song.id))
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        let (_, streamResponse) = try await URLSession.shared.data(for: request)
        let http = try #require(streamResponse as? HTTPURLResponse)
        #expect([200, 206].contains(http.statusCode))
        #expect(http.mimeType?.hasPrefix("audio/") == true)
        let cover = try #require(song.coverArt)
        let (_, imageResponse) = try await URLSession.shared.data(from: api.imageURL(itemId: cover, size: 200))
        #expect((imageResponse as? HTTPURLResponse)?.mimeType?.hasPrefix("image/") == true)
    }

    @Test("lyrics: none is nil, not an error")
    func lyrics() async throws {
        let api = try await client()
        let song = try #require(try await api.songs(limit: 1).first)
        _ = try await api.lyrics(songId: song.id)
    }

    @Test("playback reporting is accepted; the session ends cleanly")
    func reporting() async throws {
        let api = try await client()
        let song = try #require(try await api.songs(limit: 1).first)
        try await api.reportStart(songId: song.id)
        try await api.reportProgress(songId: song.id, positionSecs: 5, isPaused: true)
        try await api.reportStopped(songId: song.id, positionSecs: 5)
        await api.signOut()
        #expect(await api.checkSession() == .rejected)
    }
}
