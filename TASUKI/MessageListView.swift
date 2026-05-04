//
//  MessageListView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - Match Request Model（マッチングリクエストの一覧表示用・ユーザー同士の申請のみ。練習会招待は含めない）
enum MatchRequestType: String, Codable {
    case partner = "パートナー申請"
}

struct MatchRequestSummary: Identifiable, Codable {
    let id: String
    let fromName: String
    let type: MatchRequestType
    let message: String
    let createdAt: Date
    let isNew: Bool
    /// 提案された集合日時（単発または「次回」の基準日時）
    var proposedStart: Date?
    var location: String?
    var isWeeklyRecurring: Bool
    var recurrenceWeekday: Int?
    
    init(
        id: String,
        fromName: String,
        type: MatchRequestType,
        message: String,
        createdAt: Date,
        isNew: Bool,
        proposedStart: Date? = nil,
        location: String? = nil,
        isWeeklyRecurring: Bool = false,
        recurrenceWeekday: Int? = nil
    ) {
        self.id = id
        self.fromName = fromName
        self.type = type
        self.message = message
        self.createdAt = createdAt
        self.isNew = isNew
        self.proposedStart = proposedStart
        self.location = location
        self.isWeeklyRecurring = isWeeklyRecurring
        self.recurrenceWeekday = recurrenceWeekday
    }
}

extension MatchRequestSummary {
    /// 一覧・詳細用の一行（日時・毎週・場所）
    var scheduleSubtitle: String? {
        guard let start = proposedStart else { return nil }
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        if isWeeklyRecurring, recurrenceWeekday != nil {
            let wd = recurrenceWeekday ?? cal.component(.weekday, from: start)
            let idx = (wd + 6) % 7
            let symbols = cal.shortWeekdaySymbols
            let dayName = idx < symbols.count ? symbols[idx] : ""
            df.dateFormat = "HH:mm"
            let time = df.string(from: start)
            let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let locPart = loc.isEmpty ? "" : " · \(loc)"
            return "毎週\(dayName) \(time)\(locPart)"
        }
        df.dateStyle = .medium
        df.timeStyle = .short
        var line = df.string(from: start)
        if let loc = location?.trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            line += " · \(loc)"
        }
        return line
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
    
    var id: String { conversationId }
    
    init(
        conversationId: String,
        partnerName: String,
        avatarImage: String? = "person.circle.fill",
        lastMessage: String,
        timestamp: Date = Date(),
        hasUnread: Bool = false,
        isPractice: Bool = false,
        lastMessageSenderName: String? = nil
    ) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.avatarImage = avatarImage
        self.lastMessage = lastMessage
        self.timestamp = timestamp
        self.hasUnread = hasUnread
        self.isPractice = isPractice
        self.lastMessageSenderName = lastMessageSenderName
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
    @State private var selectedTab: MessageListTab = .chat
    @State private var conversations: [MessageConversation] = []
    @State private var isLoading = true
    /// シングルトンを `@StateObject` で保持すると未定義動作・起動時クラッシュの原因になるため `ObservedObject` を使う
    @ObservedObject private var conversationManager = ConversationManager.shared
    @ObservedObject private var matchInvitationStore = MatchInvitationStore.shared
    
    var body: some View {
        NavigationStack {
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
                        let practiceChats = conversations
                            .filter { $0.isPractice }
                            .sorted { $0.timestamp < $1.timestamp }
                        let userChats = conversations
                            .filter { !$0.isPractice }
                            .sorted { $0.timestamp < $1.timestamp }
                        let sortedRequests = matchInvitationStore.inbox
                            .sorted { $0.createdAt > $1.createdAt }
                        
                        switch selectedTab {
                        case .chat:
                            if practiceChats.isEmpty {
                                VStack {
                                    Text("練習会のチャットがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                ScrollViewReader { proxy in
                                    List {
                                        ForEach(practiceChats) { conversation in
                                            NavigationLink(
                                                destination: ChatView(
                                                    conversationId: conversation.conversationId,
                                                    partnerName: conversation.partnerName,
                                                    isPractice: true
                                                )
                                            ) {
                                                conversationRowView(conversation: conversation)
                                            }
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                        }
                                        Color.clear
                                            .frame(height: 1)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .id("practice-bottom-anchor")
                                    }
                                    .listStyle(.plain)
                                    .scrollContentBackground(.hidden)
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("practice-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                    .onChange(of: practiceChats.map(\.id)) { _ in
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("practice-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        case .message:
                            if userChats.isEmpty {
                                VStack {
                                    Text("メッセージがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                ScrollViewReader { proxy in
                                    List {
                                        ForEach(userChats) { conversation in
                                            NavigationLink(
                                                destination: ChatView(
                                                    conversationId: conversation.conversationId,
                                                    partnerName: conversation.partnerName
                                                )
                                            ) {
                                                conversationRowView(conversation: conversation)
                                            }
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                        }
                                        Color.clear
                                            .frame(height: 1)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .id("message-bottom-anchor")
                                    }
                                    .listStyle(.plain)
                                    .scrollContentBackground(.hidden)
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("message-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                    .onChange(of: userChats.map(\.id)) { _ in
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("message-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        case .request:
                            if sortedRequests.isEmpty {
                                VStack {
                                    Text("リクエストがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(.black)
                                }
                            } else {
                                ScrollViewReader { proxy in
                                    List {
                                        ForEach(sortedRequests) { req in
                                            NavigationLink(
                                                destination: RequestDetailView(request: req)
                                            ) {
                                                requestRowView(request: req)
                                            }
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                        }
                                        Color.clear
                                            .frame(height: 1)
                                            .listRowBackground(Color.clear)
                                            .listRowSeparator(.hidden)
                                            .id("request-bottom-anchor")
                                    }
                                    .listStyle(.plain)
                                    .scrollContentBackground(.hidden)
                                    .onAppear {
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("request-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                    .onChange(of: sortedRequests.map(\.id)) { _ in
                                        DispatchQueue.main.async {
                                            proxy.scrollTo("request-bottom-anchor", anchor: .bottom)
                                        }
                                    }
                                }
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
            }
        }
    }
    
    // MARK: - Conversation Row View
    private func conversationRowView(conversation: MessageConversation) -> some View {
        let iconSize: CGFloat = conversation.isPractice ? 36 : 50
        let frameSize: CGFloat = conversation.isPractice ? 44 : 56
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
                    Text(request.fromName)
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
                }
                
                Text(request.message)
                    .font(.system(size: 14))
                    .foregroundColor(.black)
                    .lineLimit(2)
                
                if let sched = request.scheduleSubtitle {
                    Text(sched)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.85))
                        .lineLimit(2)
                }
                
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
                isLoading = false
            case .failure:
                // 未ログインや取得失敗時はサンプル表示（ローカル用の仮ID）
                loadDummyConversations()
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
                partnerName: "練習会: 皇居ラン 2周 ゆっくりペース",
                avatarImage: "person.3.sequence.fill",
                lastMessage: "集合は噴水前です。5分前には集まってください！",
                timestamp: calendar.date(byAdding: .minute, value: -10, to: now) ?? now,
                hasUnread: true,
                isPractice: true,
                lastMessageSenderName: "Kenji_Run"
            ),
            MessageConversation(
                conversationId: "dummy-practice-yoyogi",
                partnerName: "練習会: 代々木公園ジョグ 60分",
                avatarImage: "person.3.sequence.fill",
                lastMessage: "ゆっくり6:30/kmペースで行きましょう。",
                timestamp: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                hasUnread: false,
                isPractice: true,
                lastMessageSenderName: "さっちゃん"
            ),
            // 個別チャット（サンプル）
            MessageConversation(
                conversationId: "dummy-tanaka",
                partnerName: "Tanaka-san",
                avatarImage: "person.circle.fill",
                lastMessage: "週末の朝が良いです。6時頃からいかがでしょうか？",
                timestamp: calendar.date(byAdding: .minute, value: -30, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-sato",
                partnerName: "Sato-san",
                avatarImage: "person.circle.fill",
                lastMessage: "明日の練習会、参加します！",
                timestamp: calendar.date(byAdding: .hour, value: -1, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-yamada",
                partnerName: "Yamada-san",
                avatarImage: "person.circle.fill",
                lastMessage: "了解しました。では明日の朝6時に待ち合わせましょう。",
                timestamp: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                hasUnread: true,
                isPractice: false
            ),
            MessageConversation(
                conversationId: "dummy-suzuki",
                partnerName: "Suzuki-san",
                avatarImage: "person.circle.fill",
                lastMessage: "ありがとうございます！一緒に走りましょう！",
                timestamp: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                hasUnread: false,
                isPractice: false
            )
        ]
        isLoading = false
    }
}

// MARK: - Request Detail View
struct RequestDetailView: View {
    let request: MatchRequestSummary
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @EnvironmentObject private var matchInvitationStore: MatchInvitationStore

    @State private var showCounterSheet = false
    @State private var navigateToChat = false

    private var chatConversationId: String { "match-\(request.id)" }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.black)
                    .saturation(0)
                Text(request.fromName)
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
            }
            .padding(.top, 32)

            VStack(alignment: .leading, spacing: 12) {
                Text("リクエスト内容")
                    .font(.headline)
                    .foregroundColor(.black)
                Text(request.message)
                    .font(.body)
                    .foregroundColor(.black)
                    .fixedSize(horizontal: false, vertical: true)
                if let sched = request.scheduleSubtitle {
                    Text(sched)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.9))
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 12) {
                Button(action: {
                    acceptMatch()
                    navigateToChat = true
                }) {
                    Text("承諾")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiOnBrandYellow)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.tasukiPrimaryButtonFill)
                        .cornerRadius(30)
                }

                Button(action: { showCounterSheet = true }) {
                    Text("日程候補を提案する")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 30)
                                .stroke(Color.black.opacity(0.2), lineWidth: 1)
                        )
                }

                Button(action: {
                    matchInvitationStore.remove(id: request.id)
                    dismiss()
                }) {
                    Text("今回は見送る")
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
        .navigationDestination(isPresented: $navigateToChat) {
            ChatView(conversationId: chatConversationId, partnerName: request.fromName)
        }
        .sheet(isPresented: $showCounterSheet) {
            MatchInviteComposerSheet(
                navigationTitle: "日程候補を提案",
                submitLabel: "送信",
                initialMessage: request.message,
                initialLocation: request.location ?? "",
                initialRunDate: request.proposedStart ?? Date(),
                initialWeeklyRepeat: request.isWeeklyRecurring,
                onSubmit: { payload in
                    matchInvitationStore.updateCounterProposal(
                        id: request.id,
                        proposedStart: payload.runDate,
                        location: payload.location,
                        isWeeklyRecurring: payload.weeklyRepeat,
                        recurrenceWeekday: payload.recurrenceWeekday,
                        message: payload.message
                    )
                }
            )
        }
        .onAppear {
            tabBarVisibility.pushHiddenContext()
        }
        .onDisappear {
            tabBarVisibility.popHiddenContext()
        }
    }

    private func acceptMatch() {
        let start = request.proposedStart ?? Date()
        var title = "\(request.fromName)さんとラン"
        if request.isWeeklyRecurring {
            title += "（毎週）"
        }
        joinedPracticesStore.add(
            JoinedPracticeItem(
                id: UUID().uuidString,
                practiceId: "match-\(request.id)",
                title: title,
                location: (request.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                date: start,
                chatId: chatConversationId
            )
        )
        matchInvitationStore.remove(id: request.id)
    }
}

#Preview {
    MessageListView()
        .environmentObject(TabBarVisibility())
        .environmentObject(JoinedPracticesStore())
        .environmentObject(MatchInvitationStore.shared)
}
