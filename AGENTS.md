# AGENTS.md — MascotKit

本仓库是作者全部 Apple App 的角色动效正身：给定角色与状态，画出会动的角色。范围裁决、不变式与数据格式记录在此；
README 是使用文档，接入步骤在 `.agents/skills/integrate-mascotkit/SKILL.md`。

## 不变式（改动前先读）

1. **公开接口只有两个参数**：`MascotView(_ character: Mascot, state: MascotState)`。尺寸用 `.frame`，深浅色跟随环境。
   不接受片段、时长、缓动、颜色、回调或「播完通知」之类的第三个入口：每多一个参数就是每个产品多一个写错的机会。
   宿主觉得缺什么，改的是 Kit 里的数据或状态表。
2. **状态只加第一个使用页面能真正区分的**。现有四个来自 MONO 记录页「发送文字后到出现账单或重试卡」。
   不预先加「思考」「倾听」「睡眠」等没有页面在用的状态。
3. **播放契约**：
   - `idle`、`working` 循环；`completed`、`failed` 先播一次入场片段，然后循环各自的保持片段，不自己回 `idle`。
   - 新状态立即打断旧状态：数值量从被打断时的姿势用 0.2 秒过渡到新片段，表情与附属部件立刻取新状态；旧片段不会先回到待机。
   - 同一状态重复传入保持进度。
   - 业务结果不跟随动画，Kit 不提供播放完成的回调。
4. **角色与动作都是数据**，在 `Sources/MascotKit/Resources/`，也是网页调试台（social-studio 的「原创角色」页）读取的同一份。
   引擎与渲染不为某个角色写分支。
5. **角色结构上限**：身体、两只眼、嘴等面部附加形状、少量附属部件。不做四肢骨骼、三维渲染，不引入 Lottie 或 Rive。
6. **自然眨眼与呼吸属于引擎**，按绝对时间计算（间隔逐格不同，但同一时刻结果恒定，不用逐帧随机数）。
   片段可以写表演性的眼睑轨道，写了就不再叠加自然眨眼。表情的 `blinks` 为 `false` 时眼睛不随眼睑压扁。
7. **静态姿势**：减弱动态效果、App 不在前台、运行在小组件或 Live Activity 的扩展里时，只画状态表 `still` 指定的那一帧，
   不启动时间轴。
8. **全部原创**。不得使用任何第三方角色的路径、配色、网格或关键帧数值；参考只停留在「有哪些轨道、哪些手法」。
9. **仓库公开，角色不公开授权**。LICENSE 写明只用于作者自己的产品。代码与提交历史不写产品策略参数。
10. **Kit 内没有用户可见字符串**，视图对辅助功能隐藏；需要朗读的状态文案由宿主自己提供。

## 数据格式（第 1 版）

`formatVersion` 必须等于 `Model.swift` 的 `mascotFormatVersion`。格式出现不兼容变化时两处同步加一，
并在同一提交更新 `Tests/MascotKitTests/Fixtures/` 的夹具与网页调试台。

### 动作：`Resources/motion.json`

- `states`：每个 `MascotState` 一项，`enter`（可选，入场片段，播一次）、`loop`（循环片段）、`still`（静态姿势取自哪个片段的哪一秒）。
- `clips`：每个片段有 `duration`、`tracks` 与可选的 `attachments`。

| 轨道 | 值 | 静止值 | 说明 |
|---|---|---|---|
| `position` | `[x, y]` | `[0, 0]` | 单位为画布边长的百分之一，向下为正 |
| `rotation` | 度 | `0` | 叠加在角色的 `baseRotation` 上 |
| `scale` | `[x, y]` | `[1, 1]` | 绕角色 `pivot` |
| `squash` | 数 | `0` | 正值压扁、负值拉长，绕角色 `squashAnchor`；纵向乘 `1 - v`，横向乘 `1 + 0.7v` |
| `gaze` | `[x, y]` | `[0, 0]` | 眼睛位移，单位为角色设计坐标 |
| `lids` | 0–1 | `0` | 眼睑闭合程度；写了这条轨道的片段不叠加自然眨眼 |
| `expression` | 表情名 | 必填 | 不插值，取当前时刻及之前最近的关键帧 |

附属部件轨道：`opacity`（静止值 0，即不显示）、`position`（设计坐标）、`rotation`、`scale`。

关键帧为 `{ "t": 秒, "v": 值, "ease": 缓动 }`，每条轨道从 `t = 0` 开始、按时间递增。`ease` 描述离开这一帧的缓动，
可写 `linear`、`in`、`out`、`inOut`（省略时的默认值）、`hold`（保持到下一帧再跳变）或三次贝塞尔的 `[x1, y1, x2, y2]`。

循环片段首尾的数值必须一致，入场片段的结尾必须等于循环片段的开头；单元测试会检查。

### 角色：`Resources/characters/<id>.json`

`canvas`（设计坐标的画布边长）、`pivot`、`baseRotation`、`squashAnchor`、`palette`（`light` 与 `dark` 各一套颜色名到 `#RRGGBB`）、
`body`（形状层）、`eyes`（两只眼的中心）、`faceCenter`、`expressions`、可选的 `attachments` 与 `states`（只覆盖个别状态的播放定义）。

- 形状层：`roundedRect`（`x y w h r`，连续曲率圆角）、`ellipse`（`cx cy rx ry`）、`path`（`d`，只支持绝对坐标的 `M L Q C Z`），
  用 `fill` 或 `stroke`（配 `lineWidth`）写调色板里的颜色名，可带 `opacity`。
- 表情：`eye` 以眼睛中心为原点、两只眼各画一次；`extras` 以 `faceCenter` 为原点画一次；`blinks` 决定是否随眼睑压扁。
- **片段引用的每个表情，每个角色都必须提供**（现有：`round`、`focus`、`happy`、`surprised`、`worried`）。
- 附属部件：`space` 为 `body`（跟随身体变换）或 `canvas`（只跟随画布），`anchor` 为位置，角色没有的部件直接不画。

## 新增角色

1. 在 `Resources/characters/` 新增 `<id>.json`，提供全部现有表情。
2. 在 `Mascot` 枚举加同名 case。
3. `swift test`：数据完整性测试会覆盖新角色。
4. 在网页调试台里逐状态看过再发版。

## 新增状态或片段

先确认有真实页面需要它（不变式 2）。在 `motion.json` 加片段与状态项，`MascotState` 加 case，
新表情要给每个角色补上。

## 测试

`swift test` 在 Mac 上运行，不需要设备。

- 数据完整性：版本号、状态与片段引用、表情齐全、形状可绘制、关键帧次序、首尾接缝。
- 定点姿势：`Fixtures/pose-checks.json` 的期望值由独立实现算出，Swift 与网页调试台各自对照同一份。
  改动 `motion.json` 里被检查的片段后须重新生成该文件，并让两端都通过：
  `python3 scripts/generate-pose-checks.py Sources/MascotKit/Resources/motion.json Tests/MascotKitTests/Fixtures/pose-checks.json`。
- 播放契约：入场播一次后保持、打断不跳变不绕道、同状态保持进度、静态姿势。
- 不写快照测试。造型与动作观感在网页调试台和真机上由人验收。

## 发布

运行时代码合并到 `main` 后当场打 semver tag 并推送；宿主以 `from:` 兼容版本范围引用。
