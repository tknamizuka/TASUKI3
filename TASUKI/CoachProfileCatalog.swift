//
//  CoachProfileCatalog.swift
//  TASUKI
//
//  認定コーチの公開プロフィールデータ（CoachProfileView と共有）。
//

import Foundation

enum CoachProfileCatalog {
    /// `coachProfileName`（Firestore）と一致させる表示名をキーにする。
    static func profile(for name: String) -> CoachProfile {
        switch name {
        case "廣 佳樹":
            return CoachProfile(
                name: "廣 佳樹",
                title: "Arke Running Club コーチ",
                bio: "中央学院大学時代に箱根駅伝4年連続出場（3・4年時は「花の2区」担当）。マツダ陸上競技部で実業団ランナーとして活躍後、SUBARUでコーチ・マネージャーを歴任。2025年6月設立のArke Running Clubでは、一般ランナーから中学生まで幅広く指導。「走ることの楽しさ」と「目標達成の喜び」を伝える指導を行っています。",
                rating: 5,
                reviewCount: 156,
                background: [
                    "兵庫県立西宮高校",
                    "中央学院大学 箱根駅伝4年連続出場（2区担当）",
                    "マツダ陸上競技部 実業団ランナー（2022年引退）",
                    "SUBARU陸上競技部 コーチ兼マネージャー",
                    "Arke Running Club コーチ（現職）"
                ],
                expertise: ["トレーニング計画", "ペース走指導", "フルマラソンコーチング", "ジュニア育成", "目標達成支援"],
                recentAnswers: [
                    "ラン後のストレッチはどのくらい時間をかけるべきですか？",
                    "サブ4を目指す場合、週間距離はどのくらい必要ですか？",
                    "フルマラソンに向けた練習計画について"
                ],
                imageName: "yoshiki_hiro"
            )
        default:
            return CoachProfile(
                name: name,
                title: "Arke Running Club コーチ",
                bio: "中央学院大学時代に箱根駅伝4年連続出場（3・4年時は「花の2区」担当）。マツダ陸上競技部で実業団ランナーとして活躍後、2025年6月設立のArke Running Clubでは、一般ランナーから中学生まで幅広く指導。「走ることの楽しさ」と「目標達成の喜び」を伝える指導を行っています。",
                rating: 5,
                reviewCount: 156,
                background: [
                    "兵庫県立西宮高校",
                    "中央学院大学 箱根駅伝4年連続出場（2区担当）",
                    "マツダ陸上競技部 実業団ランナー（2022年引退）",
                    "SUBARU陸上競技部 コーチ兼マネージャー",
                    "Arke Running Club コーチ（現職）"
                ],
                expertise: ["トレーニング計画", "ペース走指導", "フルマラソンコーチング", "ジュニア育成", "目標達成支援"],
                recentAnswers: [
                    "ラン後のストレッチはどのくらい時間をかけるべきですか？",
                    "サブ4を目指す場合、週間距離はどのくらい必要ですか？",
                    "フルマラソンに向けた練習計画について"
                ],
                imageName: "yoshiki_hiro"
            )
        }
    }
}

// MARK: - Coach Profile Model
struct CoachProfile {
    let name: String
    let title: String
    let bio: String
    let rating: Int
    let reviewCount: Int
    let background: [String]
    let expertise: [String]
    let recentAnswers: [String]
    let imageName: String
}
