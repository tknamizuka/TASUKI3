//
//  TasukiBrandedHeroHeader.swift
//  TASUKI
//
//  HomeView と同一のロゴ + 英字タイトル（`.heavy`・トラッキング・白シャドウ）。
//

import SwiftUI
import UIKit

/// Home 画面上部と同じ「TASUKI」系ヒーロータイトル。
/// `compactToolbarStyle` が `true` のときは `TeamView` の EKIDEN ナビタイトルと同じ縮小サイズ（21pt / ロゴ36 / tracking 8）。
struct TasukiBrandedHeroHeader: View {
    let title: String
    /// TeamView `teamToolbarBrandedTitle(.ekiden)` と揃える
    var compactToolbarStyle: Bool = false

    var body: some View {
        Group {
            if compactToolbarStyle {
                HStack(alignment: .center, spacing: 8) {
                    tasukiLogo(size: 36)
                    Text(title)
                        .font(.system(size: 21, weight: .heavy))
                        .tracking(8)
                        .foregroundColor(Color.tasukiPrimary)
                        .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(title)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 12)
            } else {
                GeometryReader { geo in
                    ZStack {
                        HStack(alignment: .center, spacing: 12) {
                            tasukiLogo(size: 84)
                            Text(title)
                                .font(.system(size: 50, weight: .heavy))
                                .tracking(10)
                                .foregroundColor(Color.tasukiPrimary)
                                .shadow(color: .white.opacity(0.8), radius: 2, x: 0, y: 0)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(title)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .frame(height: 136)
                .padding(.top, 20)
            }
        }
    }

    @ViewBuilder
    private func tasukiLogo(size: CGFloat) -> some View {
        if let ui = Self.loadBundledLogoImage() {
            Image(uiImage: ui)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    private static func loadBundledLogoImage() -> UIImage? {
        let base: UIImage?
        if let img = UIImage(named: "logo") {
            base = img
        } else if let path = Bundle.main.path(forResource: "logo", ofType: "png"),
                  let img = UIImage(contentsOfFile: path) {
            base = img
        } else if let path = Bundle.main.path(forResource: "logo", ofType: "jpg"),
                  let img = UIImage(contentsOfFile: path) {
            base = img
        } else {
            base = nil
        }
        guard let base else { return nil }
        return base.tasukiKnockingOutNearWhiteBackground()
    }
}
