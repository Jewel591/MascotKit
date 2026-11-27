# MascotKit

给定角色与状态，画出会动的角色。供作者自己的 Apple App 使用。

```swift
import MascotKit

MascotView(.mono, state: .working)
    .frame(width: 44, height: 44)
```

只有两个参数：内置角色与内置状态。尺寸用 `.frame`，深浅色跟随环境，没有其他配置入口。

## 安装

```swift
.package(url: "https://github.com/Jewel591/MascotKit", from: "0.3.1")
```

iOS 17 / macOS 14 起，Swift 6。

## 状态

| 状态 | 播放方式 |
|---|---|
| `.idle` | 待机，循环 |
| `.greeting` | 登场、打招呼：入场动作播一次，然后与待机相同 |
| `.listening` | 正在听用户输入，循环 |
| `.thinking` | 在想，还没开始处理，循环 |
| `.working` | 正在处理，循环 |
| `.waiting` | 等用户的下一步操作，循环 |
| `.completed` | 成功：入场动作播一次，然后保持开心的待机 |
| `.failed` | 失败：下沉、低头，停在失败姿势 |
| `.happy` | 开心，循环 |
| `.confused` | 没听懂：反复摇头 |
| `.sleeping` | 睡着，循环 |

- 换状态立即打断当前动作，从当前姿势过渡到新状态。
- 同一状态重复传入不重播。
- Kit 不会自己换状态：`.completed`、`.failed`、`.confused` 不会回到 `.idle`，由宿主在合适的时候传入。
- 状态是预设的，用哪些由宿主决定。
- 开启「减弱动态效果」、App 不在前台，或运行在小组件与 Live Activity 里时，显示该状态的静态姿势。

宿主把业务状态映射成 `MascotState`；业务结果不跟随动画（例如识别失败后输入内容保留到用户重试，
与角色播到哪一帧无关）。

## 角色

| 角色 | 产品 |
|---|---|
| `.mono` | MONO 的账本 |

## 数据

角色造型在 `Sources/MascotKit/Resources/characters/`，动作片段与状态表在
`Sources/MascotKit/Resources/motion.json`，格式说明见 [AGENTS.md](AGENTS.md)。

## 许可

见 [LICENSE](LICENSE)。仓库公开只为 SPM 引用，角色与代码不授权他人使用。
