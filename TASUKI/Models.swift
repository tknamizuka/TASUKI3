import SwiftUI
import CoreLocation

// MARK: - Enums
enum RaceCategory: String, CaseIterable, Identifiable {
    case threeKm = "3km"
    case fiveKm = "5km"
    case tenKm = "10km"
    case half = "Half"
    case full = "Full"
    
    var id: String { rawValue }
}

enum ConnectionStyle: String, CaseIterable {
    case real = "リアル"
    case virtual = "バーチャル"
    case both = "どちらでも"
}

enum RunningSchedule: String, CaseIterable {
    case weekdayMorning = "平日朝"
    case weekdayEvening = "平日夜"
    case weekendMorning = "土日午前"
    case weekendAfternoon = "土日下午"
    case flexible = "柔軟に対応"
}

enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
    
    var icon: String {
        switch self {
        case .male: return "♂"
        case .female: return "♀"
        case .other: return "⚧"
        }
    }
}

enum Condition: String, CaseIterable {
    case excellent = "絶好調"
    case good = "良好"
    case tired = "疲れ気味"
    case sos = "SOS"
    
    var colorHex: String {
        switch self {
        case .excellent: return "00C853"  // 緑
        case .good: return "5D2D91"       // ブランド紫（旧ブルー）
        case .tired: return "FF9500"      // オレンジ
        case .sos: return "FF453A"        // 赤
        }
    }
    
    var icon: String {
        switch self {
        case .excellent: return "flame.fill"
        case .good: return "checkmark.circle.fill"
        case .tired: return "moon.fill"
        case .sos: return "exclamationmark.triangle.fill"
        }
    }
}

enum ConnectionStatus {
    case none        // 何もしていない（初対面）
    case requested   // 自分からリクエスト済み（承認待ち）
    case received    // 相手からリクエストが来ている
    case matched     // マッチング成立（チャット可能）
}

// MARK: - User Model (リッチプロフィール対応版)
struct User: Identifiable, Codable {
    let id: UUID
    let name: String
    let profileImage: String // アセット名
    var profileImageUrl: String? // Firebase StorageのURL
    let bio: String
    
    // ▼ 基本ステータス
    var rank: String          // 例: "Rank S"
    var age: Int              // 例: 29
    var gender: String        // 例: "男性"
    var purpose: String       // 例: "サブ3", "健康維持"
    var prefecture: String    // 例: "東京都"
    var area: String          // 活動エリア（例: "皇居周辺"）
    
    // ▼ ランニングデータ
    var pace: String          // 例: "4:15 /km"
    var runningFrequency: String // 例: "週4回"
    var personalBest: String  // 例: "Full 2:58:00"
    var schedule: String      // 例: "土日午前, 水曜夜"
    
    // ▼ 目標・レース
    var nextRace: String      // 例: "東京マラソン 2026"
    var targetTime: String    // 例: "Sub 2:50"
    
    // ▼ 進捗データ
    var monthlyDistance: Double // 今月の走行距離 (km)
    var monthlyTarget: Double   // 月間目標 (km)
    var avgPace: String         // 平均ペース
    
    // ▼ TASUKIポイント
    var totalPoints: Int        // 累計ポイント
    var monthlyPoints: Int      // 月間ポイント
    
    // ▼ マッチング・位置情報
    var matchRate: Int        // マッチ度 (0-100)
    var lastLogin: Date       // 最終ログイン
    var spotName: String      // 表示用の活動スポット名
    var latitude: Double
    var longitude: Double
    var distanceFromUserMock: Double
    
    // 計算プロパティ: オンライン判定 (24時間以内)
    var isOnline: Bool {
        return Date().timeIntervalSince(lastLogin) < 24 * 60 * 60
    }
    
    // 計算プロパティ: 距離計算 (現在地からの距離 km)
    func distanceFrom(latitude: Double, longitude: Double) -> Double {
        let spotLocation = CLLocation(latitude: self.latitude, longitude: self.longitude)
        let currentLocation = CLLocation(latitude: latitude, longitude: longitude)
        return spotLocation.distance(from: currentLocation) / 1000.0
    }
}

// MARK: - Practice Category
enum PracticeCategory: String, CaseIterable, Identifiable, Codable {
    case interval = "インターバル"
    case distance = "距離走"
    case jog = "JOG"
    case chat = "おしゃべりラン"
    case variation = "変化走"
    case pace = "ペース走"
    case other = "その他"
    
    var id: String { rawValue }
    
    // UI用カラー
    var colorHex: String {
        switch self {
        case .interval: return "FF2D55"   // ピンク系
        case .distance: return "FF9500"   // オレンジ
        case .jog:      return "34C759"   // グリーン
        case .chat:     return "AF52DE"   // パープル
        case .variation:return "2A0F45"   // ディープパープル
        case .pace:     return "5D2D91"   // アクセント紫
        case .other:    return "8E8E93"   // グレー
        }
    }
}

// MARK: - Practice Model
struct Practice: Identifiable {
    /// 練習会の一意ID（募集作成時に発行。日時・場所データもこのIDに紐づく）
    let practiceId: String
    var id: String { practiceId }
    /// この練習会に紐づくチャットの会話ID（作成時に発行。参加者が MessageListView で参加可能）
    let chatId: String?
    let title: String
    let location: String      // 場所 (例: "皇居")
    let date: Date            // 開催日時
    let category: PracticeCategory
    let pace: String          // 設定ペース (例: "5:00 /km")
    let distance: String      // 距離・時間 (例: "20km", "90分")
    let description: String
    let organizer: User
    
    var maxParticipants: Int  // 定員
    /// practiceID に紐づく参加ユーザーID一覧（例: Firebase UID）
    var participantUserIds: [String]
    var currentParticipants: Int { participantUserIds.count }
    var isJoined: Bool = false
    
    // フィルタリング用のヘルパー
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E" // 月, 火, 水...
        return formatter.string(from: date)
    }
    
    var startTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Legacy Models (エラー回避用)
struct PartnerUser: Identifiable {
    let id = UUID()
    let name: String
    let rank: String
    let avatarImage: String?
    let isOnline: Bool
    let bestCategory: RaceCategory
    let bestTime: String
    let age: Int
    let runningSchedule: RunningSchedule
    let purpose: String
    let nextRace: String?
    let targetTime: String?
    let runningSpots: [String]
    let prefecture: String
    let gender: Gender
    let condition: Condition
    let statusMessage: String
    let ageGroup: String
    let runningGoal: String
    let personalBest: String?
    let activeTime: String
    let easyPace: String
    let connectionStyle: ConnectionStyle
    /// TASUKI累計ポイント（バッジ表示用、未指定時0）
    var totalPoints: Int = 0
    
    // 互換性のためのプロパティ
    var location: String { prefecture }
    var job: String { "" }
    var image: String { avatarImage ?? "" }
    var tags: [String] { runningSpots }
    var bio: String { statusMessage }
    
    // User型への変換
    func toUser() -> User {
        User(
            id: self.id,
            name: self.name,
            profileImage: self.avatarImage ?? "runner",
            profileImageUrl: nil,
            bio: self.statusMessage,
            rank: self.rank,
            age: self.age,
            gender: self.gender.displayName,
            purpose: self.purpose,
            prefecture: self.prefecture,
            area: self.prefecture,
            pace: self.easyPace,
            runningFrequency: "",
            personalBest: self.personalBest ?? "",
            schedule: self.runningSchedule.rawValue,
            nextRace: self.nextRace ?? "",
            targetTime: self.targetTime ?? "",
            monthlyDistance: 0.0,
            monthlyTarget: 0.0,
            avgPace: self.easyPace,
            totalPoints: self.totalPoints,
            monthlyPoints: 0,
            matchRate: 0,
            lastLogin: Date(),
            spotName: self.prefecture,
            latitude: 0.0,
            longitude: 0.0,
            distanceFromUserMock: 0.0
        )
    }
}

struct QAItem: Identifiable, Codable, Equatable {
    let id: UUID
    let question: String
    let answer: String?        // コーチの回答（まだの場合はnil）
    let askerName: String      // 質問者名
    let coachName: String?     // コーチ名（回答がある場合の名前）
    let category: String       // カテゴリ（トレーニング / ケア など）
    let postedDate: Date       // 投稿日時

    init(
        id: UUID = UUID(),
        question: String,
        answer: String?,
        askerName: String,
        coachName: String?,
        category: String,
        postedDate: Date
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.askerName = askerName
        self.coachName = coachName
        self.category = category
        self.postedDate = postedDate
    }

    func withAnswer(_ answer: String, coachName: String) -> QAItem {
        QAItem(
            id: id,
            question: question,
            answer: answer,
            askerName: askerName,
            coachName: coachName,
            category: category,
            postedDate: postedDate
        )
    }
}

/// CoachView 用サンプル（旧 mockQAItems と同一の質問・回答）。質問者は `myName` デフォルト「Hiro」、回答者は「廣 佳樹」（CoachProfileView と一致）
let coachPersonalSampleQAItems: [QAItem] = [
    QAItem(
        question: "ラン後のストレッチはどのくらい時間をかけるべきですか？",
        answer: "目安として10〜15分程度をおすすめします。特にハムストリングスとふくらはぎを重点的に伸ばしましょう。",
        askerName: "Hiro",
        coachName: "廣 佳樹",
        category: "ケア",
        postedDate: Date().addingTimeInterval(-86400)
    ),
    QAItem(
        question: "サブ4を目指す場合、週間距離はどのくらい必要ですか？",
        answer: "一般的には週40〜50km程度が一つの目安になりますが、現在の走力や疲労度に合わせて調整してください。",
        askerName: "Hiro",
        coachName: "廣 佳樹",
        category: "トレーニング",
        postedDate: Date().addingTimeInterval(-86400 * 3)
    )
]

struct PracticeRecruitment: Identifiable {
    /// 募集の一意ID（新規作成時に発行。練習の日時・場所データもこのIDに紐づく）
    let practiceId: String
    var id: String { practiceId }
    /// この練習会に紐づくチャットの会話ID（新規作成時に発行）
    let chatId: String?
    let host: PartnerUser
    let title: String
    let location: String
    let date: Date
    let category: PracticeCategory
    let pace: String
    let distance: String
    let description: String
    let applicants: [PartnerUser]
    /// practiceID に紐づく参加ユーザーID一覧（例: Firebase UID）
    var participantUserIds: [String]
    let maxParticipants: Int
    /// 毎週繰り返しなら true
    var isRecurring: Bool = false
    /// 毎週のときの曜日（Calendar.weekday: 1=日, 2=月, ... 7=土）
    var recurringWeekday: Int? = nil
    
    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]
    
    var dayOfWeek: String {
        if isRecurring, let w = recurringWeekday, (1...7).contains(w) {
            return "毎週\(Self.weekdaySymbols[w - 1])"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }
    
    var startTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "H:mm"
        return formatter.string(from: date)
    }
    
    /// 検索用: 指定日付に「開催される」か（一度きりは同日、毎週は曜日一致）
    func matches(filterDate: Date) -> Bool {
        let cal = Calendar.current
        if isRecurring, let w = recurringWeekday {
            return cal.component(.weekday, from: filterDate) == w
        }
        return cal.isDate(date, inSameDayAs: filterDate)
    }
    
    // Practiceへの変換（詳細画面用）
    func toPractice() -> Practice {
        let displayDate: Date
        if isRecurring, let w = recurringWeekday {
            let cal = Calendar.current
            let comps = DateComponents(
                hour: cal.component(.hour, from: date),
                minute: cal.component(.minute, from: date),
                weekday: w
            )
            displayDate = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) ?? date
        } else {
            displayDate = date
        }
        return Practice(
            practiceId: self.practiceId,
            chatId: self.chatId,
            title: self.title,
            location: self.location,
            date: displayDate,
            category: self.category,
            pace: self.pace,
            distance: self.distance,
            description: self.description,
            organizer: self.host.toUser(),
            maxParticipants: self.maxParticipants,
            participantUserIds: self.participantUserIds,
            isJoined: false
        )
    }
}

// MARK: - Mock Data
let mockUser = User(
    id: UUID(),
    name: "Hiro",
    profileImage: "runner",
    profileImageUrl: nil,
    bio: "ランニングは人生の一部です。一緒に高め合える仲間を探しています。",
    rank: "Rank A",
    age: 29,
    gender: "男性",
    purpose: "サブ3達成",
    prefecture: "東京都",
    area: "皇居",
    pace: "4:30 /km",
    runningFrequency: "週3-4回",
    personalBest: "Full 3:05:00",
    schedule: "平日夜, 土日朝",
    nextRace: "大阪マラソン",
    targetTime: "Sub 3",
    monthlyDistance: 120.0,
    monthlyTarget: 200.0,
    avgPace: "4:45 /km",
    totalPoints: 12500,
    monthlyPoints: 1800,
    matchRate: 100,
    lastLogin: Date(),
    spotName: "皇居",
    latitude: 35.68,
    longitude: 139.75,
    distanceFromUserMock: 0
)

let mockUsers: [User] = [
    User(
        id: UUID(),
        name: "Yuki",
        profileImage: "runner",
        profileImageUrl: nil,
        bio: "朝活メインで走ってます！楽しく走れる方募集。",
        rank: "Rank B",
        age: 26,
        gender: "女性",
        purpose: "健康維持",
        prefecture: "東京都",
        area: "代々木公園",
        pace: "6:00 /km",
        runningFrequency: "週2回",
        personalBest: "Half 1:50:00",
        schedule: "土日祝の午前",
        nextRace: "渋谷・表参道Women's Run",
        targetTime: "完走",
        monthlyDistance: 60.0,
        monthlyTarget: 100.0,
        avgPace: "6:15 /km",
        totalPoints: 3200,
        monthlyPoints: 400,
        matchRate: 98,
        lastLogin: Date(),
        spotName: "代々木公園",
        latitude: 35.67,
        longitude: 139.70,
        distanceFromUserMock: 2.5
    ),
    User(
        id: UUID(),
        name: "Kenta",
        profileImage: "runner",
        profileImageUrl: nil,
        bio: "ガチ勢です。インターバル練習一緒にやりましょう。",
        rank: "Rank S",
        age: 32,
        gender: "男性",
        purpose: "福岡国際出場",
        prefecture: "東京都",
        area: "駒沢公園",
        pace: "3:45 /km",
        runningFrequency: "週6回",
        personalBest: "Full 2:28:00",
        schedule: "平日早朝, 土日",
        nextRace: "東京マラソン",
        targetTime: "2:25:00",
        monthlyDistance: 350.0,
        monthlyTarget: 400.0,
        avgPace: "3:55 /km",
        totalPoints: 42000,
        monthlyPoints: 5200,
        matchRate: 85,
        lastLogin: Date().addingTimeInterval(-86400),
        spotName: "駒沢公園",
        latitude: 35.62,
        longitude: 139.66,
        distanceFromUserMock: 8.0
    )
]

let mockPractices = [
    Practice(
        practiceId: "mock-practice-0",
        chatId: nil,
        title: "皇居ラン",
        location: "皇居",
        date: Date(),
        category: .pace,
        pace: "5:00/km",
        distance: "15km",
        description: "調整ラン",
        organizer: mockUser,
        maxParticipants: 10,
        participantUserIds: ["mock-user-1", "mock-user-2"],
        isJoined: false
    )
]

let mockPartnerUsers: [PartnerUser] = []

let mockRecruitments: [PracticeRecruitment] = [
    PracticeRecruitment(
        practiceId: "mock-practice-1",
        chatId: nil,
        host: PartnerUser(
            name: "Kenji_Run",
            rank: "S",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .full,
            bestTime: "2:55:00",
            age: 29,
            runningSchedule: .weekdayEvening,
            purpose: "サブ3目標",
            nextRace: "東京マラソン",
            targetTime: "2:50:00",
            runningSpots: ["皇居"],
            prefecture: "東京都",
            gender: .male,
            condition: .excellent,
            statusMessage: "平日夜に皇居で走っています！",
            ageGroup: "20s",
            runningGoal: "サブ3",
            personalBest: "2:55:00",
            activeTime: "Night",
            easyPace: "4:30/km",
            connectionStyle: .real
        ),
        title: "皇居ペース走 15km",
        location: "皇居",
        date: Date().addingTimeInterval(60 * 60 * 24 * 2), // 2日後
        category: .pace,
        pace: "4:30/km",
        distance: "15km",
        description: "サブ3〜3.5目標の方向けのペース走です。途中離脱OK、一緒にビルドアップしましょう。",
        applicants: [],
        participantUserIds: [],
        maxParticipants: 10,
        isRecurring: false,
        recurringWeekday: nil
    ),
    PracticeRecruitment(
        practiceId: "mock-practice-2",
        chatId: nil,
        host: PartnerUser(
            name: "Yuki",
            rank: "A",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .half,
            bestTime: "1:35:00",
            age: 27,
            runningSchedule: .weekendMorning,
            purpose: "健康維持",
            nextRace: "横浜マラソン",
            targetTime: "3:45:00",
            runningSpots: ["大阪城公園"],
            prefecture: "大阪府",
            gender: .female,
            condition: .good,
            statusMessage: "週末にゆっくり長く走るのが好きです。",
            ageGroup: "20s",
            runningGoal: "完走",
            personalBest: "3:45:00",
            activeTime: "Morning",
            easyPace: "6:00/km",
            connectionStyle: .both
        ),
        title: "大阪城公園 LSD 120分",
        location: "大阪城公園",
        date: Date().addingTimeInterval(60 * 60 * 24 * 3), // 3日後
        category: .distance,
        pace: "6:30/km",
        distance: "120分",
        description: "フルマラソンに向けた脚づくり用のLSDです。会話できるペースでゆっくり走ります。",
        applicants: [],
        participantUserIds: [],
        maxParticipants: 8,
        isRecurring: false,
        recurringWeekday: nil
    ),
    PracticeRecruitment(
        practiceId: "mock-practice-3",
        chatId: nil,
        host: PartnerUser(
            name: "Momo",
            rank: "B",
            avatarImage: "person.circle.fill",
            isOnline: false,
            bestCategory: .tenKm,
            bestTime: "40:00",
            age: 31,
            runningSchedule: .flexible,
            purpose: "おしゃべりラン",
            nextRace: nil,
            targetTime: nil,
            runningSpots: ["代々木公園"],
            prefecture: "東京都",
            gender: .female,
            condition: .good,
            statusMessage: "楽しく走れる仲間募集中です！",
            ageGroup: "30s",
            runningGoal: "ファンラン",
            personalBest: "3:30:00",
            activeTime: "Evening",
            easyPace: "6:30/km",
            connectionStyle: .both
        ),
        title: "代々木公園 おしゃべりラン 5km",
        location: "代々木公園",
        date: Date().addingTimeInterval(60 * 60 * 24 * 5), // 5日後
        category: .chat,
        pace: "7:00/km",
        distance: "5km",
        description: "走るペースはゆっくり、会話メインのおしゃべりランです。ラン後にカフェで一息つきましょう。",
        applicants: [],
        participantUserIds: [],
        maxParticipants: 6,
        isRecurring: false,
        recurringWeekday: nil
    ),
    PracticeRecruitment(
        practiceId: "mock-practice-4",
        chatId: nil,
        host: PartnerUser(
            name: "Takeshi",
            rank: "A",
            avatarImage: "person.circle.fill",
            isOnline: true,
            bestCategory: .half,
            bestTime: "1:28:00",
            age: 30,
            runningSchedule: .weekdayMorning,
            purpose: "サブ3目標",
            nextRace: "東京マラソン",
            targetTime: "2:55:00",
            runningSpots: ["皇居"],
            prefecture: "東京都",
            gender: .male,
            condition: .excellent,
            statusMessage: "毎週水曜朝の皇居ラン！",
            ageGroup: "30s",
            runningGoal: "サブ3",
            personalBest: "2:58:00",
            activeTime: "Morning",
            easyPace: "4:45/km",
            connectionStyle: .real
        ),
        title: "毎週水曜 皇居 朝ラン 10km",
        location: "皇居",
        date: {
            let cal = Calendar.current
            var c = DateComponents()
            c.weekday = 4
            c.hour = 7
            c.minute = 0
            return cal.nextDate(after: Date(), matching: c, matchingPolicy: .nextTime) ?? Date()
        }(),
        category: .pace,
        pace: "5:00/km",
        distance: "10km",
        description: "毎週水曜朝7時から。皇居1周約5kmを2周。仕事前にさっと走りましょう。",
        applicants: [],
        participantUserIds: [],
        maxParticipants: 12,
        isRecurring: true,
        recurringWeekday: 4
    )
]

// MARK: - Missing Definitions for Compatibility

struct TeamMessage: Identifiable {
    let id: UUID
    let user: PartnerUser
    let content: String
    let timestamp: Date
    let isSystem: Bool
    
    init(id: UUID = UUID(), user: PartnerUser, content: String, timestamp: Date, isSystem: Bool) {
        self.id = id
        self.user = user
        self.content = content
        self.timestamp = timestamp
        self.isSystem = isSystem
    }
    
    // 互換性のためのプロパティ
    var sender: User {
        // PartnerUserからUserに変換（簡易版）
        User(
            id: user.id,
            name: user.name,
            profileImage: user.avatarImage ?? "runner",
            profileImageUrl: nil,
            bio: user.statusMessage,
            rank: user.rank,
            age: user.age,
            gender: user.gender.displayName,
            purpose: user.purpose,
            prefecture: user.prefecture,
            area: user.prefecture,
            pace: user.easyPace,
            runningFrequency: "",
            personalBest: user.personalBest ?? "",
            schedule: user.runningSchedule.rawValue,
            nextRace: user.nextRace ?? "",
            targetTime: user.targetTime ?? "",
            monthlyDistance: 0.0,
            monthlyTarget: 0.0,
            avgPace: user.easyPace,
            totalPoints: 0,
            monthlyPoints: 0,
            matchRate: 0,
            lastLogin: Date(),
            spotName: user.prefecture,
            latitude: 0.0,
            longitude: 0.0,
            distanceFromUserMock: 0.0
        )
    }
    
    var text: String { content }
}

// 都道府県データの簡易定義（海外を含む）
let allPrefectures = [
    "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県", "滋賀県", "京都府", "大阪府", "兵庫県",
    "奈良県", "和歌山県", "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県", "福岡県", "佐賀県", "長崎県",
    "熊本県", "大分県", "宮崎県", "鹿児島県", "沖縄県",
    "海外"
]

// 年齢グループ
let ageGroups = ["10s", "20s", "30s", "40s", "50s", "60s+"]

// 目的
let purposes = ["サブ3", "サブ3.5", "サブ4", "サブ5", "健康維持", "ダイエット", "完走", "自己ベスト更新"]

// スケジュール
let schedules = ["平日朝", "平日夜", "土日午前", "土日下午", "柔軟に対応"]

let mockTeamMessages: [TeamMessage] = [
    TeamMessage(
        user: PartnerUser(
            name: mockUser.name,
            rank: mockUser.rank,
            avatarImage: mockUser.profileImage,
            isOnline: mockUser.isOnline,
            bestCategory: .full,
            bestTime: mockUser.personalBest,
            age: mockUser.age,
            runningSchedule: .weekendMorning,
            purpose: mockUser.purpose,
            nextRace: mockUser.nextRace,
            targetTime: mockUser.targetTime,
            runningSpots: [mockUser.spotName],
            prefecture: mockUser.spotName,
            gender: .male,
            condition: .good,
            statusMessage: mockUser.bio,
            ageGroup: "\(mockUser.age / 10 * 10)s",
            runningGoal: mockUser.purpose,
            personalBest: mockUser.personalBest,
            activeTime: "Morning",
            easyPace: mockUser.avgPace,
            connectionStyle: .real
        ),
        content: "今週末の練習、参加します！",
        timestamp: Date().addingTimeInterval(-3600),
        isSystem: false
    ),
    TeamMessage(
        user: PartnerUser(
            name: mockUsers[0].name,
            rank: mockUsers[0].rank,
            avatarImage: mockUsers[0].profileImage,
            isOnline: mockUsers[0].isOnline,
            bestCategory: .half,
            bestTime: mockUsers[0].personalBest,
            age: mockUsers[0].age,
            runningSchedule: .weekendMorning,
            purpose: mockUsers[0].purpose,
            nextRace: mockUsers[0].nextRace,
            targetTime: mockUsers[0].targetTime,
            runningSpots: [mockUsers[0].spotName],
            prefecture: mockUsers[0].spotName,
            gender: .female,
            condition: .good,
            statusMessage: mockUsers[0].bio,
            ageGroup: "\(mockUsers[0].age / 10 * 10)s",
            runningGoal: mockUsers[0].purpose,
            personalBest: mockUsers[0].personalBest,
            activeTime: "Morning",
            easyPace: mockUsers[0].avgPace,
            connectionStyle: .real
        ),
        content: "了解です！よろしくお願いします。",
        timestamp: Date().addingTimeInterval(-1800),
        isSystem: false
    )
]
