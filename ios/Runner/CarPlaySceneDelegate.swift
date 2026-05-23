import CarPlay
import Foundation
import UIKit

/// CarPlay scene 入口
///
/// 树结构（与 Dart 端 `MusicBrowserService` 保持一致）：
/// ```
/// root
/// ├─ artists     (艺术家)
/// ├─ albums      (专辑)
/// ├─ playlists   (歌单)
/// └─ favorites   (收藏)
/// ```
/// 这 4 个根节点以 `CPTabBarTemplate` 形式呈现，下钻使用 `CPListTemplate`。
/// 点击曲目调 Dart `playFromMediaId`，并 push `CPNowPlayingTemplate`。
///
/// CarPlay framework 的 list/handler/Now Playing API 均自 iOS 14 起；老系统
/// (≤ 13) 不会创建 CarPlay scene，所以整个 delegate 标 `@available(iOS 14.0, *)`。
@available(iOS 14.0, *)
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {

    private var interfaceController: CPInterfaceController?

    /// 已经 push 过 Now Playing 模板，避免重复 push
    private var hasPushedNowPlaying = false

    /// 顶层 tab 配置：(label, mediaId)
    /// 与 `MusicBrowserService` 中的常量一一对应
    private let rootTabs: [(label: String, mediaId: String, systemImage: String)] = [
        ("艺术家", "artists", "music.mic"),
        ("专辑", "albums", "square.stack"),
        ("歌单", "playlists", "music.note.list"),
        ("收藏", "favorites", "heart.fill"),
    ]

    // MARK: - CPTemplateApplicationSceneDelegate

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        NSLog("🚗 CarPlaySceneDelegate: didConnect")
        self.interfaceController = interfaceController

        let tabTemplates = rootTabs.enumerated().map { index, tab in
            buildRootList(label: tab.label, mediaId: tab.mediaId, systemImage: tab.systemImage)
        }

        let tabBar = CPTabBarTemplate(templates: tabTemplates)
        interfaceController.setRootTemplate(tabBar, animated: false) { success, error in
            if let error = error {
                NSLog("🚗 CarPlaySceneDelegate: setRootTemplate failed: \(error)")
            } else {
                NSLog("🚗 CarPlaySceneDelegate: setRootTemplate ok=\(success)")
            }
        }

        // 接管 Now Playing 变化：当 Dart 端切歌时，自动 push Now Playing 模板
        CarPlayChannel.shared.onNowPlayingChanged = { [weak self] item in
            guard let self = self, item != nil else { return }
            self.pushNowPlayingIfNeeded()
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        NSLog("🚗 CarPlaySceneDelegate: didDisconnect")
        CarPlayChannel.shared.onNowPlayingChanged = nil
        self.interfaceController = nil
        self.hasPushedNowPlaying = false
    }

    // MARK: - Templates

    /// 根 tab：异步拉取数据并填充
    private func buildRootList(label: String, mediaId: String, systemImage: String) -> CPListTemplate {
        let template = CPListTemplate(title: label, sections: [emptySection(loading: true)])
        if #available(iOS 14.0, *) {
            template.tabImage = UIImage(systemName: systemImage)
        }
        template.tabTitle = label

        loadChildren(parentMediaId: mediaId) { [weak template] items in
            guard let template = template else { return }
            template.updateSections([self.section(from: items, parentLabel: label)])
        }
        return template
    }

    /// 下钻列表：从某个 parentMediaId 拉数据并 push
    private func pushBrowsableList(parentMediaId: String, title: String) {
        let template = CPListTemplate(title: title, sections: [emptySection(loading: true)])
        interfaceController?.pushTemplate(template, animated: true) { _, error in
            if let error = error { NSLog("🚗 pushTemplate err: \(error)") }
        }

        loadChildren(parentMediaId: parentMediaId) { [weak template] items in
            guard let template = template else { return }
            template.updateSections([self.section(from: items, parentLabel: title)])
        }
    }

    /// 把 [CarPlayMediaItem] 转成 CPListSection
    private func section(from items: [CarPlayMediaItem], parentLabel: String) -> CPListSection {
        if items.isEmpty {
            // CPListItem.isEnabled 是 iOS 15+ 才有；这里就给个普通条目，
            // 点了也只是再 push 一个空 list，不会影响功能。
            let empty = CPListItem(text: "无内容", detailText: "切回手机端 \(parentLabel) 加载后再试")
            return CPListSection(items: [empty])
        }

        let listItems: [CPListItem] = items.map { item in
            let listItem = CPListItem(text: item.title, detailText: item.subtitle)
            if item.isBrowsable {
                listItem.accessoryType = .disclosureIndicator
            }
            // 异步加载封面：CPListItem.setImage 是主线程操作
            if let artUri = item.artUri, let url = URL(string: artUri) {
                Self.loadImage(url: url) { [weak listItem] image in
                    guard let listItem = listItem, let image = image else { return }
                    listItem.setImage(image)
                }
            }
            listItem.handler = { [weak self] _, completion in
                guard let self = self else { completion(); return }
                if item.isBrowsable {
                    self.pushBrowsableList(parentMediaId: item.id, title: item.title)
                } else if item.isPlayable {
                    CarPlayChannel.shared.playFromMediaId(item.id)
                    self.pushNowPlayingIfNeeded()
                }
                completion()
            }
            return listItem
        }
        return CPListSection(items: listItems)
    }

    private func emptySection(loading: Bool) -> CPListSection {
        let item = CPListItem(text: loading ? "加载中…" : "暂无", detailText: nil)
        return CPListSection(items: [item])
    }

    /// 仅在尚未 push 时 push Now Playing；之后 CarPlay 自身就能维持 Now Playing 入口
    private func pushNowPlayingIfNeeded() {
        guard let interfaceController = interfaceController else { return }
        if hasPushedNowPlaying { return }
        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController.pushTemplate(nowPlaying, animated: true) { [weak self] success, error in
            if let error = error {
                NSLog("🚗 push NowPlayingTemplate err: \(error)")
                return
            }
            if success {
                self?.hasPushedNowPlaying = true
            }
        }
    }

    // MARK: - Helpers

    private func loadChildren(parentMediaId: String, completion: @escaping ([CarPlayMediaItem]) -> Void) {
        CarPlayChannel.shared.getChildren(parentMediaId: parentMediaId) { items in
            completion(items)
        }
    }

    /// CarPlay 列表封面加载：通用 HTTP/HTTPS / file URL；用 URLSession 简单实现
    /// CarPlay 列表通常项数有限，不再做磁盘缓存，URLSession 默认内存缓存够用
    private static func loadImage(url: URL, completion: @escaping (UIImage?) -> Void) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            let image = data.flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
