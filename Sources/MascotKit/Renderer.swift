import SwiftUI

/// 把一个姿势画进 `GraphicsContext`。变换顺序与网页调试台一致：
/// 画布缩放 → 位移 → 绕 `pivot` 旋转、缩放与立体转动的投影 → 绕 `squashAnchor` 挤压。
enum MascotRenderer {
    /// 眨眼时眼睛保留的最小高度比例，完全压成 0 会让眼睛在一帧里消失
    static let minimumEyeOpen = 0.1
    static func draw(
        _ pose: MascotPose,
        character: CharacterSpec,
        dark: Bool,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let side = min(size.width, size.height)
        let unit = side / character.canvas
        var canvas = context
        canvas.translateBy(x: (size.width - side) / 2, y: (size.height - side) / 2)
        canvas.scaleBy(x: unit, y: unit)
        let palette = dark ? character.palette.dark : character.palette.light

        let projection = MascotEngine.projection(turn: pose.turn, faceTravel: character.faceTravel)
        var body = canvas
        body.translateBy(
            x: pose.offset.x * character.canvas / 100,
            y: pose.offset.y * character.canvas / 100
        )
        transform(&body, about: character.pivot) { inner in
            inner.rotate(by: .degrees(character.baseRotation + pose.rotation))
            inner.scaleBy(x: pose.scale.x * projection.scale.x, y: pose.scale.y * projection.scale.y)
        }
        transform(&body, about: character.squashAnchor) { inner in
            inner.scaleBy(x: pose.squash.x, y: pose.squash.y)
        }

        for layer in character.body {
            draw(layer, palette: palette, in: &body)
        }
        if projection.faceVisible {
            var face = body
            face.translateBy(x: projection.faceOffset.x, y: projection.faceOffset.y)
            drawFace(pose, character: character, palette: palette, in: &face)
        }

        for name in (character.attachments ?? [:]).keys.sorted() {
            guard let spec = character.attachments?[name],
                  let attachment = pose.attachments[name],
                  attachment.opacity > 0
            else { continue }
            var layerContext = spec.space == .body ? body : canvas
            layerContext.translateBy(x: spec.anchor.x + attachment.offset.x, y: spec.anchor.y + attachment.offset.y)
            layerContext.rotate(by: .degrees(attachment.rotation))
            layerContext.scaleBy(x: attachment.scale.x, y: attachment.scale.y)
            layerContext.opacity = min(1, attachment.opacity)
            for layer in spec.layers {
                draw(layer, palette: palette, in: &layerContext)
            }
        }
    }

    private static func drawFace(
        _ pose: MascotPose,
        character: CharacterSpec,
        palette: [String: String],
        in context: inout GraphicsContext
    ) {
        guard let expression = character.expressions[pose.expression] else { return }
        let open = expression.blinks ? max(minimumEyeOpen, 1 - pose.lids) : 1
        for (index, eye) in character.eyes.enumerated() {
            var eyeContext = context
            eyeContext.translateBy(x: eye.x, y: eye.y)
            eyeContext.scaleBy(x: 1, y: open)
            for layer in index == 1 ? expression.rightEye ?? expression.eye : expression.eye {
                draw(layer, palette: palette, in: &eyeContext)
            }
        }
        var extras = context
        extras.translateBy(x: character.faceCenter.x, y: character.faceCenter.y)
        for layer in expression.extras ?? [] {
            draw(layer, palette: palette, in: &extras)
        }
    }

    private static func transform(
        _ context: inout GraphicsContext, about point: Vec2, _ body: (inout GraphicsContext) -> Void
    ) {
        context.translateBy(x: point.x, y: point.y)
        body(&context)
        context.translateBy(x: -point.x, y: -point.y)
    }

    private static func draw(_ layer: ShapeLayer, palette: [String: String], in context: inout GraphicsContext) {
        guard let path = path(for: layer) else { return }
        let opacity = layer.opacity ?? 1
        if let name = layer.fill, let color = color(palette[name]) {
            context.fill(path, with: .color(color.opacity(opacity)))
        }
        if let name = layer.stroke, let color = color(palette[name]) {
            context.stroke(
                path,
                with: .color(color.opacity(opacity)),
                style: StrokeStyle(lineWidth: layer.lineWidth ?? 1, lineCap: .round, lineJoin: .round)
            )
        }
    }

    static func path(for layer: ShapeLayer) -> Path? {
        switch layer.shape {
        case .roundedRect:
            guard let x = layer.x, let y = layer.y, let w = layer.w, let h = layer.h else { return nil }
            return Path(
                roundedRect: CGRect(x: x, y: y, width: w, height: h),
                cornerRadius: layer.r ?? 0,
                style: .continuous
            )
        case .ellipse:
            guard let cx = layer.cx, let cy = layer.cy, let rx = layer.rx, let ry = layer.ry else { return nil }
            return Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        case .path:
            guard let data = layer.d else { return nil }
            return try? PathParser.parse(data)
        }
    }

    /// `#RRGGBB` 转颜色。
    static func color(_ hex: String?) -> Color? {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else {
            return nil
        }
        return Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
