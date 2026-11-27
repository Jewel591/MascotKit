import Foundation
import Testing
@testable import MascotKit

private func fixture<Value: Decodable>(_ name: String, as type: Value.Type) throws -> Value {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try MascotLibrary.decode(type, from: Data(contentsOf: url))
}

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

private func close(_ a: Vec2, _ b: Vec2, _ tolerance: Double = 1e-6) -> Bool {
    close(a.x, b.x, tolerance) && close(a.y, b.y, tolerance)
}

/// 数值量是否一致（不比表情与附属部件）。
private func sameNumbers(_ a: MascotPose, _ b: MascotPose, _ tolerance: Double = 1e-6) -> Bool {
    close(a.offset, b.offset, tolerance) && close(a.rotation, b.rotation, tolerance)
        && close(a.turn, b.turn, tolerance)
        && close(a.scale, b.scale, tolerance) && close(a.squash, b.squash, tolerance)
}

// MARK: - 包内数据

@Suite struct BundledDataTests {
    let motion = MascotLibrary.motion

    @Test func formatVersionsMatch() {
        #expect(motion.formatVersion == mascotFormatVersion)
        for mascot in Mascot.allCases {
            let character = MascotLibrary.character(mascot)
            #expect(character.formatVersion == mascotFormatVersion)
            #expect(character.id == mascot.rawValue)
        }
    }

    @Test func everyStateResolvesToExistingClips() {
        for mascot in Mascot.allCases {
            let character = MascotLibrary.character(mascot)
            for state in MascotState.allCases {
                #expect(motion.states[state.rawValue] != nil, "共用状态表缺少 \(state)")
                let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
                if let enter = spec.enter { #expect(motion.clips[enter] != nil) }
                for name in spec.loop { #expect(motion.clips[name] != nil, "\(state) 引用了不存在的片段 \(name)") }
                #expect(motion.clips[spec.still.clip] != nil)
            }
        }
    }

    /// 片段引用的表情，每个角色都必须画得出来，否则该帧没有脸。
    @Test func everyCharacterDrawsEveryExpression() throws {
        let sample = try fixture("sample-character", as: CharacterSpec.self)
        let characters = Mascot.allCases.map(MascotLibrary.character) + [sample]
        for (name, clip) in motion.clips {
            #expect(!clip.tracks.expression.isEmpty, "\(name) 没有表情轨道")
            for key in clip.tracks.expression {
                for character in characters {
                    #expect(character.expressions[key.v] != nil, "\(character.id) 缺少表情 \(key.v)（\(name)）")
                }
            }
        }
    }

    @Test func everyShapeIsDrawable() throws {
        let sample = try fixture("sample-character", as: CharacterSpec.self)
        for character in Mascot.allCases.map(MascotLibrary.character) + [sample] {
            var layers = character.body
            for expression in character.expressions.values {
                layers += expression.eye + (expression.rightEye ?? []) + (expression.extras ?? [])
            }
            for attachment in (character.attachments ?? [:]).values {
                layers += attachment.layers
            }
            for layer in layers {
                let path = try #require(MascotRenderer.path(for: layer), "\(character.id) 有画不出的形状")
                #expect(!path.isEmpty)
                #expect(layer.fill != nil || layer.stroke != nil)
                for name in [layer.fill, layer.stroke].compactMap({ $0 }) {
                    #expect(MascotRenderer.color(character.palette.light[name]) != nil)
                    #expect(MascotRenderer.color(character.palette.dark[name]) != nil)
                }
            }
        }
    }

    @Test func keyframesAreOrderedAndInsideTheClip() {
        func check<Value>(_ keys: [Keyframe<Value>]?, _ clip: String, _ duration: Double) {
            guard let keys else { return }
            #expect(!keys.isEmpty)
            #expect(keys.first?.t == 0, "\(clip) 的轨道须从 0 开始")
            #expect((keys.last?.t ?? 0) <= duration)
            for (a, b) in zip(keys, keys.dropFirst()) {
                #expect(a.t < b.t, "\(clip) 的关键帧须按时间递增")
            }
        }
        for (name, clip) in motion.clips {
            #expect(clip.duration > 0)
            check(clip.tracks.position, name, clip.duration)
            check(clip.tracks.rotation, name, clip.duration)
            check(clip.tracks.turn, name, clip.duration)
            check(clip.tracks.scale, name, clip.duration)
            check(clip.tracks.squash, name, clip.duration)
            check(clip.tracks.lids, name, clip.duration)
            check(clip.tracks.expression, name, clip.duration)
            for tracks in (clip.attachments ?? [:]).values {
                check(tracks.opacity, name, clip.duration)
                check(tracks.position, name, clip.duration)
                check(tracks.rotation, name, clip.duration)
                check(tracks.scale, name, clip.duration)
            }
        }
    }

    /// 片段之间（含同一片段首尾相接）靠接缝过渡衔接：接缝前后一刻的数值量必须连续，否则角色会跳一下。
    @Test func clipsJoinWithoutAJump() {
        for (name, state) in motion.states {
            var boundaries: [Double] = []
            var elapsed = motion.clips[state.enter ?? ""]?.duration ?? 0
            if elapsed > 0 { boundaries.append(elapsed) }
            for _ in 0 ..< 2 {
                for loop in state.loop {
                    elapsed += motion.clips[loop]!.duration
                    boundaries.append(elapsed)
                }
            }
            for boundary in boundaries {
                let before = MascotEngine.pose(at: MascotEngine.phase(of: state, clips: motion.clips, elapsed: boundary - 1e-7)!)
                let after = MascotEngine.pose(at: MascotEngine.phase(of: state, clips: motion.clips, elapsed: boundary + 1e-7)!)
                // 转完整圈的片段结尾与下一段开头相差整数圈，画出来是同一个姿势
                var unwound = before
                unwound.turn.x += 360 * ((after.turn.x - before.turn.x) / 360).rounded()
                unwound.turn.y += 360 * ((after.turn.y - before.turn.y) / 360).rounded()
                #expect(sameNumbers(unwound, after, 1e-3), "\(name) 在 \(boundary) 秒处跳变")
            }
        }
    }

    /// 动作数据由 `scripts/import-grok-motion.mjs` 生成：待机与工作各由多个片段轮换。
    @Test func idleAndWorkingRotateThroughSeveralClips() {
        #expect(Set(motion.states["idle"]!.loop).count >= 3)
        #expect(Set(motion.states["working"]!.loop).count >= 6)
    }
}

// MARK: - 取样

@Suite struct SamplingTests {
    @Test func easingEndpointsAndShapes() {
        #expect(MascotEngine.ease(.linear, 0.3) == 0.3)
        #expect(MascotEngine.ease(.hold, 0.99) == 0)
        for easing in [Easing.easeIn, .easeOut, .easeInOut] {
            #expect(MascotEngine.ease(easing, 0) == 0)
            #expect(MascotEngine.ease(easing, 1) == 1)
        }
        #expect(close(MascotEngine.ease(.easeInOut, 0.5), 0.5))
        #expect(MascotEngine.ease(.easeIn, 0.5) < 0.5)
        #expect(MascotEngine.ease(.easeOut, 0.5) > 0.5)
    }

    @Test func easingDecodesNamesAndControlPoints() throws {
        let decoded = try MascotLibrary.decode(
            [Easing].self, from: Data(#"["linear","in","out","inOut","hold",[0.2,0.1,0.3,1]]"#.utf8)
        )
        #expect(decoded == [.linear, .easeIn, .easeOut, .easeInOut, .hold, .bezier(0.2, 0.1, 0.3, 1)])
        #expect(throws: (any Error).self) {
            try MascotLibrary.decode([Easing].self, from: Data(#"["bounce"]"#.utf8))
        }
    }

    /// 与网页调试台共用的定点检查：期望值由独立实现算出，两端各自对照。
    @Test func fixedTimePosesMatchSharedChecks() throws {
        struct Checks: Decodable {
            struct Expect: Decodable {
                var offset: Vec2
                var rotation: Double
                var turn: Vec2
                var scale: Vec2
                var squash: Vec2
                var lids: Double
                var expression: String
            }

            struct Check: Decodable {
                var name: String
                var clip: String
                var t: Double
                var expect: Expect
            }

            var formatVersion: Int
            var tolerance: Double
            var checks: [Check]
        }
        let checks = try fixture("pose-checks", as: Checks.self)
        #expect(checks.formatVersion == mascotFormatVersion)
        #expect(checks.checks.count >= 3)
        for check in checks.checks {
            let clip = try #require(MascotLibrary.motion.clips[check.clip])
            let pose = MascotEngine.pose(clip: clip, at: check.t)
            let expect = check.expect
            let tolerance = checks.tolerance
            #expect(close(pose.offset, expect.offset, tolerance), "\(check.name)：位移")
            #expect(close(pose.rotation, expect.rotation, tolerance), "\(check.name)：旋转")
            #expect(close(pose.turn, expect.turn, tolerance), "\(check.name)：立体转动")
            #expect(close(pose.scale, expect.scale, tolerance), "\(check.name)：缩放")
            #expect(close(pose.squash, expect.squash, tolerance), "\(check.name)：挤压")
            #expect(close(pose.lids, expect.lids, tolerance), "\(check.name)：眼睑")
            #expect(pose.expression == expect.expression, "\(check.name)：表情")
        }
    }

    @Test func attachmentsStayHiddenUntilTheirTrackShowsThem() throws {
        let celebrate = try #require(MascotLibrary.motion.clips["celebrate"])
        #expect(MascotEngine.pose(clip: celebrate, at: 0.1).attachments["spark"]?.opacity == 0)
        #expect(MascotEngine.pose(clip: celebrate, at: 0.6).attachments["spark"]?.opacity == 1)
        let idle = try #require(MascotLibrary.motion.clips["idleB"])
        #expect(MascotEngine.pose(clip: idle, at: 1).attachments.isEmpty)
    }

    @Test func pathParserReadsSupportedCommands() throws {
        let path = try PathParser.parse("M 0 0 L 4 0 Q 6 1 4 2 C 3 3 1 3 0 2 Z")
        #expect(path.boundingRect.width > 4)
        #expect(throws: PathParser.Failure.self) { try PathParser.parse("M 0 0 A 1 1 0 0 1 2 2") }
        #expect(throws: PathParser.Failure.self) { try PathParser.parse("M 0 0 L 4") }
        #expect(throws: PathParser.Failure.self) { try PathParser.parse("1 2 L 3 4") }
    }
}

// MARK: - 自主行为

@Suite struct AutonomyTests {
    /// 网页调试台用 `Math.imul` 实现同一散列，同一组向量写在它的测试里（social-studio 的 tools/mascot.test.mjs）。
    @Test func hashMatchesTheWebConsole() {
        #expect([1, 12345, 0xFFFF_FFFF].map(MascotEngine.hash) == [2_693_262_067, 4_207_900_869, 3_850_105_811])
    }

    @Test func naturalBlinkIsDeterministicAndBounded() {
        var blinking = 0
        let steps = 4400
        for step in 0 ..< steps {
            let time = 1000 + Double(step) * 0.01
            let value = MascotEngine.naturalBlink(at: time)
            #expect(value == MascotEngine.naturalBlink(at: time))
            #expect(value >= 0 && value <= 1)
            if value > 0 { blinking += 1 }
        }
        // 44 秒里有 10 格，每格眨一到两下，每下 0.2 秒
        #expect(blinking >= 10 * 18 && blinking <= 10 * 42)
    }

    @Test func blinkIntervalsVary() {
        func start(of slot: Int) -> Double {
            for step in 0 ..< 440 where MascotEngine.naturalBlink(at: Double(slot) * 4.4 + Double(step) * 0.01) > 0 {
                return Double(step) * 0.01
            }
            return -1
        }
        let starts = Set((0 ..< 12).map { (start(of: $0) * 10).rounded() })
        #expect(!starts.contains(-10))
        #expect(starts.count >= 6, "眨眼位置应逐格不同")
    }

    /// 片段自己写了眼睑轨道（表演性眨眼）时，自然眨眼让位。
    @Test func clipLidsTakePriorityOverNaturalBlink() throws {
        let motion = MascotLibrary.motion
        let scripted = try #require(motion.clips["idleB"])
        let free = try #require(motion.clips["failedHold"])
        #expect(scripted.tracks.lids != nil && free.tracks.lids == nil)
        // 找一个自然眨眼正在发生的时刻
        var time = 0.0
        while MascotEngine.naturalBlink(at: time) < 0.5 { time += 0.01 }
        let scriptedPose = MascotEngine.applyingAutonomy(
            to: MascotEngine.pose(clip: scripted, at: 0.5), clip: scripted, absoluteTime: time
        )
        #expect(scriptedPose.lids == 0)
        let freePose = MascotEngine.applyingAutonomy(
            to: MascotEngine.pose(clip: free, at: 0.5), clip: free, absoluteTime: time
        )
        #expect(freePose.lids >= 0.5)
    }
}

// MARK: - 播放契约

@Suite struct PlaybackTests {
    let motion = MascotLibrary.motion
    let character = MascotLibrary.character(.mono)

    /// 完成与打招呼先播一次入场，然后一直播各自的循环片段，不自己回待机。
    @Test func entranceStatesPlayEntranceOnceThenLoop() {
        for state in [MascotState.completed, .greeting] {
            let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
            let enter = motion.clips[spec.enter!]!
            let early = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: enter.duration / 2)!
            #expect(early.clip == enter && early.previous == nil)
            let loops = spec.loop.map { motion.clips[$0]! }
            for elapsed in [enter.duration + 0.01, 30, 600, 86400] {
                #expect(loops.contains(MascotEngine.phase(of: spec, clips: motion.clips, elapsed: elapsed)!.clip))
            }
        }
        let completed = MascotLibrary.stateSpec(.completed, character: character, motion: motion)
        for elapsed in [3.0, 30, 600] {
            let phase = MascotEngine.phase(of: completed, clips: motion.clips, elapsed: elapsed)!
            #expect(MascotEngine.pose(clip: phase.clip, at: phase.time).expression == "happy")
        }
    }

    /// 多个循环片段按顺序播，播完回到第一个；每个片段都记得自己接在谁后面。
    @Test func loopClipsPlayInOrderAndWrapAround() {
        let spec = MascotLibrary.stateSpec(.working, character: character, motion: motion)
        let clips = spec.loop.map { motion.clips[$0]! }
        let total = clips.reduce(0) { $0 + $1.duration }
        var elapsed = 0.0
        for (index, clip) in clips.enumerated() {
            let phase = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: elapsed + 0.4)!
            #expect(phase.clip == clip && close(phase.time, 0.4))
            #expect(phase.previous == (index == 0 ? nil : clips[index - 1]))
            elapsed += clip.duration
        }
        let wrapped = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: total * 7 + 0.4)!
        #expect(wrapped.clip == clips[0] && close(wrapped.time, 0.4, 1e-6) && wrapped.previous == clips.last)
    }

    /// 转完整圈后接下一个片段时不倒着转回来：过渡途中的角度始终在结尾那一圈附近。
    @Test func joinDoesNotUnwindAFullTurn() {
        var origin = MascotPose(expression: "round")
        origin.turn = Vec2(x: 360, y: 0)
        var target = MascotPose(expression: "round")
        target.turn = Vec2(x: 10, y: 0)
        let midway = MascotEngine.blend(from: origin, to: target, progress: 0.5)
        #expect(midway.turn.x > 0 && midway.turn.x < 10)
    }

    /// 平面角色的立体转动：转向侧面时身体变窄、脸滑向一侧，转到背面不画脸。
    @Test func turnProjectsOntoAFlatCharacter() {
        let travel = Vec2(x: 3, y: 2)
        let front = MascotEngine.projection(turn: .zero, faceTravel: travel)
        #expect(front == MascotEngine.Projection(scale: .one, faceOffset: .zero, faceVisible: true))
        let right = MascotEngine.projection(turn: Vec2(x: 30, y: 0), faceTravel: travel)
        #expect(close(right.scale.x, cos(.pi / 6)) && right.scale.y == 1)
        #expect(close(right.faceOffset.x, 1.5) && right.faceVisible)
        let down = MascotEngine.projection(turn: Vec2(x: 0, y: 30), faceTravel: travel)
        #expect(close(down.faceOffset.y, 1) && close(down.scale.y, cos(.pi / 6)))
        #expect(!MascotEngine.projection(turn: Vec2(x: 180, y: 0), faceTravel: travel).faceVisible)
        #expect(MascotEngine.projection(turn: Vec2(x: 90, y: 0), faceTravel: travel).scale.x == MascotEngine.minimumFlatness)
        #expect(MascotEngine.projection(turn: Vec2(x: 360, y: 0), faceTravel: travel).faceVisible)
    }

    /// 换状态立即打断：切换当刻数值量不跳，表情立刻是新状态的，过渡结束后与新片段完全一致。
    @Test func switchingInterruptsWithoutJumpOrDetour() {
        let start = 500.0
        let switchTime = start + 0.3 // 完成的入场片段第一次起跳，角色在空中
        let completed = MascotPlayback(state: .completed, start: start)
        let before = completed.pose(at: switchTime, character: character, motion: motion)
        let failed = completed.switching(to: .failed, at: switchTime, character: character, motion: motion)

        let atSwitch = failed.pose(at: switchTime, character: character, motion: motion)
        #expect(sameNumbers(atSwitch, before))
        #expect(atSwitch.expression == "worried")

        // 过渡途中位移单调离开打断点（空中）走向失败姿势（下沉），不回到待机的原点再出发
        #expect(before.offset.y < -5)
        let early = failed.pose(at: switchTime + 0.02, character: character, motion: motion)
        let midway = failed.pose(at: switchTime + 0.1, character: character, motion: motion)
        #expect(early.offset.y > before.offset.y && midway.offset.y > early.offset.y)

        let after = switchTime + MascotPlayback.blendDuration + 0.05
        let settled = failed.pose(at: after, character: character, motion: motion)
        let pure = MascotPlayback(state: .failed, start: switchTime).pose(at: after, character: character, motion: motion)
        #expect(settled == pure)
    }

    /// 每个视图的眨眼偏移不同，同屏多个角色不同时眨眼；换状态不改变偏移，眨眼节奏不被打断。
    @Test func autonomyPhaseDesynchronisesBlinksAndSurvivesSwitching() {
        var time = 100.0
        while MascotEngine.naturalBlink(at: time) < 0.5 { time += 0.01 }
        // 失败的保持片段没有表演性眨眼，自然眨眼才会叠加上来
        let aligned = MascotPlayback(state: .failed, start: 0)
        let shifted = MascotPlayback(state: .failed, start: 0, autonomyPhase: 1.5)
        #expect(aligned.pose(at: time, character: character, motion: motion).lids >= 0.5)
        #expect(shifted.pose(at: time, character: character, motion: motion).lids == 0)
        #expect(shifted.switching(to: .waiting, at: time, character: character, motion: motion).autonomyPhase == 1.5)
    }

    @Test func sameStateKeepsProgress() {
        let playback = MascotPlayback(state: .working, start: 100)
        #expect(playback.switching(to: .working, at: 101.3, character: character, motion: motion) == playback)
    }

    @Test func stillPosesAreTheRestingFrameOfEachState() {
        let expected: [MascotState: String] = [
            .idle: "round", .greeting: "round", .listening: "calm", .thinking: "round", .working: "calm", .waiting: "round",
            .completed: "happy", .failed: "worried", .happy: "happy", .confused: "confused", .sleeping: "sleepy",
        ]
        #expect(expected.count == MascotState.allCases.count)
        for state in MascotState.allCases {
            let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
            let pose = MascotEngine.stillPose(of: spec, clips: motion.clips)
            #expect(pose.expression == expected[state])
            #expect(pose.lids == 0)
        }
    }

    /// 第二只眼可以单独画；没写时两只眼相同。
    @Test func rightEyeIsOptional() {
        #expect(character.expressions["confused"]?.rightEye != nil)
        #expect(character.expressions["round"]?.rightEye == nil)
    }

    /// 附属部件在自己的状态里出现，静态姿势里也看得到（小组件只有这一帧）。
    @Test func stateAttachmentsShowInStillPoses() {
        for (state, name) in [(MascotState.thinking, "dot3"), (.waiting, "dot1"), (.confused, "question"), (.sleeping, "zzz")] {
            let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
            let pose = MascotEngine.stillPose(of: spec, clips: motion.clips)
            #expect((pose.attachments[name]?.opacity ?? 0) > 0.5, "\(state) 的静态姿势里没有 \(name)")
            #expect(character.attachments?[name] != nil)
        }
    }

    /// 角色可以只改某个状态的播放定义，其余沿用共用表。
    @Test func characterMayOverrideAState() throws {
        let sample = try fixture("sample-character", as: CharacterSpec.self)
        #expect(MascotLibrary.stateSpec(.idle, character: sample, motion: motion).loop == ["failedHold"])
        #expect(MascotLibrary.stateSpec(.working, character: sample, motion: motion).loop.first == "workA")
    }
}
