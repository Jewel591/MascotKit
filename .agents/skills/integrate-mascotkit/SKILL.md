---
name: integrate-mascotkit
description: 在任何 Apple App 里加入、调整或排查「随状态变化的角色动效」（吉祥物在待机、处理中、完成、失败之间切换）前必须先加载：一律接 MascotKit（Jewel591/MascotKit），不在宿主里手写角色的 Canvas 绘制、关键帧或眨眼计时。覆盖标准接线、业务状态映射、新增角色或状态时改哪里，以及红线。范围裁决与数据格式正文在本仓库 AGENTS.md。
---

# MascotKit 接入

本文件是 skill 正身，只在 Kit 仓库维护。范围裁决、不变式与数据格式读本仓库 `AGENTS.md`，本文件不复制。

- 仓库：<https://github.com/Jewel591/MascotKit>
- 本机检出：`~/Documents/DevProjects/MascotKit`

## 何时使用

- 页面需要一个随业务状态变化的角色（处理中、成功、失败等）。
- 宿主里已有手写的角色动效，要收回 Kit。
- 要给新产品加角色，或给现有角色加状态。

MascotKit 不是每个 App 的必备能力，没有角色需求的产品不接。

## 标准接线

1. 依赖用公开地址与兼容版本范围：

   ```swift
   .package(url: "https://github.com/Jewel591/MascotKit", from: "0.1.0")
   ```

   Xcode 工程里选 Up to Next Major Version，不指向本地路径或分支。

2. 在页面里把业务状态映射成 `MascotState`：

   ```swift
   import MascotKit

   MascotView(.mono, state: mascotState)
       .frame(width: 44, height: 44)

   private var mascotState: MascotState {
       switch recognition {
       case .idle: .idle
       case .running: .working
       case .succeeded: .completed
       case .failed: .failed
       }
   }
   ```

   映射是宿主唯一要写的代码，也是宿主唯一值得测试的部分。

## 状态语义

- `idle`、`working` 循环；`completed`、`failed` 播一次入场后停在各自的姿势。
- 回到 `idle` 由宿主决定：业务上「这一轮结束了」的时刻传入 `.idle`，不要用定时器去猜动画播完没有。
- 业务结果不跟随动画：账单卡片、重试卡片、输入内容的去留只看业务状态。
- 换状态会立即打断，快速连续切换是安全的。

## 红线

- 不给 `MascotView` 加参数、回调或环境值开关；缺什么改 Kit 的数据。
- 不在宿主里复制角色的路径、配色或关键帧，也不再保留一份手写的同一角色绘制代码；迁移时删除旧实现。
- 不叠加宿主自己的 `.animation`、`.scaleEffect` 弹跳或 `.rotationEffect` 去「补」动作。
- 不为角色写快照测试或 UI 测试。
- 小组件与 Live Activity 里直接用 `MascotView`，它会自动显示静态姿势；不要在扩展里另起时间轴。
- 视图对辅助功能隐藏。状态需要被朗读时，由相邻的文字承担。

## 新增角色或状态

改动在 Kit 仓库完成，步骤见 `AGENTS.md`「新增角色」「新增状态或片段」。造型与动作先在 social-studio 的「原创角色」页调好，
再发 Kit 新版本，宿主升级依赖。

## 排查

| 现象 | 先看 |
|---|---|
| 角色不动 | 是否开启了「减弱动态效果」，App 是否在前台，是否运行在小组件扩展里 |
| 换状态后重头播放 | 视图是否因为 `id` 或条件分支变化被重建；同一个视图实例上换状态才是过渡 |
| 完成后一直是笑脸 | 这是契约；在业务结束时传 `.idle` |
| 颜色不对 | 角色配色在 Kit 内按深浅色各一套，不随宿主强调色变化 |
