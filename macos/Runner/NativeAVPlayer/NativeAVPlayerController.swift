import Foundation
import AVFoundation
import AVKit
import Cocoa
import FlutterMacOS

/// 外部字幕的一条时间轴文本（overlay 渲染用）。
struct NativeSubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

/**
 AVPlayer 控制器 (macOS)

 封装 AVPlayer 提供完整的播放控制功能
 */
class NativeAVPlayerController: NSObject {

    let playerId: Int64
    let player: AVPlayer
    private(set) var playerItem: AVPlayerItem?

    /// 事件回调
    private let eventCallback: ([String: Any]) -> Void

    /// 观察器
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var durationObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var rateObserver: NSKeyValueObservation?

    /// 当前状态
    private var isPlaying = false
    private var isBuffering = false
    private var currentPosition: Int64 = 0
    private var totalDuration: Int64 = 0
    private var currentVolume: Float = 1.0
    private var currentSpeed: Float = 1.0
    private var videoWidth: Int = 0
    private var videoHeight: Int = 0

    /// 外部字幕（AVFoundation 无法直接挂载独立 .srt/.vtt，改用 overlay 渲染）
    private var subtitleCues: [NativeSubtitleCue] = []
    private var subtitleActive = false
    private var currentCueIndex = -1
    private weak var subtitleLabel: NSTextField?

    /// PlayerLayer (用于视图)
    private(set) var playerLayer: AVPlayerLayer?

    init(playerId: Int64, eventCallback: @escaping ([String: Any]) -> Void) {
        self.playerId = playerId
        self.player = AVPlayer()
        self.eventCallback = eventCallback
        super.init()

        setupRateObserver()
    }

    // MARK: - 生命周期

    func open(url urlString: String, headers: [String: String]?, completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(NSError(domain: "NativeAVPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }

        // 清理之前的 playerItem
        cleanupPlayerItem()

        // 配置 HTTP 请求头
        var assetOptions: [String: Any] = [:]
        if let headers = headers, !headers.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        // 创建 Asset
        let asset = AVURLAsset(url: url, options: assetOptions)

        // 异步加载资源
        asset.loadValuesAsynchronously(forKeys: ["playable", "tracks", "duration"]) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }

                var error: NSError?
                let status = asset.statusOfValue(forKey: "playable", error: &error)

                if status == .failed {
                    completion(error ?? NSError(domain: "NativeAVPlayer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to load asset"]))
                    return
                }

                // 创建 PlayerItem
                self.playerItem = AVPlayerItem(asset: asset)
                self.player.replaceCurrentItem(with: self.playerItem)

                // 设置观察器
                self.setupObservers()

                // 获取视频尺寸
                self.updateVideoSize()

                // 发送初始化事件
                self.sendEvent("initialized", data: [:])

                completion(nil)
            }
        }
    }

    func play() {
        player.play()
        player.rate = currentSpeed
    }

    func pause() {
        player.pause()
    }

    func seek(to positionMs: Int64) {
        let time = CMTime(value: positionMs, timescale: 1000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            self?.sendEvent("seekCompleted", data: [:])
        }
    }

    func setSpeed(_ speed: Float) {
        currentSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }

    func setVolume(_ volume: Float) {
        currentVolume = volume
        player.volume = volume
    }

    func dispose() {
        cleanupPlayerItem()
        player.replaceCurrentItem(with: nil)
    }

    // MARK: - 音轨管理

    func getAudioTracks() -> [[String: Any]] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible) else {
            return []
        }

        return group.options.enumerated().map { index, option in
            var track: [String: Any] = [
                "index": index,
                "id": option.displayName,
                "title": option.displayName
            ]

            if let locale = option.locale {
                track["language"] = locale.identifier
            }

            return track
        }
    }

    func setAudioTrack(index: Int) {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              index >= 0 && index < group.options.count else {
            return
        }

        item.select(group.options[index], in: group)
        sendEvent("audioTrackChanged", data: ["index": index])
    }

    // MARK: - 字幕管理

    func getSubtitleTracks() -> [[String: Any]] {
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else {
            return []
        }

        return group.options.enumerated().map { index, option in
            var track: [String: Any] = [
                "index": index,
                "id": option.displayName,
                "title": option.displayName
            ]

            if let locale = option.locale {
                track["language"] = locale.identifier
            }

            if option.hasMediaCharacteristic(.containsOnlyForcedSubtitles) {
                track["isForced"] = true
            }

            return track
        }
    }

    func setSubtitleTrack(index: Int) {
        // 选择内嵌字幕轨时关闭外部 overlay 字幕
        deactivateExternalSubtitle()
        guard let item = playerItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible),
              index >= 0 && index < group.options.count else {
            return
        }

        item.select(group.options[index], in: group)
        sendEvent("subtitleTrackChanged", data: ["index": index])
    }

    func disableSubtitle() {
        // 同时关闭外部 overlay 字幕与内嵌字幕选择
        deactivateExternalSubtitle()
        if let item = playerItem,
           let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) {
            item.select(nil, in: group)
        }
        sendEvent("subtitleTrackChanged", data: ["index": -1])
    }

    // MARK: - 外部字幕（overlay）

    /// 由 Platform View 注册用于绘制外部字幕的 NSTextField。
    func setSubtitleOverlayLabel(_ label: NSTextField?) {
        subtitleLabel = label
    }

    /// 加载外部字幕文件（本地 file:// / 纯路径 / http(s)），解析为 overlay 字幕轨并选中。
    /// 返回一个合成索引（置于内嵌字幕轨之后）；失败返回 -1。
    func loadExternalSubtitle(
        urlString: String,
        title: String?,
        language: String?,
        completion: @escaping (Int) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { completion(-1); return }
            let data = Self.loadSubtitleData(urlString)
            guard let bytes = data, let content = Self.decodeSubtitleData(bytes), !content.isEmpty else {
                DispatchQueue.main.async { completion(-1) }
                return
            }
            let cues = Self.parseSubtitles(content)
            DispatchQueue.main.async {
                guard !cues.isEmpty else { completion(-1); return }
                self.subtitleCues = cues
                self.subtitleActive = true
                self.currentCueIndex = -1
                let embedded = self.playerItem?.asset
                    .mediaSelectionGroup(forMediaCharacteristic: .legible)?.options.count ?? 0
                completion(embedded)
            }
        }
    }

    private func deactivateExternalSubtitle() {
        subtitleActive = false
        currentCueIndex = -1
        let label = subtitleLabel
        DispatchQueue.main.async {
            label?.stringValue = ""
            label?.isHidden = true
        }
    }

    private func updateSubtitleOverlay(seconds: Double) {
        guard subtitleActive, let label = subtitleLabel else { return }
        if currentCueIndex >= 0 && currentCueIndex < subtitleCues.count {
            let c = subtitleCues[currentCueIndex]
            if seconds >= c.start && seconds <= c.end { return }
        }
        var found = -1
        for (i, c) in subtitleCues.enumerated() {
            if seconds >= c.start && seconds <= c.end { found = i; break }
            if c.start > seconds { break }
        }
        if found != currentCueIndex {
            currentCueIndex = found
            if found >= 0 {
                label.stringValue = subtitleCues[found].text
                label.isHidden = false
            } else {
                label.stringValue = ""
                label.isHidden = true
            }
        }
    }

    // MARK: - 字幕文件读取与解析

    private static func loadSubtitleData(_ urlString: String) -> Data? {
        if let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" {
            return try? Data(contentsOf: url)
        }
        if let url = URL(string: urlString), url.isFileURL {
            return try? Data(contentsOf: url)
        }
        return FileManager.default.contents(atPath: urlString)
    }

    /// 依次尝试 UTF-8 / GB18030 / Latin-1 解码（中文字幕常为 GBK/GB18030）。
    private static func decodeSubtitleData(_ data: Data) -> String? {
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb)) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    static func parseSubtitles(_ raw: String) -> [NativeSubtitleCue] {
        var text = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }

        var cues: [NativeSubtitleCue] = []
        for block in text.components(separatedBy: "\n\n") {
            var lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if let first = lines.first,
               Int(first.trimmingCharacters(in: .whitespaces)) != nil {
                lines.removeFirst()
            }
            guard let timeLine = lines.first, timeLine.contains("-->") else { continue }
            let parts = timeLine.components(separatedBy: "-->")
            guard parts.count == 2,
                  let start = parseCueTime(parts[0]),
                  let end = parseCueTime(parts[1]) else { continue }
            let cueText = lines.dropFirst()
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cueText.isEmpty { continue }
            cues.append(NativeSubtitleCue(start: start, end: end, text: stripTags(cueText)))
        }
        cues.sort { $0.start < $1.start }
        return cues
    }

    private static func parseCueTime(_ s: String) -> Double? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        let token = trimmed.split(separator: " ").first.map(String.init) ?? trimmed
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        let comps = normalized.split(separator: ":").map(String.init)
        guard comps.count >= 2 else { return nil }
        var hours = 0.0, minutes = 0.0, seconds = 0.0
        if comps.count >= 3 {
            hours = Double(comps[0]) ?? 0
            minutes = Double(comps[1]) ?? 0
            seconds = Double(comps[2]) ?? 0
        } else {
            minutes = Double(comps[0]) ?? 0
            seconds = Double(comps[1]) ?? 0
        }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func stripTags(_ s: String) -> String {
        var result = s.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(
            of: "\\{[^}]*\\}", with: "", options: .regularExpression)
        return result
    }

    // MARK: - 状态获取

    func getState() -> [String: Any] {
        return [
            "isPlaying": isPlaying,
            "isBuffering": isBuffering,
            "position": currentPosition,
            "duration": totalDuration,
            "volume": currentVolume,
            "speed": currentSpeed,
            "width": videoWidth,
            "height": videoHeight,
            "isPiPActive": false
        ]
    }

    // MARK: - 截图

    func screenshot(completion: @escaping (FlutterStandardTypedData?) -> Void) {
        guard let item = playerItem else {
            completion(nil)
            return
        }

        let time = item.currentTime()
        let imageGenerator = AVAssetImageGenerator(asset: item.asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        imageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
            DispatchQueue.main.async {
                guard let cgImage = cgImage else {
                    completion(nil)
                    return
                }

                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                if let tiffData = nsImage.tiffRepresentation,
                   let bitmapImage = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
                    completion(FlutterStandardTypedData(bytes: pngData))
                } else {
                    completion(nil)
                }
            }
        }
    }

    // MARK: - PlayerLayer

    func setupPlayerLayer(_ layer: AVPlayerLayer) {
        self.playerLayer = layer
        layer.player = player
    }

    // MARK: - 私有方法

    private func setupObservers() {
        guard let item = playerItem else { return }

        // 状态观察
        statusObserver = item.observe(\.status) { [weak self] item, _ in
            self?.handleStatusChange(item.status)
        }

        // 时长观察
        durationObserver = item.observe(\.duration) { [weak self] item, _ in
            guard let self = self else { return }
            if item.duration.isValid && !item.duration.isIndefinite {
                self.totalDuration = Int64(CMTimeGetSeconds(item.duration) * 1000)
                self.sendEvent("durationChanged", data: ["duration": self.totalDuration])
            }
        }

        // 缓冲观察
        bufferObserver = item.observe(\.isPlaybackBufferEmpty) { [weak self] item, _ in
            self?.handleBufferingChange(item.isPlaybackBufferEmpty)
        }

        // 时间观察 (30Hz)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            self.currentPosition = Int64(CMTimeGetSeconds(time) * 1000)
            self.sendEvent("positionChanged", data: ["position": self.currentPosition])
            self.updateSubtitleOverlay(seconds: CMTimeGetSeconds(time))
        }

        // 播放完成通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func setupRateObserver() {
        rateObserver = player.observe(\.rate) { [weak self] player, _ in
            guard let self = self else { return }
            let newIsPlaying = player.rate > 0
            if newIsPlaying != self.isPlaying {
                self.isPlaying = newIsPlaying
                self.sendEvent("playingChanged", data: ["isPlaying": newIsPlaying])
            }
        }
    }

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            sendEvent("ready", data: [:])
        case .failed:
            let error = playerItem?.error?.localizedDescription ?? "Unknown error"
            sendEvent("error", data: ["message": error])
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handleBufferingChange(_ isEmpty: Bool) {
        if isEmpty != isBuffering {
            isBuffering = isEmpty
            sendEvent("bufferingChanged", data: ["isBuffering": isEmpty])
        }
    }

    @objc private func playerDidFinishPlaying() {
        sendEvent("completed", data: [:])
    }

    private func updateVideoSize() {
        guard let item = playerItem else { return }

        for track in item.asset.tracks(withMediaType: .video) {
            let size = track.naturalSize.applying(track.preferredTransform)
            videoWidth = Int(abs(size.width))
            videoHeight = Int(abs(size.height))

            sendEvent("videoSizeChanged", data: [
                "width": videoWidth,
                "height": videoHeight
            ])
            break
        }
    }

    private func cleanupPlayerItem() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        durationObserver?.invalidate()
        durationObserver = nil

        bufferObserver?.invalidate()
        bufferObserver = nil

        if let item = playerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: item)
        }

        // 重置外部字幕状态
        subtitleCues = []
        subtitleActive = false
        currentCueIndex = -1
        subtitleLabel?.stringValue = ""
        subtitleLabel?.isHidden = true

        playerItem = nil
    }

    private func sendEvent(_ type: String, data: [String: Any]) {
        var event = data
        event["playerId"] = playerId
        event["event"] = type
        eventCallback(event)
    }
}
