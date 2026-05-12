import SwiftUI
import UIKit

/// Find などから開く他ユーザープロフィール（`MyProfileView` と同じ項目構成の公開ビュー）。
struct UserProfileDetailView: View {
    let user: User
    private let activityChartPoints: [WeeklyActivityChartPoint]
    @State private var showInviteComposer = false
    @State private var showRequestSent = false
    @Environment(\.dismiss) private var dismiss

    init(user: User, activityChartPoints: [WeeklyActivityChartPoint]? = nil) {
        self.user = user
        self.activityChartPoints = activityChartPoints ?? FindMockWeeklyActivity.chartPoints(for: user)
    }

    var body: some View {
        ZStack {
            Color.tasukiDarkBackground
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    UserPublicProfileScrollContent(
                        user: user,
                        activityChartPoints: activityChartPoints,
                        heroAccessory: .findMatchRate(user.matchRate)
                    )
                    .padding(.bottom, 100)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Profile")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .overlay(alignment: .bottom) {
            Button(action: {
                showInviteComposer = true
            }) {
                Text("マッチングのリクエストを送る")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(Color.tasukiOnBrandYellow)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.tasukiPrimaryButtonFill)
                    .cornerRadius(30)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.tasukiDarkBackground.opacity(0), Color.tasukiDarkBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
            )
        }
        .sheet(isPresented: $showInviteComposer) {
            MatchInviteComposerSheet(
                navigationTitle: "マッチング招待",
                submitLabel: "送る",
                onSubmit: { _ in
                    showRequestSent = true
                }
            )
        }
        .alert("送信完了", isPresented: $showRequestSent) {
            Button("OK") { }
        } message: {
            Text("\(user.name)さんにマッチングの招待（日時・場所付き）を送りました。")
        }
    }
}

#Preview {
    NavigationStack {
        UserProfileDetailView(user: mockUsers[0])
    }
}
