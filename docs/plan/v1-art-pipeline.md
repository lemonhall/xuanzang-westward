# v1-art-pipeline（M1：素材管线与第一批美术）

## Goal

让"生图 → 质检 → 规范化 → 进引擎"这条链路可重复、可审计、幂等，并交付第一关所需的第一批美术资产。

## PRD Trace

REQ-0001-008（美术资产全部由 OFOX 生成）。

## Scope

- 做：manifest 驱动的批量生图（带并行、失败不重试、原始产出留档）；alpha/构图自动化质检；按 actor 目标高度与脚底基线做规范化；亮底/暗底对照图。
- 不做：人工修图、alpha 增强、像素级美术比对、动画连贯性自动评分。

## Acceptance

1. `python tools/asset_pipeline.py qa --batch l1-batch-a` 退出码 0，且 `assets/qa/qa-l1-batch-a.json` 中所有精灵图 `native_alpha=true`、`transparent_ratio > 0.15`。
2. `python tools/asset_pipeline.py normalize --verify` 退出码 0，且同一 actor/alias 的各帧 `bbox top` 与 `bbox height` 唯一（即完全对齐）。
3. 每个 `assets/raw/ofox/**/run-*/` 目录都含 `request.json`（prompt 全文可追溯）。
4. 背景层（`bg_*`）为 1024×1024 不透明 PNG，且不含人物。

## Files

- 新增：`tools/generate_assets.ps1`、`tools/asset_pipeline.py`、`tools/requirements.txt`
- 新增：`assets/manifests/l1-probe.json`、`assets/manifests/l1-assets-batch-a.json`
- 产出：`assets/raw/ofox/gpt-image-2.5-sunburst/run-*`、`assets/sprites/**`、`assets/backgrounds/l1/**`、`assets/fx/**`、`assets/qa/**`

## Steps

1. 写命令行工具（`qa` / `normalize`），先跑空实现 → 红：目录不存在时退出非 0。
2. 用 probe manifest 跑 2 张，人工+脚本确认风格与 alpha → 通过后才批量。
3. 批量生成第一批（19 张），留档。
4. 运行 `qa`，产出 `qa-l1-batch-a.json` 与对照图。
5. 运行 `normalize --verify`，产出对齐后的精灵帧。
6. 定稿：把规范化产物接入 Godot（AnimatedSprite2D / SpriteFrames）。

## Risks

- **模型对"只画一个姿态"的服从度**：可能出现多格拼图。缓解：质检报告 `bbox_w/bbox_h` 比例异常时人工介入，必要时重生成单张。
- **帧间姿态漂移**：靠规范化对齐几何，靠程序化补间补动作平滑度（见 v1-core-and-combat）。
- **花费**：每张都是付费请求，manifest 留档便于复盘；不做自动重试。

---

# v1-core-and-combat（M2 + M3：移动手感与打击感）

## Goal

先让"走路跳起来舒服"，再让"打到东西有感觉"。这两件事是平台跳跃的地基，必须在关卡内容之前完成。

## PRD Trace

REQ-0001-001（移动手感）、REQ-0001-002（打击感）、REQ-0001-003（心念/定力）。

## Scope

- 做：`CharacterBody2D` 玩家控制器（加速度/摩擦、可变跳跃、土狼时间、跳跃缓冲）、输入源抽象、摄像机跟随与震屏、hitstop、命中火花、受击闪白/击退/无敌帧、一个巡逻型敌人（关吏）。
- 不做：二段跳、冲刺、抓钩、连招树、武器成长、敌人种类扩展（L2+ 后续版本）。

## Acceptance（全部可在 headless 断言）

1. 水平最高速度 220±10 px/s；松手减速到 0 的时间 ≤0.18s。
2. 跳跃峰值 3.2±0.2 格（1 格 = 32px）；松开跳跃键后上升速度立即衰减（可变跳跃）。
3. 土狼时间 ≥0.10s：离开平台后 0.10s 内按跳跃仍可起跳。
4. 跳跃缓冲 ≥0.12s：落地前 0.12s 按下跳跃，落地瞬间自动起跳。
5. 命中触发 hitstop ∈[0.06, 0.09]s，且 `Engine.time_scale` 在之后恢复为 1.0。
6. 命中触发震屏：`ScreenShake.amplitude ∈[3,6]`、`duration ∈[0.15,0.25]`。
7. 第三次命中使关吏进入 `down`；其后不再造成伤害。
8. 玩家受击后 0.5s 内再次接触同一敌人不扣定力。

## Files

- 新增：`project.godot`、`scripts/autoload/{game_state,audio,hitstop}.gd`
- 新增：`scripts/player/{player.gd,input_source.gd,player_camera.gd}`
- 新增：`scripts/enemies/guardi.gd`、`scripts/fx/{hit_spark.gd,screen_shake.gd}`
- 新增：`scenes/player/xuanzang.tscn`、`scenes/enemies/guardi.tscn`、`scenes/fx/hit_spark.tscn`
- 测试：`tests/test_movement.gd`、`tests/test_combat.gd`、`tests/helpers/scripted_input.gd`

## Steps

1. 建工程与输入映射；写 `tests/test_runner.gd` 骨架 → 红（无测试文件）。
2. 写 `test_movement.gd` 断言 → 红（玩家不存在）。
3. 实现玩家控制器与输入源抽象 → 绿。
4. 写 `test_combat.gd` 断言 → 红。
5. 实现三段锡杖、hitstop、震屏、火花、敌人受击状态机 → 绿。
6. 用真实图像素材替换占位贴图（M1 产物）。
7. E2E：`tests/e2e_l01.gd` 走完第一关（见下一计划）。

## Risks

- **headless 下的物理帧稳定性**：用固定 `physics_ticks_per_second = 60` 并等待精确帧数，避免 datetime 抖动。
- **hitstop 与计时器交互**：hitstop 计时使用 `ignore_time_scale = true` 的 timer，避免自锁。

---

# v1-level-01-and-flow（M4 + M5：第一关与流程）

## Goal

把系统装进一个真正能玩的关卡：长安城门 → 官道 → 烽燧 → 出关；并补上文斗、叙事卡、存档。

## PRD Trace

REQ-0001-004（苦难机制）、REQ-0001-005（文斗）、REQ-0001-006（视差）、REQ-0001-007（七关结构）、REQ-0001-010（存档）、REQ-0001-011（自动化验证）。

## Scope

- 做：L1 关卡（含 3 个 checkpoint、终点、火把区、风区原型）、四层视差、HUD、文斗 4 回合脚本、叙事卡、`save.json`、关卡选择。
- 不做：L2–L7 的可玩实现；正式音频；成就系统。

## Acceptance

1. 四层视差位移比例 50/250/500/800（±4px）@ 摄像机移动 1000px。
2. L1 场景含 ≥3 个 `Checkpoint` 与 1 个 `Goal` 节点，且 `e2e_l01.gd` 能从头走到终点并触发通关信号。
3. 文斗 4 回合：全胜路径下玩家定力不下降；两次错误回应后定力 -1。
4. `save.json` 写入 → 重新读取 → 已通关卡与拾取物一致。
5. 通关 L1 后 `GameState.unlocked_levels` 含 `l02`。

## Files

- 新增：`scripts/level/{level.gd,checkpoint.gd,goal.gd,parallax_rig.gd}`、`scripts/ui/{hud.gd,narrative_card.gd}`、`scripts/debate/debate.gd`、`scenes/ui/{hud.tscn,narrative_card.tscn,debate_ui.tscn}`、`scenes/levels/l01.tscn`、`scenes/main_menu.tscn`
- 数据：`data/debate/l01_debate.json`、`data/levels/l01.json`
- 测试：`tests/test_parallax.gd`、`tests/test_debate.gd`、`tests/test_save.gd`、`tests/e2e_l01.gd`

## Steps

1. 写 `test_parallax.gd`（四层位移断言）→ 红。
2. 实现 `ParallaxRig`（按层构建 Parallax2D + 重复平铺）→ 绿。
3. 写 `test_debate.gd` → 红；实现文斗系统（数据驱动回合）→ 绿。
4. 写 `test_save.gd` → 红；实现 `GameState` 存档 → 绿。
5. 组装 `scenes/levels/l01.tscn`（地形、敌人、火把、风区、checkpoint、终点）。
6. 写 `e2e_l01.gd`：脚本化输入从起点走到终点，断言通关信号与 checkpoint 记录。
7. 运行全套测试 + Godot 导入检查，产出证据。

## Risks

- **手搭场景与代码漂移**：关卡数据放 `data/levels/l01.json`，场景只引用，避免"只存在于编辑器里"的隐式状态。
- **headless E2E 的平台跳跃稳定性**：脚本化输入采用"按帧推进 + 状态断言"，不对单帧位置做像素级断言。
