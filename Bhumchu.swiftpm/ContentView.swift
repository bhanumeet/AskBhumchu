import SwiftUI
import FoundationModels
import AVFoundation
import UIKit
import ImageIO

// MARK: - Looping video (plays only when isPlaying is true); idle = first frame
private final class VideoContainerView: UIView {
    var playerLayer: AVPlayerLayer? { didSet { guard let layer = playerLayer else { return }; layer.frame = bounds; layer.removeFromSuperlayer(); self.layer.addSublayer(layer) } }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

private struct LoopingVideoView: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String
    let isPlaying: Bool

    func makeUIView(context: Context) -> VideoContainerView {
        let view = VideoContainerView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else { return view }
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        queuePlayer.isMuted = false
        queuePlayer.pause()
        let playerLayer = AVPlayerLayer(player: queuePlayer)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = view.bounds
        view.layer.addSublayer(playerLayer)
        view.playerLayer = playerLayer
        context.coordinator.player = queuePlayer
        context.coordinator.playerItem = playerItem
        context.coordinator.looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        context.coordinator.seekToFirstFrameWhenReady(player: queuePlayer, item: playerItem)
        return view
    }

    func updateUIView(_ uiView: VideoContainerView, context: Context) {
        if isPlaying {
            context.coordinator.player?.play()
        } else {
            context.coordinator.player?.pause()
            context.coordinator.player?.seek(to: .zero)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var player: AVQueuePlayer?
        var playerItem: AVPlayerItem?
        var looper: AVPlayerLooper?
        private var didSeekToStart = false
        private var timeObserver: Any?
        private let loopThreshold: Double = 0.15

        func seekToFirstFrameWhenReady(player: AVQueuePlayer, item: AVPlayerItem) {
            item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        }

        override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard keyPath == "status", let item = object as? AVPlayerItem, item.status == .readyToPlay, !didSeekToStart else { return }
            didSeekToStart = true
            item.removeObserver(self, forKeyPath: "status")
            let playerRef = player
            DispatchQueue.main.async {
                playerRef?.seek(to: .zero)
            }
            if let p = player {
                addSeamlessLoopObserver(player: p)
            }
        }

        private func addSeamlessLoopObserver(player: AVQueuePlayer) {
            if let existing = timeObserver {
                player.removeTimeObserver(existing)
            }
            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self, let item = player.currentItem else { return }
                let duration = item.duration
                guard duration.isNumeric, duration.seconds.isFinite, duration.seconds > self.loopThreshold else { return }
                if time.seconds >= duration.seconds - self.loopThreshold {
                    player.seek(to: .zero)
                }
            }
        }

        deinit {
            if let obs = timeObserver, let p = player {
                p.removeTimeObserver(obs)
            }
        }
    }
}

// MARK: - One-shot video (plays once, then calls onComplete); uses a view that sets layer frame in layoutSubviews
private final class OneShotVideoHostView: UIView {
    var playerLayer: AVPlayerLayer? { didSet { guard let layer = playerLayer else { return }; layer.removeFromSuperlayer(); self.layer.addSublayer(layer) } }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}

private struct OneShotVideoView: UIViewRepresentable {
    let resourceName: String
    let fileExtension: String
    let onComplete: () -> Void

    func makeUIView(context: Context) -> OneShotVideoHostView {
        let view = OneShotVideoHostView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension) else {
            DispatchQueue.main.async(execute: onComplete)
            return view
        }
        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        view.playerLayer = layer
        context.coordinator.player = player
        context.coordinator.onComplete = onComplete
        context.coordinator.observeEnd()
        player.play()
        return view
    }

    func updateUIView(_ uiView: OneShotVideoHostView, context: Context) {
        uiView.playerLayer?.frame = uiView.bounds
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var player: AVPlayer?
        var onComplete: (() -> Void)?
        private var observer: NSObjectProtocol?

        func observeEnd() {
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onComplete?()
            }
        }

        deinit {
            observer.map { NotificationCenter.default.removeObserver($0) }
        }
    }
}

// MARK: - Curtain overlay (two panels closing from sides)
private struct CurtainView: View {
    let isClosed: Bool
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.black)
                    .frame(width: isClosed ? w / 2 : 0)
                Spacer(minLength: 0)
                Rectangle()
                    .fill(.black)
                    .frame(width: isClosed ? w / 2 : 0)
            }
            .animation(.easeInOut(duration: 0.55), value: isClosed)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Launch phase: splash (Ask.gif) first, then logo, then starting screen or main
private enum LaunchPhase {
    case splash
    case logoVideo
    case startingTutorial
    case main
}

// MARK: - Animated GIF splash (Ask.gif)
private struct SplashGifView: View {
    let resourceName: String
    let onComplete: () -> Void

    var body: some View {
        AnimatedGifView(resourceName: resourceName, onComplete: onComplete)
            .ignoresSafeArea()
    }
}

private struct AnimatedGifView: UIViewRepresentable {
    let resourceName: String
    let onComplete: () -> Void

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .white
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "gif"),
              let data = try? Data(contentsOf: url),
              let (animatedImage, duration) = Self.decodeGif(data: data) else {
            DispatchQueue.main.async(execute: onComplete)
            return container
        }
        let imageView = UIImageView(image: animatedImage.images?.first)
        imageView.contentMode = .scaleAspectFit
        imageView.animationImages = animatedImage.images
        imageView.animationDuration = duration
        imageView.animationRepeatCount = 1
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        imageView.startAnimating()
        context.coordinator.duration = duration
        context.coordinator.onComplete = onComplete
        context.coordinator.scheduleCompletion()
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var duration: TimeInterval = 2
        var onComplete: (() -> Void)?
        private var workItem: DispatchWorkItem?

        func scheduleCompletion() {
            workItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.onComplete?()
            }
            workItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        }
    }

    private static let maxFrameDelay: TimeInterval = 0.1

    private static func decodeGif(data: Data) -> (UIImage, TimeInterval)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var images: [UIImage] = []
        var totalDuration: TimeInterval = 0
        for i in 0..<count {
            if let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) {
                images.append(UIImage(cgImage: cgImage))
            }
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifDict = props[kCGImagePropertyGIFDictionary as String] as? [String: Any] {
                var delay = (gifDict[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double)
                    ?? (gifDict[kCGImagePropertyGIFDelayTime as String] as? Double)
                    ?? 0.05
                if delay > 0.5 { delay = delay / 100.0 }
                totalDuration += min(delay, maxFrameDelay)
            } else {
                totalDuration += maxFrameDelay
            }
        }
        guard !images.isEmpty else { return nil }
        let duration = max(0.4, totalDuration)
        let animated = UIImage.animatedImage(with: images, duration: duration)
        return animated.map { ($0, duration) }
    }
}

private let hasCompletedTutorialKey = "bhumchu.hasCompletedTutorial"
private let hasCompletedInAppTutorialKey = "bhumchu.hasCompletedInAppTutorial"

private struct TutorialFrames: Equatable {
    var food: CGRect? = nil
    var play: CGRect? = nil
    var read: CGRect? = nil
    var sleep: CGRect? = nil
    var searchBar: CGRect? = nil

    static func merge(_ a: TutorialFrames, _ b: TutorialFrames) -> TutorialFrames {
        TutorialFrames(
            food: a.food ?? b.food,
            play: a.play ?? b.play,
            read: a.read ?? b.read,
            sleep: a.sleep ?? b.sleep,
            searchBar: a.searchBar ?? b.searchBar
        )
    }
}

private struct TutorialFramesPreferenceKey: PreferenceKey {
    static var defaultValue: TutorialFrames { TutorialFrames() }
    static func reduce(value: inout TutorialFrames, nextValue: () -> TutorialFrames) {
        value = TutorialFrames.merge(value, nextValue())
    }
}

// MARK: - Thought cloud (individual frames 1–9); cloud on top of video, text on top of cloud; subtitle-style
private struct CloudOverlayView: View {
    let frameIndex: Int
    let subtitleChunk: String
    let cloudSize: CGFloat

    var body: some View {
        ZStack {
            cloudImage
            if frameIndex == 9 && !subtitleChunk.isEmpty {
                Text(subtitleChunk)
                    .font(cloudTextFont)
                    .italic()
                    .textCase(.uppercase)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, cloudSize * 0.12)
                    .padding(.vertical, cloudSize * 0.1)
                    .frame(width: cloudSize * 0.62, height: cloudSize * 0.68)
                    .clipped()
            }
        }
        .frame(width: cloudSize, height: cloudSize)
        .contentShape(Rectangle())
        .clipped()
        .allowsHitTesting(false)
    }

    private var fontSizeForCloud: CGFloat {
        max(12, min(20, cloudSize * 0.048))
    }

    private var cloudTextFont: Font {
        let size = fontSizeForCloud
        if UIFont(name: "ComicSansMS", size: size) != nil {
            return .custom("ComicSansMS", size: size)
        }
        if UIFont(name: "Comic Sans MS", size: size) != nil {
            return .custom("Comic Sans MS", size: size)
        }
        return .custom("Chalkboard SE", size: size)
    }

    private func cloudImageURL(for index: Int) -> URL? {
        let name = "cloud\(index)"
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "cloud") { return url }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") { return url }
        if let resourceURL = Bundle.main.resourceURL {
            let fileURL = resourceURL.appendingPathComponent("cloud", isDirectory: true).appendingPathComponent("\(name).png")
            if (try? fileURL.checkResourceIsReachable()) == true { return fileURL }
        }
        return nil
    }

    private var cloudImage: some View {
        Group {
            if let uiImage = cloudUIImage() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: cloudSize, height: cloudSize)
            } else {
                RoundedRectangle(cornerRadius: cloudSize * 0.2)
                    .fill(.white.opacity(0.95))
                    .overlay(RoundedRectangle(cornerRadius: cloudSize * 0.2).stroke(.gray.opacity(0.5), lineWidth: 2))
                    .frame(width: cloudSize, height: cloudSize)
            }
        }
    }

    private func cloudUIImage() -> UIImage? {
        if let url = cloudImageURL(for: frameIndex), let data = try? Data(contentsOf: url), let img = UIImage(data: data) { return img }
        return UIImage(named: "cloud\(frameIndex)", in: Bundle.main, with: nil)
            ?? UIImage(named: "cloud/cloud\(frameIndex)", in: Bundle.main, with: nil)
    }
}

// MARK: - First-time intro (two screens about Bhumchu)
private struct TutorialView: View {
    let onComplete: () -> Void

    var body: some View {
        TabView {
            VStack(spacing: 24) {
                Spacer()
                Text("Meet Bhumchu")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("A fluffy little companion who loves to play, eat, and nap — just like you! Take care of Bhumchu and watch him react.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .padding()

            VStack(spacing: 24) {
                Spacer()
                Text("Ask Bhumchu Anything")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Curious about something? Type a question and Bhumchu will answer out loud! He loves chatting with kids about anything — animals, space, stories, you name it.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
                Spacer()
                Button(action: onComplete) {
                    Text("Let's Go!")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 40)
                Spacer().frame(height: 40)
            }
            .padding()
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(.ultraThinMaterial)
    }
}

// MARK: - First-time in-app tutorial overlay (text at each button, no cloud, skippable)
private struct InAppTutorialOverlayView: View {
    let frames: TutorialFrames
    let onComplete: () -> Void
    @State private var step = 0

    private static let steps: [String] = [
        "Meet Bhumchu! Tap him to tickle.",
        "Press this to feed Bhumchu.",
        "Press this to play together.",
        "Press this to hear a story.",
        "Press this to put Bhumchu to sleep.",
        "Ask your question here. Bhumchu will answer out loud!",
        "You're all set! Have fun."
    ]

    private let maxLabelWidth: CGFloat = 260
    private let edgePadding: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let rect = rectForStep(containerSize: size)
            let (posX, posY) = clampedPosition(rect: rect, size: size)

            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { }

                VStack(spacing: 14) {
                    Text(Self.steps[step])
                        .font(.system(size: 17, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: maxLabelWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                    HStack(spacing: 12) {
                        if step < Self.steps.count - 1 {
                            Button("Next") {
                                withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button("Skip") {
                                onComplete()
                            }
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Button("Get started") {
                                onComplete()
                            }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .position(x: posX, y: posY)
            }
        }
        .allowsHitTesting(true)
    }

    private func clampedPosition(rect: CGRect, size: CGSize) -> (CGFloat, CGFloat) {
        let idealY = rect.minY - 50
        let minY: CGFloat = edgePadding + 60
        let maxY: CGFloat = size.height - edgePadding - 60
        let posY = min(max(idealY, minY), maxY)

        let halfW = maxLabelWidth / 2 + 24
        let idealX = rect.midX
        let posX = min(max(idealX, edgePadding + halfW), size.width - edgePadding - halfW)
        return (posX, posY)
    }

    private func rectForStep(containerSize: CGSize) -> CGRect {
        switch step {
        case 0: return CGRect(x: containerSize.width / 2, y: containerSize.height * 0.45, width: 0, height: 0)
        case 1: return frames.food ?? CGRect(x: containerSize.width * 0.2, y: containerSize.height - 220, width: 0, height: 0)
        case 2: return frames.play ?? CGRect(x: containerSize.width * 0.2, y: containerSize.height - 120, width: 0, height: 0)
        case 3: return frames.read ?? CGRect(x: containerSize.width * 0.8, y: containerSize.height - 220, width: 0, height: 0)
        case 4: return frames.sleep ?? CGRect(x: containerSize.width * 0.8, y: containerSize.height - 120, width: 0, height: 0)
        case 5: return frames.searchBar ?? CGRect(x: containerSize.width / 2, y: containerSize.height - 60, width: 0, height: 0)
        default: return CGRect(x: containerSize.width / 2, y: containerSize.height * 0.5, width: 0, height: 0)
        }
    }
}

private final class SpeechDelegate: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    @Published var isSpeaking = false
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) { isSpeaking = true }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) { isSpeaking = false }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) { isSpeaking = false }
}

// MARK: - Character care (hunger, sleep, happiness) – persists locally, decays over time
private final class CharacterCareStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let decayPerMinute: Double = 0.5
    private let lastDecayKey = "bhumchu.lastDecayDate"
    private let hungerKey = "bhumchu.hunger"
    private let sleepKey = "bhumchu.sleep"
    private let happinessKey = "bhumchu.happiness"

    @Published var hunger: Double {
        didSet { defaults.set(hunger, forKey: hungerKey) }
    }
    @Published var sleep: Double {
        didSet { defaults.set(sleep, forKey: sleepKey) }
    }
    @Published var happiness: Double {
        didSet { defaults.set(happiness, forKey: happinessKey) }
    }

    init() {
        let initial = 75.0
        self.hunger = defaults.object(forKey: hungerKey) as? Double ?? initial
        self.sleep = defaults.object(forKey: sleepKey) as? Double ?? initial
        self.happiness = defaults.object(forKey: happinessKey) as? Double ?? initial
    }

    func applyDecay() {
        let now = Date()
        let last = defaults.object(forKey: lastDecayKey) as? Date ?? now
        defaults.set(now, forKey: lastDecayKey)
        let minutes = max(0, now.timeIntervalSince(last) / 60)
        let drop = minutes * decayPerMinute
        hunger = max(0, hunger - drop)
        sleep = max(0, sleep - drop)
        happiness = max(0, happiness - drop)
    }

    func feed() { hunger = min(100, hunger + 25) }
    func sleepCare() { sleep = min(100, sleep + 25) }
    func play() { happiness = min(100, happiness + 25) }
}

@MainActor
struct ContentView: View {
    @State private var question = ""
    @State private var isThinking = false
    @State private var modelAvailable: Bool? = nil
    @State private var session: LanguageModelSession?
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @StateObject private var speechDelegate = SpeechDelegate()
    @StateObject private var characterCare = CharacterCareStore()
    @State private var showingPlayVideo = false
    @State private var showingReadVideo = false
    @State private var showingSleepVideo = false
    @State private var showingEatVideo = false
    @State private var showingTickleVideo = false
    @State private var curtainClosed = false
    @State private var thoughtCloudVisible = false
    @State private var thoughtCloudFrame = 1
    @State private var thoughtCloudChunks: [String] = []
    @State private var thoughtCloudChunkIndex = 0
    @State private var launchPhase: LaunchPhase = .splash
    @AppStorage(hasCompletedTutorialKey) private var hasCompletedTutorial = false
    @AppStorage(hasCompletedInAppTutorialKey) private var hasCompletedInAppTutorial = false
    @State private var tutorialFrames: TutorialFrames = TutorialFrames()
    private let model = SystemLanguageModel.default

    var body: some View {
        Group {
            switch launchPhase {
            case .splash:
                SplashGifView(resourceName: "Ask") {
                    if hasCompletedTutorial {
                        launchPhase = .logoVideo
                    } else {
                        launchPhase = .startingTutorial
                    }
                }
            case .logoVideo:
                OneShotVideoView(resourceName: "bhumchuintro", fileExtension: "mp4") {
                    if hasCompletedTutorial {
                        launchPhase = .main
                    } else {
                        launchPhase = .startingTutorial
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            case .startingTutorial:
                TutorialView {
                    hasCompletedTutorial = true
                    launchPhase = .main
                }
            case .main:
                mainAppContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .all)
        .onAppear {
            if launchPhase == .main {
                checkModelAvailability()
                speechSynthesizer.delegate = speechDelegate
                characterCare.applyDecay()
            }
        }
        .onChange(of: launchPhase) { _, newPhase in
            if newPhase == .main {
                checkModelAvailability()
                speechSynthesizer.delegate = speechDelegate
                characterCare.applyDecay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            if launchPhase == .main { characterCare.applyDecay() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if launchPhase == .main { characterCare.applyDecay() }
        }
    }

    private var mainAppContent: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let cardWidth = min(width - 24, 760)
            Group {
                if let available = modelAvailable {
                    if available {
                        mainContent(maxWidth: cardWidth)
                    } else {
                        unsupportedView(maxWidth: cardWidth)
                    }
                } else {
                    ProgressView()
                        .scaleEffect(1.2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea(edges: .all)
    }

    private func mainContent(maxWidth: CGFloat) -> some View {
        GeometryReader { geo in
            let cloudSize = min(geo.size.width, geo.size.height) * 0.52
            let size = geo.size

            ZStack {
                characterView(size: size)
                    .frame(width: size.width, height: size.height)
                    .ignoresSafeArea(edges: .all)
                overlayUI(size: size, maxWidth: min(maxWidth, size.width))
            }
            .coordinateSpace(name: "tutorial")
            .onPreferenceChange(TutorialFramesPreferenceKey.self) { tutorialFrames = $0 }
            .overlay(alignment: .top) {
                if thoughtCloudVisible {
                    CloudOverlayView(
                        frameIndex: thoughtCloudFrame,
                        subtitleChunk: thoughtCloudChunkIndex < thoughtCloudChunks.count ? thoughtCloudChunks[thoughtCloudChunkIndex] : "",
                        cloudSize: cloudSize
                    )
                    .padding(.top, geo.size.height * 0.06)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .ignoresSafeArea(edges: .all)
        .onChange(of: thoughtCloudVisible) { _, visible in
            if visible && thoughtCloudFrame == 1 {
                runThoughtCloudGrowth()
            }
        }
        .onChange(of: speechDelegate.isSpeaking) { _, speaking in
            if !speaking && thoughtCloudVisible {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    thoughtCloudVisible = false
                    thoughtCloudChunks = []
                    thoughtCloudChunkIndex = 0
                }
            }
        }
        .overlay {
            if !hasCompletedInAppTutorial {
                InAppTutorialOverlayView(frames: tutorialFrames) {
                    hasCompletedInAppTutorial = true
                }
            }
        }
    }

    private func runThoughtCloudGrowth() {
        Task { @MainActor in
            for frame in 2...9 {
                try? await Task.sleep(nanoseconds: 130_000_000)
                thoughtCloudFrame = frame
            }
        }
    }

    private func showFullStatCloud(message: String) {
        thoughtCloudChunks = [message]
        thoughtCloudChunkIndex = 0
        thoughtCloudFrame = 1
        thoughtCloudVisible = true
        Task { @MainActor in
            for frame in 2...9 {
                try? await Task.sleep(nanoseconds: 130_000_000)
                thoughtCloudFrame = frame
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            thoughtCloudVisible = false
            thoughtCloudChunks = []
            thoughtCloudChunkIndex = 0
        }
    }

    private func startSleepSequence() {
        characterCare.sleepCare()
        withAnimation(.easeInOut(duration: 0.55)) { curtainClosed = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            showingSleepVideo = true
            withAnimation(.easeInOut(duration: 0.55)) { curtainClosed = false }
        }
    }

    private func subtitleChunks(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let sentences = trimmed.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var chunks: [String] = []
        let maxWordsPerChunk = 10
        for sentence in sentences {
            let words = sentence.split(separator: " ").map(String.init)
            if words.count <= maxWordsPerChunk, !sentence.isEmpty {
                chunks.append(sentence)
            } else if !words.isEmpty {
                var i = 0
                while i < words.count {
                    let end = min(i + maxWordsPerChunk, words.count)
                    chunks.append(words[i..<end].joined(separator: " "))
                    i = end
                }
            }
        }
        return chunks.isEmpty ? [trimmed] : chunks
    }

    /// Words per second for TTS (rate 0.44 is slightly slower than default).
    private static let subtitleWordsPerSecond: Double = 2.2

    private func chunkStartTimes(for chunks: [String]) -> [TimeInterval] {
        var times: [TimeInterval] = [0]
        for c in chunks {
            let words = c.split(separator: " ").count
            times.append(times.last! + Double(max(1, words)) / Self.subtitleWordsPerSecond)
        }
        return times
    }

    private func startSubtitleAdvance(chunkStartTimes times: [TimeInterval]) {
        guard times.count > 1 else { return }
        let speechStart = Date()
        Task { @MainActor in
            for i in 1..<times.count {
                let delay = times[i] - Date().timeIntervalSince(speechStart)
                if delay > 0.02 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                thoughtCloudChunkIndex = i
            }
        }
    }

    private func characterView(size: CGSize) -> some View {
        let hideIntro = speechDelegate.isSpeaking || showingPlayVideo || showingReadVideo || showingSleepVideo || showingEatVideo || showingTickleVideo
        return ZStack {
            LoopingVideoView(
                resourceName: "bhumchuintro",
                fileExtension: "mp4",
                isPlaying: !hideIntro
            )
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(hideIntro ? 0 : 1)
            .onTapGesture {
                if !showingTickleVideo, !showingSleepVideo, !showingEatVideo, !showingPlayVideo, !showingReadVideo {
                    showingTickleVideo = true
                }
            }

            LoopingVideoView(
                resourceName: "bhumchutalk",
                fileExtension: "mp4",
                isPlaying: speechDelegate.isSpeaking && !showingReadVideo && !showingSleepVideo && !showingEatVideo && !showingTickleVideo
            )
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(speechDelegate.isSpeaking && !showingReadVideo && !showingSleepVideo && !showingEatVideo && !showingTickleVideo ? 1 : 0)

            if showingPlayVideo {
                LoopingVideoView(
                    resourceName: "bhumchuplay",
                    fileExtension: "mp4",
                    isPlaying: true
                )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        showingPlayVideo = false
                    }
                }
            }

            if showingReadVideo {
                LoopingVideoView(
                    resourceName: "bhumchuread",
                    fileExtension: "mp4",
                    isPlaying: true
                )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: speechDelegate.isSpeaking) { _, nowSpeaking in
                    if !nowSpeaking { showingReadVideo = false }
                }
            }

            if showingSleepVideo {
                OneShotVideoView(resourceName: "bhumchusleeping", fileExtension: "mp4") {
                    withAnimation(.easeInOut(duration: 0.55)) { curtainClosed = true }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 550_000_000)
                        showingSleepVideo = false
                        withAnimation(.easeInOut(duration: 0.55)) { curtainClosed = false }
                    }
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showingEatVideo {
                OneShotVideoView(resourceName: "bhumchueat", fileExtension: "mp4") {
                    showingEatVideo = false
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showingTickleVideo {
                OneShotVideoView(resourceName: "bhumchutickle", fileExtension: "mp4") {
                    showingTickleVideo = false
                }
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if showingReadVideo || speechDelegate.isSpeaking {
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: size.width * 0.48, height: size.height * 0.52)
                    .onTapGesture {
                        if showingReadVideo { showingReadVideo = false }
                        if speechDelegate.isSpeaking { speechSynthesizer.stopSpeaking(at: .immediate) }
                    }
            }

            CurtainView(isClosed: curtainClosed)
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clipped()
    }

    private func overlayUI(size: CGSize, maxWidth: CGFloat) -> some View {
        let w = size.width
        let h = size.height
        let padH = max(12, min(24, w * 0.04))
        let padBottom = max(16, min(32, h * 0.028))
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 24) {
                HStack {
                    VStack(spacing: 18) {
                        careButtonWithRing(systemImage: "fork.knife", iconColor: .orange, value: characterCare.hunger, color: .orange, action: {
                            if characterCare.hunger >= 100 {
                                showFullStatCloud(message: "Bhumchu is not hungry right now")
                            } else {
                                characterCare.feed()
                                showingEatVideo = true
                            }
                        })
                        .background(GeometryReader { g in Color.clear.preference(key: TutorialFramesPreferenceKey.self, value: TutorialFrames(food: g.frame(in: .named("tutorial")))) })
                        careButtonWithRing(systemImage: "soccerball", iconColor: .green, value: characterCare.happiness, color: .green, action: {
                            if characterCare.happiness >= 100 {
                                showFullStatCloud(message: "Bhumchu doesn't want to play right now")
                            } else {
                                characterCare.play()
                                showingPlayVideo = true
                            }
                        })
                        .background(GeometryReader { g in Color.clear.preference(key: TutorialFramesPreferenceKey.self, value: TutorialFrames(play: g.frame(in: .named("tutorial")))) })
                    }
                    Spacer()
                    VStack(spacing: 18) {
                        readButton()
                        .background(GeometryReader { g in Color.clear.preference(key: TutorialFramesPreferenceKey.self, value: TutorialFrames(read: g.frame(in: .named("tutorial")))) })
                        careButtonWithRing(systemImage: "bed.double.fill", iconColor: .indigo, value: characterCare.sleep, color: .indigo, action: {
                            if characterCare.sleep >= 100 {
                                showFullStatCloud(message: "Bhumchu is not sleepy right now")
                            } else {
                                startSleepSequence()
                            }
                        })
                        .background(GeometryReader { g in Color.clear.preference(key: TutorialFramesPreferenceKey.self, value: TutorialFrames(sleep: g.frame(in: .named("tutorial")))) })
                    }
                }

                inputBarContent(maxWidth: .infinity)
                .background(GeometryReader { g in Color.clear.preference(key: TutorialFramesPreferenceKey.self, value: TutorialFrames(searchBar: g.frame(in: .named("tutorial")))) })
            }
            .padding(.horizontal, padH)
            .padding(.bottom, padBottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func inputBarContent(maxWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            TextField("", text: $question, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .padding(16)
                .frame(maxWidth: .infinity)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button(action: sendQuestion) {
                Group {
                    if isThinking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .frame(width: 52, height: 52)
                .glassEffect(.clear, in: Circle())
                .foregroundStyle(.white)
            }
            .disabled(isThinking || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(14)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .frame(maxWidth: maxWidth)
    }

    private func careButtonWithRing(systemImage: String, iconColor: Color, value: Double, color: Color, action: @escaping () -> Void) -> some View {
        let progress = min(100, max(0, value)) / 100
        return Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: systemImage)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 78, height: 78)
                    .glassEffect(.clear, in: Circle())
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
    }

    private func readButton() -> some View {
        Button(action: requestStoryAndRead) {
            ZStack {
                Circle()
                    .stroke(Color(red: 1, green: 0.15, blue: 0.15), lineWidth: 6)
                Image(systemName: "book.fill")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(Color(red: 1, green: 0.15, blue: 0.15))
                    .frame(width: 78, height: 78)
                    .glassEffect(.clear, in: Circle())
            }
            .frame(width: 92, height: 92)
        }
        .buttonStyle(.plain)
        .disabled(session == nil || isThinking)
    }

    private func requestStoryAndRead() {
        guard let session else { return }
        showingReadVideo = true
        isThinking = true
        thoughtCloudVisible = true
        thoughtCloudFrame = 1
        thoughtCloudChunks = []
        thoughtCloudChunkIndex = 0
        let prompt = "Narrate a short children's story in one paragraph. Keep it friendly and suitable for kids."
        Task {
            do {
                let response = try await session.respond(to: Prompt(prompt))
                thoughtCloudChunks = subtitleChunks(from: response.content)
                thoughtCloudChunkIndex = 0
                startSubtitleAdvance(chunkStartTimes: chunkStartTimes(for: thoughtCloudChunks))
                speak(text: response.content)
            } catch {
                showingReadVideo = false
                let fallback = "Something went wrong. Try again later."
                thoughtCloudChunks = subtitleChunks(from: fallback)
                thoughtCloudChunkIndex = 0
                startSubtitleAdvance(chunkStartTimes: chunkStartTimes(for: thoughtCloudChunks))
                speak(text: fallback)
            }
            isThinking = false
        }
    }

    private func unsupportedView(maxWidth: CGFloat) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .glassEffect(.clear)
            Text("iOS 26 required")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Apple Intelligence is needed for Bhumchu. Please use a device with iOS 26 or later and turn on Apple Intelligence in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: maxWidth)
        .padding()
    }

    private func checkModelAvailability() {
        switch model.availability {
        case .available:
            modelAvailable = true
            session = LanguageModelSession(model: model)
        default:
            modelAvailable = false
            print("iOS version: \(UIDevice.current.systemVersion)")
        }
    }

    private func sendQuestion() {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        question = ""

        guard let session else { return }

        isThinking = true
        thoughtCloudVisible = true
        thoughtCloudFrame = 1
        thoughtCloudChunks = []
        thoughtCloudChunkIndex = 0

        Task {
            do {
                let response = try await session.respond(to: Prompt(trimmed))
                let spokenAnswer = response.content
                thoughtCloudChunks = subtitleChunks(from: spokenAnswer)
                thoughtCloudChunkIndex = 0
                startSubtitleAdvance(chunkStartTimes: chunkStartTimes(for: thoughtCloudChunks))
                speak(text: spokenAnswer)
            } catch LanguageModelSession.GenerationError.guardrailViolation {
                let fallback = "I can't help with that request. Try asking in a different way."
                thoughtCloudChunks = subtitleChunks(from: fallback)
                thoughtCloudChunkIndex = 0
                startSubtitleAdvance(chunkStartTimes: chunkStartTimes(for: thoughtCloudChunks))
                speak(text: fallback)
            } catch {
                let fallback = "Something went wrong. Try another question."
                thoughtCloudChunks = subtitleChunks(from: fallback)
                thoughtCloudChunkIndex = 0
                startSubtitleAdvance(chunkStartTimes: chunkStartTimes(for: thoughtCloudChunks))
                speak(text: fallback)
            }
            isThinking = false
        }
    }

    private func speak(text: String) {
        speechDelegate.isSpeaking = true
        speakWithAVSpeech(text: text)
    }

    private func speakWithAVSpeech(text: String) {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.44
        utterance.pitchMultiplier = 3
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.04

        if let preferredVoice = bestVoiceForKids() {
            utterance.voice = preferredVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        speechSynthesizer.speak(utterance)
    }

    private func bestVoiceForKids() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        if voices.isEmpty { return nil }

        // Prefer higher-quality voices first, then names that usually sound friendlier.
        let preferredNames = ["siri", "ava", "zoe", "samantha", "karen", "moira"]

        let sorted = voices.sorted { lhs, rhs in
            let lhsPremium = lhs.quality == .premium
            let rhsPremium = rhs.quality == .premium
            if lhsPremium != rhsPremium { return lhsPremium }

            let lhsEnhanced = lhs.quality == .enhanced
            let rhsEnhanced = rhs.quality == .enhanced
            if lhsEnhanced != rhsEnhanced { return lhsEnhanced }

            let lhsName = lhs.name.lowercased()
            let rhsName = rhs.name.lowercased()
            let lhsRank = preferredNames.firstIndex(where: { lhsName.contains($0) }) ?? Int.max
            let rhsRank = preferredNames.firstIndex(where: { rhsName.contains($0) }) ?? Int.max
            if lhsRank != rhsRank { return lhsRank < rhsRank }

            return lhsName < rhsName
        }

        return sorted.first
    }
}

#Preview {
    ContentView()
}
