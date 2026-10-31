import AVKit
import SwiftUI

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}

struct VideoPane: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        ZStack(alignment: .bottom) {
            if model.videoURL != nil {
                PlayerView(player: model.player)
                if model.showOverlay, let text = model.activeCueText, !text.isEmpty {
                    Text(text)
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black, radius: 2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                        .padding(.bottom, 64)
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("打开视频（MP4 / MOV / M4V）")
                        .font(.title3)
                    Text("会自动加载同名的 .srt / .vtt 字幕；也可以把文件拖到窗口中")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("打开视频…") { model.presentOpenPanel(kinds: EditorModel.videoExtensions) }
                        Button("打开字幕…") { model.presentOpenPanel(kinds: EditorModel.subtitleExtensions) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
        }
        .background(Color.black.opacity(model.videoURL == nil ? 0.05 : 1))
    }
}
