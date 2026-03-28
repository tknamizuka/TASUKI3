import SwiftUI
import UIKit
import FirebaseAuth

struct PracticeDetailView: View {
    // 前の画面から渡されるデータ（画面内でステータスを変えるためStateにする）
    @State var practice: Practice
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var joinedPracticesStore: JoinedPracticesStore
    @State private var showJoinConfirm = false
    
    /// 現在ログイン中のユーザーID（practiceID に紐づく参加者リストの更新に使用）
    private var currentUserId: String? { Auth.auth().currentUser?.uid }
    
    // 練習会限定チャット（ベータ版）
    @State private var chatMessages: [PracticeChatMessage] = [
        PracticeChatMessage(senderName: "主催者", text: "集合は噴水前です。5分前には集まってください！", isMe: false),
        PracticeChatMessage(senderName: "参加者A", text: "よろしくお願いします！", isMe: false)
    ]
    @State private var chatInputText: String = ""
    
    // 主催者を含めた定員と現在数
    var totalMax: Int { practice.maxParticipants }
    var totalCurrent: Int { practice.currentParticipants + 1 } // 主催者1名を常にプラス
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                
                // 1. ヘッダー情報
                VStack(alignment: .leading, spacing: 10) {
                    Text(practice.title)
                        .font(.title)
                        .fontWeight(.heavy)
                        .foregroundColor(Color.tasukiPrimary)
                        .lineLimit(2)
                    
                    HStack(spacing: 15) {
                        Label(practice.date.formatted(date: .numeric, time: .shortened), systemImage: "calendar")
                        Label(practice.location, systemImage: "mappin.and.ellipse")
                    }
                    .font(.subheadline)
                    .foregroundColor(.gray)
                }
                
                Divider()
                
                // 2. スペック・主催者
                HStack(alignment: .top) {
                    // ペース表示
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ペース目安")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(practice.pace)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(Color.tasukiPrimary)
                    }
                    
                    Spacer()
                    
                    // 主催者
                    HStack {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("主催")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(practice.organizer.name)
                                .font(.headline)
                                .fontWeight(.bold)
                        }
                        
                        Image("runner") // アセット名に合わせて変更してください
                            .resizable()
                            .scaledToFill()
                            .frame(width: 45, height: 45)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.tasukiPrimary, lineWidth: 1))
                    }
                }
                
                // 3. 参加状況（ここが心理ハードル対策の肝）
                VStack(alignment: .leading, spacing: 10) {
                    Text("参加状況")
                        .font(.headline)
                        .foregroundColor(Color.tasukiPrimary)
                    
                    // 状況テキスト
                    HStack(alignment: .bottom) {
                        if practice.currentParticipants == 0 {
                            // まだ誰もいない時は「募集中」と出して0を見せない
                            Text("募集中！")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(Color.tasukiPrimary)
                            
                            Text("(あと \(totalMax - 1) 名)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.bottom, 2)
                        } else {
                            // 誰かいたら実数を出す
                            Text("\(totalCurrent)")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundColor(Color.tasukiPrimary)
                            
                            Text("/ \(totalMax) 名")
                                .font(.title3)
                                .foregroundColor(.gray)
                                .padding(.bottom, 4)
                            
                            Spacer()
                            
                            Text("主催者含む")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.bottom, 6)
                        }
                    }
                    
                    // プログレスバー
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // 背景バー
                            RoundedRectangle(cornerRadius: 5)
                                .frame(height: 10)
                                .foregroundColor(Color.gray.opacity(0.1))
                            
                            // 進捗バー
                            let ratio = CGFloat(totalCurrent) / CGFloat(totalMax)
                            RoundedRectangle(cornerRadius: 5)
                                .frame(width: geometry.size.width * ratio, height: 10)
                                .foregroundColor(Color.tasukiPrimary) // TASUKI Navy
                                .animation(.easeOut, value: totalCurrent)
                        }
                    }
                    .frame(height: 10)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                
                // 4. 詳細説明
                VStack(alignment: .leading, spacing: 10) {
                    Text("詳細")
                        .font(.headline)
                        .foregroundColor(Color.tasukiPrimary)
                    
                    Text(practice.description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineSpacing(4)
                }
                
                // 5. 練習会限定チャット（参加者のみ表示）
                if practice.isJoined {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("練習会チャット")
                            .font(.headline)
                            .foregroundColor(Color.tasukiPrimary)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(chatMessages) { message in
                                VStack(alignment: message.isMe ? .trailing : .leading, spacing: 4) {
                                    Text(message.senderName)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    
                                    Text(message.text)
                                        .font(.system(size: 14))
                                        .foregroundColor(message.isMe ? .white : Color.tasukiPrimary)
                                        .padding(10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(message.isMe ? Color.tasukiPrimary : Color.tasukiDarkCardSecondary)
                                        )
                                }
                                .frame(maxWidth: .infinity, alignment: message.isMe ? .trailing : .leading)
                            }
                        }
                        
                        HStack(spacing: 8) {
                            TextField("メッセージを入力", text: $chatInputText)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: {
                                let text = chatInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !text.isEmpty else { return }
                                let newMessage = PracticeChatMessage(senderName: "自分", text: text, isMe: true)
                                chatMessages.append(newMessage)
                                chatInputText = ""
                            }) {
                                Image(systemName: "paperplane.fill")
                                    .foregroundColor(Color.tasukiPrimary)
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("練習会チャット")
                            .font(.headline)
                            .foregroundColor(Color.tasukiPrimary)
                        Text("参加すると、この練習会専用のチャットが利用できるようになります。")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                }
                
                Spacer(minLength: 100) // ボタン分の余白
            }
            .padding()
        }
        .background(Color.tasukiDarkBackground)
        .overlay(alignment: .bottom) {
            // 5. アクションボタン
            Button(action: {
                // タップ時のアクション（モック動作）
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
                
                if practice.isJoined {
                    // 参加済み → 即キャンセル（participantUserIds から自分のIDを削除）
                    if let uid = currentUserId {
                        withAnimation(.spring()) {
                            practice.participantUserIds.removeAll { $0 == uid }
                            practice.isJoined = false
                        }
                        joinedPracticesStore.remove(practiceId: practice.practiceId)
                    }
                } else {
                    // 未参加 → 確認アラートを表示
                    showJoinConfirm = true
                }
            }) {
                Text(practice.isJoined ? "参加をキャンセル" : "参加する")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(practice.isJoined ? .gray : .white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(practice.isJoined ? Color.white : Color.tasukiPrimary)
                    .cornerRadius(30)
                    .shadow(color: practice.isJoined ? .clear : .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 30)
                            .stroke(Color.gray.opacity(0.3), lineWidth: practice.isJoined ? 1 : 0)
                    )
            }
            .padding()
            .background(
                LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            if let uid = currentUserId {
                practice.isJoined = practice.participantUserIds.contains(uid)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.tasukiAccent)
                }
            }
        }
        .alert("参加リクエスト", isPresented: $showJoinConfirm) {
            Button("キャンセル", role: .cancel) { }
            Button("参加する", role: .none) {
                if let uid = currentUserId, !practice.participantUserIds.contains(uid) {
                    withAnimation(.spring()) {
                        practice.participantUserIds.append(uid)
                        practice.isJoined = true
                    }
                    if let cid = practice.chatId {
                        ConversationManager.shared.addParticipantToPracticeChat(conversationId: cid, userId: uid)
                    }
                    joinedPracticesStore.add(JoinedPracticeItem(
                        id: practice.practiceId,
                        practiceId: practice.practiceId,
                        title: practice.title,
                        location: practice.location,
                        date: practice.date,
                        chatId: practice.chatId
                    ))
                }
            }
        } message: {
            Text("この練習会に参加しますか？\n参加すると練習会限定チャットが利用できるようになります。")
        }
    }
}

// MARK: - 練習会チャット用モデル（ベータ版）
struct PracticeChatMessage: Identifiable {
    let id = UUID()
    let senderName: String
    let text: String
    let isMe: Bool
}

// プレビュー用データ
#Preview {
    NavigationView {
        PracticeDetailView(
            practice: Practice(
            practiceId: "preview-practice-1",
            chatId: nil,
            title: "皇居ラン 2周 ゆっくりペース",
            location: "皇居周辺",
            date: Date(),
            category: .jog,
            pace: "6:00 /km",
            distance: "10km",
            description: "朝の皇居をゆっくり走りましょう！初心者の方も大歓迎です。終わった後は近くのカフェでコーヒーでも。",
            organizer: mockUser,
            maxParticipants: 5,
            participantUserIds: [],
            isJoined: false
        ))
        .environmentObject(JoinedPracticesStore())
    }
}
