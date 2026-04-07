import SwiftUI
import Combine

/// Run タブなどからホームタブ（index 0）へ切り替えるための共有ルーター。
@MainActor
final class MainTabRouter: ObservableObject {
    @Published var selectedTab: Int = 0
}
