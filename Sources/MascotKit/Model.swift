import Foundation

/// 数据格式版本。角色与动作 JSON 的 `formatVersion` 必须等于它；格式有不兼容变化时同步加一。
let mascotFormatVersion = 1

/// 二维量，JSON 里写成 `[x, y]`。
struct Vec2: Equatable, Sendable, Codable {
    var x: Double
    var y: Double

    static let zero = Vec2(x: 0, y: 0)
    static let one = Vec2(x: 1, y: 1)

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        x = try container.decode(Double.self)
        y = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }
}

// MARK: - 缓动

/// 离开某个关键帧、走向下一个关键帧时使用的缓动。JSON 里写名称或 `[x1, y1, x2, y2]`，省略为 `inOut`。
enum Easing: Equatable, Sendable, Decodable {
    case hold
    case bezier(Double, Double, Double, Double)

    static let linear = Easing.bezier(0, 0, 1, 1)
    static let easeIn = Easing.bezier(0.42, 0, 1, 1)
    static let easeOut = Easing.bezier(0, 0, 0.58, 1)
    static let easeInOut = Easing.bezier(0.42, 0, 0.58, 1)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            switch name {
            case "hold": self = .hold
            case "linear": self = .linear
            case "in": self = .easeIn
            case "out": self = .easeOut
            case "inOut": self = .easeInOut
            default:
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "未知缓动 \(name)")
            }
            return
        }
        let values = try container.decode([Double].self)
        guard values.count == 4 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "缓动须为四个数")
        }
        self = .bezier(values[0], values[1], values[2], values[3])
    }
}

// MARK: - 关键帧

struct Keyframe<Value: Equatable & Sendable & Decodable>: Equatable, Sendable, Decodable {
    var t: Double
    var v: Value
    var ease: Easing

    private enum CodingKeys: String, CodingKey { case t, v, ease }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        t = try container.decode(Double.self, forKey: .t)
        v = try container.decode(Value.self, forKey: .v)
        ease = try container.decodeIfPresent(Easing.self, forKey: .ease) ?? .easeInOut
    }
}

/// 身体与面部的轨道。未写的轨道取静止值。
struct ClipTracks: Equatable, Sendable, Decodable {
    /// 位移，单位为画布边长的百分之一，向下为正
    var position: [Keyframe<Vec2>]?
    /// 叠加在角色固定倾角上的角度
    var rotation: [Keyframe<Double>]?
    var scale: [Keyframe<Vec2>]?
    /// 挤压量：正值压扁、负值拉长，绕角色的 `squashAnchor`
    var squash: [Keyframe<Double>]?
    /// 视线偏移，单位为角色设计坐标
    var gaze: [Keyframe<Vec2>]?
    /// 眼睑闭合程度 0–1。写了这条轨道的片段不再叠加自然眨眼
    var lids: [Keyframe<Double>]?
    /// 表情名，逐帧切换不插值
    var expression: [Keyframe<String>]
}

/// 附属部件的轨道。未写的轨道取静止值，不透明度静止值为 0（不显示）。
struct AttachmentTracks: Equatable, Sendable, Decodable {
    var opacity: [Keyframe<Double>]?
    var position: [Keyframe<Vec2>]?
    var rotation: [Keyframe<Double>]?
    var scale: [Keyframe<Vec2>]?
}

struct ClipSpec: Equatable, Sendable, Decodable {
    var duration: Double
    var tracks: ClipTracks
    var attachments: [String: AttachmentTracks]?
}

/// 一个状态怎样播放：可选的入场片段播一次，然后循环片段一直播到宿主换状态。
struct StateSpec: Equatable, Sendable, Decodable {
    struct Still: Equatable, Sendable, Decodable {
        var clip: String
        var t: Double
    }

    var enter: String?
    var loop: String
    /// 减弱动态效果、小组件与 Live Activity 使用的静态姿势
    var still: Still
}

struct MotionSpec: Equatable, Sendable, Decodable {
    var formatVersion: Int
    var states: [String: StateSpec]
    var clips: [String: ClipSpec]
}

// MARK: - 角色

/// 一层形状。`fill` 与 `stroke` 写调色板里的颜色名。
struct ShapeLayer: Equatable, Sendable, Decodable {
    enum Kind: String, Sendable, Decodable { case roundedRect, ellipse, path }

    var shape: Kind
    var x: Double?
    var y: Double?
    var w: Double?
    var h: Double?
    var r: Double?
    var cx: Double?
    var cy: Double?
    var rx: Double?
    var ry: Double?
    var d: String?
    var fill: String?
    var stroke: String?
    var lineWidth: Double?
    var opacity: Double?
}

struct ExpressionSpec: Equatable, Sendable, Decodable {
    /// 是否随眼睑与自然眨眼压扁
    var blinks: Bool
    /// 以眼睛中心为原点，两只眼各画一次
    var eye: [ShapeLayer]
    /// 以 `faceCenter` 为原点画一次（嘴等）
    var extras: [ShapeLayer]?
}

struct AttachmentSpec: Equatable, Sendable, Decodable {
    enum Space: String, Sendable, Decodable {
        /// 跟随身体的位移、旋转与挤压
        case body
        /// 只跟随画布，不随身体动
        case canvas
    }

    var space: Space
    var anchor: Vec2
    var layers: [ShapeLayer]
}

struct CharacterSpec: Equatable, Sendable, Decodable {
    struct Palette: Equatable, Sendable, Decodable {
        var light: [String: String]
        var dark: [String: String]
    }

    var formatVersion: Int
    var id: String
    /// 设计坐标的画布边长
    var canvas: Double
    var pivot: Vec2
    var baseRotation: Double
    var squashAnchor: Vec2
    var palette: Palette
    var body: [ShapeLayer]
    var eyes: [Vec2]
    var faceCenter: Vec2
    var expressions: [String: ExpressionSpec]
    var attachments: [String: AttachmentSpec]?
    /// 个别状态改用本角色专属的播放定义
    var states: [String: StateSpec]?
}
