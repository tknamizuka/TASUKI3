//
//  ChatView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - スワイプで返信（バブルが指に追従）
private struct SwipeToReplyContainer<Content: View>: View {
    let onReply: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offsetX: CGFloat = 0

    private let maxPull: CGFloat = 76
    private let triggerThreshold: CGFloat = 52

    var body: some View {
        ZStack(alignment: .trailing) {
            Image(systemName: "arrowshape.turn.up.left.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary.opacity(offsetX < -12 ? 0.55 : 0.28))
                .padding(.trailing, 2)
                .accessibilityHidden(true)

            content()
                .offset(x: offsetX)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 16, coordinateSpace: .local)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.08, dx <= 0 else { return }
                    offsetX = max(dx, -maxPull)
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    let mostlyHorizontal = abs(dx) > abs(dy) * 1.08
                    let triggered = mostlyHorizontal && dx <= -triggerThreshold
                    if triggered {
                        onReply()
                    }
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                        offsetX = 0
                    }
                }
        )
    }
}

// MARK: - 次回練習の案内メッセージ（送信フォーマットと受信UIの判定で共有）
enum ChatNextPracticeMessages {
    static let proposalPrefix = "【次回練習の提案】"
    static let attendingReplyLine = "【次回練習の回答】参加します"
    static let decliningReplyLine = "【次回練習の回答】今回は参加できません"

    /// 提案本文の「日時:」行と同一（送信時と解析で共有）
    static let proposalLineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func isProposalBody(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(proposalPrefix)
    }

    static func isPracticeAnswerLine(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).contains("【次回練習の回答】")
    }

    /// 「場所:」「日時:」行を読み取り、日時を解析できれば返す（カレンダー登録用）
    static func parseProposalPlaceAndDate(_ text: String) -> (place: String, date: Date)? {
        guard isProposalBody(text) else { return nil }
        var placeValue: String?
        var dateLine: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("場所:") {
                placeValue = String(trimmed.dropFirst("場所:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.hasPrefix("日時:") {
                dateLine = String(trimmed.dropFirst("日時:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        guard let place = placeValue, !place.isEmpty, let rawDate = dateLine, !rawDate.isEmpty else { return nil }
        if let d = proposalLineDateFormatter.date(from: rawDate) {
            return (place: place, date: d)
        }
        return nil
    }
}

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
    /// 練習会チャットに紐づく practiceId（存在しない場合は nil）
    var practiceId: String? = nil
    /// 1on1 会話相手の userId（取得できない場合は nil）
    var partnerUserId: String? = nil
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var tabBarVisibility: TabBarVisibility
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @EnvironmentObject private var partnerMatchStore: PartnerMatchRequestsStore
    @EnvironmentObject private var matchPromisesStore: MatchPromisesStore
    @EnvironmentObject private var practiceRecruitmentsStore: PracticeRecruitmentsStore

    @State private var messages: [ChatMessage] = []
    @State private var messageText: String = ""
    @State private var replyingTo: ChatMessage?
    @FocusState private var isTextFieldFocused: Bool
    @AppStorage("myName") private var myName: String = "Hiro"
    @AppStorage("blockedConversationIds") private var blockedConversationIdsRaw: String = ""
    
    @State private var showReportSheet = false
    @State private var showReportDetailSheet = false
    @State private var selectedReportCategory: String = ""
    @State private var reportOccurredAt: Date = Date()
    @State private var reportDetailText: String = ""
    @State private var reportIncludedBlock = false
    @State private var showReportSuccess = false
    @State private var showReportErrorAlert = false
    @State private var reportErrorMessage: String = ""
    @State private var isSubmittingReport = false
    @State private var showLinkedProfile = false
    @State private var showLinkedPractice = false
    @State private var showBlockConfirmAlert = false
    @State private var showUnblockConfirmAlert = false
    @State private var showBlockSuccessAlert = false
    @State private var showPracticeScheduleSheet = false
    /// 相手からの「次回練習の提案」メッセージ id → 自分の回答（未回答は nil）
    @State private var practiceProposalChoiceByMessageId: [String: PracticeProposalChoice] = [:]

    private enum PracticeProposalChoice {
        case attending
        case declining
    }

    init(
        conversationId: String = "dummy-preview",
        partnerName: String = "Kenji_Run",
        isPractice: Bool = false,
        practiceId: String? = nil,
        partnerUserId: String? = nil
    ) {
        self.conversationId = conversationId
        self.partnerName = partnerName
        self.isPractice = isPractice
        self.practiceId = practiceId
        self.partnerUserId = partnerUserId
    }
    
    private var hasUnansweredIncomingPracticeProposal: Bool {
        messages.contains { message in
            !message.isFromMe
                && ChatNextPracticeMessages.isProposalBody(message.text)
                && practiceProposalChoiceByMessageId[message.id] == nil
        }
    }

    /// 「参加」でカレンダー／約束に入れた次回練習（提案経由）。当日までは上部バナーを出す。
    private var proposalAcceptedCalendarSticky: (location: String, date: Date)? {
        let conv = conversationId
        let prefix = "next-practice-\(conv)-"
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        if isPractice {
            let hits = joinedPracticesStore.items.filter { item in
                item.chatId == conv
                    && item.practiceId.hasPrefix(prefix)
                    && cal.startOfDay(for: item.date) >= todayStart
            }
            return hits.min(by: { $0.date < $1.date }).map { ($0.location, $0.date) }
        } else {
            let hits = matchPromisesStore.items.filter { item in
                (item.conversationId ?? "") == conv
                    && item.id.hasPrefix(prefix)
                    && cal.startOfDay(for: item.date) >= todayStart
            }
            return hits.min(by: { $0.date < $1.date }).map { ($0.location, $0.date) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            safetyHeaderView

            if hasUnansweredIncomingPracticeProposal {
                practiceProposalTopNotice
            }

            if let sticky = proposalAcceptedCalendarSticky {
                practiceProposalAcceptedStickyBanner(place: sticky.location, date: sticky.date)
            }

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
                    if !isPractice {
                        Button("プロフィールを見る") {
                            showLinkedProfile = true
                        }
                    } else {
                        Button("練習会を見る") {
                            showLinkedPractice = true
                        }
                        .disabled(linkedPracticeForChat == nil)
                    }
                    Divider()
                    Button("通報する") { openReportSheet() }
                    Button(isBlockedConversation ? "ブロック解除する" : "ブロックする", role: isBlockedConversation ? .none : .destructive) {
                        if isBlockedConversation {
                            showUnblockConfirmAlert = true
                        } else {
                            showBlockConfirmAlert = true
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
        .sheet(isPresented: $showReportSheet) {
            reportSheetContent
        }
        .sheet(isPresented: $showReportDetailSheet) {
            reportDetailSheetContent
        }
        .alert("受け付けました", isPresented: $showReportSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportIncludedBlock ? "内容を確認のうえ、適切に対応します。あわせて相手をブロックしました。" : "内容を確認のうえ、適切に対応します。")
        }
        .alert("ブロックしますか？", isPresented: $showBlockConfirmAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック", role: .destructive) {
                blockCurrentConversation()
            }
        } message: {
            Text("相手はあなたにメッセージを送ったり、あなたのプロフィールを見つけたりすることができなくなります。ブロックしたことは相手に通知されません。")
        }
        .alert("ブロックしました", isPresented: $showBlockSuccessAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("この相手との会話をブロックしました。")
        }
        .alert("ブロック解除しますか？", isPresented: $showUnblockConfirmAlert) {
            Button("キャンセル", role: .cancel) {}
            Button("ブロック解除", role: .destructive) {
                unblockCurrentConversation()
            }
        } message: {
            Text("この相手をブロック解除します。")
        }
        .alert("通報に失敗しました", isPresented: $showReportErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(reportErrorMessage)
        }
        .sheet(isPresented: $showPracticeScheduleSheet) {
            ChatPracticeScheduleSheet(
                initialPlace: resolvedDefaultSchedulePlace(),
                onSend: { place, date in
                    sendScheduleProposal(place: place, date: date)
                }
            )
        }
        .onAppear {
            tabBarVisibility.pushHiddenContext()
            loadDummyMessages()
            ConversationManager.shared.markConversationAsRead(conversationId: conversationId)
        }
        .onDisappear {
            tabBarVisibility.popHiddenContext()
        }
        .navigationDestination(isPresented: $showLinkedProfile) {
            UserProfileDetailView(user: linkedUserForProfile)
        }
        .navigationDestination(isPresented: $showLinkedPractice) {
            if let practice = linkedPracticeForChat {
                PracticeDetailView(practice: practice)
            } else {
                Text("練習会情報が見つかりません")
                    .font(.system(size: 14))
                    .foregroundColor(Color.tasukiMutedText)
            }
        }
    }

    private var linkedUserForProfile: User {
        let pool = [mockUser] + mockUsers
        if let id = partnerUserId {
            if let byId = pool.first(where: { $0.id.uuidString == id }) {
                return byId
            }
        }
        if let byName = pool.first(where: { $0.name == partnerName }) {
            return byName
        }
        // 一覧に無い表示名でもプロフィール画面へ遷移できるよう、最低限の表示用データを補完する
        return User(
            id: UUID(),
            name: partnerName,
            profileImage: User.findMockInitialsProfileImageToken,
            profileImageUrl: nil,
            bio: "ランニング仲間です。",
            rank: "Rank C",
            age: 30,
            gender: "未設定",
            purpose: "ランニングを楽しむ",
            prefecture: "未設定",
            area: "未設定",
            pace: "--:-- /km",
            runningFrequency: "未設定",
            personalBest: "未設定",
            schedule: "未設定",
            nextRace: "",
            targetTime: "",
            monthlyDistance: 0,
            monthlyTarget: 100,
            avgPace: "--:-- /km",
            totalPoints: 0,
            monthlyPoints: 0,
            matchRate: 50,
            lastLogin: Date(),
            spotName: "未設定",
            latitude: 35.68,
            longitude: 139.76,
            distanceFromUserMock: 0,
            monthlyGpsActivityCount: nil
        )
    }

    private var linkedPracticeForChat: Practice? {
        if let pid = practiceId,
           let recruitment = practiceRecruitmentsStore.recruitment(forPracticeId: pid) {
            return recruitment.toPractice()
        }
        if let recruitment = practiceRecruitmentsStore.recruitment(matchingPracticeChatPartnerName: partnerName) {
            return recruitment.toPractice()
        }
        if let pid = practiceId,
           let joined = joinedPracticesStore.items.first(where: { $0.practiceId == pid }) {
            return practiceFromJoinedItem(joined)
        }
        if let joined = joinedPracticesStore.items.first(where: { $0.chatId == conversationId }) {
            return practiceFromJoinedItem(joined)
        }
        return nil
    }

    private func practiceFromJoinedItem(_ item: JoinedPracticeItem) -> Practice {
        let joined = joinedPracticesStore.items.contains { $0.practiceId == item.practiceId }
        return Practice(
            practiceId: item.practiceId,
            chatId: item.chatId,
            title: item.title,
            location: item.location,
            date: item.date,
            category: .other,
            pace: "—",
            distance: "",
            description: "参加予定の練習会です。詳細は募集ページ（Find）とあわせてご確認ください。",
            organizer: mockUser,
            maxParticipants: 30,
            participantUserIds: [],
            isJoined: joined
        )
    }
    
    private var reportSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("理由を選択してください。")
                    .font(.system(size: 24, weight: .bold))
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                List {
                    ForEach(reportCategories, id: \.self) { category in
                        Button {
                            selectedReportCategory = category
                        } label: {
                            HStack {
                                Text(category)
                                    .font(.system(size: 16))
                                    .foregroundColor(Color.tasukiPrimary)
                                Spacer()
                                Image(systemName: selectedReportCategory == category ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedReportCategory == category ? Color.tasukiAccent : Color.gray.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.tasukiSurface)
                    }
                }
                .listStyle(.plain)
            }
            .background(Color.tasukiDarkBackground)
            .navigationTitle("会話を報告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showReportSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("通報する") {
                        openReportDetailSheet()
                    }
                    .disabled(isSubmittingReport || selectedReportCategory.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var reportDetailSheetContent: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("通報カテゴリ: \(selectedReportCategory)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                DatePicker("発生日時", selection: $reportOccurredAt, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                VStack(alignment: .leading, spacing: 6) {
                    Text("理由（テキスト）")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.tasukiMutedText)
                    TextEditor(text: $reportDetailText)
                        .frame(minHeight: 140)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.tasukiDarkCardSecondary, lineWidth: 1)
                        )
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("報告してブロック") {
                        submitReportDetail(alsoBlock: true)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.pureWhite)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimary))
                    .disabled(isSubmittingReport || reportDetailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("報告する") {
                        submitReportDetail(alsoBlock: false)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    .disabled(isSubmittingReport || reportDetailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .background(Color.tasukiDarkBackground)
            .navigationTitle("通報内容を入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        showReportDetailSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var reportCategories: [String] {
        ["スパム", "ハラスメント", "不適切な内容", "その他"]
    }

    private func openReportSheet() {
        selectedReportCategory = ""
        reportDetailText = ""
        reportOccurredAt = Date()
        showReportSheet = true
    }
    
    private func openReportDetailSheet() {
        showReportSheet = false
        showReportDetailSheet = true
    }

    private func submitReportDetail(alsoBlock: Bool) {
        let text = reportDetailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            reportErrorMessage = "理由（テキスト）を入力してください。"
            showReportErrorAlert = true
            return
        }
        reportIncludedBlock = alsoBlock
        if alsoBlock {
            blockCurrentConversation(showSuccessAlert: false)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd HH:mm"
        let detail = "発生日時: \(f.string(from: reportOccurredAt))\n理由: \(text)"
        showReportDetailSheet = false
        submitReport(category: selectedReportCategory, detail: detail)
    }

    private func blockCurrentConversation(showSuccessAlert: Bool = true) {
        var blocked = Set(blockedConversationIdsRaw.split(separator: ",").map(String.init))
        blocked.insert(conversationId)
        blockedConversationIdsRaw = blocked.sorted().joined(separator: ",")
        if showSuccessAlert {
            showBlockSuccessAlert = true
        }
    }

    private func unblockCurrentConversation() {
        var blocked = Set(blockedConversationIdsRaw.split(separator: ",").map(String.init))
        blocked.remove(conversationId)
        blockedConversationIdsRaw = blocked.sorted().joined(separator: ",")
    }

    private var isBlockedConversation: Bool {
        Set(blockedConversationIdsRaw.split(separator: ",").map(String.init)).contains(conversationId)
    }

    private var userDefaultsSchedulePlaceKey: String {
        "ChatSchedule.lastPlace.\(conversationId)"
    }

    /// 次回練習シートの既定の場所: この会話で最後に送った場所 → マッチング／約束／参加練習会から推定
    private func resolvedDefaultSchedulePlace() -> String {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsSchedulePlaceKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            return saved
        }
        if isPractice {
            if let pid = practiceId,
               let loc = joinedPracticesStore.items.first(where: { $0.practiceId == pid })?.location
                .trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                return loc
            }
            if let loc = joinedPracticesStore.items.first(where: { $0.chatId == conversationId })?.location
                .trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
                return loc
            }
            return ""
        }
        if let loc = partnerMatchStore.lastKnownPlace(peerName: partnerName, conversationId: conversationId)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return loc
        }
        if let loc = matchPromisesStore.items.first(where: { $0.conversationId == conversationId })?.location
            .trimmingCharacters(in: .whitespacesAndNewlines), !loc.isEmpty {
            return loc
        }
        return ""
    }

    private var practiceProposalTopNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("次回練習会の案内が届いています")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                Text("下のメッセージ欄の案内に「参加」「不参加」で回答できます。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiBrandYellow.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.tasukiPrimary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    private func practiceProposalAcceptedStickyBanner(place: String, date: Date) -> some View {
        let when = ChatNextPracticeMessages.proposalLineDateFormatter.string(from: date)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("参加予定の次回練習会です")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.black)
                Text("場所: \(place)\n日時: \(when)\n練習当日までは、このお知らせは上部に表示されたままになります。")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.tasukiMutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tasukiBrandYellow.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.tasukiPrimary.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
    }

    private func sendScheduleProposal(place: String, date: Date) {
        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: userDefaultsSchedulePlaceKey)
        let when = ChatNextPracticeMessages.proposalLineDateFormatter.string(from: date)
        let body = "\(ChatNextPracticeMessages.proposalPrefix)\n場所: \(trimmed)\n日時: \(when)"
        let newMessage = ChatMessage(
            text: body,
            isFromMe: true,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)
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
    
    // MARK: - Message Bubble + swipe to reply（バブルがオブジェクトのように横移動）
    private func messageBubbleWithSwipe(message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.isFromMe {
                Spacer(minLength: 60)
            }

            SwipeToReplyContainer(onReply: { replyingTo = message }) {
                Group {
                    if !message.isFromMe, ChatNextPracticeMessages.isProposalBody(message.text) {
                        incomingNextPracticeProposalCard(message: message)
                    } else {
                        defaultMessageBubble(message: message)
                    }
                }
            }

            if !message.isFromMe {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private func defaultMessageBubble(message: ChatMessage) -> some View {
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
    }

    private func incomingNextPracticeProposalCard(message: ChatMessage) -> some View {
        let choice = practiceProposalChoiceByMessageId[message.id]
        let detailLines = message.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .dropFirst()
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                Text("次回練習会の案内")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
            }

            if let name = message.senderName, !name.isEmpty {
                Text("\(name)さんから届きました")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText)
            }

            Text(detailLines.isEmpty ? message.text : detailLines)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.black.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            if let choice {
                HStack(spacing: 8) {
                    Image(systemName: choice == .attending ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(choice == .attending ? Color.tasukiPrimary : Color.tasukiMutedText)
                    Text(choice == .attending ? "参加で回答しました" : "不参加で回答しました")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 10) {
                    Button {
                        respondToPracticeProposal(message, attending: true)
                    } label: {
                        Text("参加")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.tasukiPrimaryButtonFill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Button {
                        respondToPracticeProposal(message, attending: false)
                    } label: {
                        Text("不参加")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.tasukiDarkCardSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .disabled(isBlockedConversation)
                .opacity(isBlockedConversation ? 0.45 : 1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiBrandYellow.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.tasukiPrimary.opacity(0.35), lineWidth: 1.5)
        )
        .onAppear {
            guard practiceProposalChoiceByMessageId[message.id] == nil else { return }
            PendingNextPracticeReplyStore.shared.register(conversationId: conversationId, messageId: message.id)
            let peer = message.senderName ?? partnerName
            TasukiLocalNotifications.notifyNextPracticeProposalIfUnposted(peerName: peer, messageId: message.id)
        }
    }

    private func respondToPracticeProposal(_ proposal: ChatMessage, attending: Bool) {
        guard !isBlockedConversation else { return }
        guard practiceProposalChoiceByMessageId[proposal.id] == nil else { return }
        PendingNextPracticeReplyStore.shared.clear(conversationId: conversationId, messageId: proposal.id)
        practiceProposalChoiceByMessageId[proposal.id] = attending ? .attending : .declining
        if attending {
            recordAcceptedPracticeProposalOnCalendar(proposal)
        }
        let line = attending ? ChatNextPracticeMessages.attendingReplyLine : ChatNextPracticeMessages.decliningReplyLine
        messages.append(
            ChatMessage(
                text: line,
                isFromMe: true,
                senderName: isPractice ? myName : nil
            )
        )
    }

    /// 「参加」時にホームのカレンダー（参加予定 or マッチ約束）へ反映
    private func recordAcceptedPracticeProposalOnCalendar(_ proposal: ChatMessage) {
        guard let parsed = ChatNextPracticeMessages.parseProposalPlaceAndDate(proposal.text) else { return }
        let syntheticPracticeId = "\(practiceId ?? "chat-\(conversationId)")-proposal-\(proposal.id)"
        let rowId = "next-practice-\(conversationId)-\(proposal.id)"
        if isPractice {
            joinedPracticesStore.add(
                JoinedPracticeItem(
                    id: rowId,
                    practiceId: syntheticPracticeId,
                    title: partnerName,
                    location: parsed.place,
                    date: parsed.date,
                    chatId: conversationId
                ),
                postJoinNotification: false
            )
        } else {
            matchPromisesStore.add(
                MatchPromiseItem(
                    id: rowId,
                    title: "次回練習・\(partnerName)",
                    date: parsed.date,
                    location: parsed.place,
                    conversationId: conversationId
                )
            )
        }
    }
    
    private var inputAreaView: some View {
        HStack(spacing: 10) {
            TextField("メッセージを入力", text: $messageText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(.systemGray6))
                )
                .focused($isTextFieldFocused)

            Button {
                showPracticeScheduleSheet = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.tasukiPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .strokeBorder(Color.tasukiPrimary.opacity(0.35), lineWidth: 1.5)
                            .background(Circle().fill(Color.tasukiPrimary.opacity(0.08)))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("次回の練習の日程調整")

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
        .disabled(isBlockedConversation)
        .opacity(isBlockedConversation ? 0.45 : 1)
    }
    
    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let replyId = replyingTo?.id
        let newMessage = ChatMessage(
            text: trimmed,
            isFromMe: true,
            replyToMessageId: replyId,
            senderName: isPractice ? myName : nil
        )
        messages.append(newMessage)
        messageText = ""
        replyingTo = nil
        isTextFieldFocused = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if ChatNextPracticeMessages.isPracticeAnswerLine(trimmed) {
                return
            }
            let replyMessage = ChatMessage(
                text: "ありがとうございます！",
                isFromMe: false,
                replyToMessageId: nil,
                senderName: isPractice ? "Kenji_Run" : nil
            )
            messages.append(replyMessage)
        }
    }
    
    private func submitReport(category: String, detail: String?) {
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

        let demoPracticeProposalDay = cal.date(byAdding: .day, value: 10, to: now) ?? now
        let demoPracticeProposalAt = cal.date(bySettingHour: 6, minute: 30, second: 0, of: demoPracticeProposalDay) ?? demoPracticeProposalDay
        let demoPracticeWhenLine = ChatNextPracticeMessages.proposalLineDateFormatter.string(from: demoPracticeProposalAt)
        let demoPartnerProposalDay = cal.date(byAdding: .day, value: 12, to: now) ?? now
        let demoPartnerProposalAt = cal.date(bySettingHour: 7, minute: 0, second: 0, of: demoPartnerProposalDay) ?? demoPartnerProposalDay
        let demoPartnerWhenLine = ChatNextPracticeMessages.proposalLineDateFormatter.string(from: demoPartnerProposalAt)

        if isPractice {
            messages = [
                ChatMessage(id: "dummy-p1", text: "集合は噴水前です。5分前には集まってください！", isFromMe: false, timestamp: hourAgo(2), senderName: "Kenji_Run"),
                ChatMessage(id: "dummy-p2", text: "了解です！", isFromMe: true, timestamp: hourAgo(2), senderName: myName),
                ChatMessage(id: "dummy-p3", text: "よろしくお願いします！", isFromMe: false, timestamp: hourAgo(1), senderName: "さっちゃん"),
                ChatMessage(id: "dummy-p4", text: "ペースは6:30/kmでゆっくり行きましょう。", isFromMe: false, timestamp: minAgo(45), senderName: "Kenji_Run"),
                ChatMessage(id: "dummy-p5", text: "お願いします！", isFromMe: true, timestamp: minAgo(30), senderName: myName),
                ChatMessage(
                    id: "dummy-p-proposal",
                    text: "\(ChatNextPracticeMessages.proposalPrefix)\n場所: 皇居外苑\n日時: \(demoPracticeWhenLine)",
                    isFromMe: false,
                    timestamp: minAgo(8),
                    senderName: "Kenji_Run"
                ),
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
                ChatMessage(
                    id: "dummy-proposal-sample",
                    text: "\(ChatNextPracticeMessages.proposalPrefix)\n場所: 代々木公園（ケヤキ並木付近）\n日時: \(demoPartnerWhenLine)",
                    isFromMe: false,
                    timestamp: minAgo(6),
                    senderName: nil
                ),
            ]
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(conversationId: "preview-1", partnerName: "Kenji_Run")
            .environmentObject(TabBarVisibility())
            .environmentObject(JoinedPracticesStore())
            .environmentObject(PartnerMatchRequestsStore.shared)
            .environmentObject(MatchPromisesStore())
            .environmentObject(PracticeRecruitmentsStore.shared)
    }
}
