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
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var replyingTo: ChatMessage?
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage("myName") private var myName: String = "Hiro"
    
    @State private var showReportSheet = false
    @State private var reportCategory: String = ""
    @State private var reportDetailText: String = ""
    @FocusState private var isReportDetailFocused: Bool
    @State private var showReportSuccess = false
    @State private var showReportErrorAlert = false
    @State private var reportErrorMessage: String = ""
    @State private var isSubmittingReport = false

    init(conversationId: String = "dummy-preview", partnerName: String = "Tanaka-san", isPractice: Bool = false) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.isPractice = isPractice
    }
    
    var body: some View {
        VStack(spacing: 0) {
            safetyHeaderView
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            messageBubbleWithSwipe(message: message)
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
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerStack
                .background(Color.white)
        }
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("スパム") { openReportSheet(category: "スパム") }
                    Button("ハラスメント") { openReportSheet(category: "ハラスメント") }
                    Button("不適切な内容") { openReportSheet(category: "不適切な内容") }
                    Button("その他") { openReportSheet(category: "その他") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color.tasukiAccent)
                }
                .disabled(isSubmittingReport)
            }
        }
        .sheet(isPresented: $showReportSheet, onDismiss: {
            reportDetailText = ""
        }) {
            reportSheetContent
        }
        .alert("受け付けました", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("内容を確認のうえ、適切に対応します。")
        }
        .alert("通報に失敗しました", isPresented: $showReportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportErrorMessage)
        }
        .onAppear {
            tabBarVisibility.pushHiddenContext()
            loadDummyMessages()
            ConversationManager.shared.markConversationAsRead(conversationId: conversationId)
        }
        .onDisappear {
            tabBarVisibility.popHiddenContext()
        }
    }
    
    private var reportSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("選択した理由: \(reportCategory)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("詳しい内容を入力してください（運営が確認します）")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("具体的な理由を入力", text: $reportDetailText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .focused($isReportDetailFocused)
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("会話を通報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showReportSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("通報する") {
                        submitReportFromSheet()
                    }
                    .disabled(isSubmittingReport)
                }
            }
            .onAppear {
                isReportDetailFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func openReportSheet(category: String) {
        reportCategory = category
        reportDetailText = ""
        showReportSheet = true
    }
    
    private func submitReportFromSheet() {
        let detail = reportDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            reportErrorMessage = "詳しい内容を入力してください。"
            showReportErrorAlert = true
            return
        }
        showReportSheet = false
        submitReport(category: reportCategory, detail: detail)
    }
    
    private var composerStack: some View {
        VStack(spacing: 0) {
            if let target = replyingTo {
                compactReplyPreview(target: target)
            }
            inputAreaView
        }
    }
    
    /// 返信先は入力欄の直上に1行だけ表示
    private func compactReplyPreview(target: ChatMessage) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.tasukiPrimary.opacity(0.85))
                .frame(width: 2)
                .frame(maxHeight: 14)
            Text("返信: \(target.text)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Button {
                replyingTo = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(.systemGray6).opacity(0.6))
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
    
    // MARK: - Message Bubble + swipe to reply
    private func messageBubbleWithSwipe(message: ChatMessage) -> some View {
        messageBubbleView(message: message)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 28)
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > abs(dy) * 1.15, dx < -48 else { return }
                        replyingTo = message
                    }
            )
    }
    
    @ViewBuilder
    private func messageBubbleView(message: ChatMessage) -> some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
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
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let replyId = replyingTo?.id
        let newMessage = ChatMessage(
            text: messageText,
            isFromMe: true,
            replyToMessageId: replyId,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)
        messageText = ""
        replyingTo = nil
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
    
    private func submitReport(category: String, detail: String) {
        isSubmittingReport = true
        ConversationManager.shared.submitConversationReport(
            conversationId: conversationId,
            partnerName: partnerName,
            reasonCategory: category,
            detail: detail
        ) { result in
            isSubmittingReport = false
            switch result {
            case .success:
                showReportSuccess = true
            case .failure(let error):
                reportErrorMessage = error.localizedDescription
                showReportErrorAlert = true
            }
        }
    }
    
    private func loadDummyMessages() {
        let cal = Calendar.current
        let now = Date()
        func minAgo(_ m: Int) -> Date { cal.date(byAdding: .minute, value: -m, to: now) ?? now }
        func hourAgo(_ h: Int) -> Date { cal.date(byAdding: .hour, value: -h, to: now) ?? now }
        func dayAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }

        if isPractice {
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
            .environmentObject(TabBarVisibility())
    }
}
