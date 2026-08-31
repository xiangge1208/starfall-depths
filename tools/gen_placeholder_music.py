# -*- coding: utf-8 -*-
"""m2-t22 占位音乐生成器：程序化芯片风 5 曲（菜单 1 + 生态 3 + Boss 1）。

用法:
    python tools/gen_placeholder_music.py            # 已存在的曲目跳过（幂等）
    python tools/gen_placeholder_music.py --force    # 全量重生成（覆盖既有文件）

输出:
    audio/generated/music/music_menu.wav     A0 主菜单（120 BPM, 120s 无缝循环）
    audio/generated/music/music_garden.wav   A1 庭院生态（126 BPM, 120s）
    audio/generated/music/music_crystal.wav  A2 晶核洞穴（120 BPM, 120s）
    audio/generated/music/music_magma.wav    A3 熔火核心（140 BPM, 120s）
    audio/generated/music/music_boss.wav     Boss 战（138 BPM, 120s）

规格（GDD §17）: 芯片音三轨（方波/三角波/噪声简单音型），120~140 BPM，
2 分钟首尾无缝循环，seed 固定可复现（每曲独立 SEED，纯标准库确定性）。
无缝口径: 循环总长 = 整数小节；所有音符完整落在循环内（包络在音符内归零，
不跨循环边界），首尾衔接处振幅为 0 —— 运行时配合 AudioMgr 的
AudioStreamWAV.LOOP_FORWARD 全长循环即可无爆音循环（disclose: 循环点在
Godot 侧运行时启用，非 WAV smpl chunk）。
全部 22050Hz / 16bit / 单声道（与 tools/gen_placeholder_sfx.py 同规格）。
"""
import argparse
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "audio" / "generated" / "music"
SR = 22050
LOOP_SECONDS = 120.0        # GDD §17: 2 分钟无缝循环
PEAK = 0.75                 # 归一化峰值（不做尾部 fade——保持循环衔接）


# ------------------------------------------------------------- 波形基元
class LoopBuf:
    """定长循环缓冲；音符按绝对时间写入，越界样本静默丢弃（防御）。"""

    def __init__(self, dur):
        self.n = int(round(SR * dur))
        self.data = [0.0] * self.n

    def note(self, t0, dur, freq, wave_fn, gain, attack=0.01, release=0.06):
        """单音符：包络(线性 attack/release) × 波形，相位增量法（无逐样本三角函数）。"""
        start = int(round(t0 * SR))
        count = int(round(dur * SR))
        a = max(1, int(attack * SR))
        r = max(1, int(release * SR))
        phase = 0.0
        step = freq / SR
        for i in range(count):
            j = start + i
            if j >= self.n:
                break
            t = i / SR
            env = 1.0
            if i < a:
                env = i / a
            elif i > count - r:
                env = max(0.0, (count - i) / r)
            phase += step
            self.data[j] += wave_fn(phase) * env * gain

    def normalize(self, peak=PEAK):
        m = max(1e-9, max(abs(v) for v in self.data))
        k = peak / m
        self.data = [v * k for v in self.data]

    def save(self, name, purpose, bpm, seed):
        p = OUT / name
        p.parent.mkdir(parents=True, exist_ok=True)
        self.normalize()
        frames = bytearray()
        for v in self.data:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
        with wave.open(str(p), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(bytes(frames))
        print(f"  {name:22s} {bpm:3d} BPM  {self.n / SR:6.2f}s  seed={seed}  {purpose}")


def sq(phase):
    """方波：相位 0..1 → ±1（<0.5 为正）。"""
    return 1.0 if (phase - math.floor(phase)) < 0.5 else -1.0


def tri(phase):
    """三角波：相位 0..1 → -1..1..-1。"""
    p = phase - math.floor(phase)
    return 4.0 * abs(p - 0.5) - 1.0


def noise_fn(rng):
    return lambda _phase: rng.random() * 2.0 - 1.0


def sine_fn(freq):
    w = 2.0 * math.pi * freq
    return lambda phase: math.sin(w * (phase / freq))


def bar_len(bpm):
    return 4.0 * 60.0 / bpm


def bars_for(bpm):
    """取恰好覆盖 LOOP_SECONDS 的整数小节数（各曲选型下恰为 120.0s）。"""
    return int(round(LOOP_SECONDS / bar_len(bpm)))


def drum(buf, rng, t0, kind):
    """噪声打击：kind='kick'(低频感长衰减) / 'hat'(短促)。"""
    if kind == "kick":
        buf.note(t0, 0.10, 55.0, noise_fn(rng), 0.55, attack=0.001, release=0.07)
    else:
        buf.note(t0, 0.035, 0.0, noise_fn(rng), 0.18, attack=0.001, release=0.02)


# ------------------------------------------------------------- 五曲
def music_menu():
    """A0 主菜单：Am-F-C-G 慢琶音垫（三角波铺底 + 正弦低音 + 方波高音点缀），120 BPM。"""
    bpm, seed = 120, 20260831
    rng = random.Random(seed)
    bl = bar_len(bpm)
    buf = LoopBuf(bars_for(bpm) * bl)
    prog = [
        (110.0, 130.81, 164.81),   # Am
        (87.31, 110.0, 130.81),    # F
        (130.81, 164.81, 196.0),   # C
        (98.0, 123.47, 146.83),    # G
    ]
    for bar in range(bars_for(bpm)):
        t0 = bar * bl
        chord = prog[bar % 4]
        # 铺底：根音三角波整小节（慢起音，包络在小节内归零——循环无缝）
        buf.note(t0, bl, chord[0], tri, 0.30, attack=0.10, release=0.35)
        # 低音：根音低八度正弦，2 分音符
        for half in (0.0, bl / 2):
            buf.note(t0 + half, bl / 2, chord[0] / 2, sine_fn(chord[0] / 2), 0.34,
                     attack=0.02, release=0.12)
        # 高音琶音：方波 8 分音符走和弦音（每 4 小节一次装饰八度）
        for k in range(8):
            f = chord[k % 3] * 4.0
            if (bar % 4 == 3) and k % 4 == 2:
                f *= 1.5
            buf.note(t0 + k * bl / 8, bl / 8 * 0.9, f, sq, 0.10,
                     attack=0.008, release=0.05)
        # 风铃：每 4 小节尾拍一颗高音三角波
        if bar % 4 == 3:
            buf.note(t0 + bl * 0.75, bl / 4, chord[2] * 4.0, tri, 0.14,
                     attack=0.01, release=0.15)
        _ = rng  # 本曲全确定性（无噪声轨），rng 仅占位保持签名一致
    buf.save("music_menu.wav", "A0 主菜单/层间 BGM", bpm, seed)


def music_garden():
    """A1 庭院生态：C 大调五声田园（三角波主旋律 + 方波琶音 + 三角低音 + 噪声沙锤），126 BPM。"""
    bpm, seed = 126, 20260922
    rng = random.Random(seed)
    bl = bar_len(bpm)
    buf = LoopBuf(bars_for(bpm) * bl)
    pent = [523.25, 587.33, 659.26, 783.99, 880.0]   # C5 D5 E5 G5 A5
    prog = [
        (130.81, 164.81, 196.0),   # C
        (87.31, 110.0, 130.81),    # F
        (110.0, 130.81, 164.81),   # Am
        (98.0, 123.47, 146.83),    # G
    ]
    for bar in range(bars_for(bpm)):
        t0 = bar * bl
        chord = prog[bar % 4]
        # 主旋律：五声音阶随机游走（seed 确定），8 分/4 分混合
        idx = bar % len(pent)
        k = 0
        while k < 8:
            step = 2 if rng.random() < 0.35 else 1
            f = pent[idx % len(pent)]
            buf.note(t0 + k * bl / 8, bl / 8 * step * 0.92, f, tri, 0.17,
                     attack=0.012, release=0.07)
            idx += 1 if rng.random() < 0.7 else -1
            k += step
        # 琶音：方波 8 分和弦音（中音区）
        for k in range(8):
            f = chord[k % 3] * 2.0
            buf.note(t0 + k * bl / 8, bl / 8 * 0.85, f, sq, 0.075,
                     attack=0.006, release=0.04)
        # 低音：根音三角波 1/3 拍
        for k in (0, 2):
            buf.note(t0 + k * bl / 4, bl / 4 * 0.9, chord[0] / 2, tri, 0.26,
                     attack=0.015, release=0.10)
        # 沙锤：反拍 8 分噪声
        for k in range(4):
            drum(buf, rng, t0 + (2 * k + 1) * bl / 8, "hat")
    buf.save("music_garden.wav", "A1 庭院生态 BGM", bpm, seed)


def music_crystal():
    """A2 晶核洞穴：Dm 冷色调（正弦和弦垫 + 三角波 16 分琶音 + 正弦低音），120 BPM。"""
    bpm, seed = 120, 20260714
    rng = random.Random(seed)
    bl = bar_len(bpm)
    buf = LoopBuf(bars_for(bpm) * bl)
    prog = [
        (146.83, 174.61, 220.0),   # Dm
        (116.54, 146.83, 174.61),  # Bb
        (130.81, 164.81, 196.0),   # C
        (174.61, 220.0, 261.63),   # F
    ]
    arp = [587.33, 698.46, 880.0, 1046.5]   # D5 F5 A5 C6
    for bar in range(bars_for(bpm)):
        t0 = bar * bl
        chord = prog[bar % 4]
        # 和弦垫：根音+五音正弦整小节
        buf.note(t0, bl, chord[0], sine_fn(chord[0]), 0.24, attack=0.12, release=0.30)
        buf.note(t0, bl, chord[2] / 2, sine_fn(chord[2] / 2), 0.14, attack=0.12, release=0.30)
        # 高音琶音：三角波 16 分循环（每小节起点音随小节移位）
        for k in range(16):
            f = arp[(k + bar) % 4]
            buf.note(t0 + k * bl / 16, bl / 16 * 0.85, f, tri, 0.095,
                     attack=0.004, release=0.04)
        # 低音：2 分音符正弦
        for half in (0.0, bl / 2):
            buf.note(t0 + half, bl / 2, chord[0] / 2, sine_fn(chord[0] / 2), 0.30,
                     attack=0.02, release=0.12)
        # 洞穴水滴：每 2 小节一颗高音正弦点
        if bar % 2 == 1:
            drum(buf, rng, t0 + bl * 0.5, "hat")
    buf.save("music_crystal.wav", "A2 晶核洞穴 BGM", bpm, seed)


def music_magma():
    """A3 熔火核心：E 弗里几亚驱动（方波低音 8 分 + 方波音型 + 噪声鼓），140 BPM。"""
    bpm, seed = 140, 20261031
    rng = random.Random(seed)
    bl = bar_len(bpm)
    buf = LoopBuf(bars_for(bpm) * bl)
    roots = [82.41, 82.41, 87.31, 98.0]        # E2 E2 F2 G2
    motif = [164.81, 164.81, 174.61, 196.0, 164.81, 246.94]   # E3 E3 F3 G3 E3 B3
    for bar in range(bars_for(bpm)):
        t0 = bar * bl
        root = roots[bar % 4]
        # 低音：方波 8 分（3/6 拍高八度强调）
        for k in range(8):
            f = root * (2.0 if k in (3, 6) else 1.0)
            buf.note(t0 + k * bl / 8, bl / 8 * 0.8, f, sq, 0.17,
                     attack=0.004, release=0.03)
        # 音型：方波单元（偶数小节）
        if bar % 2 == 0:
            for k, f in enumerate(motif):
                buf.note(t0 + k * bl / 8, bl / 8 * 0.75, f, sq, 0.09,
                         attack=0.004, release=0.03)
        # 三角波强拍：1/3 拍和弦楔
        for k in (0, 2):
            buf.note(t0 + k * bl / 4, bl / 4 * 0.8, root * 3.0, tri, 0.12,
                     attack=0.005, release=0.05)
        # 鼓：每拍 kick + 反拍 hat
        for k in range(4):
            drum(buf, rng, t0 + k * bl / 4, "kick")
            drum(buf, rng, t0 + k * bl / 4 + bl / 8, "hat")
    buf.save("music_magma.wav", "A3 熔火核心 BGM", bpm, seed)


def music_boss():
    """Boss 战：A 小调 138 BPM（GDD §17 战斗曲贴射击节奏；方波贝斯 + 方波 riff + 噪声鼓）。"""
    bpm, seed = 138, 20261225
    rng = random.Random(seed)
    bl = bar_len(bpm)
    buf = LoopBuf(bars_for(bpm) * bl)
    roots = [110.0, 110.0, 87.31, 103.83]      # A2 A2 F2 G#2
    riff = [440.0, 523.25, 493.88, 415.30]     # A4 C5 B4 G#4
    for bar in range(bars_for(bpm)):
        t0 = bar * bl
        root = roots[bar % 4]
        # 贝斯：方波 8 分驱动（4/7 拍五度）
        for k in range(8):
            f = root * (1.5 if k in (3, 7) else 1.0)
            buf.note(t0 + k * bl / 8, bl / 8 * 0.85, f, sq, 0.19,
                     attack=0.004, release=0.03)
        # Riff：方波 4 分移位（每 2 小节整体抬高/还原制造推进感）
        shift = 2.0 if (bar % 8) in (6, 7) else 1.0
        for k in range(4):
            f = riff[(k + bar) % 4] * shift
            buf.note(t0 + k * bl / 4 + (bl / 16 if bar % 2 else 0.0),
                     bl / 4 * 0.7, f, sq, 0.11, attack=0.004, release=0.04)
        # 三角波楔：1 拍根音高八度
        buf.note(t0, bl / 4 * 0.8, root * 4.0, tri, 0.10, attack=0.005, release=0.05)
        # 鼓：每拍 kick + 全部反拍 hat
        for k in range(4):
            drum(buf, rng, t0 + k * bl / 4, "kick")
            drum(buf, rng, t0 + k * bl / 4 + bl / 8, "hat")
    buf.save("music_boss.wav", "Boss 战 BGM", bpm, seed)


TRACKS = [music_menu, music_garden, music_crystal, music_magma, music_boss]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--force", action="store_true",
                    help="覆盖重生成全部曲目（默认跳过已存在文件）")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    made = 0
    for gen in TRACKS:
        target = OUT / (gen.__name__ + ".wav")   # 函数名 music_* 即文件名
        if target.exists() and not args.force:
            print(f"  skip {target.name}（已存在；--force 覆盖）")
            continue
        gen()
        made += 1
    print(f"生成 {made} 曲 -> {OUT}" + ("" if args.force else "（既有文件跳过）"))


if __name__ == "__main__":
    main()
