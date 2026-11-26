"""独立于 Swift 实现，按数据格式说明重新实现取样，生成 pose-checks.json 的期望值。"""
import json
import sys

EASE = {"linear": (0, 0, 1, 1), "in": (0.42, 0, 1, 1), "out": (0, 0, 0.58, 1), "inOut": (0.42, 0, 0.58, 1)}


def cubic(u, p1, p2):
    return 3 * (1 - u) ** 2 * u * p1 + 3 * (1 - u) * u * u * p2 + u ** 3


def ease(e, x):
    if e == "hold":
        return 0.0
    x1, y1, x2, y2 = EASE[e] if isinstance(e, str) else e
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    # 牛顿法求参数，与 Swift 的二分法是两种解法
    u = x
    for _ in range(60):
        f = cubic(u, x1, x2) - x
        d = 3 * (1 - u) ** 2 * x1 + 6 * (1 - u) * u * (x2 - x1) + 3 * u * u * (1 - x2)
        if abs(d) < 1e-12:
            break
        u -= f / d
    return cubic(u, y1, y2)


def sample(keys, t, rest):
    if not keys:
        return rest
    if t <= keys[0]["t"]:
        return keys[0]["v"]
    for i in range(1, len(keys)):
        if t < keys[i]["t"]:
            a, b = keys[i - 1], keys[i]
            p = ease(a.get("ease", "inOut"), (t - a["t"]) / (b["t"] - a["t"]))
            if isinstance(a["v"], list):
                return [a["v"][k] + (b["v"][k] - a["v"][k]) * p for k in range(2)]
            return a["v"] + (b["v"] - a["v"]) * p
    return keys[-1]["v"]


def expression(keys, t):
    value = keys[0]["v"]
    for key in keys:
        if key["t"] <= t:
            value = key["v"]
    return value


def pose(clip, t):
    tr = clip["tracks"]
    return {
        "offset": sample(tr.get("position"), t, [0, 0]),
        "rotation": sample(tr.get("rotation"), t, 0),
        "scale": sample(tr.get("scale"), t, [1, 1]),
        "squash": sample(tr.get("squash"), t, 0),
        "gaze": sample(tr.get("gaze"), t, [0, 0]),
        "lids": sample(tr.get("lids"), t, 0),
        "expression": expression(tr["expression"], t),
    }


motion = json.load(open(sys.argv[1]))
clips = motion["clips"]
checks = [
    ("旋转与挤压同时变化的中间帧", "celebrate", 0.36),
    ("表情切换前一刻", "alarm", 0.6999),
    ("表情切换当刻", "alarm", 0.7),
    ("循环接缝前一刻", "idle", 5.5999),
    ("循环接缝后（回到片段开头）", "idle", 0),
    ("匀速与回弹缓动", "working", 1.62),
]
out = {
    "formatVersion": 1,
    "tolerance": 1e-5,
    "checks": [{"name": n, "clip": c, "t": t, "expect": pose(clips[c], t)} for n, c, t in checks],
}
json.dump(out, open(sys.argv[2], "w"), ensure_ascii=False, indent=2)
print(json.dumps(out, ensure_ascii=False, indent=1))
