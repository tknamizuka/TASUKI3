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
    @State private var requests: [MatchRequestSummary] = []
    @State private var isLoading = true
    /// シングルトンを `@StateObject` で保持すると未定義動作・起動時クラッシュの原因になるため `ObservedObject` を使う
    @ObservedObject private var conversationManager = ConversationManager.shared
    
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                
                ZStack {
                    Color.white
                        .ignoresSafeArea()
                    
                    if isLoading {
                        ProgressView()
                    } else {
                        let practiceChats = conversations.filter { $0.isPractice }
                        let userChats = conversations.filter { !$0.isPractice }
                        
                        switch selectedTab {
                        case .chat:
                            if practiceChats.isEmpty {
                                VStack {
                                    Text("練習会のチャットがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                                }
                            } else {
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
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        case .message:
                            if userChats.isEmpty {
                                VStack {
                                    Text("メッセージがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))
                                }
                            } else {
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
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        case .request:
                            if requests.isEmpty {
                                VStack {
                                    Text("リクエストがありません")
                                        .font(.system(size: 16, weight: .regular))
                                        .foregroundColor(Color.tasukiPrimary.opacity(0.6))
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
            .navigationTitle(
                selectedTab == .chat ? "チャット" :
                selectedTab == .message ? "メッセージ" : "リクエスト"
            )
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadConversations()
                loadRequests()
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
                    .foregroundColor(Color.tasukiPrimary)
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
                            .fill(Color.tasukiAccent)
                            .frame(width: 8, height: 8)
                    }
                    Text(conversation.partnerName)
                        .font(.system(size: 16, weight: conversation.hasUnread ? .bold : .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .lineLimit(1)
                }
                
                if conversation.isPractice, let sender = conversation.lastMessageSenderName, !sender.isEmpty {
                    Text("\(sender): \(conversation.lastMessage)")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(conversation.hasUnread ? Color.tasukiPrimary.opacity(0.8) : Color.tasukiPrimary.opacity(0.6))
                        .lineLimit(2)
                } else {
                    Text(conversation.lastMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(conversation.hasUnread ? Color.tasukiPrimary.opacity(0.8) : Color.tasukiPrimary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右: 送信時間
            Text(formatTime(conversation.timestamp))
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(Color.tasukiPrimary.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
    
    // MARK: - Request Row View
    private func requestRowView(request: MatchRequestSummary) -> some View {
        HStack(spacing: 12) {
            // 左: アイコン
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(Color.tasukiPrimary)
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
                            .fill(Color.tasukiAccent)
                            .frame(width: 8, height: 8)
                    }
                    Text(request.fromName)
                        .font(.system(size: 16, weight: request.isNew ? .bold : .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .lineLimit(1)
                    Text(request.type.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.tasukiAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.tasukiAccent.opacity(0.1))
                        )
                }
                
                Text(request.message)
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                    .lineLimit(2)
                
                Text(formatTime(request.createdAt))
                    .font(.system(size: 11))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        )
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
    
    var body: some View {
        VStack(spacing: 24) {
            // 送信者情報
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(Color.tasukiPrimary)
                    .saturation(0)
                Text(request.fromName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
                Text(request.type.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.tasukiAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.tasukiAccent.opacity(0.1))
                    )
            }
            .padding(.top, 32)
            
            // リクエスト内容
            VStack(alignment: .leading, spacing: 12) {
                Text("リクエスト内容")
                    .font(.headline)
                    .foregroundColor(Color.tasukiPrimary)
                Text(request.message)
                    .font(.body)
                    .foregroundColor(Color.tasukiPrimary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.tasukiDarkCardSecondary)
            )
            .padding(.horizontal, 20)
            
            Spacer()
            
            // アクションボタン
            VStack(spacing: 12) {
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
                
                Button(action: {
                    dismiss()
                }) {
                    Text("今回は見送る")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.white)
        .navigationTitle("リクエスト詳細")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    MessageListView()
}
