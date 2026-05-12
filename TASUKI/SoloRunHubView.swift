//
//  SoloRunHubView.swift
//  TASUKI
//
//  一人で走る: Run（記録）と Time Trial（タイムトライアル）をまとめたハブ画面
//

import SwiftUI

struct SoloRunHubView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.tasukiDarkBackground
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Text("SOLO RUN MODE")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.2)
                            .foregroundColor(Color.tasukiMutedText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 8)
                            .padding(.bottom, 12)

                        VStack(spacing: 0) {
                            NavigationLink(destination: RunRecordingView()) {
                                TasukiFlatHubRow(title: "RUN", subtitle: "走行を記録して保存", systemImage: "figure.run")
                            }
                            .buttonStyle(.plain)

                            NavigationLink(destination: TimeTrialEntryView()) {
                                TasukiFlatHubRow(title: "TIME TRIAL", subtitle: "距離を選んで同ランクと競う", systemImage: "stopwatch.fill")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 20)

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Run")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(Color.tasukiPrimary)
                }
            }
        }
    }
}

#Preview {
    SoloRunHubView()
}
