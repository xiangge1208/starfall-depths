# -*- coding: utf-8 -*-
"""占位音效生成器（可重复运行，输出确定性一致）。纯标准库实现。

用法:
    python tools/gen_placeholder_sfx.py

输出:
    audio/generated/sfx/*.wav   事件音效占位
    audio/generated/music/*.wav 菜单/战斗 BGM 循环占位
    audio/generated/MANIFEST.md 音效清单

说明: 当前工程没有任何音频播放代码（grep 无 AudioStreamPlayer），
本目录为音频系统落地前的占位与需求清单。全部 22050Hz/16bit/单声道。
"""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "audio" / "generated"
SR = 22050

SPEC = []  # [(relpath, purpose, trigger_point, seconds)]


def add(rel, purpose, trigger, sec):
    SPEC.append((rel, purpose, trigger, sec))


# ------------------------------------------------------------- 基础波形
def env(t, dur, attack=0.005, release=0.05):
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


def sine(f, t):
    return math.sin(2 * math.pi * f * t)


def square(f, t):
    return 1.0 if math.sin(2 * math.pi * f * t) >= 0 else -1.0


def saw(f, t):
    return 2.0 * ((f * t) % 1.0) - 1.0


def tri(f, t):
    p = (f * t) % 1.0
    return 4 * abs(p - 0.5) - 1


class Buf:
    def __init__(self, dur):
        self.n = int(SR * dur)
        self.data = [0.0] * self.n

    def mix(self, fn, gain=1.0, delay=0.0):
        off = int(SR * delay)
        for i in range(self.n - off):
            t = i / SR
            self.data[off + i] += fn(t) * gain

    def normalize(self, peak=0.82):
        m = max(1e-9, max(abs(v) for v in self.data))
        k = peak / m
        self.data = [v * k for v in self.data]

    def fade_out(self, dur):
        n = int(SR * dur)
        for i in range(n):
            self.data[-n + i] *= (n - i) / n

    def save(self, rel, purpose, trigger):
        p = OUT / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        self.normalize()
        self.fade_out(0.03)
        with wave.open(str(p), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(b"".join(
                struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in self.data))
        add(rel, purpose, trigger, round(self.n / SR, 2))


def slide(f0, f1, dur, wave_fn=sine):
    return lambda t: wave_fn(f0 + (f1 - f0) * (t / dur), t) * env(t, dur)


def burst(dur, gain=1.0, seed=1):
    import random
    rng = random.Random(seed)
    return lambda t: (rng.random() * 2 - 1) * math.exp(-6.0 * t / dur) * gain


# ------------------------------------------------------------- 音效
def sfx_shoot_player():
    b = Buf(0.09)
    b.mix(slide(900, 480, 0.09, square), 0.5)
    b.mix(slide(1800, 900, 0.05), 0.25)
    b.save("sfx/shoot_player.wav", "玩家武器射击", "core/player/weapon_rig.gd 开火处（待建 Sfx autoload）")


def sfx_shoot_enemy():
    b = Buf(0.11)
    b.mix(slide(420, 240, 0.11, square), 0.5)
    b.save("sfx/shoot_enemy.wav", "敌人射击", "EnemyBase.fire_bullet / 原型 _engage 开火")


def sfx_melee():
    b = Buf(0.14)
    b.mix(burst(0.14, 0.9, 3), 0.7)
    b.mix(slide(300, 90, 0.14), 0.2)
    b.save("sfx/melee_swing.wav", "近战挥砍", "core/player/melee.gd 挥击触发")


def sfx_hit_enemy():
    b = Buf(0.07)
    b.mix(burst(0.07, 0.8, 5), 0.8)
    b.mix(slide(220, 140, 0.07, tri), 0.5)
    b.save("sfx/hit_enemy.wav", "命中敌人（普通）", "EventBus.enemy_damaged 消费处")


def sfx_crit():
    b = Buf(0.12)
    b.mix(slide(1300, 900, 0.05, square), 0.4)
    b.mix(slide(1700, 1200, 0.05, square), 0.4, delay=0.05)
    b.mix(burst(0.12, 0.7, 6), 0.5)
    b.save("sfx/crit_hit.wav", "暴击命中", "enemy_damaged is_crit=true 分支")


def sfx_player_hurt():
    b = Buf(0.22)
    b.mix(slide(400, 110, 0.22, saw), 0.7)
    b.mix(burst(0.1, 0.6, 7), 0.4)
    b.save("sfx/player_hurt.wav", "玩家受伤", "EventBus.player_damaged 消费处")


def sfx_enemy_die():
    b = Buf(0.3)
    b.mix(slide(520, 90, 0.3, square), 0.45)
    b.mix(burst(0.25, 0.8, 8), 0.6)
    b.save("sfx/enemy_die.wav", "敌人死亡", "EventBus.enemy_killed 消费处")


def sfx_explosion():
    b = Buf(0.5)
    b.mix(slide(120, 40, 0.5, sine), 0.9)
    b.mix(burst(0.45, 1.0, 9), 0.9)
    b.save("sfx/explosion.wav", "爆炸（自爆/死亡爆/Boss 弹雨）", "Fx.on_explosion / die() _death_explosion")


def sfx_roll():
    b = Buf(0.16)
    b.mix(burst(0.16, 0.7, 10), 0.55)
    b.mix(slide(700, 300, 0.16, tri), 0.15)
    b.save("sfx/roll.wav", "玩家翻滚", "Player.start_roll → Fx.on_roll")


def sfx_pickup_coin():
    b = Buf(0.14)
    b.mix(lambda t: square(1320, t) * env(t, 0.06), 0.35)
    b.mix(lambda t: square(1980, t) * env(t, 0.08), 0.35, delay=0.06)
    b.save("sfx/pickup_coin.wav", "金币拾取", "core/rooms/pickup.gd coin 拾取")


def sfx_pickup_heart():
    b = Buf(0.3)
    for i, f in enumerate((523, 659, 784)):
        b.mix(lambda t, f=f: tri(f, t) * env(t, 0.12), 0.4, delay=i * 0.08)
    b.save("sfx/pickup_heart.wav", "红心拾取", "pickup.gd heart 拾取")


def sfx_pickup_energy():
    b = Buf(0.12)
    b.mix(slide(880, 1500, 0.12, tri), 0.5)
    b.save("sfx/pickup_energy.wav", "蓝能拾取", "pickup.gd energy 拾取")


def sfx_drink():
    b = Buf(0.35)
    for i, f in enumerate((240, 300, 380)):
        b.mix(lambda t, f=f: sine(f, t) * env(t, 0.08, 0.005, 0.04), 0.8, delay=i * 0.1)
    b.save("sfx/drink.wav", "喝饮料", "core/interact/drink_machine.gd 购买确认")


def sfx_buff_pick():
    b = Buf(0.4)
    for i, f in enumerate((523, 659, 784, 1046)):
        b.mix(lambda t, f=f: square(f, t) * env(t, 0.12), 0.25, delay=i * 0.08)
    b.save("sfx/buff_pick.wav", "Buff 三选一确认", "ui/buff_pick.gd 选择确认")


def sfx_door_open():
    b = Buf(0.4)
    b.mix(slide(110, 70, 0.4, saw), 0.4)
    b.mix(burst(0.3, 0.4, 11), 0.3)
    b.save("sfx/door_open.wav", "房门开启", "floor_scene.gd 门开启动画 / inter_floor 进门")


def sfx_shield_break():
    b = Buf(0.25)
    b.mix(burst(0.22, 1.0, 12), 0.8)
    b.mix(slide(2400, 900, 0.2, tri), 0.3)
    b.save("sfx/shield_break.wav", "护盾破碎（坚守被动触发点）", "EventBus.shield_broken → Player._on_shield_broken")


def sfx_ui_click():
    b = Buf(0.04)
    b.mix(lambda t: square(1000, t) * env(t, 0.03, 0.002, 0.02), 0.5)
    b.save("sfx/ui_click.wav", "UI 点击", "全部按钮按下")


def sfx_ui_buy():
    b = Buf(0.25)
    b.mix(lambda t: square(1400, t) * env(t, 0.1), 0.3)
    b.mix(lambda t: square(2100, t) * env(t, 0.12), 0.3, delay=0.09)
    b.save("sfx/ui_buy.wav", "购买成功", "core/meta/shop_logic.gd 购买成功")


def sfx_ui_error():
    b = Buf(0.18)
    b.mix(lambda t: square(180, t) * env(t, 0.16, 0.005, 0.05), 0.6)
    b.save("sfx/ui_error.wav", "购买失败/操作无效", "shop.gd FAIL_FLASH 处")


def sfx_boss_roar():
    b = Buf(0.8)
    b.mix(lambda t: saw(80 + 8 * math.sin(2 * math.pi * 6 * t), t) * env(t, 0.8, 0.05, 0.3), 0.8)
    b.mix(slide(50, 40, 0.8, sine), 0.6)
    b.save("sfx/boss_roar.wav", "Boss 登场咆哮", "vine_colossus.gd 开战入场")


def sfx_room_clear():
    b = Buf(0.45)
    for i, f in enumerate((659, 784, 988, 1319)):
        b.mix(lambda t, f=f: tri(f, t) * env(t, 0.14, 0.01, 0.08), 0.32, delay=i * 0.09)
    b.save("sfx/room_clear.wav", "房间清空（开门/结算提示）", "floor_flow.gd 房间清空判定 / 开门动画")


def sfx_boss_phase():
    b = Buf(0.5)
    b.mix(slide(200, 90, 0.5, saw), 0.55)
    b.mix(burst(0.35, 0.6, 13), 0.5)
    b.mix(lambda t: square(300, t) * env(t, 0.1, 0.005, 0.05), 0.3, delay=0.3)
    b.save("sfx/boss_phase.wav", "Boss 换阶段提示", "vine_colossus.gd 阶段切换（3 阶段）")


def sfx_lowhp():
    b = Buf(0.6)
    for delay in (0.0, 0.28):
        b.mix(lambda t: sine(70, t) * env(t, 0.12, 0.005, 0.09), 0.9, delay=delay)
    b.save("sfx/lowhp_heartbeat.wav", "低血警告心跳（循环）", "hud.gd:184 vignette 低血红屏触发处（hp<=2 循环播放）")


# ------------------------------------------------------------- BGM
# ------------------------------------------------------- M2: 武器类射击/机制音
def sfx_shoot_bow():
    b = Buf(0.12)
    b.mix(slide(260, 90, 0.12, tri), 0.6)
    b.mix(burst(0.05, 0.5, 20), 0.4)
    b.save("sfx/shoot_bow.wav", "弓弩射击（弦振）", "weapons.json category=bow 开火")


def sfx_shoot_staff():
    b = Buf(0.16)
    b.mix(slide(900, 1500, 0.16, sine), 0.35)
    b.mix(slide(1350, 2200, 0.12, tri), 0.2, delay=0.03)
    b.save("sfx/shoot_staff.wav", "法杖射击（嗡鸣）", "category=staff 开火")


def sfx_shoot_laser():
    b = Buf(0.09)
    b.mix(slide(1900, 320, 0.09, square), 0.45)
    b.mix(slide(3800, 640, 0.09, sine), 0.2)
    b.save("sfx/shoot_laser.wav", "激光射击（电 zap）", "category=laser 开火")


def sfx_shoot_throw():
    b = Buf(0.1)
    b.mix(burst(0.1, 0.8, 21), 0.6)
    b.mix(slide(500, 220, 0.1, sine), 0.2)
    b.save("sfx/shoot_throw.wav", "投掷出手（呼啸）", "category=throwable 开火")


def sfx_shoot_sniper():
    b = Buf(0.22)
    b.mix(burst(0.04, 1.0, 22), 0.9)
    b.mix(slide(140, 60, 0.2, sine), 0.7)
    b.save("sfx/shoot_sniper.wav", "狙击/重炮（爆响）", "category=sniper 开火")


def sfx_shoot_shotgun():
    b = Buf(0.18)
    b.mix(burst(0.12, 0.9, 23), 0.8)
    b.mix(slide(220, 90, 0.16, square), 0.4)
    b.save("sfx/shoot_shotgun.wav", "霰弹（轰）", "category=shotgun 开火")


def sfx_shoot_smg():
    b = Buf(0.04)
    b.mix(slide(1300, 900, 0.04, square), 0.4)
    b.save("sfx/shoot_smg.wav", "冲锋枪（急促 tick）", "category=smg 开火")


def sfx_shoot_rifle():
    b = Buf(0.09)
    b.mix(slide(430, 160, 0.08, square), 0.5)
    b.mix(burst(0.06, 0.6, 24), 0.4)
    b.save("sfx/shoot_rifle.wav", "步枪（脆响）", "category=rifle 开火")


def sfx_reflect():
    b = Buf(0.14)
    b.mix(lambda t: sine(2500, t) * env(t, 0.1, 0.002, 0.08), 0.4)
    b.mix(lambda t: sine(3150, t) * env(t, 0.12, 0.002, 0.1), 0.25)
    b.save("sfx/reflect.wav", "近战反弹弹幕（清脆 ping）", "melee.gd 反弹窗口命中（GDD §7.4）")


def sfx_freeze():
    b = Buf(0.2)
    b.mix(slide(600, 1200, 0.15, tri), 0.4)
    b.mix(burst(0.15, 0.5, 25), 0.35)
    b.save("sfx/freeze.wav", "冻结生效", "冰状态叠满冻结（GDD §7.3）")


def sfx_nova():
    b = Buf(0.32)
    b.mix(slide(1300, 260, 0.3, sine), 0.5)
    b.mix(burst(0.3, 0.6, 26), 0.4)
    b.save("sfx/nova.wav", "奥术新星（法师技能）", "法师·烬 skill 奥术新星")


def sfx_turret_place():
    b = Buf(0.12)
    b.mix(lambda t: square(210, t) * env(t, 0.06, 0.002, 0.04), 0.5)
    b.mix(lambda t: sine(820, t) * env(t, 0.09, 0.002, 0.07), 0.3, delay=0.03)
    b.save("sfx/turret_place.wav", "炮台部署", "工程师·铆 技能/被动")


def sfx_turret_shot():
    b = Buf(0.04)
    b.mix(slide(1600, 1100, 0.035, square), 0.35)
    b.save("sfx/turret_shot.wav", "炮台射击", "工程师炮台开火")


def sfx_missile():
    b = Buf(0.3)
    b.mix(slide(90, 340, 0.28, saw), 0.45)
    b.mix(burst(0.25, 0.5, 27), 0.3)
    b.save("sfx/missile.wav", "导弹发射（炮台强化/星陨炮）", "工程师强化导弹 / 星陨炮")


def sfx_heal_tide():
    b = Buf(0.42)
    for i, f in enumerate((392, 523, 659)):
        b.mix(lambda t, f=f: tri(f, t) * env(t, 0.2, 0.02, 0.12), 0.3, delay=i * 0.1)
    b.save("sfx/heal_tide.wav", "生命潮汐（守护者治疗法阵）", "守护者·萄 技能")


def sfx_forge():
    b = Buf(0.4)
    b.mix(burst(0.1, 0.9, 28), 0.7)
    b.mix(lambda t: square(230, t) * env(t, 0.12, 0.002, 0.09), 0.5)
    b.mix(burst(0.25, 0.4, 29), 0.35, delay=0.15)
    b.save("sfx/forge.wav", "熔铸台锻造", "GDD §8.3 熔铸确认")


def sfx_destroy():
    b = Buf(0.28)
    b.mix(burst(0.24, 0.9, 30), 0.8)
    b.mix(slide(300, 80, 0.25, tri), 0.35)
    b.save("sfx/destroy.wav", "可破坏掩体被摧毁", "GDD §9.2 掩体 HP→0")


def sfx_spikes():
    b = Buf(0.06)
    b.mix(burst(0.05, 0.9, 31), 0.7)
    b.save("sfx/spikes.wav", "地刺弹出/收回归位", "A2 地刺陷阱")


def sfx_lava_burn():
    b = Buf(0.3)
    import random as _r
    rng = _r.Random(33)
    b.mix(lambda t: (rng.random() * 2 - 1) * (0.6 + 0.4 * math.sin(40 * t)) * math.exp(-4 * t), 0.55)
    b.save("sfx/lava_burn.wav", "岩浆灼烧（DOT 跳伤）", "A3 岩浆地块结算")


def sfx_empty():
    b = Buf(0.07)
    b.mix(slide(160, 90, 0.07, tri), 0.6)
    b.save("sfx/empty.wav", "空仓（蓝耗尽禁射）", "weapon_rig.try_fire 蓝不足分支（GDD §7.2 HUD 变灰+空仓音）")


def sfx_door_lock():
    b = Buf(0.2)
    b.mix(burst(0.1, 0.8, 32), 0.6)
    b.mix(slide(90, 55, 0.18, sine), 0.8)
    b.save("sfx/door_lock.wav", "战斗房落闸锁门", "GDD §11 战斗房进门落闸")


def sfx_crystal_get():
    b = Buf(0.22)
    b.mix(lambda t: sine(1568, t) * env(t, 0.12, 0.002, 0.1), 0.35)
    b.mix(lambda t: sine(2093, t) * env(t, 0.16, 0.002, 0.13), 0.3, delay=0.07)
    b.save("sfx/crystal_get.wav", "获得蓝晶", "局内蓝晶掉落/结算")


def sfx_unlock():
    b = Buf(0.4)
    for i, f in enumerate((523, 659, 784, 1046)):
        b.mix(lambda t, f=f: square(f, t) * env(t, 0.13, 0.005, 0.08), 0.22, delay=i * 0.08)
    b.save("sfx/unlock.wav", "解锁提示（图鉴/成就/角色 toast）", "GDD §19 右下角 toast")


def sfx_fuse_beep():
    b = Buf(0.24)
    for i in range(3):
        b.mix(lambda t: square(1150, t) * env(t, 0.05, 0.002, 0.03), 0.4, delay=i * 0.08)
    b.save("sfx/fuse_beep.wav", "自爆引信倒计时哔声", "苦力虫/自爆王虫 fuse（配 fx/fuse_zone）")


def music_crystal():
    """A2 晶核洞穴 BGM：冷色调慢琶音（Dm-Am-Bb-F），三角波+正弦垫。"""
    dur, bpm = 9.6, 96
    beat = 60 / bpm
    b = Buf(dur)
    prog = [(293.7, 349.2, 440), (220, 261.6, 329.6), (233.1, 293.7, 349.2), (349.2, 440, 523.3)]
    for bar in range(4):
        t0 = bar * 2 * beat
        chord = prog[bar]
        for k in range(8):
            off = int((t0 + k * beat / 2) * SR)
            f = chord[k % 3]
            for i in range(int(beat / 2 * SR * 0.9)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += sine(f, t) * env(t, beat / 2 * 0.9, 0.02, 0.12) * 0.22
        for i in range(int(2 * beat * SR)):
            t = i / SR
            b.data[int(t0 * SR) + i] += tri(chord[0] / 2, t) * env(t, 2 * beat, 0.03, 0.4) * 0.16
    b.save("music/music_crystal.wav", "A2 晶核洞穴 BGM 循环", "GDD §17 音乐=菜单1+生态3+Boss1")


def music_magma():
    """A3 熔火核心 BGM：低音驱动+密集镲（E 弗里几亚）。"""
    dur, bpm = 12.0, 150
    beat = 60 / bpm
    b = Buf(dur)
    roots = [82.4, 82.4, 87.3, 98.0]  # E2 E2 F2 G2
    for bar in range(8):
        t0 = bar * 2 * beat
        root = roots[bar % 4]
        for k in range(8):
            off = int((t0 + k * beat / 2) * SR)
            f = root * (2 if k in (3, 6) else 1)
            for i in range(int(beat / 2 * SR * 0.8)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += saw(f, t) * env(t, beat / 2 * 0.8, 0.004, 0.05) * 0.14
        import random as _r
        rng = _r.Random(bar + 50)
        for k in range(8):
            off = int((t0 + k * beat / 2) * SR)
            for i in range(int(0.03 * SR)):
                if off + i >= b.n:
                    break
                b.data[off + i] += (rng.random() * 2 - 1) * math.exp(-90 * i / SR) * 0.2
    b.save("music/music_magma.wav", "A3 熔火核心 BGM 循环", "GDD §17")


def music_boss():
    """Boss 战 BGM：138BPM 贴合射击节奏（GDD §17），驱动贝斯+旋律层。"""
    dur, bpm = 17.4, 138
    beat = 60 / bpm
    b = Buf(dur)
    roots = [110, 110, 87.3, 103.8]  # A2 A2 F2 G#2
    for bar in range(12):
        t0 = bar * 2 * beat
        root = roots[bar % 4]
        for k in range(8):
            off = int((t0 + k * beat / 2) * SR)
            f = root * (1.5 if k in (3, 7) else 1.0)
            for i in range(int(beat / 2 * SR * 0.85)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += square(f, t) * env(t, beat / 2 * 0.85, 0.003, 0.04) * 0.15
        lead = [root * 4, root * 4.5, root * 5, root * 4.5]
        for k in range(4):
            off = int((t0 + k * beat / 2) * SR)
            f = lead[k]
            for i in range(int(beat / 2 * SR * 0.7)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += square(f, t) * env(t, beat / 2 * 0.7, 0.004, 0.05) * 0.08
        import random as _r
        rng = _r.Random(bar + 90)
        for k in (0, 1, 2, 3):
            off = int((t0 + k * beat / 2) * SR)
            for i in range(int(0.09 * SR)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += math.sin(2 * math.pi * (90 - 300 * t) * t) * math.exp(-28 * t) * 0.6
        for k in range(8):
            off = int((t0 + k * beat + beat / 2) * SR)
            for i in range(int(0.04 * SR)):
                if off + i >= b.n:
                    break
                b.data[off + i] += (rng.random() * 2 - 1) * math.exp(-80 * i / SR) * 0.22
    b.save("music/music_boss.wav", "Boss 战 BGM 循环", "Boss 房（M2 起 6 Boss 共用, 后续可分层）")


def music_menu():
    dur, bpm = 9.6, 100
    beat = 60 / bpm
    b = Buf(dur)
    prog = [(220, 261.6, 329.6), (174.6, 220, 261.6), (130.8, 164.8, 196), (196, 246.9, 293.7)]
    for bar in range(4):
        t0 = bar * 2 * beat
        chord = prog[bar]
        for k in range(8):
            tt = t0 + k * beat / 2
            f = chord[k % 3] * (2 if k % 4 == 2 else 1)
            off = int(tt * SR)
            for i in range(int(beat / 2 * SR * 0.9)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += (tri(f, t) * 0.5 + sine(f / 2, t) * 0.3) * env(t, beat / 2 * 0.9, 0.01, 0.1) * 0.30
        for i in range(int(2 * beat * SR)):
            t = i / SR
            b.data[int(t0 * SR) + i] += sine(chord[0] / 2, t) * env(t, 2 * beat, 0.02, 0.4) * 0.18
    b.save("music/music_menu.wav", "主菜单/层间 BGM 循环", "ui/main_menu.tscn / inter_floor.tscn（待建音频管理器）")


def music_battle():
    dur, bpm = 19.2, 140
    beat = 60 / bpm
    b = Buf(dur)
    root_notes = [110, 110, 87.3, 98]  # A2 A2 F2 G2
    for bar in range(8):
        t0 = bar * 4 * beat
        root = root_notes[bar % 4]
        for k in range(8):
            tt = t0 + k * beat / 2
            off = int(tt * SR)
            f = root * (1.5 if k in (3, 7) else 1.0)
            for i in range(int(beat / 2 * SR * 0.85)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += square(f, t) * env(t, beat / 2 * 0.85, 0.004, 0.05) * 0.16
        # 琶音
        arp = [root * 2, root * 2.5, root * 3, root * 4]
        for k in range(16):
            tt = t0 + k * beat / 4
            off = int(tt * SR)
            f = arp[k % 4]
            for i in range(int(beat / 4 * SR * 0.8)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += tri(f, t) * env(t, beat / 4 * 0.8, 0.003, 0.04) * 0.10
        # 鼓点: 1/3 拍 kick(低正弦), 半拍 hihat(噪声)
        import random
        rng = random.Random(bar)
        for k in (0, 2):
            off = int((t0 + k * beat) * SR)
            for i in range(int(0.1 * SR)):
                if off + i >= b.n:
                    break
                t = i / SR
                b.data[off + i] += math.sin(2 * math.pi * (90 - 300 * t) * t) * math.exp(-30 * t) * 0.7
        for k in range(8):
            off = int((t0 + k * beat + beat / 2) * SR)
            for i in range(int(0.04 * SR)):
                if off + i >= b.n:
                    break
                b.data[off + i] += (rng.random() * 2 - 1) * math.exp(-80 * i / SR) * 0.25
    b.save("music/music_battle.wav", "战斗 BGM 循环", "room_combat / floor_scene 战斗态（待建音频管理器）")


def write_manifest():
    lines = [
        "# 占位音效清单（audio/generated）",
        "",
        "> 由 `tools/gen_placeholder_sfx.py` 生成（纯标准库，重跑可复现）。22050Hz / 16bit / 单声道 WAV。",
        "> **当前工程没有任何音频代码**（无 AudioStreamPlayer / bus 配置），本目录既是占位也是需求清单。",
        "",
        "| 文件 | 用途 | 触发点（接线位置） | 时长(s) |",
        "|---|---|---|---|",
    ]
    for rel, purpose, trigger, sec in SPEC:
        lines.append(f"| `{rel}` | {purpose} | {trigger} | {sec} |")
    lines += [
        "",
        "## 落地建议",
        "",
        "1. 新建 `autoload/sfx.gd`：`play(name, pitch_scale=1.0, volume_db=0.0)`，预加载本目录 WAV（Godot 导入 WAV 无损、体积可接受）。",
        "2. BGM 用 `AudioStreamWAV.loop_mode=forward` 或改用 OGG；战斗/菜单两张 bus（Music/SFX）便于统一调音量。",
        "3. 正式素材采购/录制后按同名替换本目录文件即可，无需改代码。",
        "",
        "## 待采购（无法程序生成）",
        "",
        "- 语音/旁白（如有）、Boss 专属台词音、环境音（洞穴水滴/风）。",
    ]
    (OUT / "MANIFEST.md").write_text("\n".join(lines), encoding="utf-8")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    SPEC.clear()
    for p in OUT.rglob("*.wav"):
        p.unlink()
    sfx_shoot_player()
    sfx_shoot_enemy()
    sfx_melee()
    sfx_hit_enemy()
    sfx_crit()
    sfx_player_hurt()
    sfx_enemy_die()
    sfx_explosion()
    sfx_roll()
    sfx_pickup_coin()
    sfx_pickup_heart()
    sfx_pickup_energy()
    sfx_drink()
    sfx_buff_pick()
    sfx_door_open()
    sfx_shield_break()
    sfx_ui_click()
    sfx_ui_buy()
    sfx_ui_error()
    sfx_boss_roar()
    sfx_room_clear()
    sfx_boss_phase()
    sfx_lowhp()
    # M2 批次
    sfx_shoot_bow()
    sfx_shoot_staff()
    sfx_shoot_laser()
    sfx_shoot_throw()
    sfx_shoot_sniper()
    sfx_shoot_shotgun()
    sfx_shoot_smg()
    sfx_shoot_rifle()
    sfx_reflect()
    sfx_freeze()
    sfx_nova()
    sfx_turret_place()
    sfx_turret_shot()
    sfx_missile()
    sfx_heal_tide()
    sfx_forge()
    sfx_destroy()
    sfx_spikes()
    sfx_lava_burn()
    sfx_empty()
    sfx_door_lock()
    sfx_crystal_get()
    sfx_unlock()
    sfx_fuse_beep()
    music_menu()
    music_battle()
    music_crystal()
    music_magma()
    music_boss()
    write_manifest()
    print(f"生成 {len(SPEC)} 个音频 -> {OUT}")


if __name__ == "__main__":
    main()
