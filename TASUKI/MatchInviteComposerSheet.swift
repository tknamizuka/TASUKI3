import SwiftUI

struct MatchInvitePayload {
    let message: String
    let location: String
    let runDate: Date
    let weeklyRepeat: Bool
    var recurrenceWeekday: Int? {
        guard weeklyRepeat else { return nil }
        return Calendar.current.component(.weekday, from: runDate)
    }
}

/// マッチング招待・日程カウンター・チャット内の次回提案で共通利用
struct MatchInviteComposerSheet: View {
    let navigationTitle: String
    let submitLabel: String

    @Environment(\.dismiss) private var dismiss

    @State private var message: String
    @State private var location: String
    @State private var runDate: Date
    @State private var weeklyRepeat: Bool

    private let onSubmit: (MatchInvitePayload) -> Void

    init(
        navigationTitle: String,
        submitLabel: String,
        initialMessage: String = "",
        initialLocation: String = "",
        initialRunDate: Date = Date(),
        initialWeeklyRepeat: Bool = false,
        onSubmit: @escaping (MatchInvitePayload) -> Void
    ) {
        self.navigationTitle = navigationTitle
        self.submitLabel = submitLabel
        _message = State(initialValue: initialMessage)
        _location = State(initialValue: initialLocation)
        _runDate = State(initialValue: initialRunDate)
        _weeklyRepeat = State(initialValue: initialWeeklyRepeat)
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("日時", selection: $runDate)
                    Toggle("毎週同じ曜日・時刻", isOn: $weeklyRepeat)
                }
                Section("場所") {
                    TextField("集合場所", text: $location)
                }
                Section("メッセージ") {
                    TextField("メッセージ", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(submitLabel) {
                        let payload = MatchInvitePayload(
                            message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            runDate: runDate,
                            weeklyRepeat: weeklyRepeat
                        )
                        onSubmit(payload)
                        dismiss()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
