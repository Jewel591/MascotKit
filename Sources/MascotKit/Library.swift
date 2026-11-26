import Foundation

/// 包内角色与动作数据的读取入口。数据只在首次使用时解码一次。
enum MascotLibrary {
    static let motion: MotionSpec = load("motion", subdirectory: "Resources")

    private static let characters: [Mascot: CharacterSpec] = Dictionary(
        uniqueKeysWithValues: Mascot.allCases.map { mascot in
            (mascot, load(mascot.rawValue, subdirectory: "Resources/characters") as CharacterSpec)
        }
    )

    static func character(_ mascot: Mascot) -> CharacterSpec {
        // 字典由 `Mascot.allCases` 构建，每个角色必有一项
        characters[mascot]!
    }

    /// 角色对某个状态有专属定义时用专属的，否则用全角色共用的。
    static func stateSpec(_ state: MascotState, character: CharacterSpec, motion: MotionSpec) -> StateSpec {
        if let own = character.states?[state.rawValue] { return own }
        // 包内数据的完整性由单元测试保证：每个状态必有定义
        return motion.states[state.rawValue]!
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }

    /// 包内数据损坏属于构建产物错误，直接终止，不静默画出空白角色。
    private static func load<Value: Decodable>(_ name: String, subdirectory: String) -> Value {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdirectory) else {
            preconditionFailure("MascotKit 缺少资源 \(subdirectory)/\(name).json")
        }
        do {
            return try decode(Value.self, from: Data(contentsOf: url))
        } catch {
            preconditionFailure("MascotKit 资源 \(name).json 解码失败：\(error)")
        }
    }
}
