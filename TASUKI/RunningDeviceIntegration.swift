import SwiftUI

/// ランニング取得元の「連携」
/// - **Apple Health**: ヘルスケアの権限と今月距離の確認
/// - **各社デバイス（Garmin 等）**: ヘルスケアを使わず各公式アプリを起動。走行データの集計は TASUKI 内の `RunActivity`（`source` 照合）のみ
enum RunningDeviceIntegration {
    static func connect(
        source: RunningDataSource,
        openURL: OpenURLAction,
        completion: @escaping (String) -> Void
    ) {
        guard source != .all else {
            DispatchQueue.main.async { completion("データソースを選び直してください。") }
            return
        }

        if source == .appleHealth {
            connectAppleHealthOnly(completion: completion)
            return
        }

        openCompanionAppURLs(for: source, openURL: openURL) { companionPart in
            Task { @MainActor in
                RunActivityStore.shared.refreshFromRemote()
                completion(
                    "\(companionPart) この取得元を選んだときの距離・タイムトライアルは、TASUKIに保存された走行記録のうち \(source.displayName) 由来のものだけを使います（ヘルスケアは読みません）。"
                )
            }
        }
    }

    private static func connectAppleHealthOnly(completion: @escaping (String) -> Void) {
        HealthKitManager.shared.requestAuthorization { success, error in
            guard success else {
                let msg: String
                if let err = error {
                    msg = "ヘルスケアの許可が必要です：\(err.localizedDescription)"
                } else {
                    msg = "ヘルスケアの「距離・ワークアウト・ワークアウト経路」の読み取りを許可してください（設定 → プライバシーとセキュリティ → ヘルスケア）。"
                }
                DispatchQueue.main.async { completion(msg) }
                return
            }

            HealthKitManager.shared.fetchRunningDistanceThisMonth(dataSource: .appleHealth) { result in
                Task { @MainActor in
                    switch result {
                    case .failure(let err):
                        completion("ヘルスケアからの読み取りに失敗しました：\(err.localizedDescription)")
                    case .success(let km):
                        RunActivityStore.shared.refreshFromRemote()
                        let distancePart: String
                        if km > 0 {
                            distancePart = "今月の距離（約\(String(format: "%.1f", km))km）をヘルスケアで確認しました。"
                        } else {
                            distancePart = "今月ヘルスケアに記録されたランはまだありません。"
                        }
                        completion(distancePart)
                    }
                }
            }
        }
    }

    private static func openCompanionAppURLs(
        for source: RunningDataSource,
        openURL: OpenURLAction,
        completion: @escaping (String) -> Void
    ) {
        let links = source.deepLinks
        guard !links.isEmpty else {
            DispatchQueue.main.async {
                completion("\(source.displayName) の起動リンクが未設定です。")
            }
            return
        }

        func tryOpen(_ index: Int) {
            if index >= links.count {
                if let appStore = source.appStoreURL {
                    openURL(appStore)
                    DispatchQueue.main.async {
                        completion("\(source.displayName): App Store を開きました。公式アプリをインストールし、デバイスとのペアリングとアカウント連携を完了してください。")
                    }
                } else {
                    DispatchQueue.main.async {
                        completion("\(source.displayName) を開けませんでした。")
                    }
                }
                return
            }
            openURL(links[index]) { accepted in
                if accepted {
                    DispatchQueue.main.async {
                        completion("\(source.displayName) の公式アプリを開きました。")
                    }
                } else {
                    tryOpen(index + 1)
                }
            }
        }
        tryOpen(0)
    }
}
