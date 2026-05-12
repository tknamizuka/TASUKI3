import SwiftUI
import UIKit

/// Find などから開く他ユーザープロフィール（`MyProfileView` と同じ項目構成）。
struct UserProfileDetailView: View {
    let user: User
    private let activityChartPoints: [WeeklyActivityChartPoint]
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
            NavigationLink {
                MatchingRequestComposeView(recipient: user)
            } label: {
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
    }
}

#Preview {
    NavigationStack {
        UserProfileDetailView(user: mockUsers[0])
    }
    .environmentObject(PartnerMatchRequestsStore.shared)
}
