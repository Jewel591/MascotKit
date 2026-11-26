import Foundation

/// 某一时刻角色的完整姿势。渲染只依赖它。
struct MascotPose: Equatable, Sendable {
    struct Attachment: Equatable, Sendable {
        var opacity: Double = 0
        var offset: Vec2 = .zero
        var rotation: Double = 0
        var scale: Vec2 = .one
    }

    var offset: Vec2 = .zero
    var rotation: Double = 0
    var scale: Vec2 = .one
    var squash: Double = 0
    var gaze: Vec2 = .zero
    var lids: Double = 0
    var expression: String
    var attachments: [String: Attachment] = [:]
}

enum MascotEngine {
    // MARK: - 缓动与插值

    /// 三次贝塞尔缓动：给定时间进度 `x`，返回数值进度。
    static func ease(_ easing: Easing, _ x: Double) -> Double {
        switch easing {
        case .hold:
            return 0
        case .bezier(let x1, let y1, let x2, let y2):
            if x <= 0 { return 0 }
            if x >= 1 { return 1 }
            if x1 == y1, x2 == y2 { return x }
            // 二分求参数 u，使贝塞尔的 x 分量等于时间进度
            var low = 0.0
            var high = 1.0
            var u = x
            for _ in 0 ..< 40 {
                let value = cubic(u, x1, x2)
                if abs(value - x) < 1e-10 { break }
                if value < x { low = u } else { high = u }
                u = (low + high) / 2
            }
            return cubic(u, y1, y2)
        }
    }

    private static func cubic(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
        let inverse = 1 - u
        return 3 * inverse * inverse * u * p1 + 3 * inverse * u * u * p2 + u * u * u
    }

    /// 找到 `time` 所在的区间，返回起止关键帧下标与缓动后的进度。
    private static func segment<Value>(_ keys: [Keyframe<Value>], _ time: Double) -> (Int, Int, Double) {
        guard let first = keys.first, time > first.t else { return (0, 0, 0) }
        for index in 1 ..< keys.count where time < keys[index].t {
            let from = keys[index - 1]
            let span = keys[index].t - from.t
            let progress = span > 0 ? (time - from.t) / span : 1
            return (index - 1, index, ease(from.ease, progress))
        }
        return (keys.count - 1, keys.count - 1, 0)
    }

    static func sample(_ keys: [Keyframe<Double>]?, at time: Double, rest: Double) -> Double {
        guard let keys, !keys.isEmpty else { return rest }
        let (from, to, progress) = segment(keys, time)
        return keys[from].v + (keys[to].v - keys[from].v) * progress
    }

    static func sample(_ keys: [Keyframe<Vec2>]?, at time: Double, rest: Vec2) -> Vec2 {
        guard let keys, !keys.isEmpty else { return rest }
        let (from, to, progress) = segment(keys, time)
        return mix(keys[from].v, keys[to].v, progress)
    }

    /// 表情不插值：取 `time` 时刻及之前最近的一个关键帧。
    static func sample(_ keys: [Keyframe<String>], at time: Double) -> String {
        var value = keys.first?.v ?? ""
        for key in keys where key.t <= time {
            value = key.v
        }
        return value
    }

    static func mix(_ a: Double, _ b: Double, _ progress: Double) -> Double {
        a + (b - a) * progress
    }

    static func mix(_ a: Vec2, _ b: Vec2, _ progress: Double) -> Vec2 {
        Vec2(x: mix(a.x, b.x, progress), y: mix(a.y, b.y, progress))
    }

    // MARK: - 片段

    /// 片段在 `time` 时刻的姿势，不含自然眨眼与呼吸。
    static func pose(clip: ClipSpec, at time: Double) -> MascotPose {
        let tracks = clip.tracks
        var pose = MascotPose(expression: sample(tracks.expression, at: time))
        pose.offset = sample(tracks.position, at: time, rest: .zero)
        pose.rotation = sample(tracks.rotation, at: time, rest: 0)
        pose.scale = sample(tracks.scale, at: time, rest: .one)
        pose.squash = sample(tracks.squash, at: time, rest: 0)
        pose.gaze = sample(tracks.gaze, at: time, rest: .zero)
        pose.lids = sample(tracks.lids, at: time, rest: 0)
        for (name, attachment) in clip.attachments ?? [:] {
            pose.attachments[name] = MascotPose.Attachment(
                opacity: sample(attachment.opacity, at: time, rest: 0),
                offset: sample(attachment.position, at: time, rest: .zero),
                rotation: sample(attachment.rotation, at: time, rest: 0),
                scale: sample(attachment.scale, at: time, rest: .one)
            )
        }
        return pose
    }

    /// 状态进入 `elapsed` 秒后正在播放的片段与片段内时间：入场片段播一次，之后循环片段反复播。
    static func phase(of state: StateSpec, clips: [String: ClipSpec], elapsed: Double) -> (clip: ClipSpec, time: Double)? {
        var local = max(0, elapsed)
        if let name = state.enter, let enter = clips[name] {
            if local < enter.duration { return (enter, local) }
            local -= enter.duration
        }
        guard let loop = clips[state.loop] else { return nil }
        let time = loop.duration > 0 ? local.truncatingRemainder(dividingBy: loop.duration) : 0
        return (loop, time)
    }

    static func stillPose(of state: StateSpec, clips: [String: ClipSpec]) -> MascotPose {
        guard let clip = clips[state.still.clip] else { return MascotPose(expression: "") }
        return pose(clip: clip, at: state.still.t)
    }

    // MARK: - 自主行为

    /// 自然眨眼在某一绝对时刻的闭合程度 0–1。
    /// 时间切成等长的格子，每格在由格子序号决定的位置眨一次，约四分之一的格子连眨两下：
    /// 间隔不固定，但同一时刻的结果恒定，不依赖逐帧随机数。
    static func naturalBlink(at time: Double) -> Double {
        let slot = 4.4
        let duration = 0.2
        let index = (time / slot).rounded(.down)
        let local = time - index * slot
        let key = UInt32(truncatingIfNeeded: Int64(index))
        let start = 0.3 + unit(hash(key)) * (slot - 1.2)
        var value = bump(local - start, duration)
        if unit(hash(key ^ 0x9E37_79B9)) < 0.25 {
            value = max(value, bump(local - start - 0.32, duration))
        }
        return value
    }

    private static func bump(_ local: Double, _ duration: Double) -> Double {
        guard local > 0, local < duration else { return 0 }
        return sin(.pi * local / duration)
    }

    /// 32 位整数散列。网页调试台用同一算法（`Math.imul`）。
    static func hash(_ value: UInt32) -> UInt32 {
        var x = value &+ 0x6D2B_79F5
        x = (x ^ (x >> 15)) &* (x | 1)
        x ^= x &+ ((x ^ (x >> 7)) &* (x | 61))
        return x ^ (x >> 14)
    }

    private static func unit(_ value: UInt32) -> Double {
        Double(value) / 4_294_967_296
    }

    /// 呼吸：叠加在挤压量上的小幅起伏。
    static func breath(at time: Double) -> Double {
        0.012 * sin(2 * .pi * time / 3.4)
    }

    /// 在片段姿势上叠加自然眨眼与呼吸。片段自己写了眼睑轨道时不再叠加眨眼。
    static func applyingAutonomy(to pose: MascotPose, clip: ClipSpec, absoluteTime: Double) -> MascotPose {
        var pose = pose
        if clip.tracks.lids == nil {
            pose.lids = max(pose.lids, naturalBlink(at: absoluteTime))
        }
        pose.squash += breath(at: absoluteTime)
        return pose
    }

    // MARK: - 状态切换

    /// 从 `origin` 过渡到 `target`。数值量插值；表情与附属部件直接取新状态。
    static func blend(from origin: MascotPose, to target: MascotPose, progress: Double) -> MascotPose {
        guard progress < 1 else { return target }
        let eased = ease(.easeOut, max(0, progress))
        var pose = target
        pose.offset = mix(origin.offset, target.offset, eased)
        pose.rotation = mix(origin.rotation, target.rotation, eased)
        pose.scale = mix(origin.scale, target.scale, eased)
        pose.squash = mix(origin.squash, target.squash, eased)
        pose.gaze = mix(origin.gaze, target.gaze, eased)
        return pose
    }
}

/// 一次播放：当前状态、它开始的时刻，以及被打断时的姿势（用于过渡）。
struct MascotPlayback: Equatable, Sendable {
    /// 状态切换时数值量的过渡时长
    static let blendDuration = 0.2

    var state: MascotState
    var start: Double
    var origin: MascotPose?
    /// 自然眨眼与呼吸的时间偏移。每个视图取一个不同的值，同屏多个角色才不会齐刷刷地眨眼；换状态时保持不变。
    var autonomyPhase: Double

    init(state: MascotState, start: Double, autonomyPhase: Double = 0) {
        self.state = state
        self.start = start
        self.autonomyPhase = autonomyPhase
    }

    /// `time` 时刻的姿势。`time` 是绝对时间（秒）。
    func pose(at time: Double, character: CharacterSpec, motion: MotionSpec) -> MascotPose {
        let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
        let elapsed = time - start
        guard let (clip, clipTime) = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: elapsed) else {
            return MascotPose(expression: "")
        }
        var pose = MascotEngine.pose(clip: clip, at: clipTime)
        pose = MascotEngine.applyingAutonomy(to: pose, clip: clip, absoluteTime: time + autonomyPhase)
        if let origin {
            pose = MascotEngine.blend(from: origin, to: pose, progress: elapsed / Self.blendDuration)
        }
        return pose
    }

    /// 换到新状态：立即打断当前片段，从当前姿势过渡到新状态，不经过待机。
    func switching(
        to newState: MascotState, at time: Double, character: CharacterSpec, motion: MotionSpec
    ) -> MascotPlayback {
        guard newState != state else { return self }
        var next = MascotPlayback(state: newState, start: time, autonomyPhase: autonomyPhase)
        next.origin = pose(at: time, character: character, motion: motion)
        return next
    }
}
