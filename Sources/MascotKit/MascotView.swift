import SwiftUI

/// 内置角色。每个产品一个，造型与配色都在 Kit 内。
public enum Mascot: String, CaseIterable, Sendable {
    /// MONO 的账本
    case mono
}

/// 角色状态。宿主把自己的业务状态映射到这里。
///
/// 状态按语义预设，用不用由宿主决定。除特别说明外都是循环播放，直到宿主传入别的状态；
/// Kit 不会自己换状态。
public enum MascotState: String, CaseIterable, Sendable {
    /// 待机
    case idle
    /// 登场、打招呼：播一次入场动作，然后与待机相同
    case greeting
    /// 正在听用户输入（语音、打字）
    case listening
    /// 在想，还没开始处理
    case thinking
    /// 正在处理
    case working
    /// 等用户的下一步操作
    case waiting
    /// 成功：播一次入场动作，然后停在完成姿势
    case completed
    /// 失败：播一次入场动作，然后停在失败姿势
    case failed
    /// 开心（达成目标等）
    case happy
    /// 没听懂、需要补充信息：播一次入场动作，然后停在困惑姿势
    case confused
    /// 睡着（长时间无操作、空状态）
    case sleeping
}

/// 会动的角色。
///
/// ```swift
/// MascotView(.mono, state: .working)
///     .frame(width: 44, height: 44)
/// ```
///
/// 尺寸由 `.frame` 决定，深浅色跟随环境。换状态会立即打断当前动作；同一状态重复传入不重播。
/// 开启「减弱动态效果」、App 不在前台，或运行在小组件与 Live Activity 里时显示该状态的静态姿势。
public struct MascotView: View {
    private let character: Mascot
    private let state: MascotState

    @State private var playback: MascotPlayback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    public init(_ character: Mascot, state: MascotState) {
        self.character = character
        self.state = state
        _playback = State(initialValue: MascotPlayback(
            state: state, start: Self.now(), autonomyPhase: Double.random(in: 0 ..< 60)
        ))
    }

    public var body: some View {
        let spec = MascotLibrary.character(character)
        let motion = MascotLibrary.motion
        Group {
            if reduceMotion || scenePhase != .active || Self.isWidgetExtension {
                canvas(MascotEngine.stillPose(
                    of: MascotLibrary.stateSpec(state, character: spec, motion: motion),
                    clips: motion.clips
                ), spec)
            } else {
                TimelineView(.animation) { timeline in
                    canvas(playback.pose(
                        at: timeline.date.timeIntervalSinceReferenceDate,
                        character: spec,
                        motion: motion
                    ), spec)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onChange(of: state) { _, newState in
            playback = playback.switching(to: newState, at: Self.now(), character: spec, motion: motion)
        }
    }

    private func canvas(_ pose: MascotPose, _ spec: CharacterSpec) -> some View {
        let dark = colorScheme == .dark
        return Canvas { context, size in
            MascotRenderer.draw(pose, character: spec, dark: dark, in: &context, size: size)
        }
    }

    private static func now() -> Double {
        Date().timeIntervalSinceReferenceDate
    }

    /// 小组件与 Live Activity 的视图只渲染一帧，不能依赖时间轴。
    private static let isWidgetExtension: Bool = {
        let info = Bundle.main.infoDictionary?["NSExtension"] as? [String: Any]
        return info?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
    }()
}

#Preview("全部状态") {
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(88), spacing: 24), count: 4), spacing: 24) {
        ForEach(MascotState.allCases, id: \.self) { state in
            VStack(spacing: 6) {
                MascotView(.mono, state: state)
                    .frame(width: 88, height: 88)
                Text(state.rawValue).font(.caption)
            }
        }
    }
    .padding(32)
}
