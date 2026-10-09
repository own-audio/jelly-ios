# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Implementation plan: feature parity with own.audio for Subsonic, on a hand-written
  Jellyfin client and the shared player-engine package.
- `JellyfinKit`: sign-in by name and password or Quick Connect (the token is kept, never the
  password), server info, music libraries (listings can be limited to one), album artists,
  albums in seven orders (name, artist, newest, recently played, most played, random,
  favorites), album and artist detail, songs page by page, genres, random songs, search,
  instant mix, favorites, playlists (create, add, rename, remove by entry, delete), synced
  lyrics, playback reporting and counted plays, stream and image URLs, sign-out.
  Models follow own.audio for Subsonic's field names so the screens can stay alike.
- Offline support in the client: read answers are kept on disk (`DiskResponseCache`) and come
  back when the network fails or the app is offline (`OfflineSwitch`); writes are refused
  offline with `.offline`.
- `ServerStore`: signed-in servers in one Keychain item, with the chosen library.
- Tests: 12 stubbed client tests; 8 live tests against a real Jellyfin 12.2 server (sign-in,
  browsing, paging, search, instant mix, a favorite and a playlist put back as they were,
  stream and covers, lyrics, reporting and sign-out).
