import XCTest
@testable import KKNasTV

final class KKNasTVTests: XCTestCase {
    func testNormalizesLocalServerAddress() throws {
        XCTAssertEqual(
            try MediaServerClient.normalizedBaseURL(" 192.168.1.20:8096/ ").absoluteString,
            "http://192.168.1.20:8096"
        )
        XCTAssertThrowsError(try MediaServerClient.normalizedBaseURL("ftp://nas.local"))
    }

    func testUsesServerSpecificAuthorizationHeader() {
        let jellyfin = MediaServerClient.authorizationHeader(kind: .jellyfin, deviceID: "tv-1", token: "secret")
        XCTAssertEqual(jellyfin.name, "Authorization")
        XCTAssertTrue(jellyfin.value.hasPrefix("MediaBrowser "))
        XCTAssertTrue(jellyfin.value.contains("Device=\"Apple TV\""))
        XCTAssertTrue(jellyfin.value.contains("Token=\"secret\""))

        let emby = MediaServerClient.authorizationHeader(kind: .emby, deviceID: "tv-1", token: nil)
        XCTAssertEqual(emby.name, "X-Emby-Authorization")
        XCTAssertFalse(emby.value.contains("Token="))
    }

    func testTVDeviceProfileDoesNotAdvertiseUnsupportedContainers() throws {
        XCTAssertTrue(TVDeviceProfile.supportsDirectPlay(container: "mp4"))
        XCTAssertTrue(TVDeviceProfile.supportsDirectPlay(container: "MOV"))
        XCTAssertFalse(TVDeviceProfile.supportsDirectPlay(container: "mkv"))
        XCTAssertFalse(TVDeviceProfile.supportsDirectPlay(container: "avi"))

        let payload = TVDeviceProfile.payload(maxBitrate: 40_000_000)
        XCTAssertEqual(payload["MaxStreamingBitrate"] as? Int, 40_000_000)
        let directProfiles = try XCTUnwrap(payload["DirectPlayProfiles"] as? [[String: Any]])
        XCTAssertFalse(directProfiles.description.lowercased().contains("mkv"))
    }

    func testDecodesMediaProgressAndEpisodeMetadata() throws {
        let data = Data(
            """
            {
              "Id": "episode-8",
              "Name": "第八集",
              "Type": "Episode",
              "SeriesName": "听我的电波吧",
              "ParentIndexNumber": 1,
              "IndexNumber": 8,
              "RunTimeTicks": 12000000000,
              "UserData": {
                "PlaybackPositionTicks": 3000000000,
                "PlayedPercentage": 25
              }
            }
            """.utf8
        )
        let item = try JSONDecoder().decode(MediaItem.self, from: data)
        XCTAssertEqual(item.id, "episode-8")
        XCTAssertEqual(item.subtitle, "第 1 季 · 第 8 集")
        XCTAssertEqual(try XCTUnwrap(item.progress), 0.25, accuracy: 0.0001)
        XCTAssertEqual(item.durationText, "20 分钟")
        XCTAssertTrue(item.isPlayable)
    }

    func testPlaybackPlanPreservesServerSubpathForRelativeMediaURL() async throws {
        StubURLProtocol.handler = { request in
            let data = Data(
                """
                {
                  "PlaySessionId": "play-subpath",
                  "MediaSources": [{
                    "Id": "source-subpath",
                    "Container": "mkv",
                    "SupportsDirectPlay": false,
                    "SupportsDirectStream": false,
                    "SupportsTranscoding": true,
                    "TranscodingUrl": "/Videos/movie-subpath/master.m3u8?MediaSourceId=source-subpath"
                  }]
                }
                """.utf8
            )
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = MediaServerClient(
            session: makeSession(baseURL: URL(string: "https://media.example.com/jellyfin")!),
            urlSession: makeURLSession()
        )
        let plan = try await client.playbackPlan(
            item: try makeMediaItem(id: "movie-subpath", type: "Movie"),
            preferDirectPlay: false,
            maxBitrate: 80_000_000
        )

        XCTAssertEqual(plan.url.path, "/jellyfin/Videos/movie-subpath/master.m3u8")
        XCTAssertTrue(plan.url.query?.contains("api_key=test-token") == true)
    }

    func testRequestEncodesPathIdentifiersWithoutDroppingServerSubpath() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/jellyfin/Users/user id/Views")
            XCTAssertTrue(request.url?.absoluteString.contains("user%20id") == true)
            let data = Data("{\"Items\":[]}".utf8)
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let session = ServerSession(
            kind: .jellyfin,
            baseURL: URL(string: "https://media.example.com/jellyfin")!,
            userID: "user id",
            username: "tester",
            serverName: "Media",
            serverVersion: "10.10.0",
            deviceID: "tv-1",
            accessToken: "test-token"
        )
        let client = MediaServerClient(session: session, urlSession: makeURLSession())

        _ = try await client.libraries()
    }

    func testPlaybackPlanDoesNotLeakTokenToExternalMediaHost() async throws {
        StubURLProtocol.handler = { request in
            let data = Data(
                """
                {
                  "PlaySessionId": "play-external",
                  "MediaSources": [{
                    "Id": "source-external",
                    "Container": "mp4",
                    "SupportsDirectPlay": false,
                    "SupportsDirectStream": true,
                    "SupportsTranscoding": false,
                    "DirectStreamUrl": "https://cdn.example.net/movie.mp4?signature=signed"
                  }]
                }
                """.utf8
            )
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = MediaServerClient(session: makeSession(), urlSession: makeURLSession())
        let plan = try await client.playbackPlan(
            item: try makeMediaItem(id: "movie-external", type: "Movie"),
            preferDirectPlay: false,
            maxBitrate: 80_000_000
        )

        XCTAssertEqual(plan.url.host, "cdn.example.net")
        XCTAssertEqual(plan.url.query, "signature=signed")
        XCTAssertFalse(plan.url.absoluteString.contains("test-token"))
    }

    func testPlaybackPlanForcesHLSForMKV() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/Items/movie-1/PlaybackInfo")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let data = Data(
                """
                {
                  "PlaySessionId": "play-1",
                  "MediaSources": [{
                    "Id": "source-1",
                    "Container": "mkv",
                    "SupportsDirectPlay": true,
                    "SupportsDirectStream": false,
                    "SupportsTranscoding": true,
                    "TranscodingUrl": "/Videos/movie-1/master.m3u8?MediaSourceId=source-1"
                  }]
                }
                """.utf8
            )
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = MediaServerClient(session: makeSession(), urlSession: makeURLSession())
        let item = try makeMediaItem(id: "movie-1", type: "Movie")
        let plan = try await client.playbackPlan(item: item, preferDirectPlay: true, maxBitrate: 80_000_000)

        XCTAssertEqual(plan.method, .transcode)
        XCTAssertEqual(plan.playSessionID, "play-1")
        XCTAssertEqual(plan.url.path, "/Videos/movie-1/master.m3u8")
        XCTAssertTrue(plan.url.query?.contains("api_key=test-token") == true)
    }

    func testPlaybackPlanDirectPlaysCompatibleMP4() async throws {
        StubURLProtocol.handler = { request in
            let data = Data(
                """
                {
                  "PlaySessionId": "play-2",
                  "MediaSources": [{
                    "Id": "source-2",
                    "Container": "mp4",
                    "SupportsDirectPlay": true,
                    "SupportsDirectStream": true,
                    "SupportsTranscoding": true
                  }]
                }
                """.utf8
            )
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
        }

        let client = MediaServerClient(session: makeSession(), urlSession: makeURLSession())
        let plan = try await client.playbackPlan(
            item: try makeMediaItem(id: "movie-2", type: "Movie"),
            preferDirectPlay: true,
            maxBitrate: 80_000_000
        )

        XCTAssertEqual(plan.method, .directPlay)
        XCTAssertEqual(plan.url.path, "/Videos/movie-2/stream")
        XCTAssertTrue(plan.url.query?.contains("static=true") == true)
    }

    func testServerMetadataNeverStoresAccessTokenInDefaults() throws {
        let suiteName = "KKNasTVTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tokenStore = MemoryTokenStore()
        let store = ServerAccountStore(defaults: defaults, tokenStore: tokenStore)
        let session = makeSession()

        try store.save(session)

        XCTAssertEqual(try store.load(), session)
        XCTAssertEqual(tokenStore.value, "test-token")
        let serializedDefaults = String(describing: defaults.dictionaryRepresentation())
        XCTAssertFalse(serializedDefaults.contains("test-token"))
    }

    private func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeSession(
        baseURL: URL = URL(string: "https://media.example.com")!
    ) -> ServerSession {
        ServerSession(
            kind: .jellyfin,
            baseURL: baseURL,
            userID: "user-1",
            username: "tester",
            serverName: "Media",
            serverVersion: "10.10.0",
            deviceID: "tv-1",
            accessToken: "test-token"
        )
    }

    private func makeMediaItem(id: String, type: String) throws -> MediaItem {
        try JSONDecoder().decode(
            MediaItem.self,
            from: Data("{\"Id\":\"\(id)\",\"Name\":\"Movie\",\"Type\":\"\(type)\"}".utf8)
        )
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw MediaServerError.invalidResponse }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class MemoryTokenStore: TokenStoring {
    var value: String?

    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}
