import SwiftUI

/// 路径数据的最小解析器：只支持绝对坐标的 `M` `L` `Q` `C` `Z`，与网页 `Path2D` 的写法一致。
enum PathParser {
    struct Failure: Error, Equatable {
        var message: String
    }

    static func parse(_ data: String) throws -> Path {
        var path = Path()
        var command: Character?
        var numbers: [Double] = []

        func flush() throws {
            guard let command else {
                if numbers.isEmpty { return }
                throw Failure(message: "数字前缺少命令")
            }
            func point(_ index: Int) -> CGPoint {
                CGPoint(x: numbers[index], y: numbers[index + 1])
            }
            switch command {
            case "M":
                guard numbers.count == 2 else { throw Failure(message: "M 需要 2 个数") }
                path.move(to: point(0))
            case "L":
                guard numbers.count == 2 else { throw Failure(message: "L 需要 2 个数") }
                path.addLine(to: point(0))
            case "Q":
                guard numbers.count == 4 else { throw Failure(message: "Q 需要 4 个数") }
                path.addQuadCurve(to: point(2), control: point(0))
            case "C":
                guard numbers.count == 6 else { throw Failure(message: "C 需要 6 个数") }
                path.addCurve(to: point(4), control1: point(0), control2: point(2))
            case "Z":
                guard numbers.isEmpty else { throw Failure(message: "Z 不带数字") }
                path.closeSubpath()
            default:
                throw Failure(message: "不支持的命令 \(command)")
            }
            numbers = []
        }

        for token in data.split(whereSeparator: { $0 == " " || $0 == "," }) {
            if let number = Double(token) {
                numbers.append(number)
            } else if token.count == 1, let letter = token.first, letter.isLetter {
                try flush()
                command = letter
            } else {
                throw Failure(message: "无法识别 \(token)")
            }
        }
        try flush()
        return path
    }
}
