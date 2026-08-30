# 占位音效清单（audio/generated）

> 由 `tools/gen_placeholder_sfx.py` 生成（纯标准库，重跑可复现）。22050Hz / 16bit / 单声道 WAV。
> **当前工程没有任何音频代码**（无 AudioStreamPlayer / bus 配置），本目录既是占位也是需求清单。

| 文件 | 用途 | 触发点（接线位置） | 时长(s) |
|---|---|---|---|
| `sfx/shoot_player.wav` | 玩家武器射击 | core/player/weapon_rig.gd 开火处（待建 Sfx autoload） | 0.09 |
| `sfx/shoot_enemy.wav` | 敌人射击 | EnemyBase.fire_bullet / 原型 _engage 开火 | 0.11 |
| `sfx/melee_swing.wav` | 近战挥砍 | core/player/melee.gd 挥击触发 | 0.14 |
| `sfx/hit_enemy.wav` | 命中敌人（普通） | EventBus.enemy_damaged 消费处 | 0.07 |
| `sfx/crit_hit.wav` | 暴击命中 | enemy_damaged is_crit=true 分支 | 0.12 |
| `sfx/player_hurt.wav` | 玩家受伤 | EventBus.player_damaged 消费处 | 0.22 |
| `sfx/enemy_die.wav` | 敌人死亡 | EventBus.enemy_killed 消费处 | 0.3 |
| `sfx/explosion.wav` | 爆炸（自爆/死亡爆/Boss 弹雨） | Fx.on_explosion / die() _death_explosion | 0.5 |
| `sfx/roll.wav` | 玩家翻滚 | Player.start_roll → Fx.on_roll | 0.16 |
| `sfx/pickup_coin.wav` | 金币拾取 | core/rooms/pickup.gd coin 拾取 | 0.14 |
| `sfx/pickup_heart.wav` | 红心拾取 | pickup.gd heart 拾取 | 0.3 |
| `sfx/pickup_energy.wav` | 蓝能拾取 | pickup.gd energy 拾取 | 0.12 |
| `sfx/drink.wav` | 喝饮料 | core/interact/drink_machine.gd 购买确认 | 0.35 |
| `sfx/buff_pick.wav` | Buff 三选一确认 | ui/buff_pick.gd 选择确认 | 0.4 |
| `sfx/door_open.wav` | 房门开启 | floor_scene.gd 门开启动画 / inter_floor 进门 | 0.4 |
| `sfx/shield_break.wav` | 护盾破碎（坚守被动触发点） | EventBus.shield_broken → Player._on_shield_broken | 0.25 |
| `sfx/ui_click.wav` | UI 点击 | 全部按钮按下 | 0.04 |
| `sfx/ui_buy.wav` | 购买成功 | core/meta/shop_logic.gd 购买成功 | 0.25 |
| `sfx/ui_error.wav` | 购买失败/操作无效 | shop.gd FAIL_FLASH 处 | 0.18 |
| `sfx/boss_roar.wav` | Boss 登场咆哮 | vine_colossus.gd 开战入场 | 0.8 |
| `sfx/room_clear.wav` | 房间清空（开门/结算提示） | floor_flow.gd 房间清空判定 / 开门动画 | 0.45 |
| `sfx/boss_phase.wav` | Boss 换阶段提示 | vine_colossus.gd 阶段切换（3 阶段） | 0.5 |
| `sfx/lowhp_heartbeat.wav` | 低血警告心跳（循环） | hud.gd:184 vignette 低血红屏触发处（hp<=2 循环播放） | 0.6 |
| `sfx/shoot_bow.wav` | 弓弩射击（弦振） | weapons.json category=bow 开火 | 0.12 |
| `sfx/shoot_staff.wav` | 法杖射击（嗡鸣） | category=staff 开火 | 0.16 |
| `sfx/shoot_laser.wav` | 激光射击（电 zap） | category=laser 开火 | 0.09 |
| `sfx/shoot_throw.wav` | 投掷出手（呼啸） | category=throwable 开火 | 0.1 |
| `sfx/shoot_sniper.wav` | 狙击/重炮（爆响） | category=sniper 开火 | 0.22 |
| `sfx/shoot_shotgun.wav` | 霰弹（轰） | category=shotgun 开火 | 0.18 |
| `sfx/shoot_smg.wav` | 冲锋枪（急促 tick） | category=smg 开火 | 0.04 |
| `sfx/shoot_rifle.wav` | 步枪（脆响） | category=rifle 开火 | 0.09 |
| `sfx/reflect.wav` | 近战反弹弹幕（清脆 ping） | melee.gd 反弹窗口命中（GDD §7.4） | 0.14 |
| `sfx/freeze.wav` | 冻结生效 | 冰状态叠满冻结（GDD §7.3） | 0.2 |
| `sfx/nova.wav` | 奥术新星（法师技能） | 法师·烬 skill 奥术新星 | 0.32 |
| `sfx/turret_place.wav` | 炮台部署 | 工程师·铆 技能/被动 | 0.12 |
| `sfx/turret_shot.wav` | 炮台射击 | 工程师炮台开火 | 0.04 |
| `sfx/missile.wav` | 导弹发射（炮台强化/星陨炮） | 工程师强化导弹 / 星陨炮 | 0.3 |
| `sfx/heal_tide.wav` | 生命潮汐（守护者治疗法阵） | 守护者·萄 技能 | 0.42 |
| `sfx/forge.wav` | 熔铸台锻造 | GDD §8.3 熔铸确认 | 0.4 |
| `sfx/destroy.wav` | 可破坏掩体被摧毁 | GDD §9.2 掩体 HP→0 | 0.28 |
| `sfx/spikes.wav` | 地刺弹出/收回归位 | A2 地刺陷阱 | 0.06 |
| `sfx/lava_burn.wav` | 岩浆灼烧（DOT 跳伤） | A3 岩浆地块结算 | 0.3 |
| `sfx/empty.wav` | 空仓（蓝耗尽禁射） | weapon_rig.try_fire 蓝不足分支（GDD §7.2 HUD 变灰+空仓音） | 0.07 |
| `sfx/door_lock.wav` | 战斗房落闸锁门 | GDD §11 战斗房进门落闸 | 0.2 |
| `sfx/crystal_get.wav` | 获得蓝晶 | 局内蓝晶掉落/结算 | 0.22 |
| `sfx/unlock.wav` | 解锁提示（图鉴/成就/角色 toast） | GDD §19 右下角 toast | 0.4 |
| `sfx/fuse_beep.wav` | 自爆引信倒计时哔声 | 苦力虫/自爆王虫 fuse（配 fx/fuse_zone） | 0.24 |
| `music/music_menu.wav` | 主菜单/层间 BGM 循环 | ui/main_menu.tscn / inter_floor.tscn（待建音频管理器） | 9.6 |
| `music/music_battle.wav` | 战斗 BGM 循环 | room_combat / floor_scene 战斗态（待建音频管理器） | 19.2 |
| `music/music_crystal.wav` | A2 晶核洞穴 BGM 循环 | GDD §17 音乐=菜单1+生态3+Boss1 | 9.6 |
| `music/music_magma.wav` | A3 熔火核心 BGM 循环 | GDD §17 | 12.0 |
| `music/music_boss.wav` | Boss 战 BGM 循环 | Boss 房（M2 起 6 Boss 共用, 后续可分层） | 17.4 |

## 落地建议

1. 新建 `autoload/sfx.gd`：`play(name, pitch_scale=1.0, volume_db=0.0)`，预加载本目录 WAV（Godot 导入 WAV 无损、体积可接受）。
2. BGM 用 `AudioStreamWAV.loop_mode=forward` 或改用 OGG；战斗/菜单两张 bus（Music/SFX）便于统一调音量。
3. 正式素材采购/录制后按同名替换本目录文件即可，无需改代码。

## 待采购（无法程序生成）

- 语音/旁白（如有）、Boss 专属台词音、环境音（洞穴水滴/风）。