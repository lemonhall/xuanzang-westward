# v1 总论与索引：西行·玄奘（竖切）

**关联 PRD**：[PRD-0001](../prd/PRD-0001-xuanzang-westward.md)
**成本档位**：`standard`（最多 3 轮 Review）
**本轮目标**：交付**第一关可玩竖切** + 全套核心系统 + 可复现的美术管线；七关的设计与音频文案已在前述文档中交付。

## 里程碑

| M | 名称 | 范围 | DoD（可二元判定） | 验证命令 / 证据 | 状态 |
|---|---|---|---|---|---|
| M1 | 素材管线与第一批美术 | OFOX manifest → raw 留档 → QA → 规范化 → Godot 可用贴图 | ① 每个 run 目录含 `request.json`；② `qa-*.json` 中精灵图 `native_alpha=true` 且 `transparent_ratio>0.15`；③ 规范化后同 actor/alias 各帧 `top` 与 `height` 唯一 | `python tools/asset_pipeline.py qa --batch l1-batch-a`；`python tools/asset_pipeline.py normalize --verify`（退出码 0） | doing（主角 11 帧 / 3 层视差 / 天空 / 特效 / 道具 已通过；**敌兵姿态待补**，见差异列表） |
| M2 | 工程骨架与移动手感 | Godot 4.7.2 工程、输入映射、玩家控制器、摄像机 | ① 水平速度 220±10 px/s；② 跳跃峰值 103±14 px（≈3.2 格）；③ 土狼时间内起跳成功 | `godot --headless --path . tests/test_scene.tscn` → `ALL TESTS PASSED` | done |
| M3 | 打击感与战斗 | 锡杖攻击、hitstop、震屏、受击击退、关吏 AI（美术占位） | ① hitstop ∈[0.06,0.09]s 且 `time_scale` 复原；② 攻击命中使关吏掉血；③ 震屏幅度 3–6px | 同上（攻击命中 / hitstop 0.07 / time_scale=1.0 均断言） | doing（连击第二段、火花节点、敌兵美术待补） |
| M4 | 视差与第一关 | Parallax2D 四层、地形、3× checkpoint、终点、HUD | ① 层间相对位移符合 50/250/500/800 比例（±8px）；② 真实关卡数据上玩家落地且能前进 | 同上（`_test_parallax` / `_test_real_level_ground`） | doing（终点结算、叙事卡待补） |
| M5 | 文斗 / 存档 / 流程 | 文斗回合制、叙事卡、存档、关卡选择 | ① `save.json` 往返一致；② 通关 L1 解锁 L2；③ 文斗 4 回合可走通 | 存档与解锁断言已过；文斗未实现 | doing（存档 done；文斗 todo） |

## 计划索引

| 计划 | 覆盖里程碑 | 追溯 Req |
|---|---|---|
| [v1-art-pipeline.md](v1-art-pipeline.md) | M1 | REQ-0001-008 |
| [v1-core-and-combat.md](v1-core-and-combat.md) | M2, M3 | REQ-0001-001, REQ-0001-002, REQ-0001-003 |
| [v1-level-01-and-flow.md](v1-level-01-and-flow.md) | M4, M5 | REQ-0001-004, REQ-0001-005, REQ-0001-006, REQ-0001-007, REQ-0001-010, REQ-0001-011 |

## 追溯矩阵

| Req ID | v1 计划 | 测试 / 证据 | 状态 |
|---|---|---|---|
| REQ-0001-001 | v1-core-and-combat §Step1 | `tests/test_scene.gd::_test_movement` / `_test_coyote_time` | done |
| REQ-0001-002 | v1-core-and-combat §Step3 | `tests/test_scene.gd::_test_combat`（hitstop + time_scale） | doing（火花节点待补） |
| REQ-0001-003 | v1-core-and-combat §Step4 | `tests/test_scene.gd::_test_combat` + `Hud` 显示 | done |
| REQ-0001-004 | v1-level-01-and-flow §Step2 | 未实现（风沙机制属下一轮） | todo |
| REQ-0001-005 | v1-level-01-and-flow §Step5 | 未实现（文斗属下一轮） | todo |
| REQ-0001-006 | v1-level-01-and-flow §Step1 | `tests/test_scene.gd::_test_parallax` | done |
| REQ-0001-007 | v1-level-01-and-flow §Step2 | `tests/test_scene.gd::_test_real_level_ground` + `data/levels/l01.json` | doing（L1 可玩；结算与叙事卡待补） |
| REQ-0001-008 | v1-art-pipeline | `assets/qa/consistency-final.json`、`assets/qa/contact-xuanzang.png`、`normalize --verify` exit 0 | doing（敌兵待补） |
| REQ-0001-009 | 文档层（无代码） | `docs/audio/AUDIO-DESIGN.md` | done |
| REQ-0001-010 | v1-level-01-and-flow §Step6 | `tests/test_scene.gd::_test_save_roundtrip` | done |
| REQ-0001-011 | 全部计划 | `tests/test_scene.tscn`（headless 场景跑法） | done |

## ECN 索引

| ECN | 摘要 | 状态 |
|---|---|---|
| [ECN-0001](../ecn/ECN-0001-art-consistency-route.md) | 人物一致性路线改为"定版图 + 参考图条件生成" | PRD / v1 计划 / SKILL 已同步 |

## Review 记录

### Tashan Review - v1 / M1

- reviewer_context: fresh
- round: 1
- cost_profile: standard
- verdict: blocked（敌兵姿态缺失；M2–M5 未开始）
- blocker_count: 0
- major_count: 1
- commands_checked: `asset_pipeline.py normalize --verify`（exit 0，全部 OK）；`Godot --headless --import` 与 `--headless --quit`（无 ERROR）；`consistency_check.py`（留档 `assets/qa/consistency-final.json`）
- residual_risks: 生成端内容安全策略随机拒绝（同一动作措辞三次被拒、换概念即过）；`attack_01` 最终采用"向前推杖"姿态而非最初设想的横扫

### Findings

| severity | signature | evidence | disposition |
|---|---|---|---|
| MAJOR | art::REQ-0001-008::enemy-poses-missing | `assets/raw/ofox/**/run-41-sheet_enemy_guardi_3/error.txt`（内容安全策略拒绝） | 进入下一轮：按 ECN-0001 用"一张 ≤5 姿态图 + 参考图编辑"补关吏 |
| MINOR | art::tools::duplicate-slug-overwrites | 同一 slug 的两次运行（run-64/run-70）写入同一目标，后者覆盖前者 | 驱动加 slug 唯一性检查（下一轮） |
| BLOCKER | gameplay::player.gd::collision-mask-excludes-terrain | 玩家 `collision_mask=2`（只碰敌人）→ 穿地掉落并循环重生；用户人工复现"循环掉落出去" | 已修复为 `collision_mask=1`；固化为永久检查 `_test_real_level_ground`（真实 l01 数据上必须落地、贴地跑 >250px） |
| NOTE | test::runner-mode::autoload-unavailable | `--script` 模式下 autoload 不注册，编译期报 `Identifier not found: Hitstop` | 测试入口改为场景方式 `tests/test_scene.tscn`；PRD/计划已同步 |
| BLOCKER | level::l01.json::unreachable-platforms | 用户实测"高台跳不上去"：平台抬升 140px > 跳高 103px | 高台改到 y=478（抬升 82px）；新增 `_test_level_is_reachable` 连通性 + 孤儿平台检查，负向对照（改回 140px）已验证会报红 |
| BLOCKER | level::l01.json::gaps-wider-than-jump | 用户实测"深坑跳不过去"：坑宽 100–120px > 可跨越上限 93.8px | 坑宽统一收到 72px；新增 `_test_level_gaps_are_jumpable` 与 `_test_first_gap_crossing` |
| BLOCKER | art::parallax_rig.gd::node-position-overwritten | Parallax2D 的 position 由引擎按相机滚动覆写，导致垂直偏移失效、背景与地面之间出现空带 | 垂直偏移改到子精灵；新增 `_test_background_meets_the_ground`（四层内容底边必须压到地平线以下） |
| BLOCKER | art::parallax_rig.gd::cropped-edge-enters-view | 用户实测"一跳起来就露出贴图被裁剪的边"（柳枝画到贴图第 0 行） | 天空/中景/近景放大到 1.10 并重设 y（顶边 −288/−213/−223，均高于可见顶端 −177）；新增 `_test_background_crop_edges_stay_out_of_view` |
| NOTE | test::parallax::wrap-period-per-layer | 各层缩放不同导致 repeat 周期不同，原"层间差值"断言口径失效 | 位移断言改为逐层按自身周期回绕归一化，实测残差 0 |
| MAJOR | framing::l01::earth-band-too-tall | 用户实测"地面咖啡色土地从屏幕底部顶到屏幕中部"：地形厚度 420px + 相机偏移 110px → 土带占屏 35% | 地形厚度改 170、相机偏移改 170 → 土带 26%、脚底 74%；新增 `_test_ground_band_framing`（土带 ≤30%、脚底 60%–80%） |
| BLOCKER | framing::l01::ground-floats-above-screen-bottom | 用户实测"屏幕底部的地面悬空"：地形削到 170px 后够不到可见下缘，只能靠背景层斑驳的土坡（该行 alpha 仅 4%–60%）补 | 地形碰撞厚度 240 + 视觉填充拉到 720（`LevelBuilder.EARTH_FILL_HEIGHT`）→ 自家土一定越过可见下缘；新增 `_test_ground_reaches_below_the_view` |
| BLOCKER | art::wolf::size-jitter | 用户实测"狼一会儿大一会儿小"：四足动物按包围盒高度归一，潜行/跃扑被强行放大 | 四足改为按体长（宽度）归一到 300px，并加画布钳制；五帧体长一致、高度自然变化 |
| MAJOR | art::enemy::placeholder-only | 用户实测"对手只是个占位符" | 新增 `Enemy`（美术按 actor 加载、缺图退回剪影）、`SpriteFramesLoader`（与玩家共用命名规范）、狼定版图 5 帧；新增 `_test_enemy_art_and_facing`（美术存在 + 朝向镜像） |
| BLOCKER | art::sprites::2.5-policy-blocks-multipose | 2.5 对多姿态请求稳定拒绝（6/12 姿态必拒、4 帧行走被拒、挥杖 3 次被拒） | ECN-0003：精灵动画全部改用 Seedream + 本地抠图；背景继续用 2.5 |
| BLOCKER | art::normalization::per-frame-scaling-jitter | 用户实测玄奘与狼"忽大忽小"：逐帧各自缩放 + 窄画布触发钳制 | 一张图一个缩放比（取中立姿态）、脚/爪质心锚定、画布宁宽不缩（玄奘 768×512）；新增缩放账本与 `zoom-lock` 闸门（`unique_scales` 单一 + `clamped` 为空） |

### Tashan Trigger Audit

- expected_review_triggers: 文档写作完成、每个里程碑完成、v1 整体完成、commit/push 前
- actual_review_runs:
- skipped_triggers:
- skip_reasons:
- mitigation:

## 差异列表（本轮结束前填写）

| 类型 | 内容 | 证据 / 去向 |
|---|---|---|
| 未满足 | （待填） | |

## 风险与取舍

1. **AI 生成的连帧动画天然不连贯**：因此走"少帧数 + 程序化补间（挤压拉伸、倾斜、位移）"路线，而不是指望模型画出 6 帧一致的走路循环。
2. **透明底素材可能存在边缘半透明**：保留原始字节，规范化时不做 alpha 增强，避免"偷偷修图"。
3. **音频暂无原型**：本轮只交付文案（REQ-0001-009），实现路线待确认。
