//
//  ChatView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Chat Message Model（conversationId に紐づくメッセージ。replyToMessageId で返信先を参照）
struct ChatMessage: Identifiable {
    /// メッセージの一意ID（バックエンドでは Firestore ドキュメントID）
    let id: String
    let text: String
    let isFromMe: Bool
    let timestamp: Date
    /// 返信先メッセージのID（同一会話内）。nil の場合は通常メッセージ
    let replyToMessageId: String?
    /// 送信時点の返信元テキスト（Firestore にも保存。一覧に無くても引用表示・ジャンプ先特定に利用）
    let replyPreviewText: String?
    /// 送信者名（練習会など複数参加者チャットで「誰が送ったか」を表示する用。nil の場合は表示しない）
    let senderName: String?
    
    init(
        id: String? = nil,
        text: String,
        isFromMe: Bool,
        timestamp: Date = Date(),
        replyToMessageId: String? = nil,
        replyPreviewText: String? = nil,
        senderName: String? = nil
    ) {
        self.id = id ?? UUID().uuidString
        self.text = text
        self.isFromMe = isFromMe
        self.timestamp = timestamp
        self.replyToMessageId = replyToMessageId
        self.replyPreviewText = replyPreviewText
        self.senderName = senderName
    }
}

// MARK: - Chat View
struct ChatView: View {
    /// バックエンドで発行された一意の会話ID（このチャットルームの識別子）
    let conversationId: String
    let partnerName: String
    /// 1対1チャットの相手 UID（ブロック用。未指定時は会話ドキュメントから解決）
    var partnerUid: String? = nil
    /// 練習会チャットかどうか（true のときメッセージに送信者名を表示）
    var isPractice: Bool = false
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var runProposalStore: RunProposalStore
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    
    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var replyingTo: ChatMessage?
    @State private var swipeOffsets: [String: CGFloat] = [:]
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage("myName") private var myName: String = "Hiro"
    
    @State private var showReportSheet = false
    @State private var showRunProposalSheet = false
    @State private var reportCategory: String = ""
    @State private var reportDetailText: String = ""
    @FocusState private var isReportDetailFocused: Bool
    @State private var showReportSuccess = false
    @State private var showReportErrorAlert = false
    @State private var reportErrorMessage: String = ""
    @State private var isSubmittingReport = false
    @State private var scrollToMessageId: String?
    @State private var resolvedPartnerUid: String?
    @State private var showBlockConfirm = false
    @State private var showBlockResult = false
    @State private var blockResultMessage = ""

    init(
        conversationId: String = "dummy-preview",
        partnerName: String = "Tanaka-san",
        partnerUid: String? = nil,
        isPractice: Bool = false
    ) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.partnerUid = partnerUid
        self.isPractice = isPractice
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if !isPractice, let incoming = runProposalStore.incomingAttentionProposal(conversationId: conversationId, myDisplayName: myName) {
                nextRunAttentionBanner(proposal: incoming)
            }
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
                .onChange(of: scrollToMessageId) { _, newId in
                    guard let id = newId else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                    scrollToMessageId = nil
                }
                .onChange(of: messages.count) { _, _ in
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
                    if !isPractice, effectivePartnerUid != nil {
                        Divider()
                        Button("このユーザーをブロック", role: .destructive) {
                            showBlockConfirm = true
                        }
                    }
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
        .sheet(isPresented: $showRunProposalSheet) {
            MatchInviteComposerSheet(
                navigationTitle: "次回の日程を提案",
                submitLabel: "送信",
                onSubmit: { payload in
                    submitRunProposal(payload)
                }
            )
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
        .confirmationDialog("このユーザーをブロックしますか？", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("ブロックする", role: .destructive) {
                Task { await blockPartner() }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("ブロック", isPresented: $showBlockResult) {
            Button("OK") { dismiss() }
        } message: {
            Text(blockResultMessage)
        }
        .onAppear {
            tabBarVisibility.pushHiddenContext()
            if useRemoteMessages {
                loadMessagesFromFirestore()
                resolvePartnerUidIfNeeded()
            } else {
                loadDummyMessages()
            }
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
    /// ログイン済みかつデモ用 conversationId 以外は Firestore からメッセージを読む
    private var useRemoteMessages: Bool {
        if conversationId.hasPrefix("dummy-") { return false }
        if conversationId.hasPrefix("request-") { return false }
        if conversationId.hasPrefix("match-") { return false }
        if conversationId == "dummy-preview" { return false }
        if conversationId == "preview-1" { return false }
        return Auth.auth().currentUser != nil
    }

    private func loadMessagesFromFirestore() {
        ConversationManager.shared.fetchMessages(conversationId: conversationId) { result in
            switch result {
            case .success(let list):
                messages = list
            case .failure:
                messages = []
            }
        }
    }

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
    
    private func nextRunAttentionBanner(proposal: RunProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 20))
                    .foregroundColor(Color.tasukiPrimary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(proposal.fromSenderName)から次回の日程の提案")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                    Text(runProposalStore.scheduleLine(for: proposal))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.95))
                    if !proposal.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(proposal.note)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            if proposal.attendance == nil {
                HStack(spacing: 10) {
                    Button("参加") {
                        attendRunProposal(proposal, .attending)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.tasukiPrimaryButtonFill)
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .cornerRadius(10)
                    Button("不参加") {
                        attendRunProposal(proposal, .notAttending)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.12), lineWidth: 1)
                    )
                }
            } else {
                Text(proposal.attendance == .attending ? "参加で回答済み" : "不参加で回答済み")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.tasukiBrandYellow.opacity(0.3))
    }
    
    private func attendRunProposal(_ proposal: RunProposal, _ status: RunProposalAttendance) {
        runProposalStore.setAttendance(proposalId: proposal.id, status)
        if status == .attending {
            var title = "\(partnerName)さんとラン"
            if proposal.isWeeklyRecurring { title += "（毎週）" }
            joinedPracticesStore.add(
                JoinedPracticeItem(
                    id: UUID().uuidString,
                    practiceId: "chat-proposal-\(proposal.id)",
                    title: title,
                    location: proposal.location,
                    date: proposal.proposedStart,
                    chatId: conversationId
                )
            )
        }
    }
    
    private func submitRunProposal(_ payload: MatchInvitePayload) {
        runProposalStore.addProposal(
            conversationId: conversationId,
            fromSenderName: myName,
            proposedStart: payload.runDate,
            location: payload.location,
            isWeeklyRecurring: payload.weeklyRepeat,
            recurrenceWeekday: payload.recurrenceWeekday,
            note: payload.message
        )
        let all = runProposalStore.proposals.filter { $0.conversationId == conversationId }
        if let last = all.max(by: { $0.createdAt < $1.createdAt }) {
            var line = "📅 次回の日程を提案しました\n\(runProposalStore.scheduleLine(for: last))"
            if !payload.message.isEmpty {
                line += "\n\n\(payload.message)"
            }
            let newMessage = ChatMessage(text: line, isFromMe: true)
            messages.append(newMessage)
        }
    }
    
    /// 返信引用に表示するテキスト（メモリ上のメッセージがあれば優先、なければ保存済みプレビュー）
    private func replyQuoteText(for message: ChatMessage) -> String? {
        guard message.replyToMessageId != nil else { return nil }
        if let rid = message.replyToMessageId,
           let repliedTo = messages.first(where: { $0.id == rid }) {
            return repliedTo.text
        }
        if let p = message.replyPreviewText?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            return p
        }
        return nil
    }

    // MARK: - Message Bubble + swipe to reply
    private func messageBubbleWithSwipe(message: ChatMessage) -> some View {
        ZStack(alignment: .trailing) {
            if !message.isFromMe {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary.opacity(0.82))
                    .padding(.trailing, 8)
                    .opacity(replyIndicatorOpacity(for: message.id))
            }
            messageBubbleView(message: message)
                .offset(x: message.isFromMe ? 0 : (swipeOffsets[message.id] ?? 0))
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    guard !message.isFromMe else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.1 else { return }
                    swipeOffsets[message.id] = max(-78, min(0, dx))
                }
                .onEnded { value in
                    defer {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                            swipeOffsets[message.id] = 0
                        }
                    }
                    guard !message.isFromMe else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.15, dx < -52 else { return }
                    replyingTo = message
                }
        )
    }

    private func replyIndicatorOpacity(for messageId: String) -> Double {
        let offset = abs(swipeOffsets[messageId] ?? 0)
        guard offset > 8 else { return 0 }
        return min(1.0, Double((offset - 8) / 44))
    }
    
    @ViewBuilder
    private func messageBubbleView(message: ChatMessage) -> some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 6) {
                if let name = message.senderName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary.opacity(0.7))
                }
                if let quote = replyQuoteText(for: message), let replyId = message.replyToMessageId {
                    Group {
                        if message.isFromMe {
                            Button {
                                scrollToMessageId = replyId
                            } label: {
                                replyQuoteChrome(text: quote, isFromMe: true)
                            }
                            .buttonStyle(.plain)
                        } else {
                            replyQuoteChrome(text: quote, isFromMe: false)
                        }
                    }
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

    private func replyQuoteChrome(text: String, isFromMe: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(isFromMe ? Color.white.opacity(0.85) : Color.tasukiPrimary.opacity(0.55))
                .frame(width: 3)
                .frame(minHeight: 28)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isFromMe ? Color.white.opacity(0.92) : Color.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isFromMe ? Color.white.opacity(0.14) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isFromMe ? Color.white.opacity(0.22) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    private var inputAreaView: some View {
        HStack(spacing: 8) {
            if !isPractice {
                Button(action: { showRunProposalSheet = true }) {
                    Image(systemName: "calendar")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color.tasukiPrimary)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("次回の日程を提案")
            }
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
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let replyId = replyingTo?.id
        let previewFromReply: String? = replyingTo.map { msg in
            let t = msg.text
            if t.count <= 500 { return t }
            return String(t.prefix(500))
        }
        messageText = ""
        replyingTo = nil
        isTextFieldFocused = false

        if useRemoteMessages {
            ConversationManager.shared.sendMessage(
                conversationId: conversationId,
                text: trimmed,
                replyToMessageId: replyId,
                replyPreviewText: previewFromReply
            ) { result in
                switch result {
                case .success(let docId):
                    let newMessage = ChatMessage(
                        id: docId,
                        text: trimmed,
                        isFromMe: true,
                        replyToMessageId: replyId,
                        replyPreviewText: previewFromReply,
                        senderName: isPractice ? myName : nil
                    )
                    messages.append(newMessage)
                case .failure:
                    break
                }
            }
            return
        }

        let newMessage = ChatMessage(
            text: trimmed,
            isFromMe: true,
            replyToMessageId: replyId,
            replyPreviewText: previewFromReply,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let replyMessage = ChatMessage(
                text: "ありがとうございます！",
                isFromMe: false,
                replyToMessageId: nil,
                replyPreviewText: nil,
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

    private var effectivePartnerUid: String? {
        partnerUid ?? resolvedPartnerUid
    }

    private func resolvePartnerUidIfNeeded() {
        guard !isPractice, partnerUid == nil, let myUid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("conversations").document(conversationId).getDocument { snapshot, _ in
            guard let ids = snapshot?.data()?["participantIds"] as? [String] else { return }
            let other = ids.first { $0 != myUid }
            DispatchQueue.main.async {
                resolvedPartnerUid = other
            }
        }
    }

    @MainActor
    private func blockPartner() async {
        guard let uid = effectivePartnerUid else {
            blockResultMessage = "相手ユーザーを特定できませんでした"
            showBlockResult = true
            return
        }
        do {
            try await FindComplianceService.shared.blockUser(blockedUid: uid)
            blockResultMessage = "\(partnerName)さんをブロックしました"
            showBlockResult = true
        } catch {
            blockResultMessage = error.localizedDescription
            showBlockResult = true
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
                ChatMessage(
                    id: "dummy-4",
                    text: "週末の朝が良いです。6時頃からいかがでしょうか？",
                    isFromMe: true,
                    timestamp: dayAgo(1),
                    replyToMessageId: "dummy-3",
                    replyPreviewText: "ありがとうございます！いつ頃が都合よろしいですか？"
                ),
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
            .environmentObject(RunProposalStore.shared)
            .environmentObject(JoinedPracticesStore())
    }
}
