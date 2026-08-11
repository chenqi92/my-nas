import AVKit
import Combine
import SwiftUI

struct PlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel

    init(item: MediaItem, appModel: AppModel) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(item: item, appModel: appModel))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player = viewModel.player {
                PlayerViewControllerRepresentable(player: player)
                    .ignoresSafeArea()
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 28) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.yellow)
                    Text("无法播放")
                        .font(.largeTitle.bold())
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 800)
                    Button("返回") { dismiss() }
                }
            } else {
                LoadingOverlay(text: "正在准备播放…")
            }
        }
        .task { await viewModel.prepare() }
        .onDisappear { Task { await viewModel.stop() } }
    }
}

private struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
    }
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var errorMessage: String?

    private let item: MediaItem
    private let appModel: AppModel
    private var plan: PlaybackPlan?
    private var timeObserver: Any?
    private var didPrepare = false
    private var didStop = false
    private var lastReportSeconds: Double = 0

    init(item: MediaItem, appModel: AppModel) {
        self.item = item
        self.appModel = appModel
    }

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        do {
            let plan = try await appModel.playbackPlan(for: item)
            self.plan = plan
            let player = AVPlayer(url: plan.url)
            player.preventsDisplaySleepDuringVideoPlayback = true
            self.player = player

            let resumeTicks = item.userData?.playbackPositionTicks ?? 0
            if resumeTicks > 0 {
                let seconds = Double(resumeTicks) / 10_000_000
                await player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
            }
            addProgressObserver(to: player)
            await appModel.reportPlaybackStart(itemID: item.id, plan: plan, positionTicks: resumeTicks)
            player.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        guard !didStop else { return }
        didStop = true
        let position = positionTicks
        player?.pause()
        removeProgressObserver()
        if let plan {
            await appModel.reportPlaybackStopped(itemID: item.id, plan: plan, positionTicks: position)
        }
    }

    private var positionTicks: Int64 {
        guard let seconds = player?.currentTime().seconds, seconds.isFinite else { return 0 }
        return Int64(max(seconds, 0) * 10_000_000)
    }

    private func addProgressObserver(to player: AVPlayer) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self, time.seconds.isFinite else { return }
            Task { @MainActor in
                await self.reportProgressIfNeeded(seconds: time.seconds)
            }
        }
    }

    private func reportProgressIfNeeded(seconds: Double) async {
        guard abs(seconds - lastReportSeconds) >= 15, let plan else { return }
        lastReportSeconds = seconds
        let paused = player?.timeControlStatus != .playing
        await appModel.reportPlaybackProgress(
            itemID: item.id,
            plan: plan,
            positionTicks: Int64(max(seconds, 0) * 10_000_000),
            isPaused: paused
        )
    }

    private func removeProgressObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
    }
}
