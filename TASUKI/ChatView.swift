//
//  ChatView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - Chat Message Model（conversationId に紐づくメッセージ。replyToMessageId で返信先を参照）
struct ChatMessage: Identifiable {
    /// メッセージの一意ID（バックエンドでは Firestore ドキュメントID）
    let id: String
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    /// 返信先メッセージのID（同一会話内）。nil の場合は通常メッセージ
    let replyToMessageId: String?
    /// 送信者名（練習会など複数参加者チャットで「誰が送ったか」を表示する用。nil の場合は表示しない）
    let senderName: String?
    
    init(id: String? = nil, text: String, isFromMe: Bool, timestamp: Date = Date(), replyToMessageId: String? = nil, senderName: String? = nil) {
        self.id = id ?? UUID().uuidString
        self.text = text
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.replyToMessageId = replyToMessageId
        self.senderName = senderName
    }
}

// MARK: - Chat View
struct ChatView: View {
    /// バックエンドで発行された一意の会話ID（このチャットルームの識別子）
    let conversationId: String
    let partnerName: String
    /// 練習会チャットかどうか（true のときメッセージに送信者名を表示）
    var isPractice: Bool = false
    @Environment(\.dismiss) var dismiss
    
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage("myName") private var myName: String = "Hiro"

    init(conversationId: String = "dummy-preview", partnerName: String = "Tanaka-san", isPractice: Bool = false) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.isPractice = isPractice
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 安全対策ヘッダー
            safetyHeaderView
            
            // メッセージエリア
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            messageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            companionQuickPhraseBar

            // 入力エリア（画面最下部に固定）
            inputAreaView
        }
        .background(Color.white)
        .navigationTitle(partnerName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiAccent)
                }
            }
        }
        .onAppear {
            loadDummyMessages()
            ConversationManager.shared.markConversationAsRead(conversationId: conversationId)
        }
    }
    
    // MARK: - Safety Header View
    private var safetyHeaderView: some View {
        HStack {
            Text("トラブル防止のため、金銭のやり取りやLINE交換は禁止されています")
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.1))
    }
    
    // MARK: - Message Bubble View
    @ViewBuilder
    private func messageBubbleView(message: ChatMessage) -> some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                // 送信者名（練習会などで表示）
                if let name = message.senderName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                }
                if let replyId = message.replyToMessageId,
                   let repliedTo = messages.first(where: { $0.id == replyId }) {
                    Text("返信: \(repliedTo.text)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(message.isFromMe ? .white.opacity(0.9) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(message.isFromMe ? .white : .black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(message.isFromMe ? Color.royalBlue : Color.gray.opacity(0.2))
                    )
            }
            
            if !message.isFromMe {
                Spacer(minLength: 60)
            }
        }
    }
    
    private var companionQuickPhraseBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CompanionChatQuickPhrases.all, id: \.self) { phrase in
                    Button {
                        sendPresetMessage(phrase)
                    } label: {
                        Text(phrase)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.tasukiPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.tasukiAccent.opacity(0.12))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color.white)
    }

    // MARK: - Input Area View
    private var inputAreaView: some View {
        HStack(spacing: 12) {
            TextField("メッセージを入力", text: $messageText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemGray6))
                )
                .focused($isTextFieldFocused)
            
            Button(action: {
                sendMessage()
            }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(messageText.isEmpty ? Color.white : Color.tasukiOnBrandYellow)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(messageText.isEmpty ? Color.gray : Color.tasukiPrimaryButtonFill)
                    )
            }
            .disabled(messageText.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }
    
    // MARK: - Helper Methods
    private func sendPresetMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let newMessage = ChatMessage(
            text: trimmed,
            isFromMe: true,
            replyToMessageId: nil,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)
        isTextFieldFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let replyMessage = ChatMessage(
                text: "ありがとうございます！",
                isFromMe: false,
                replyToMessageId: nil,
                senderName: isPractice ? "Kenji_Run" : nil
            )
            messages.append(replyMessage)
        }
    }

    private func sendMessage(replyToMessageId: String? = nil) {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        let newMessage = ChatMessage(
            text: messageText,
            isFromMe: true,
            replyToMessageId: replyToMessageId,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)
        messageText = ""
        isTextFieldFocused = false
        
        // ダミー: 相手からの返信をシミュレート（1秒後）
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let replyMessage = ChatMessage(
                text: "ありがとうございます！",
                isFromMe: false,
                replyToMessageId: nil,
                senderName: isPractice ? "Kenji_Run" : nil
            )
            messages.append(replyMessage)
        }
    }
    
    private func loadDummyMessages() {
        let cal = Calendar.current
        let now = Date()
        func minAgo(_ m: Int) -> Date { cal.date(byAdding: .minute, value: -m, to: now) ?? now }
        func hourAgo(_ h: Int) -> Date { cal.date(byAdding: .hour, value: -h, to: now) ?? now }
        func dayAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }

        if isPractice {
            // 練習会チャット用サンプル（送信者名付き）
            messages = [
                ChatMessage(id: "dummy-p1", text: "集合は噴水前です。5分前には集まってください！", isFromMe: false, timestamp: hourAgo(2), senderName: "Kenji_Run"),
                ChatMessage(id: "dummy-p2", text: "了解です！", isFromMe: true, timestamp: hourAgo(2), senderName: myName),
                ChatMessage(id: "dummy-p3", text: "よろしくお願いします！", isFromMe: false, timestamp: hourAgo(1), senderName: "さっちゃん"),
                ChatMessage(id: "dummy-p4", text: "ペースは6:30/kmでゆっくり行きましょう。", isFromMe: false, timestamp: minAgo(45), senderName: "Kenji_Run"),
                ChatMessage(id: "dummy-p5", text: "お願いします！", isFromMe: true, timestamp: minAgo(30), senderName: myName),
            ]
        } else {
            messages = [
                ChatMessage(id: "dummy-1", text: "こんにちは！ランニングパートナーを探しています。", isFromMe: false, timestamp: dayAgo(2)),
                ChatMessage(id: "dummy-2", text: "こんにちは！私も探していました。一緒に走りましょう！", isFromMe: true, timestamp: dayAgo(2)),
                ChatMessage(id: "dummy-3", text: "ありがとうございます！いつ頃が都合よろしいですか？", isFromMe: false, timestamp: dayAgo(1)),
                ChatMessage(id: "dummy-4", text: "週末の朝が良いです。6時頃からいかがでしょうか？", isFromMe: true, timestamp: dayAgo(1), replyToMessageId: "dummy-3"),
                ChatMessage(id: "dummy-5", text: "6時、大丈夫です！どこで待ち合わせましょうか？", isFromMe: false, timestamp: hourAgo(5)),
                ChatMessage(id: "dummy-6", text: "代々木公園の入口、ベンチの前でどうですか？", isFromMe: true, timestamp: hourAgo(4)),
                ChatMessage(id: "dummy-7", text: "いいですね！では土曜の朝6時代々木公園で。", isFromMe: false, timestamp: hourAgo(3)),
                ChatMessage(id: "dummy-8", text: "了解です。当日は軽くストレッチしてから走りましょう。", isFromMe: true, timestamp: hourAgo(2)),
                ChatMessage(id: "dummy-9", text: "5kmくらいのペースで行きましょうか？", isFromMe: false, timestamp: minAgo(45)),
                ChatMessage(id: "dummy-10", text: "6分/kmくらいでゆっくりいきましょう！", isFromMe: true, timestamp: minAgo(30)),
            ]
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(conversationId: "preview-1", partnerName: "Tanaka-san")
    }
}
