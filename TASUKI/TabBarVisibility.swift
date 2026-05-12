import SwiftUI
import Combine

/// メイン画面下部のカスタムタブバーを一時的に隠す（チャット・リクエスト詳細など）
@MainActor
final class TabBarVisibility: ObservableObject {
    private var depth = 0
    @Published private(set) var isHidden: Bool = false
    
    func pushHiddenContext() {
        depth += 1
        isHidden = depth > 0
    }
    
    func popHiddenContext() {
        depth = max(0, depth - 1)
        isHidden = depth > 0
    }
}
