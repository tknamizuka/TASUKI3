//
//  MatchingRequestComposeView.swift
//  TASUKI
//
//  マッチングリクエスト送信前に場所・日時候補を入力する画面。
//

import SwiftUI

struct MatchingRequestComposeView: View {
    let recipient: User

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var partnerMatchStore: PartnerMatchRequestsStore

    @State private var place: String = ""
    @State private var message: String = ""
    @State private var dateCandidates: [Date] = [Date()]
    @State private var showValidationAlert = false
    @State private var showSentConfirmation = false

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(recipient.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.black)

                    Text("マッチングリクエスト")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.tasukiMutedText)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("場所")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                        TextField("例: 皇居外苑 竹橋口", text: $place)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("日時候補")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.black)
                            Spacer()
                            if dateCandidates.count < 5 {
                                Button("候補を追加") {
                                    dateCandidates.append(Date())
                                }
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color.tasukiPrimary)
                            }
                        }

                        ForEach(Array(dateCandidates.enumerated()), id: \.offset) { index, _ in
                            DatePicker(
                                "候補 \(index + 1)",
                                selection: $dateCandidates[index],
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .labelsHidden()
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("メッセージ（任意）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.black)
                        TextField("一言添えますか？", text: $message, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button(action: submit) {
                        Text("リクエストを送る")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.tasukiOnBrandYellow)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.tasukiPrimaryButtonFill)
                            .cornerRadius(30)
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("リクエスト内容")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .alert("入力を確認してください", isPresented: $showValidationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("場所と、少なくとも1つの日時候補を入力してください。")
        }
        .alert("送信しました", isPresented: $showSentConfirmation) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("\(recipient.name)さんにマッチングリクエストを送りました。")
        }
    }

    private func submit() {
        let trimmedPlace = place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlace.isEmpty, !dateCandidates.isEmpty else {
            showValidationAlert = true
            return
        }
        partnerMatchStore.recordOutgoing(to: recipient, place: trimmedPlace, dates: dateCandidates, message: message)
        showSentConfirmation = true
    }
}

#Preview {
    NavigationStack {
        MatchingRequestComposeView(recipient: mockUsers[0])
            .environmentObject(PartnerMatchRequestsStore.shared)
    }
}
