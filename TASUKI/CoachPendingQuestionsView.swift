//
//  CoachPendingQuestionsView.swift
//  TASUKI
//
//  認定コーチのみ: 未回答の Q&A に返信する。
//

import SwiftUI

struct CoachPendingQuestionsView: View {
    @EnvironmentObject private var coachCertification: CoachCertificationManager
    @ObservedObject private var qaStore = CoachQAStore.shared
    @State private var selectedItem: QAItem?
    @State private var replyDraft: String = ""

    private var respondentName: String {
        let n = coachCertification.coachProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return CoachProfileCatalog.profile(for: "廣 佳樹").name
    }

    var body: some View {
        Group {
            if coachCertification.isCertifiedCoach {
                content
            } else {
                VStack(spacing: 12) {
                    Text("この画面は管理者によってコーチ認定されたアカウントのみ利用できます。")
                        .font(.system(size: 15))
                        .foregroundColor(Color.tasukiPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.tasukiDarkBackground)
            }
        }
        .background(Color.tasukiDarkBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("質問に回答")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Color.tasukiPrimary)
            }
        }
        .sheet(item: $selectedItem) { item in
            coachReplySheet(for: item)
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                if qaStore.pendingQuestions.isEmpty {
                    Text("未回答の質問はありません。")
                        .font(.system(size: 15))
                        .foregroundColor(Color.tasukiMutedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                } else {
                    VStack(spacing: 12) {
                        ForEach(qaStore.pendingQuestions) { item in
                            Button {
                                selectedItem = item
                                replyDraft = ""
                            } label: {
                                pendingRow(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func pendingRow(_ item: QAItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.category)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.tasukiPrimaryButtonFill))
                Spacer()
                Text(shortDate(item.postedDate))
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiMutedText)
            }
            Text(item.question)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color.tasukiPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("質問者: \(item.askerName)")
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiMutedText)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.tasukiMutedText.opacity(0.7))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.tasukiDarkCard)
        )
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }

    private func coachReplySheet(for item: QAItem) -> some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("質問")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.tasukiMutedText)
                        Text(item.question)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiPrimary)

                        Text("回答（\(respondentName)）")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.tasukiMutedText)
                            .padding(.top, 8)

                        TextEditor(text: $replyDraft)
                            .font(.system(size: 16))
                            .foregroundColor(Color.tasukiPrimary)
                            .frame(minHeight: 160)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.tasukiDarkCard))
                    }
                    .padding(20)
                }
            }
            .navigationTitle("回答を入力")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        selectedItem = nil
                    }
                    .foregroundColor(Color.tasukiPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信") {
                        qaStore.submitAnswer(
                            itemId: item.id,
                            answer: replyDraft,
                            coachName: respondentName
                        )
                        selectedItem = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(
                        replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray
                            : Color.tasukiAccentOrange
                    )
                    .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
