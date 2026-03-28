//
//  ContentView.swift
//  TASUKI
//
//  Created by yoshi H on 2026/01/28.
//

import SwiftUI

// MARK: - Home View
struct ContentView: View {
    @AppStorage("myMonthlyDist") private var monthlyDistance: String = "0km"
    @AppStorage("runningDataSource") private var runningDataSourceRaw: String = RunningDataSource.all.rawValue
    @State private var currentKilo: Int = 12500
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Base background (White)
                Color.tasukiBase
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                    
                    Spacer()
                    
                    // Main Status Card
                    statusCardView
                        .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Action Area
                    actionButtonView
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
            }
            // HealthKit の権限要求はユーザーアクションで行う（UX向上）
            .onAppear {
                // No automatic HealthKit authorization
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack {
            // ロゴ（TASUKIリレー背景画像 + TASUKIテキスト）
            ZStack {
                // TASUKIリレー背景画像（透過）
                Image("runner")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(.tasukiPrimary)
                    .opacity(0.15)
                    .frame(height: 150)
                
                // TASUKIロゴテキスト（前面）
                Text("TASUKI")
                    .font(.system(size: 40, weight: .semibold, design: .default))
                    .foregroundColor(Color.tasukiPrimary)
                    .tracking(2)
            }
            
            Spacer()
            
            // User Icon (tap to request HealthKit authorization)
            Button(action: {
                // ユーザーが明示的に連携ボタンを押したら権限を要求する
                updateMonthlyDistanceFromHealthKit()
            }) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.tasukiPrimary)
            }
        }
    }
    
    // MARK: - Status Card
    private var statusCardView: some View {
        VStack(spacing: 48) {
            // 今月の走行距離
            VStack(spacing: 8) {
                Text("今月の走行距離")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.tasukiPrimary.opacity(0.5))
                    .tracking(1)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(extractDistanceNumber(from: monthlyDistance))
                        .font(.system(size: 48, weight: .bold, design: .default))
                        .foregroundColor(.tasukiPrimary)
                    
                    Text("km")
                        .font(.system(size: 28, weight: .regular, design: .default))
                        .foregroundColor(.tasukiPrimary.opacity(0.7))
                }
            }
            
            // 保有KILO
            VStack(spacing: 8) {
                Text("保有KILO")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(.tasukiPrimary.opacity(0.5))
                    .tracking(1)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(formatKilo(currentKilo))")
                        .font(.system(size: 36, weight: .semibold, design: .default))
                        .foregroundColor(.tasukiPrimary)
                    
                    Text("k")
                        .font(.system(size: 24, weight: .regular, design: .default))
                        .foregroundColor(.tasukiPrimary.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.tasukiSurface)
        )
    }
    
    // MARK: - Action Button
    private var actionButtonView: some View {
        NavigationLink(destination: PartnerView()) {
            HStack {
                Spacer()
                Text("パートナーを探す")
                    .font(.system(size: 16, weight: .semibold, design: .default))
                    .foregroundColor(.tasukiBase)
                    .tracking(1)
                Spacer()
            }
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.tasukiPrimary)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper
    private var selectedRunningDataSource: RunningDataSource {
        RunningDataSource(rawValue: runningDataSourceRaw) ?? .all
    }

    private func formatKilo(_ kilo: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: kilo)) ?? "\(kilo)"
    }
    
    // 距離文字列から数字部分を抽出（例: "120km" -> "120"）
    private func extractDistanceNumber(from distanceString: String) -> String {
        let cleaned = distanceString.replacingOccurrences(of: "km", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "0" : cleaned
    }

    /// HealthKit から今月の走行距離を取得して `monthlyDistance` に反映
    private func updateMonthlyDistanceFromHealthKit() {
        HealthKitManager.shared.requestAuthorization { success, error in
            guard success else {
                if let error = error {
                    print("HealthKit authorization failed: \(error.localizedDescription)")
                } else {
                    print("HealthKit authorization failed.")
                }
                return
            }
            
            HealthKitManager.shared.fetchRunningDistanceThisMonth(dataSource: selectedRunningDataSource) { result in
                switch result {
                case .success(let kilometers):
                    // 小数1桁までで表示（例: 12.3km）
                    let formatted = String(format: "%.1fkm", kilometers)
                    monthlyDistance = formatted
                case .failure(let error):
                    print("Failed to fetch monthly distance: \(error.localizedDescription)")
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
