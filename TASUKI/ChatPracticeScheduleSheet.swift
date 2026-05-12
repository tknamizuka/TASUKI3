//
//  ChatPracticeScheduleSheet.swift
//  TASUKI
//
//  チャット内「次回の練習」の日程調整（場所・日時）入力シート。
//

import SwiftUI

struct ChatPracticeScheduleSheet: View {
    let initialPlace: String
    let onSend: (String, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var place: String
    @State private var date: Date

    init(initialPlace: String, onSend: @escaping (String, Date) -> Void) {
        self.initialPlace = initialPlace
        self.onSend = onSend
        _place = State(initialValue: initialPlace)
        let defaultDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        _date = State(initialValue: defaultDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("練習場所", text: $place)
                } header: {
                    Text("場所")
                } footer: {
                    Text("前回マッチング時の場所を初期表示しています。必要なら書き換えてください。")
                }

                Section("日時") {
                    DatePicker("開始予定", selection: $date, displayedComponents: [.date, .hourAndMinute])
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                }
            }
            .navigationTitle("次回の練習")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("チャットに送る") {
                        let trimmed = place.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSend(trimmed, date)
                        dismiss()
                    }
                    .disabled(place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
