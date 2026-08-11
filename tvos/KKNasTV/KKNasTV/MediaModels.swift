import Foundation

enum MediaServerKind: String, Codable, CaseIterable, Identifiable {
    case jellyfin
    case emby

    var id: String { rawValue }
    var title: String { rawValue == "jellyfin" ? "Jellyfin" : "Emby" }
    var supportsQuickConnect: Bool { self == .jellyfin }
}

struct ServerSession: Codable, Equatable {
    let kind: MediaServerKind
    let baseURL: URL
    let userID: String
    let username: String
    let serverName: String
    let serverVersion: String
    let deviceID: String
    let accessToken: String
}

struct ServerInfo: Decodable, Equatable {
    let serverName: String
    let id: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case serverName = "ServerName"
        case id = "Id"
        case version = "Version"
    }
}

struct AuthenticationResponse: Decodable, Equatable {
    struct User: Decodable, Equatable {
        let id: String
        let name: String
        let serverID: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case serverID = "ServerId"
        }
    }

    let user: User
    let accessToken: String
    let serverID: String?
    let serverName: String?

    enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
        case serverName = "ServerName"
    }
}

struct QuickConnectState: Decodable, Equatable {
    let code: String
    let secret: String
    let authenticated: Bool

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case secret = "Secret"
        case authenticated = "Authenticated"
    }
}

struct MediaLibrary: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let collectionType: String?
    let primaryImageItemID: String?
    let childCount: Int?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case collectionType = "CollectionType"
        case primaryImageItemID = "PrimaryImageItemId"
        case childCount = "ChildCount"
    }
}

struct MediaUserData: Decodable, Hashable {
    let playbackPositionTicks: Int64?
    let playedPercentage: Double?
    let playCount: Int?
    let played: Bool?

    enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
        case playCount = "PlayCount"
        case played = "Played"
    }
}

struct MediaItem: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?
    let overview: String?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let runTimeTicks: Int64?
    let seriesID: String?
    let seriesName: String?
    let seasonID: String?
    let seasonName: String?
    let indexNumber: Int?
    let parentIndexNumber: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let primaryImageAspectRatio: Double?
    let userData: MediaUserData?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case officialRating = "OfficialRating"
        case runTimeTicks = "RunTimeTicks"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seasonID = "SeasonId"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case primaryImageAspectRatio = "PrimaryImageAspectRatio"
        case userData = "UserData"
    }

    var isPlayable: Bool {
        ["Movie", "Episode", "Video", "Audio"].contains(type)
    }

    var isSeries: Bool { type == "Series" }

    var subtitle: String {
        if type == "Episode" {
            let season = parentIndexNumber.map { "第 \($0) 季" } ?? seasonName
            let episode = indexNumber.map { "第 \($0) 集" }
            return [season, episode].compactMap { $0 }.joined(separator: " · ")
        }
        if let productionYear { return String(productionYear) }
        return type ?? "媒体"
    }

    var durationText: String? {
        guard let runTimeTicks, runTimeTicks > 0 else { return nil }
        let totalMinutes = Int(runTimeTicks / 10_000_000 / 60)
        if totalMinutes >= 60 {
            return "\(totalMinutes / 60) 小时 \(totalMinutes % 60) 分钟"
        }
        return "\(totalMinutes) 分钟"
    }

    var progress: Double? {
        if let playedPercentage { return min(max(playedPercentage / 100, 0), 1) }
        guard let position = userData?.playbackPositionTicks,
              let duration = runTimeTicks,
              duration > 0 else { return nil }
        return min(max(Double(position) / Double(duration), 0), 1)
    }

    private var playedPercentage: Double? { userData?.playedPercentage }
}

struct ItemsResponse: Decodable, Equatable {
    let items: [MediaItem]
    let totalRecordCount: Int
    let startIndex: Int

    enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
        case startIndex = "StartIndex"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([MediaItem].self, forKey: .items) ?? []
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount) ?? items.count
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex) ?? 0
    }

    init(items: [MediaItem], totalRecordCount: Int, startIndex: Int = 0) {
        self.items = items
        self.totalRecordCount = totalRecordCount
        self.startIndex = startIndex
    }
}

struct LibrariesResponse: Decodable {
    let items: [MediaLibrary]

    enum CodingKeys: String, CodingKey { case items = "Items" }
}

struct PlaybackInfo: Decodable, Equatable {
    let mediaSources: [MediaSource]
    let playSessionID: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case playSessionID = "PlaySessionId"
    }
}

struct MediaSource: Decodable, Equatable {
    let id: String
    let container: String?
    let supportsDirectPlay: Bool
    let supportsDirectStream: Bool
    let supportsTranscoding: Bool
    let directStreamURL: String?
    let transcodingURL: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case directStreamURL = "DirectStreamUrl"
        case transcodingURL = "TranscodingUrl"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        self.container = try container.decodeIfPresent(String.self, forKey: .container)
        supportsDirectPlay = try container.decodeIfPresent(Bool.self, forKey: .supportsDirectPlay) ?? false
        supportsDirectStream = try container.decodeIfPresent(Bool.self, forKey: .supportsDirectStream) ?? false
        supportsTranscoding = try container.decodeIfPresent(Bool.self, forKey: .supportsTranscoding) ?? false
        directStreamURL = try container.decodeIfPresent(String.self, forKey: .directStreamURL)
        transcodingURL = try container.decodeIfPresent(String.self, forKey: .transcodingURL)
    }
}

struct PlaybackPlan: Equatable {
    enum Method: String, Equatable {
        case directPlay = "DirectPlay"
        case directStream = "DirectStream"
        case transcode = "Transcode"
    }

    let url: URL
    let method: Method
    let playSessionID: String
    let mediaSourceID: String
}
