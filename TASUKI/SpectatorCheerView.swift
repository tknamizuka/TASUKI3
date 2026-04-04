//
//  SpectatorCheerView.swift
//  TASUKI
//
//  沿道・観客向け応援投稿（postSpectatorCheer Callable）
//

import SwiftUI
import FirebaseAuth
import FirebaseFunctions

enum SpectatorCheerClientInstance {
    private static let defaultsKey = "spectatorCheerClientInstanceId"

    /// 未ログイン時のレート制限キー用。端末に保存した UUID
    static var value: String {
        if let existing = UserDefaults.standard.string(forKey: defaultsKey), !existing.isEmpty {
            return existing
        }
        let u = UUID().uuidString
        UserDefaults.standard.set(u, forKey: defaultsKey)
        return u
    }
}

struct SpectatorCheerView: View {
    let eventId: String
    let teamId: String
    var teamName: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var nickname: String = ""
    @State private var message: String = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var didSucceed = false

    private var functions: Functions {
        Functions.functions(region: "asia-northeast1")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    Text(teamName.isEmpty ? "チームを応援" : "「\(teamName)」を応援")
                        .font(.headline)
                        .foregroundColor(Color.tasukiPrimary)
                    Text("メッセージはチームメンバーの駅伝画面に表示されます。")
                        .font(.footnote)
                        .foregroundColor(Color.tasukiMutedText)

                    TextField("呼ばれ方（任意）", text: $nickname)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiDarkCardSecondary))
                        .foregroundColor(Color.tasukiPrimary)

                    TextField("応援メッセージ", text: $message, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.tasukiDarkCardSecondary))
                        .foregroundColor(Color.tasukiPrimary)

                    if let err = errorText {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red.opacity(0.9))
                    }

                    if didSucceed {
                        Text("送信しました。ありがとうございます！")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(Color(hex: "34C759"))
                    }

                    Spacer(minLength: 0)

                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending {
                                ProgressView()
                                    .tint(Color.tasukiOnBrandYellow)
                            } else {
                                Text("応援を送る")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color.tasukiOnBrandYellow)
                            }
                            Spacer()
                        }
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiPrimaryButtonFill))
                    }
                    .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationTitle("沿道応援")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
    }

    private func send() async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        errorText = nil
        didSucceed = false
        defer { isSending = false }

        var payload: [String: Any] = [
            "eventId": eventId,
            "teamId": teamId,
            "message": trimmed,
            "nickname": nickname.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if Auth.auth().currentUser == nil {
            payload["clientInstanceId"] = SpectatorCheerClientInstance.value
        }

        do {
            _ = try await functions.httpsCallable("postSpectatorCheer").call(payload)
            await MainActor.run {
                didSucceed = true
                message = ""
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }
}
