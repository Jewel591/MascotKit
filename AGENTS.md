# AGENTS.md — MascotKit

本仓库是作者全部 Apple App 的角色动效正身：给定角色与状态，画出会动的角色。范围裁决、不变式与数据格式记录在此；
README 是使用文档，接入步骤在 `.agents/skills/integrate-mascotkit/SKILL.md`。

## 不变式（改动前先读）

1. **公开接口只有两个参数**：`MascotView(_ character: Mascot, state: MascotState)`。尺寸用 `.frame`，深浅色跟随环境。
   不接受片段、时长、缓动、颜色、回调或「播完通知」之类的第三个入口：每多一个参数就是每个产品多一个写错的机会。
   宿主觉得缺什么，改的是 Kit 里的数据或状态表。
2. **状态按语义预设，用不用由宿主决定**。状态名描述角色在做什么（倾听、思考、等待），不按某个页面起名；
   改名或删除是破坏性变更。没有页面检验过的状态，动作数值是初稿，第一次真正用到时允许重调。
   需要改播放契约或公开接口才能实现的东西（独立于状态的一次性手势等）不属于「加状态」，另行裁决。
3. **播放契约**：
   - 状态表里没有 `enter` 的状态直接循环；有 `enter` 的（`greeting`、`completed`）先播一次入场片段，
     然后循环各自的保持片段。Kit 不自己换状态，`completed` 等不会自动回 `idle`；`greeting` 的保持片段就是待机片段。
   - `loop` 写了多个片段时按顺序一个接一个播，播完回到第一个。片段之间（含同一片段首尾相接、入场接循环）的数值量
     用 0.3 秒从上一个片段的结尾姿势过渡，片段数据的首尾不要求一致。
   - 新状态立即打断旧状态：数值量从被打断时的姿势用 0.2 秒过渡到新片段，表情与附属部件立刻取新状态；旧片段不会先回到待机。
   - 同一状态重复传入保持进度。
   - 业务结果不跟随动画，Kit 不提供播放完成的回调。
4. **角色与动作都是数据**，在 `Sources/MascotKit/Resources/`，也是网页调试台读取的同一份。
   引擎与渲染不为某个角色写分支。
5. **角色结构上限**：身体、两只眼、嘴等面部附加形状、少量附属部件。不做四肢骨骼、三维渲染，不引入 Lottie 或 Rive。
   角色是平面的：片段里的立体转动只投影成身体变窄与脸部滑动（`MascotEngine.projection`），转到背面不画脸。
6. **自然眨眼与呼吸属于引擎**，按绝对时间计算（间隔逐格不同，但同一时刻结果恒定，不用逐帧随机数）。
   每个视图创建时取一个随机的时间偏移，同屏多个角色不会同时眨眼，换状态不改变它。
   片段可以写表演性的眼睑轨道，写了就不再叠加自然眨眼。表情的 `blinks` 为 `false` 时眼睛不随眼睑压扁。
7. **静态姿势**：减弱动态效果、App 不在前台、运行在小组件或 Live Activity 的扩展里时，只画状态表 `still` 指定的那一帧，
   不启动时间轴。
8. **角色造型与动作分开维护**。角色文件定义路径、配色与表情。动作文件定义播放状态、关键帧与附属部件。
9. **仓库公开，只供作者自己的 App 引用**，角色不公开授权。LICENSE 写明只用于作者自己的产品。代码与提交历史不写产品策略参数。
10. **Kit 内没有用户可见字符串**，视图对辅助功能隐藏；需要朗读的状态文案由宿主自己提供。

## 数据格式（第 2 版）

`formatVersion` 必须等于 `Model.swift` 的 `mascotFormatVersion`。格式出现不兼容变化时两处同步加一，
并在同一提交更新 `Tests/MascotKitTests/Fixtures/` 的夹具与网页调试台。

### 动作：`Resources/motion.json`

- `states`：每个 `MascotState` 一项，`enter`（可选，入场片段，播一次）、`loop`（循环片段，一个片段名或按顺序轮换的片段名数组）、
  `still`（静态姿势取自哪个片段的哪一秒）。
- `clips`：每个片段有 `duration`、`tracks` 与可选的 `attachments`。

| 轨道 | 值 | 静止值 | 说明 |
|---|---|---|---|
| `position` | `[x, y]` | `[0, 0]` | 单位为画布边长的百分之一，向下为正 |
| `rotation` | 度 | `0` | 平面内转动，顺时针为正，叠加在角色的 `baseRotation` 上 |
| `turn` | `[左右转, 俯仰]`，度 | `[0, 0]` | 立体转动，向右转、低头为正。身体横向乘 `\|cos 左右转\|`、纵向乘 `\|cos 俯仰\|`（不小于 0.05），脸按 `faceTravel × sin` 滑动，两个余弦之积不为正时不画脸 |
| `scale` | `[x, y]` | `[1, 1]` | 绕角色 `pivot` |
| `squash` | `[横向倍率, 纵向倍率]` | `[1, 1]` | 绕角色 `squashAnchor`；引擎的呼吸叠加在它上面 |
| `lids` | 0–1 | `0` | 眼睑闭合程度；写了这条轨道的片段不叠加自然眨眼 |
| `expression` | 表情名 | 必填 | 不插值，取当前时刻及之前最近的关键帧 |

附属部件轨道：`opacity`（静止值 0，即不显示）、`position`（设计坐标）、`rotation`、`scale`。

关键帧为 `{ "t": 秒, "v": 值, "ease": 缓动 }`，每条轨道从 `t = 0` 开始、按时间递增。`ease` 描述离开这一帧的缓动，
可写 `linear`、`in`、`out`、`inOut`（省略时的默认值）、`hold`（保持到下一帧再跳变）或三次贝塞尔的 `[x1, y1, x2, y2]`。

片段首尾的数值不要求一致，接缝由引擎过渡；单元测试检查每个接缝前后的姿势连续。

### 角色：`Resources/characters/<id>.json`

`canvas`（设计坐标的画布边长）、`pivot`、`baseRotation`、`squashAnchor`、`palette`（`light` 与 `dark` 各一套颜色名到 `#RRGGBB`）、
`body`（形状层）、`eyes`（两只眼的中心）、`faceCenter`、`faceTravel`（立体转动转到侧面时脸横向与纵向滑出的最大距离）、`expressions`、可选的 `attachments` 与 `states`（只覆盖个别状态的播放定义）。

- 形状层：`roundedRect`（`x y w h r`，连续曲率圆角）、`ellipse`（`cx cy rx ry`）、`path`（`d`，只支持绝对坐标的 `M L Q C Z`），
  用 `fill` 或 `stroke`（配 `lineWidth`）写调色板里的颜色名，可带 `opacity`。
- 表情：`eye` 以眼睛中心为原点、两只眼各画一次；第二只眼不同时另写 `rightEye`；`extras` 以 `faceCenter` 为原点画一次；
  `blinks` 决定是否随眼睑压扁。
- **片段引用的每个表情，每个角色都必须提供**（现有：`round`、`focus`、`calm`、`squinted`、`happy`、`surprised`、`worried`、`confused`、`sleepy`；`wide` 目前没有片段使用）。
- 附属部件：`space` 为 `body`（跟随身体变换）或 `canvas`（只跟随画布），`anchor` 为位置，角色没有的部件直接不画。
  片段用到的部件名：`spark`（完成）、`dot1` 至 `dot3`（思考时依次冒出，等待时环绕身体）、`question`（困惑）、`zzz`（睡着）。一个部件只有一组轨道，
  要依次出现的多个图形拆成多个部件。

## 新增角色

1. 在 `Resources/characters/` 新增 `<id>.json`，提供全部现有表情。
2. 在 `Mascot` 枚举加同名 case。
3. `swift test`：数据完整性测试会覆盖新角色。
4. 在网页调试台里逐状态看过再发版。

## 新增状态或片段

在 `motion.json` 中编辑状态与片段，在 `MascotState` 添加对应状态。新增表情时同步补齐各角色，并更新 README 的状态表。

```sh
python3 scripts/generate-pose-checks.py Sources/MascotKit/Resources/motion.json Tests/MascotKitTests/Fixtures/pose-checks.json
```

## 测试

`swift test` 在 Mac 上运行，不需要设备。

- 数据完整性：版本号、状态与片段引用、表情齐全、形状可绘制、关键帧次序、片段接缝连续。
- 定点姿势：`Fixtures/pose-checks.json` 的期望值由独立实现算出，Swift 与网页调试台各自对照同一份。
  改动 `motion.json` 里被检查的片段后须重新生成该文件，并让两端都通过：
  `python3 scripts/generate-pose-checks.py Sources/MascotKit/Resources/motion.json Tests/MascotKitTests/Fixtures/pose-checks.json`。
- 播放契约：入场播一次后循环、多个片段按顺序轮换、打断不跳变不绕道、同状态保持进度、静态姿势、立体转动的投影。
- 不写快照测试。造型与动作观感在网页调试台和真机上由人验收。

## 发布

运行时代码合并到 `main` 后当场打 semver tag 并推送；宿主以 `from:` 兼容版本范围引用。
