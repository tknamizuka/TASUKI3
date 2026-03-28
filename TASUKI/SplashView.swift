import SwiftUI
import AVKit

struct SplashView: View {
    @State private var isVideoVisible = false // ノイズ隠し用のフラグ
    @State private var opacity = 0.0
    
    var body: some View {
        ZStack {
            // 1. 背景色（動画が出るまでのチラつき防止用）
            Color.tasukiDarkBackground
                .ignoresSafeArea()
            
            // 2. 動画プレイヤー（intro_run.mp4 を TASUKI フォルダに追加すると再生されます）
            if let url = Bundle.main.url(forResource: "intro_run", withExtension: "mp4") {
                LoopingVideoPlayer(url: url)
                    .ignoresSafeArea()
                    .opacity(isVideoVisible ? 0.6 : 0) // 最初は隠す
                    .onAppear {
                        // 0.2秒待ってから動画をフワッと表示（ノイズ回避）
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeIn(duration: 0.5)) {
                                isVideoVisible = true
                            }
                        }
                    }
            }
            
            // 3. ロゴ（紫＋ブランド黄のアクセントライン）
            VStack(spacing: 16) {
                Text("TASUKI")
                    .font(.system(size: 60, weight: .heavy))
                    .foregroundColor(Color.tasukiPrimary)
                    .tracking(10)
                    .opacity(opacity)
                Capsule()
                    .fill(Color.tasukiBrandYellow)
                    .frame(width: 120, height: 5)
                    .opacity(opacity)
            }
        }
        .onAppear {
            // ロゴのアニメーション
            withAnimation(.easeIn(duration: 1.5)) {
                opacity = 1.0
            }
        }
    }
}

// MARK: - Looping Video Player (音量ゼロ強制版)
struct LoopingVideoPlayer: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PlayerView {
        return PlayerView(url: url)
    }
    
    func updateUIView(_ uiView: PlayerView, context: Context) {
        // 更新時にも念のためミュート
        uiView.enforceMute()
    }
}

// UIKitベースのプレイヤービュー（細かい制御のため）
class PlayerView: UIView {
    private var playerLooper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    
    init(url: URL) {
        super.init(frame: .zero)
        
        // 1. プレイヤーアイテムの作成
        let item = AVPlayerItem(url: url)
        
        // 2. プレイヤーの作成
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true // ★ミュート
        player.volume = 0.0   // ★音量ゼロ（念には念を）
        
        // 3. ループ設定
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        queuePlayer = player
        
        // 4. レイヤー設定
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(playerLayer)
        
        // 5. 再生開始
        player.play()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.sublayers?.first?.frame = bounds
    }
    
    func enforceMute() {
        queuePlayer?.volume = 0.0
        queuePlayer?.isMuted = true
    }
}

