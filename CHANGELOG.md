# Changelog

## 0.3.1

- 随包资源仅包含角色播放所需的数据。公开接口、动作和静态姿势保持兼容。

## 0.3.0

- 数据格式第 2 版：新增立体转动轨道 `turn`（平面角色上投影为身体变窄与脸部滑动），挤压改为横纵两个倍率，
  状态的 `loop` 可写多个片段按顺序轮换，片段之间用 0.3 秒接缝过渡；移除视线轨道 `gaze`。
- 待机在三个片段间轮换，工作在六个片段间轮换。`failed`、`confused` 不再有单独的入场片段。
- 新增表情 `calm`、`squinted`；角色新增 `faceTravel`。

## 0.2.0

- 新增状态 `greeting`、`listening`、`thinking`、`waiting`、`happy`、`confused`、`sleeping`。
- 新增表情 `wide`、`confused`、`sleepy`，附属部件思考圆点、问号与睡着的 z。
- 表情可用 `rightEye` 单独画第二只眼。

## 0.1.0

- `MascotView(_:state:)`：内置角色与内置状态两个参数。
- 状态 `idle`、`working`、`completed`、`failed`；角色 `mono`。
- 数据格式第 1 版：位移、旋转、缩放、挤压、视线、眼睑、表情与附属部件轨道。
- 自然眨眼与呼吸由引擎叠加；减弱动态效果、非前台与小组件环境显示静态姿势。
