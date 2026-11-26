import SwiftUI

/// 内置角色。每个产品一个，造型与配色都在 Kit 内。
public enum Mascot: String, CaseIterable, Sendable {
    /// MONO 的账本
    case mono
}

/// 角色状态。宿主把自己的业务状态映射到这里。
///
/// - `idle` 与 `working` 一直循环。
/// - `completed` 与 `failed` 先播一次入场动作，然后停在各自的姿势上，直到宿主传入别的状态；
///   Kit 不会自己回到 `idle`。
public enum MascotState: String, CaseIterable, Sendable {
    case idle
    case working
    case completed
    case failed
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
        _playback = State(initialValue: MascotPlayback(state: state, start: Self.now()))
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

#Preview("四种状态") {
    HStack(spacing: 24) {
        ForEach(MascotState.allCases, id: \.self) { state in
            MascotView(.mono, state: state)
                .frame(width: 88, height: 88)
        }
    }
    .padding(32)
}
