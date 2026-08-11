import Foundation

enum TVDeviceProfile {
    static let directPlayVideoContainers: Set<String> = ["mp4", "m4v", "mov"]

    static func supportsDirectPlay(container: String?) -> Bool {
        guard let container else { return false }
        return directPlayVideoContainers.contains(container.lowercased())
    }

    static func payload(maxBitrate: Int) -> [String: Any] {
        [
            "Name": "KKNas Apple TV",
            "MaxStreamingBitrate": maxBitrate,
            "MaxStaticBitrate": maxBitrate,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                [
                    "Container": "mp4,m4v,mov",
                    "Type": "Video",
                    "VideoCodec": "h264,hevc",
                    "AudioCodec": "aac,mp3,ac3,eac3,alac",
                ],
                [
                    "Container": "mp3,m4a,aac,wav,alac",
                    "Type": "Audio",
                ],
            ],
            "TranscodingProfiles": [
                [
                    "Container": "ts",
                    "Type": "Video",
                    "VideoCodec": "h264",
                    "AudioCodec": "aac,ac3,eac3",
                    "Protocol": "hls",
                    "Context": "Streaming",
                    "MaxAudioChannels": "8",
                    "MinSegments": 2,
                    "BreakOnNonKeyFrames": true,
                ],
            ],
            "ContainerProfiles": [],
            "CodecProfiles": [],
            "SubtitleProfiles": [
                ["Format": "vtt", "Method": "Hls"],
                ["Format": "srt", "Method": "Encode"],
                ["Format": "ass", "Method": "Encode"],
                ["Format": "ssa", "Method": "Encode"],
            ],
        ]
    }
}
