//
//  MessageListView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - Match Request Model（マッチングリクエストの一覧表示用）
enum MatchRequestType: String {
    case partner      = "パートナー申請"
    case practice     = "練習会参加リクエスト"
}

struct MatchRequestSummary: Identifiable {
    let id: String
    let fromName: String
    let type: MatchRequestType
    let message: String
    let createdAt: Date
    let isNew: Bool
    /// パートナーマッチングの提案場所
    let proposedPlace: String?
    let proposedDateLabels: [String]?
    let counterProposedPlace: String?
    let counterProposedDateLabels: [String]?
    let storeRequestId: String?
    let isOutgoing: Bool
    let partnerStatus: PartnerMatchRequestStatus?
    /// パートナー申請で「毎週同じ曜日」での走行希望が含まれる場合 true（候補日は直近の具体例）
    let isWeeklyRecurringProposal: Bool
    /// 自分が送り返した日時候補が「毎週希望」として付いている場合 true
    let counterIsWeeklyRecurringProposal: Bool

    init(
        id: String,
        fromName: String,
        type: MatchRequestType,
        message: String,
        createdAt: Date,
        isNew: Bool,
        proposedPlace: String? = nil,
        proposedDateLabels: [String]? = nil,
        counterProposedPlace: String? = nil,
        counterProposedDateLabels: [String]? = nil,
        storeRequestId: String? = nil,
        isOutgoing: Bool = false,
        partnerStatus: PartnerMatchRequestStatus? = nil,
        isWeeklyRecurringProposal: Bool = false,
        counterIsWeeklyRecurringProposal: Bool = false
    ) {
        self.id = id
        self.fromName = fromName
        self.type = type
        self.message = message
        self.createdAt = createdAt
        self.isNew = isNew
        self.proposedPlace = proposedPlace
        self.proposedDateLabels = proposedDateLabels
        self.counterProposedPlace = counterProposedPlace
        self.counterProposedDateLabels = counterProposedDateLabels
        self.storeRequestId = storeRequestId
        self.isOutgoing = isOutgoing
        self.partnerStatus = partnerStatus
        self.isWeeklyRecurringProposal = isWeeklyRecurringProposal
        self.counterIsWeeklyRecurringProposal = counterIsWeeklyRecurringProposal
    }

    var listTitle: String {
        if isOutgoing {
            return "送信: \(fromName)"
        }
        return fromName
    }
}

// MARK: - Message Conversation Model（バックエンドで一意の conversationId を持つ。既読・未読フラグ付き）
struct MessageConversation: Identifiable {
    /// バックエンド（Firestore）で発行された一意の会話ID
    let conversationId: String
    let partnerName: String
    let avatarImage: String?
    let lastMessage: String
    let timestamp: Date
    /// 未読があるか（lastMessageAt > 自分の lastReadAt）
    let hasUnread: Bool
    /// 練習会チャットかどうか（partnerName や practiceId などで判定）
    let isPractice: Bool
    /// 最終メッセージの送信者名（練習会チャットで「誰が発信したか」を表示する用、任意）
    let lastMessageSenderName: String?
    /// 1on1 会話相手の userId（取得できない場合は nil）
    let partnerUserId: String?
    /// 練習会チャットの practiceId（通常会話では nil）
    let practiceId: String?
    
    var id: String { conversationId }
    
    init(
        conversationId: String,
        partnerName: String,
        avatarImage: String? = "person.circle.fill",
        lastMessage: String,
        timestamp: Date = Date(),
        hasUnread: Bool = false,
        isPractice: Bool = false,
        lastMessageSenderName: String? = nil,
        partnerUserId: String? = nil,
        practiceId: String? = nil
    ) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.avatarImage = avatarImage
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.hasUnread = hasUnread
        self.isPractice = isPractice
        self.lastMessageSenderName = lastMessageSenderName
        self.partnerUserId = partnerUserId
        self.practiceId = practiceId
    }
}

// MARK: - チャット / メッセージ / リクエスト タブ
enum MessageListTab: String, CaseIterable {
    case chat = "チャット"
    case message = "メッセージ"
    case request = "リクエスト"
}

// MARK: - Message List View
struct MessageListView: View {
    @State private var selectedTab: MessageListTab
    /// `MainTabView` の `NavigationStack` から `NavigationLink` で開くときは `false`（二重スタックでナビバーがずれるのを防ぐ）
    private let embedNavigationStack: Bool

    init(initialTab: MessageListTab = .chat, embedNavigationStack: Bool = true) {
        _selectedTab = State(initialValue: initialTab)
        self.embedNavigationStack = embedNavigationStack
    }
    @State private var conversations: [MessageConversation] = []
    @State private var requests: [MatchRequestSummary] = []
    @State private var isLoading = true
    @AppStorage("blockedConversationIds") private var blockedConversationIdsRaw: String = ""
    /// シングルトンを `@StateObject` で保持すると未定義動作・起動時クラッシュの原因になるため `ObservedObject` を使う
    @ObservedObject private var conversationManager = ConversationManager.shared
    @EnvironmentObject private var partnerMatchStore: PartnerMatchRequestsStore

    var body: some View {
        Group {
            if embedNavigationStack {
                NavigationStack {
                    messageListContent
                }
            } else {
                messageListContent
            }
        }
    }

    private var messageListContent: some View {
        VStack(spacing: 0) {
                // チャット / メッセージ 切り替えタブ
                Picker("", selection: $selectedTab) {
                    ForEach(MessageListTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .tint(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.tasukiDarkBackground)
                
                ZStack {
                    Color.tasukiDarkBackground
                        .ignoresSafeArea()
                    
                    if isLoading {
                        ProgressView()
                    } else {
                        let practiceChats = conversations.filter { $0.isPractice }
                        let userChats = conversations.filter { !$0.isPractice }
                        
                        switch selectedTab {
                        case .chat:
                            if userChats.isEmpty {
                                VStack {
                                    Text("メッセージがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                List {
                                    ForEach(userChats) { conversation in
                                        NavigationLink(
                                            destination: ChatView(
                                                conversationId: conversation.conversationId,
                                                partnerName: conversation.partnerName,
                                                isPractice: false,
                                                practiceId: conversation.practiceId,
                                                partnerUserId: conversation.partnerUserId
                                            )
                                        ) {
                                            conversationRowView(conversation: conversation)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        case .message:
                            if practiceChats.isEmpty {
                                VStack {
                                    Text("練習会のチャットがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                List {
                                    ForEach(practiceChats) { conversation in
                                        NavigationLink(
                                            destination: ChatView(
                                                conversationId: conversation.conversationId,
                                                partnerName: conversation.partnerName,
                                                isPractice: true,
                                                practiceId: conversation.practiceId,
                                                partnerUserId: conversation.partnerUserId
                                            )
                                        ) {
                                            conversationRowView(conversation: conversation)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        case .request:
                            if requests.isEmpty {
                                VStack {
                                    Text("リクエストがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                List {
                                    ForEach(requests) { req in
                                        NavigationLink(
                                            destination: RequestDetailView(request: req)
                                        ) {
                                            requestRowView(request: req)
                                        }
                                        .listRowBackground(Color.clear)
                                        .listRowSeparator(.hidden)
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        }
                    }
                }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(
                    selectedTab == .chat ? "チャット" :
                    selectedTab == .message ? "メッセージ" : "リクエスト"
                )
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Color.tasukiPrimary)
            }
        }
        .onAppear {
            loadConversations()
            loadRequests()
        }
        .onReceive(partnerMatchStore.$items) { _ in
            loadRequests()
        }
    }
    
    // MARK: - Conversation Row View
    private func conversationRowView(conversation: MessageConversation) -> some View {
        let iconSize: CGFloat = conversation.isPractice ? 36 : 50
        let frameSize: CGFloat = conversation.isPractice ? 44 : 56
        let isBlocked = blockedConversationIds.contains(conversation.conversationId)
        return HStack(spacing: 12) {
            // アバター画像（左）（練習会はやや小さめ）
            if let avatarImage = conversation.avatarImage {
                Image(systemName: avatarImage)
                    .font(.system(size: iconSize))
                    .foregroundColor(.black)
                    .saturation(0)
                    .frame(width: frameSize, height: frameSize)
                    .background(
                        Circle()
                            .fill(Color.tasukiDarkCardSecondary)
                    )
            } else {
                Circle()
                    .fill(Color.tasukiDarkCardSecondary)
                    .frame(width: frameSize, height: frameSize)
            }
            
            // 中央: 名前と最新メッセージ（練習会は送信者名も表示）
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if conversation.hasUnread {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 8, height: 8)
                    }
                    Text(conversation.partnerName)
                        .font(.system(size: 16, weight: conversation.hasUnread ? .bold : .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    if isBlocked {
                        Text("ブロック中")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.tasukiMutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiDarkCardSecondary)
                            )
                    }
                }
                
                if conversation.isPractice, let sender = conversation.lastMessageSenderName, !sender.isEmpty {
                    Text("\(sender): \(conversation.lastMessage)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(2)
                } else {
                    Text(conversation.lastMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.black)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右: 送信時間
            Text(formatTime(conversation.timestamp))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.black)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var blockedConversationIds: Set<String> {
        Set(
            blockedConversationIdsRaw
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
    
    // MARK: - Request Row View
    private func requestRowView(request: MatchRequestSummary) -> some View {
        HStack(spacing: 12) {
            // 左: アイコン
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.black)
                .saturation(0)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(Color.tasukiDarkCardSecondary)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if request.isNew {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 8, height: 8)
                    }
                    Text(request.listTitle)
                        .font(.system(size: 16, weight: request.isNew ? .bold : .semibold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(request.type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.tasukiBrandYellow.opacity(0.35))
                        )
                    if request.type == .partner, request.partnerStatus == .rejected {
                        Text(request.isOutgoing ? "相手が見送り" : "見送り済み")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Color.tasukiMutedText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiDarkCardSecondary)
                            )
                    }
                    if request.isWeeklyRecurringProposal {
                        Text("毎週希望")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiAccent.opacity(0.28))
                            )
                    }
                }

                if request.type == .partner, request.partnerStatus == .rejected {
                    Text(request.isOutgoing
                         ? "相手がこのマッチングリクエストを見送りました。"
                         : "あなたがこのマッチングリクエストを見送りました。")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let p = request.proposedPlace, !p.isEmpty {
                    Text("場所: \(p)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.black.opacity(0.85))
                        .lineLimit(2)
                }
                if let labels = request.proposedDateLabels, !labels.isEmpty {
                    Text("候補: " + labels.joined(separator: " / "))
                        .font(.system(size: 12))
                        .foregroundColor(.black.opacity(0.7))
                        .lineLimit(2)
                }

                Text(request.message)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .lineLimit(2)

                Text(formatTime(request.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(.black)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Helper Methods
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func loadConversations() {
        isLoading = true
        conversationManager.fetchMyConversations { result in
            switch result {
            case .success(let list):
                conversations = list
                loadRequests()
            case .failure:
                // 未ログインや取得失敗時はサンプル表示（ローカル用の仮ID）
                loadDummyConversations()
                loadRequests()
            }
        }
    }
    
    private func loadDummyConversations() {
        let calendar = Calendar.current
        let now = Date()
        conversations = [
            // 参加予定の練習会チャット（サンプル・送信者名付き）
            MessageConversation(
                conversationId: "dummy-practice-kokyo",
                partnerName: "練習会: 皇居ペース走 15km",
                avatarImage: "person.3.sequence.fill",
                lastMessage: "集合は噴水前です。5分前には集まってください！",
                timestamp: calendar.date(byAdding: .minute, value: -10, to: now) ?? now,
                hasUnread: true,
                isPractice: true,
                lastMessageSenderName: "Kenji_Run",
                practiceId: "mock-practice-1"
            ),
            MessageConversation(
                conversationId: "dummy-practice-yoyogi",
                partnerName: "練習会: 大阪城公園 LSD 120分",
                avatarImage: "person.3.sequence.fill",
                lastMessage: "ゆっくり6:30/kmペースで行きましょう。",
                timestamp: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                hasUnread: false,
                isPractice: true,
                lastMessageSenderName: "さっちゃん",
                practiceId: "mock-practice-2"
            ),
            // 個別チャット（サンプル）
            MessageConversation(
                conversationId: "dummy-tanaka",
                partnerName: "Kenji_Run",
                avatarImage: "person.circle.fill",
                lastMessage: "週末の朝が良いです。6時頃からいかがでしょうか？",
                timestamp: calendar.date(byAdding: .minute, value: -30, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-sato",
                partnerName: "さっちゃん",
                avatarImage: "person.circle.fill",
                lastMessage: "明日の練習会、参加します！",
                timestamp: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-yamada",
                partnerName: "Taka@Sub3",
                avatarImage: "person.circle.fill",
                lastMessage: "了解しました。では明日の朝6時に待ち合わせましょう。",
                timestamp: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-suzuki",
                partnerName: "Momo",
                avatarImage: "person.circle.fill",
                lastMessage: "ありがとうございます！一緒に走りましょう！",
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                hasUnread: false,
                isPractice: false
            )
        ]
        isLoading = false
    }
    
    private func loadRequests() {
        conversationManager.fetchMyMatchRequests { result in
            isLoading = false
            switch result {
            case .success(let list):
                requests = list.sorted { $0.createdAt > $1.createdAt }
            case .failure:
                requests = []
            }
        }
    }
}

// MARK: - Request Detail View（簡易版）
struct RequestDetailView: View {
    let request: MatchRequestSummary
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var partnerMatchStore: PartnerMatchRequestsStore

    @State private var showCounterSheet = false
    @State private var showRejectEntry = false
    @State private var counterPlace: String = ""
    @State private var counterDates: [Date] = [Date()]
    @State private var counterProposeWeekly = false
    @State private var counterWeekday: Int = 4
    /// 毎週希望のときの時刻（日付部分は無視し、時・分のみ使用）
    @State private var counterWeeklyTime: Date = Date()
    @State private var rejectMessage: String = ""

    private func counterWeekdayShortName(_ weekday: Int) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        guard weekday >= 1, weekday <= 7 else { return "?" }
        return symbols[weekday - 1]
    }

    /// 毎週の曜日＋時刻から、直近の具体日時を2件（今週以降の次回とその1週間後）
    private static func nextTwoWeeklyOccurrences(weekday: Int, timeFrom: Date) -> [Date]? {
        let cal = Calendar.current
        guard (1...7).contains(weekday) else { return nil }
        let hour = cal.component(.hour, from: timeFrom)
        let minute = cal.component(.minute, from: timeFrom)
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = hour
        comps.minute = minute
        guard let first = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) else { return nil }
        guard let second = cal.date(byAdding: .weekOfYear, value: 1, to: first) else { return nil }
        return [first, second]
    }

    private var isPartnerStoreRequest: Bool {
        request.type == .partner && request.storeRequestId != nil
    }

    private var canRespondIncoming: Bool {
        isPartnerStoreRequest && !request.isOutgoing && request.partnerStatus == .pending
    }

    private var effectiveConversationId: String? {
        guard let sid = request.storeRequestId else { return nil }
        return partnerMatchStore.item(id: sid)?.conversationId
    }

    var body: some View {
        VStack(spacing: 24) {
            // 送信者情報
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.black)
                    .saturation(0)
                Text(request.listTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.black)
                Text(request.type.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.tasukiBrandYellow.opacity(0.35))
                    )
                if request.isWeeklyRecurringProposal {
                    Text("毎週希望")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.tasukiAccent.opacity(0.28))
                        )
                }
            }
            .padding(.top, 32)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let p = request.proposedPlace, !p.isEmpty {
                        detailBlock(title: "場所", body: p)
                    }
                    if request.isWeeklyRecurringProposal {
                        detailBlock(
                            title: "毎週希望について",
                            body: "相手は毎週同じ曜日・時間帯での走行を希望しています。日時候補の先頭行はその要約で、続く行は直近の具体例です。OK後もチャットで調整できます。"
                        )
                    }
                    if let labels = request.proposedDateLabels, !labels.isEmpty {
                        detailBlock(title: "日時候補", body: labels.joined(separator: "\n"))
                    }
                    if let cp = request.counterProposedPlace, !cp.isEmpty {
                        detailBlock(title: "あなたが送り返した場所", body: cp)
                    }
                    if request.counterIsWeeklyRecurringProposal {
                        detailBlock(
                            title: "送り返した毎週希望について",
                            body: "あなたは送り返し画面で指定した曜日・時刻で、毎週同じリズムでの走行を提案しています。日時候補の先頭行がその要約で、続く行は直近の具体例です。"
                        )
                    }
                    if let cl = request.counterProposedDateLabels, !cl.isEmpty {
                        detailBlock(title: "あなたが送り返した日時候補", body: cl.joined(separator: "\n"))
                    }

                    detailBlock(title: "メッセージ", body: request.message.isEmpty ? "（なし）" : request.message)

                    if request.partnerStatus == .counterProposed && !request.isOutgoing {
                        Text("相手の返答を待っています")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Color.tasukiMutedText)
                    }
                    if request.partnerStatus == .rejected,
                       let sid = request.storeRequestId,
                       let item = partnerMatchStore.item(id: sid),
                       let rm = item.rejectMessage,
                       !rm.isEmpty {
                        detailBlock(title: "見送りメッセージ", body: rm)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
            }

            Spacer(minLength: 0)

            // アクションボタン
            VStack(spacing: 12) {
                if request.type == .practice {
                    NavigationLink(
                        destination: ChatView(conversationId: "request-\(request.id)", partnerName: request.fromName)
                    ) {
                        Text("承認してチャットを開始")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(30)
                    }

                    Button(action: { dismiss() }) {
                        Text("今回は見送る")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                } else if isPartnerStoreRequest, request.partnerStatus == .accepted,
                          let cid = effectiveConversationId {
                    NavigationLink(
                        destination: ChatView(conversationId: cid, partnerName: request.fromName)
                    ) {
                        Text("メッセージを開く")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(30)
                    }
                } else if canRespondIncoming {
                    Button {
                        if let sid = request.storeRequestId {
                            partnerMatchStore.acceptIncoming(id: sid)
                        }
                    } label: {
                        Text("OK（メッセージのやり取りを始める）")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(30)
                    }

                    Button { showCounterSheet = true } label: {
                        Text("日時・場所を指定して送り返す")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiDarkCardSecondary)
                            .cornerRadius(30)
                    }

                    Button { showRejectEntry = true } label: {
                        Text("マッチングを見送る（メッセージ付き）")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.black.opacity(0.75))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                } else if isPartnerStoreRequest, request.isOutgoing, request.partnerStatus == .pending {
                    Text("相手の返答を待っています")
                        .font(.subheadline)
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(maxWidth: .infinity)
                }

                Button(action: { dismiss() }) {
                    Text("閉じる")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.tasukiDarkBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("リクエスト詳細")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .onAppear {
            tabBarVisibility.pushHiddenContext()
        }
        .onDisappear {
            tabBarVisibility.popHiddenContext()
        }
        .onChange(of: showCounterSheet) { _, isPresented in
            if isPresented {
                counterProposeWeekly = false
                let cal = Calendar.current
                let base = counterDates.first ?? Date()
                counterWeekday = cal.component(.weekday, from: base)
                counterWeeklyTime = cal.date(
                    bySettingHour: cal.component(.hour, from: base),
                    minute: cal.component(.minute, from: base),
                    second: 0,
                    of: Date()
                ) ?? Date()
            }
        }
        .sheet(isPresented: $showCounterSheet) {
            NavigationStack {
                Form {
                    Section("送り返す場所") {
                        TextField("場所", text: $counterPlace)
                    }
                    Section("送り返す日時候補") {
                        Toggle("毎週の希望として送る", isOn: $counterProposeWeekly)
                            .onChange(of: counterProposeWeekly) { _, on in
                                guard on, let d = counterDates.first else { return }
                                let cal = Calendar.current
                                counterWeekday = cal.component(.weekday, from: d)
                                counterWeeklyTime = cal.date(
                                    bySettingHour: cal.component(.hour, from: d),
                                    minute: cal.component(.minute, from: d),
                                    second: 0,
                                    of: Date()
                                ) ?? counterWeeklyTime
                            }
                        if counterProposeWeekly {
                            Picker("毎週の曜日", selection: $counterWeekday) {
                                ForEach(1...7, id: \.self) { w in
                                    Text("毎週\(counterWeekdayShortName(w))").tag(w)
                                }
                            }
                            DatePicker("希望の時刻", selection: $counterWeeklyTime, displayedComponents: .hourAndMinute)
                                .environment(\.locale, Locale(identifier: "ja_JP"))
                            Text("この曜日と時刻から、次回分と1週間後の2件を「直近の例」として付けて送信します。")
                                .font(.caption)
                                .foregroundColor(Color.tasukiMutedText)
                        } else {
                            ForEach(counterDates.indices, id: \.self) { i in
                                DatePicker("候補 \(i + 1)", selection: $counterDates[i], displayedComponents: [.date, .hourAndMinute])
                            }
                            if counterDates.count < 5 {
                                Button("候補を追加") {
                                    counterDates.append(Date())
                                }
                            }
                        }
                    }
                }
                .navigationTitle("日時・場所を送り返す")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") { showCounterSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送信") {
                            guard let sid = request.storeRequestId else { return }
                            let place = counterPlace.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !place.isEmpty else { return }
                            let datesToSend: [Date] = {
                                if counterProposeWeekly {
                                    return Self.nextTwoWeeklyOccurrences(weekday: counterWeekday, timeFrom: counterWeeklyTime) ?? counterDates
                                }
                                return counterDates
                            }()
                            guard !datesToSend.isEmpty else { return }
                            partnerMatchStore.sendCounterIncoming(
                                id: sid,
                                place: place,
                                dates: datesToSend,
                                counterWeeklyPreferred: counterProposeWeekly,
                                counterWeekday: counterProposeWeekly ? counterWeekday : nil
                            )
                            showCounterSheet = false
                            dismiss()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showRejectEntry) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("相手に通知されます（短い文で構いません）。")
                        .font(.subheadline)
                        .foregroundColor(Color.tasukiMutedText)
                    TextField("メッセージ", text: $rejectMessage, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                    Spacer()
                }
                .padding(20)
                .navigationTitle("マッチングを見送る")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("キャンセル") {
                            rejectMessage = ""
                            showRejectEntry = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("送信") {
                            guard let sid = request.storeRequestId else { return }
                            partnerMatchStore.rejectIncoming(id: sid, message: rejectMessage)
                            rejectMessage = ""
                            showRejectEntry = false
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundColor(.black)
            Text(body)
                .font(.body)
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        MessageListView(embedNavigationStack: false)
            .environmentObject(TabBarVisibility())
            .environmentObject(PartnerMatchRequestsStore.shared)
            .environmentObject(JoinedPracticesStore())
            .environmentObject(MatchPromisesStore())
            .environmentObject(PracticeRecruitmentsStore.shared)
    }
}
