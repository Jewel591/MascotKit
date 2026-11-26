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
        && close(a.scale, b.scale, tolerance) && close(a.squash, b.squash, tolerance)
        && close(a.gaze, b.gaze, tolerance)
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
                #expect(motion.clips[spec.loop] != nil)
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
            check(clip.tracks.scale, name, clip.duration)
            check(clip.tracks.squash, name, clip.duration)
            check(clip.tracks.gaze, name, clip.duration)
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

    /// 循环片段首尾须一致，入场片段的结尾须接上循环片段的开头，否则角色会跳一下。
    @Test func loopsAndEntrancesJoinWithoutAJump() {
        for (name, state) in motion.states {
            let loop = motion.clips[state.loop]!
            let start = MascotEngine.pose(clip: loop, at: 0)
            let end = MascotEngine.pose(clip: loop, at: loop.duration)
            #expect(sameNumbers(start, end), "\(name) 的循环片段首尾不一致")
            #expect(start.expression == end.expression)
            if let enterName = state.enter, let enter = motion.clips[enterName] {
                let landing = MascotEngine.pose(clip: enter, at: enter.duration)
                #expect(sameNumbers(landing, start), "\(name) 的入场片段接不上循环片段")
                #expect(landing.expression == start.expression)
            }
        }
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
                var scale: Vec2
                var squash: Double
                var gaze: Vec2
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
            #expect(close(pose.scale, expect.scale, tolerance), "\(check.name)：缩放")
            #expect(close(pose.squash, expect.squash, tolerance), "\(check.name)：挤压")
            #expect(close(pose.gaze, expect.gaze, tolerance), "\(check.name)：视线")
            #expect(close(pose.lids, expect.lids, tolerance), "\(check.name)：眼睑")
            #expect(pose.expression == expect.expression, "\(check.name)：表情")
        }
    }

    @Test func attachmentsStayHiddenUntilTheirTrackShowsThem() throws {
        let celebrate = try #require(MascotLibrary.motion.clips["celebrate"])
        #expect(MascotEngine.pose(clip: celebrate, at: 0.1).attachments["spark"]?.opacity == 0)
        #expect(MascotEngine.pose(clip: celebrate, at: 0.6).attachments["spark"]?.opacity == 1)
        let idle = try #require(MascotLibrary.motion.clips["idle"])
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
        let working = try #require(motion.clips["working"])
        let idle = try #require(motion.clips["idle"])
        // 找一个自然眨眼正在发生的时刻
        var time = 0.0
        while MascotEngine.naturalBlink(at: time) < 0.5 { time += 0.01 }
        let workingPose = MascotEngine.applyingAutonomy(
            to: MascotEngine.pose(clip: working, at: 0.5), clip: working, absoluteTime: time
        )
        #expect(workingPose.lids == 0)
        let idlePose = MascotEngine.applyingAutonomy(
            to: MascotEngine.pose(clip: idle, at: 0.5), clip: idle, absoluteTime: time
        )
        #expect(idlePose.lids >= 0.5)
    }
}

// MARK: - 播放契约

@Suite struct PlaybackTests {
    let motion = MascotLibrary.motion
    let character = MascotLibrary.character(.mono)

    private func clipPose(_ state: MascotState, elapsed: Double) -> MascotPose {
        let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
        let (clip, time) = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: elapsed)!
        return MascotEngine.pose(clip: clip, at: time)
    }

    /// 完成与失败先播一次入场，然后一直停在各自的姿势上，不自己回待机。
    @Test func terminalStatesPlayEntranceOnceThenHold() {
        for (state, held) in [(MascotState.completed, "happy"), (.failed, "worried"), (.confused, "confused"), (.greeting, "round")] {
            let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
            let enter = motion.clips[spec.enter!]!
            let early = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: enter.duration / 2)!
            #expect(early.clip == enter)
            for elapsed in [enter.duration + 0.01, 30, 600, 86400] {
                let phase = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: elapsed)!
                #expect(phase.clip == motion.clips[spec.loop]!)
                #expect(MascotEngine.pose(clip: phase.clip, at: phase.time).expression == held)
            }
        }
    }

    @Test func loopingStatesWrapAround() {
        let spec = MascotLibrary.stateSpec(.working, character: character, motion: motion)
        let duration = motion.clips[spec.loop]!.duration
        let first = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: 0.4)!
        let later = MascotEngine.phase(of: spec, clips: motion.clips, elapsed: 0.4 + duration * 7)!
        #expect(close(first.time, later.time))
    }

    /// 换状态立即打断：切换当刻数值量不跳，表情立刻是新状态的，过渡结束后与新片段完全一致。
    @Test func switchingInterruptsWithoutJumpOrDetour() {
        let start = 500.0
        let switchTime = start + 0.36 // 完成的入场片段播到一半，角色在空中
        let completed = MascotPlayback(state: .completed, start: start)
        let before = completed.pose(at: switchTime, character: character, motion: motion)
        let failed = completed.switching(to: .failed, at: switchTime, character: character, motion: motion)

        let atSwitch = failed.pose(at: switchTime, character: character, motion: motion)
        #expect(sameNumbers(atSwitch, before))
        #expect(atSwitch.expression == "surprised")

        // 过渡途中位移单调离开打断点，不回到待机的原点再出发
        let midway = failed.pose(at: switchTime + 0.05, character: character, motion: motion)
        #expect(midway.offset.y < 0 && midway.offset.y > before.offset.y)

        let after = switchTime + MascotPlayback.blendDuration + 0.05
        let settled = failed.pose(at: after, character: character, motion: motion)
        let pure = MascotPlayback(state: .failed, start: switchTime).pose(at: after, character: character, motion: motion)
        #expect(settled == pure)
    }

    @Test func sameStateKeepsProgress() {
        let playback = MascotPlayback(state: .working, start: 100)
        #expect(playback.switching(to: .working, at: 101.3, character: character, motion: motion) == playback)
    }

    @Test func stillPosesAreTheRestingFrameOfEachState() {
        let expected: [MascotState: String] = [
            .idle: "round", .greeting: "round", .listening: "wide", .thinking: "round", .working: "focus", .waiting: "round",
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
        for (state, name) in [(MascotState.thinking, "dot3"), (.confused, "question"), (.sleeping, "zzz")] {
            let spec = MascotLibrary.stateSpec(state, character: character, motion: motion)
            let pose = MascotEngine.stillPose(of: spec, clips: motion.clips)
            #expect((pose.attachments[name]?.opacity ?? 0) > 0.5, "\(state) 的静态姿势里没有 \(name)")
            #expect(character.attachments?[name] != nil)
        }
    }

    /// 角色可以只改某个状态的播放定义，其余沿用共用表。
    @Test func characterMayOverrideAState() throws {
        let sample = try fixture("sample-character", as: CharacterSpec.self)
        #expect(MascotLibrary.stateSpec(.idle, character: sample, motion: motion).loop == "completedHold")
        #expect(MascotLibrary.stateSpec(.working, character: sample, motion: motion).loop == "working")
    }
}
