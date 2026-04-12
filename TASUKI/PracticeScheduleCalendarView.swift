//
//  PracticeScheduleCalendarView.swift
//  TASUKI
//
//  参加予定の練習会をカレンダー形式で表示
//

import SwiftUI

struct PracticeScheduleCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: JoinedPracticesStore
    @ObservedObject var matchPromisesStore: MatchPromisesStore

    @State private var displayedMonth: Date = Date()
    @State private var selectedDay: Date?
    
    private let calendar = Calendar.current
    private let weekdaySymbols: [String] = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ja_JP")
        return cal.shortWeekdaySymbols
    }()
    
    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: displayedMonth)
    }
    
    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth)) else {
            return []
        }
        let firstWeekday = calendar.component(.weekday, from: first)
        let offset = firstWeekday - 1
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let d = calendar.date(byAdding: .day, value: day - 1, to: first) {
                days.append(d)
            }
        }
        return days
    }
    
    /// ストアの参加予定 + サンプルスケジュール（表示用。サンプルもタップで PracticeDetailView → 練習会チャット利用可）
    private var allDisplayItems: [JoinedPracticeItem] {
        let sample = sampleScheduleItems(for: displayedMonth)
        let fromStore = store.items
        let storeIds = Set(fromStore.map(\.practiceId))
        let extraSamples = sample.filter { !storeIds.contains($0.practiceId) }
        return (fromStore + extraSamples).sorted(by: { $0.date < $1.date })
    }

    /// ストアの約束 + 表示用サンプル（練習会サンプルと同様に ID で重複除外）
    private var allMatchDisplayItems: [MatchPromiseItem] {
        let sample = sampleMatchPromises(for: displayedMonth)
        let fromStore = matchPromisesStore.items
        let storeIds = Set(fromStore.map(\.id))
        let extraSamples = sample.filter { !storeIds.contains($0.id) }
        return (fromStore + extraSamples).sorted(by: { $0.date < $1.date })
    }

    private var practicesForSelected: [JoinedPracticeItem] {
        if let day = selectedDay {
            return allDisplayItems.filter { calendar.isDate($0.date, inSameDayAs: day) }
        }
        return allDisplayItems.filter { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }
    }

    private var matchesForSelected: [MatchPromiseItem] {
        if let day = selectedDay {
            return allMatchDisplayItems.filter { calendar.isDate($0.date, inSameDayAs: day) }
        }
        return allMatchDisplayItems.filter { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }
    }

    private enum ScheduleCalendarListEntry: Identifiable {
        case practice(JoinedPracticeItem)
        case match(MatchPromiseItem)

        var id: String {
            switch self {
            case .practice(let p): return "p-\(p.id)"
            case .match(let m): return "m-\(m.id)"
            }
        }

        var sortDate: Date {
            switch self {
            case .practice(let p): return p.date
            case .match(let m): return m.date
            }
        }
    }

    private var entriesForSelected: [ScheduleCalendarListEntry] {
        let p = practicesForSelected.map { ScheduleCalendarListEntry.practice($0) }
        let m = matchesForSelected.map { ScheduleCalendarListEntry.match($0) }
        return (p + m).sorted { $0.sortDate < $1.sortDate }
    }
    
    /// 今月用のサンプルスケジュール（参加予定として表示。タップで詳細→チャット利用可）
    private func sampleScheduleItems(for month: Date) -> [JoinedPracticeItem] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let baseDates: [(Int, String, String)] = [
            (min(5, range.count), "皇居ラン", "皇居周辺"),
            (min(12, range.count), "代々木公園ジョグ", "代々木公園"),
            (min(18, range.count), "神宮外苑ゆっくり走", "神宮外苑"),
            (min(22, range.count), "早朝ラン 5km", "芝公園"),
            (min(28, range.count), "週末ロング走", "多摩川河川敷")
        ]
        return baseDates.compactMap { dayOffset, title, location in
            guard let d = cal.date(byAdding: .day, value: dayOffset - 1, to: start) else { return nil }
            let atNine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: d) ?? d
            // 先頭サンプルのみダミー会話IDを付与（カレンダーからチャット画面への遷移確認用）
            let chatId = (dayOffset == min(5, range.count)) ? "sample-conv-calendar-1" : nil
            return JoinedPracticeItem(
                id: "sample-\(dayOffset)",
                practiceId: "sample-p-\(dayOffset)",
                title: title,
                location: location,
                date: atNine,
                chatId: chatId
            )
        }
    }

    /// 今月用のサンプル約束（マッチング。タップでチャット遷移確認用に conversationId を一部付与）
    private func sampleMatchPromises(for month: Date) -> [MatchPromiseItem] {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: month)),
              let range = cal.range(of: .day, in: .month, for: start) else { return [] }
        let baseDates: [(Int, String, String, String?)] = [
            (min(8, range.count), "Aさんと朝ラン", "代々木公園", "sample-conv-match-1"),
            (min(15, range.count), "週末ペース走", "皇居", nil),
            (min(25, range.count), "朝活ジョグ", "多摩川", "sample-conv-match-2")
        ]
        return baseDates.compactMap { dayOffset, title, location, conv in
            guard let d = cal.date(byAdding: .day, value: dayOffset - 1, to: start) else { return nil }
            let atSeven = cal.date(bySettingHour: 7, minute: 30, second: 0, of: d) ?? d
            return MatchPromiseItem(
                id: "sample-match-\(dayOffset)",
                title: title,
                date: atSeven,
                location: location,
                conversationId: conv
            )
        }
    }

    /// 今月のうち練習会（ストア+サンプル）がある日
    private var datesWithPractices: Set<Date> {
        let inMonth = allDisplayItems.filter { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }
        return Set(inMonth.map { calendar.startOfDay(for: $0.date) })
    }

    /// 今月のうちマッチング約束（ストア+サンプル）がある日
    private var datesWithMatches: Set<Date> {
        let inMonth = allMatchDisplayItems.filter { calendar.isDate($0.date, equalTo: displayedMonth, toGranularity: .month) }
        return Set(inMonth.map { calendar.startOfDay(for: $0.date) })
    }
    
    /// スケジュールの1件から PracticeDetailView 用の Practice を組み立てる
    private func practiceFrom(item: JoinedPracticeItem) -> Practice {
        Practice(
            practiceId: item.practiceId,
            chatId: item.chatId,
            title: item.title,
            location: item.location,
            date: item.date,
            category: .jog,
            pace: "6:00 /km",
            distance: "10km",
            description: "参加予定の練習会です。練習会チャットでやり取りできます。",
            organizer: mockUser,
            maxParticipants: 10,
            participantUserIds: [],
            isJoined: true
        )
    }
    
    private var sectionTitle: String {
        if let day = selectedDay {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "M月d日(E)"
            return f.string(from: day)
        }
        return "今月のスケジュール"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 月ナビ
                HStack {
                    Button {
                        if let prev = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                            displayedMonth = prev
                            selectedDay = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                    Spacer()
                    Text(monthTitle)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.black)
                    Spacer()
                    Button {
                        if let next = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                            displayedMonth = next
                            selectedDay = nil
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                
                // 曜日ヘッダー
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol)
                            .frame(maxWidth: .infinity)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                
                // カレンダーグリッド（黒=練習会、オレンジ=マッチング約束）
                let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, dateOpt in
                        if let date = dateOpt {
                            let dayStart = calendar.startOfDay(for: date)
                            let hasPractice = datesWithPractices.contains(dayStart)
                            let hasMatch = datesWithMatches.contains(dayStart)
                            let isSelected = selectedDay.map { calendar.isDate(date, inSameDayAs: $0) } ?? false
                            dayCell(date: date, hasPractice: hasPractice, hasMatch: hasMatch, isSelected: isSelected)
                        } else {
                            Color.clear
                                .frame(height: 36)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
                
                Divider()
                
                // 選択日 or 今月のリスト（練習会 + マッチング約束）
                VStack(alignment: .leading, spacing: 8) {
                    Text(sectionTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                    
                    if entriesForSelected.isEmpty {
                        Text(selectedDay == nil ? "今月の予定はありません" : "この日の予定はありません")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                    } else {
                        List {
                            ForEach(entriesForSelected) { entry in
                                Group {
                                    switch entry {
                                    case .practice(let item):
                                        VStack(alignment: .leading, spacing: 10) {
                                            NavigationLink(
                                                destination: PracticeDetailView(practice: practiceFrom(item: item))
                                                    .environmentObject(store)
                                            ) {
                                                practiceRow(item, showChatHint: item.chatId != nil)
                                            }

                                            if let cid = item.chatId {
                                                NavigationLink(
                                                    destination: ChatView(
                                                        conversationId: cid,
                                                        partnerName: "練習会: \(item.title)",
                                                        isPractice: true
                                                    )
                                                ) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                                            .font(.system(size: 16))
                                                        Text("練習会チャットを開く")
                                                            .font(.system(size: 15, weight: .semibold))
                                                        Spacer()
                                                        Image(systemName: "chevron.right")
                                                            .font(.system(size: 12, weight: .semibold))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .foregroundColor(Color.tasukiPrimary)
                                                    .padding(.vertical, 4)
                                                }
                                            } else {
                                                Text("練習会チャットは会話作成・参加後に利用できます")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    case .match(let item):
                                        VStack(alignment: .leading, spacing: 10) {
                                            matchRow(item)
                                            if let cid = item.conversationId {
                                                NavigationLink(
                                                    destination: ChatView(
                                                        conversationId: cid,
                                                        partnerName: item.title,
                                                        isPractice: false
                                                    )
                                                ) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: "bubble.left.and.bubble.right.fill")
                                                            .font(.system(size: 16))
                                                        Text("チャットを開く")
                                                            .font(.system(size: 15, weight: .semibold))
                                                        Spacer()
                                                        Image(systemName: "chevron.right")
                                                            .font(.system(size: 12, weight: .semibold))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .foregroundColor(Color.tasukiPrimary)
                                                    .padding(.vertical, 4)
                                                }
                                            } else {
                                                Text("チャットは会話が作成されると利用できます")
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.visible)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.tasukiDarkBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("スケジュール")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.black)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                    .foregroundColor(.black)
                }
            }
        }
    }
    
    private func dayCell(date: Date, hasPractice: Bool, hasMatch: Bool, isSelected: Bool) -> some View {
        let dayNum = calendar.component(.day, from: date)
        let isToday = calendar.isDateInToday(date)
        return Button {
            selectedDay = calendar.startOfDay(for: date)
        } label: {
            VStack(spacing: 4) {
                Text("\(dayNum)")
                    .font(.system(size: 16, weight: isToday ? .bold : .regular))
                    .foregroundColor(.black)
                HStack(spacing: 3) {
                    if hasPractice {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 5, height: 5)
                    }
                    if hasMatch {
                        Circle()
                            .fill(Color.tasukiAccent)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.tasukiBrandYellow.opacity(0.5) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func practiceRow(_ item: JoinedPracticeItem, showChatHint: Bool = false) -> some View {
        let timeStr: String = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: item.date)
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                if showChatHint {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                }
            }
            HStack(spacing: 8) {
                Text(timeStr)
                    .font(.caption)
                    .foregroundColor(.black)
                Text(item.location)
                    .font(.caption)
                    .foregroundColor(.black)
            }
        }
        .padding(.vertical, 8)
    }

    private func matchRow(_ item: MatchPromiseItem) -> some View {
        let timeStr: String = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: item.date)
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color.tasukiAccent)
                Text("マッチング")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.tasukiAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.tasukiAccent.opacity(0.12))
                    )
                Spacer()
                if item.conversationId != nil {
                    Image(systemName: "message.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                }
            }
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
            HStack(spacing: 8) {
                Text(timeStr)
                    .font(.caption)
                    .foregroundColor(.black)
                if !item.location.isEmpty {
                    Text(item.location)
                        .font(.caption)
                        .foregroundColor(.black)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("カレンダー（サンプルあり）") {
    let store = JoinedPracticesStore()
    let matchStore = MatchPromisesStore()
    let cal = Calendar.current
    store.add(JoinedPracticeItem(id: "1", practiceId: "p1", title: "皇居ラン", location: "皇居", date: cal.date(byAdding: .day, value: 2, to: Date())!, chatId: "conv-p1"))
    store.add(JoinedPracticeItem(id: "2", practiceId: "p2", title: "代々木ジョグ", location: "代々木公園", date: cal.date(byAdding: .day, value: 5, to: Date())!, chatId: nil))
    return PracticeScheduleCalendarView(store: store, matchPromisesStore: matchStore)
        .environmentObject(TabBarVisibility())
}
#endif
