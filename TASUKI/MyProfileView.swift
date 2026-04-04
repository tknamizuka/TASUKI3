import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct MyProfileView: View {
    @AppStorage("myName") private var name: String = "Hiro"
    @AppStorage("myArea") private var area: String = "Tokyo, Setagaya"
    @AppStorage("myRank") private var rank: String = "Rank A"
    @AppStorage("myPurpose") private var purpose: String = "サブ3, 健康維持"
    @AppStorage("myRunningSpots") private var runningSpots: String = "皇居, 代々木公園"
    @AppStorage("mySchedule") private var schedule: String = "平日夜, 土日午前"
    @AppStorage("myPersonalBest") private var personalBest: String = "Full 3:10:00"
    @AppStorage("myTargetTime") private var targetTime: String = "Full 2:59:00"
    @AppStorage("myNextRace") private var nextRace: String = "東京マラソン2026"
    @AppStorage("myAvgPace") private var avgPace: String = "5:30/km"
    @AppStorage("myMonthlyDist") private var monthlyDist: String = "150km"
    @AppStorage("myTotalPoints") private var myTotalPoints: Int = 0
    @AppStorage("myBio") private var bio: String = "平日は仕事終わりに5-10km走ってます！週末は距離走やりたいです。"

    @State private var userUUID: String = ""
    @State private var showCopiedToast: Bool = false
    @ObservedObject private var activityStore = RunActivityStore.shared

    private var myBadgeTier: PointBadgeTier? {
        PointBadgeHelper.tier(forTotalPoints: myTotalPoints)
    }

    private var runningSpotTags: [String] {
        runningSpots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                            .padding(.bottom, 28)
                        activitySection
                            .padding(.bottom, 28)
                        statsSection
                            .padding(.bottom, 28)
                        profileSection
                            .padding(.bottom, 28)
                        aboutSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Me")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.black)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: ProfileEditView()) {
                        Image(systemName: "pencil")
                            .foregroundColor(.black)
                    }
                }
            }
            .task { loadUserUUID() }
            .overlay(alignment: .top) {
                if showCopiedToast {
                    Text("UUIDをコピーしました")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.8)))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                        .transition(.opacity)
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 96))
                .foregroundColor(.black)
                .frame(width: 140, height: 140)

            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.black)
                if let tier = myBadgeTier {
                    HStack(spacing: 4) {
                        Image(systemName: tier.iconName)
                        Text(tier.displayName)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black)
                }
            }

            Text(rank)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.black)

            HStack(spacing: 5) {
                Text("保有ポイント")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.black)
                Text("\(PointService.shared.currentTotalPoints())pt")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black)
            }

            HStack(spacing: 8) {
                Text(userUUID.isEmpty ? "—" : userUUID)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    guard !userUUID.isEmpty else { return }
                    UIPasteboard.general.string = userUUID
                    withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) { showCopiedToast = false }
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .foregroundColor(.black)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("RUNNING STATS")

            HStack(spacing: 12) {
                statItem(title: "Avg Pace", value: avgPace)
                statItem(title: "Monthly Dist", value: monthlyDist)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .font(.system(size: 14, weight: .bold))
                .tracking(1.1)
                .foregroundColor(.black)

            HStack(spacing: 14) {
                graphStatActivity(title: "今週距離", value: String(format: "%.1f km", weeklyDistanceKm()))
                graphStatActivity(title: "今週回数", value: "\(activityStore.weeklyRunCount()) 回")
                graphStatActivity(title: "今月距離", value: String(format: "%.1f km", activityStore.monthlyDistanceKm()))
            }

            WeeklyActivityLineChart(points: weeklyActivityPoints)
                .frame(height: 190)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionEyebrow("PROFILE")

            HStack {
                Image(systemName: "mappin.and.ellipse")
                Text(area)
            }
            .font(.subheadline)
            .foregroundColor(.black)

            if !purpose.isEmpty {
                tagView(text: purpose, isPrimary: true)
            }

            if !runningSpotTags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(runningSpotTags, id: \.self) { spot in
                        tagView(text: spot, isPrimary: false)
                    }
                }
            }

            VStack(spacing: 0) {
                infoRow(icon: "trophy.fill", title: "Personal Best", value: personalBest)
                infoRow(icon: "calendar", title: "Schedule", value: schedule)
                if !nextRace.isEmpty {
                    infoRow(icon: "flag.fill", title: "Next Race", value: nextRace)
                }
                if !targetTime.isEmpty {
                    infoRow(icon: "scope", title: "Target", value: targetTime)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionEyebrow("ABOUT ME")
            Text(bio)
                .font(.system(size: 15))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionEyebrow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.2)
            .foregroundColor(.black)
    }


    private func statItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func graphStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func graphStatActivity(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.black)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weeklyActivityPoints: [WeeklyActivityPoint] {
        let calendar = Calendar.current
        let now = Date()
        let real = weeklyDistances(weeks: 8, calendar: calendar, now: now)
        if real.contains(where: { $0.distanceKm > 0 }) {
            return real
        }

        let fallbackValues: [Double] = [12.0, 18.5, 10.2, 21.3, 16.4, 22.1, 19.8, 24.0]
        return fallbackValues.enumerated().map { index, value in
            let offset = index - (fallbackValues.count - 1)
            let weekStart = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            return WeeklyActivityPoint(
                label: shortWeekLabel(for: weekStart, calendar: calendar),
                distanceKm: value
            )
        }
    }

    private func weeklyDistanceKm() -> Double {
        let calendar = Calendar.current
        let now = Date()
        guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return activityStore.activities
            .filter { weekRange.contains($0.startedAt) }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private func weeklyDistances(weeks: Int, calendar: Calendar, now: Date) -> [WeeklyActivityPoint] {
        (0..<weeks).map { idx in
            let offset = idx - (weeks - 1)
            let targetDate = calendar.date(byAdding: .weekOfYear, value: offset, to: now) ?? now
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: targetDate) else {
                return WeeklyActivityPoint(label: shortWeekLabel(for: targetDate, calendar: calendar), distanceKm: 0)
            }
            let distance = activityStore.activities
                .filter { interval.contains($0.startedAt) }
                .reduce(0) { $0 + $1.distanceKm }
            return WeeklyActivityPoint(
                label: shortWeekLabel(for: targetDate, calendar: calendar),
                distanceKm: distance
            )
        }
    }

    private func shortWeekLabel(for date: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)/\(day)"
    }

    private func tagView(text: String, isPrimary: Bool) -> some View {
        Text(text)
            .font(.system(size: 13, weight: isPrimary ? .semibold : .medium))
            .foregroundColor(.black)
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.black)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    private func loadUserUUID() {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        let db = Firestore.firestore()
        db.collection("users").document(firebaseUser.uid).getDocument { snapshot, _ in
            if let data = snapshot?.data(), let idString = data["id"] as? String {
                DispatchQueue.main.async {
                    self.userUUID = idString
                }
            }
        }
    }

}

private struct WeeklyActivityPoint: Identifiable {
    let id = UUID()
    let label: String
    let distanceKm: Double
}

private struct WeeklyActivityLineChart: View {
    let points: [WeeklyActivityPoint]

    private var maxY: Double {
        max(points.map(\.distanceKm).max() ?? 0, 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let leftPadding: CGFloat = 30
            let bottomPadding: CGFloat = 28
            let topPadding: CGFloat = 10
            let plotWidth = max(1, width - leftPadding)
            let plotHeight = max(1, height - bottomPadding - topPadding)
            let count = max(points.count, 2)

            ZStack {
                ForEach(0..<4, id: \.self) { row in
                    let ratio = CGFloat(row) / 3
                    let y = topPadding + plotHeight * ratio
                    Path { path in
                        path.move(to: CGPoint(x: leftPadding, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                Path { path in
                    guard !points.isEmpty else { return }
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = CGFloat(point.distanceKm / maxY)
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    let lastIndex = points.count - 1
                    let lastX = leftPadding + plotWidth * CGFloat(lastIndex) / CGFloat(count - 1)
                    let firstX = leftPadding
                    let bottomY = topPadding + plotHeight
                    path.addLine(to: CGPoint(x: lastX, y: bottomY))
                    path.addLine(to: CGPoint(x: firstX, y: bottomY))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.tasukiBrandYellow.opacity(0.42),
                            Color.tasukiBrandYellow.opacity(0.14),
                            Color.tasukiBrandYellow.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    for (index, point) in points.enumerated() {
                        let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                        let normalized = CGFloat(point.distanceKm / maxY)
                        let y = topPadding + (1 - normalized) * plotHeight
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.tasukiBrandYellow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let x = leftPadding + plotWidth * CGFloat(index) / CGFloat(count - 1)
                    let normalized = CGFloat(point.distanceKm / maxY)
                    let y = topPadding + (1 - normalized) * plotHeight

                    Circle()
                        .fill(Color.tasukiBrandYellow)
                        .overlay(
                            Circle()
                                .stroke(Color.tasukiOnBrandYellow.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)

                    Text(point.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                        .position(x: x, y: height - 12)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.0fkm", maxY))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                    Spacer()
                    Text("0km")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black)
                }
                .padding(.top, topPadding - 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    MyProfileView()
        .environmentObject(AuthManager())
}
