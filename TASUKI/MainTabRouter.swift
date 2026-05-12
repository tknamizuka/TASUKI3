import SwiftUI
import Combine

/// Run タブなどからホームタブ（index 0）へ切り替えるための共有ルーター。
@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selectedTab: Int = 0
    /// `HomeView` がシートで `MessageListView` を開く（例: ログイン済みで規約をスキップしたあと「メッセージ」タブへ）
    @Published var pendingMessageHubTab: MessageListTab?
    /// Run タブから履歴一覧へ入ったときなど、ナビの「戻る」と二重になるため MainTabView の Home ショートカットを隠す
    @Published var suppressBackToHomeOverlay: Bool = false
}
