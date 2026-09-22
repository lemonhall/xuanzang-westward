# v1 总论与索引：西行·玄奘（竖切）

**关联 PRD**：[PRD-0001](../prd/PRD-0001-xuanzang-westward.md)
**成本档位**：`standard`（最多 3 轮 Review）
**本轮目标**：交付**第一关可玩竖切** + 全套核心系统 + 可复现的美术管线；七关的设计与音频文案已在前述文档中交付。

## 里程碑

| M | 名称 | 范围 | DoD（可二元判定） | 验证命令 / 证据 | 状态 |
|---|---|---|---|---|---|
| M1 | 素材管线与第一批美术 | OFOX manifest → raw 留档 → QA → 规范化 → Godot 可用贴图 | ① 每个 run 目录含 `request.json`；② `qa-*.json` 中精灵图 `native_alpha=true` 且 `transparent_ratio>0.15`；③ 规范化后同 actor/alias 各帧 `top` 与 `height` 唯一 | `python tools/asset_pipeline.py qa --batch l1-batch-a`；`python tools/asset_pipeline.py normalize --verify`（退出码 0） | todo |
| M2 | 工程骨架与移动手感 | Godot 4.7.2 工程、输入映射、玩家控制器、摄像机 | ① `godot --headless --quit` 无 `ERROR`/`SCRIPT ERROR`；② `tests/test_movement.gd` 全绿：跳跃峰值 3.2±0.2 格、土狼时间 ≥0.10s、跳跃缓冲 ≥0.12s、水平速度 220±10 px/s | `godot --headless --script tests/test_runner.gd` 输出 `ALL TESTS PASSED` | todo |
| M3 | 打击感与战斗 | 三段锡杖、hitstop、震屏、火花、受击闪白与击退、关吏 AI | ① hitstop 落在 0.06–0.09s；② 命中触发震屏（幅度 3–6px）与火花节点；③ 敌人在 3 次命中后进入 `down` 状态；④ 玩家无敌帧 0.5s 内不重复扣定力 | `tests/test_combat.gd` 全绿 | todo |
| M4 | 视差与第一关 | Parallax2D 四层、地形、checkpoint、终点、HUD | ① 摄像机位移 1000px 时四层位移为 50/250/500/800（±4px）；② 关卡含 ≥3 个 checkpoint 与 1 个终点；③ HUD 显示定力 3 颗、心念 0–100 | `tests/test_parallax.gd`；`tests/e2e_l01.gd` | todo |
| M5 | 文斗 / 存档 / 流程 | 文斗回合制、叙事卡、存档、关卡选择 | ① 文斗 4 回合脚本可走通且"全胜"路径不触发伤害；② `save.json` 写入后重新读取一致；③ 通关 L1 后解锁 L2 入口 | `tests/test_debate.gd`；`tests/test_save.gd` | todo |

## 计划索引

| 计划 | 覆盖里程碑 | 追溯 Req |
|---|---|---|
| [v1-art-pipeline.md](v1-art-pipeline.md) | M1 | REQ-0001-008 |
| [v1-core-and-combat.md](v1-core-and-combat.md) | M2, M3 | REQ-0001-001, REQ-0001-002, REQ-0001-003 |
| [v1-level-01-and-flow.md](v1-level-01-and-flow.md) | M4, M5 | REQ-0001-004, REQ-0001-005, REQ-0001-006, REQ-0001-007, REQ-0001-010, REQ-0001-011 |

## 追溯矩阵

| Req ID | v1 计划 | 测试 / 证据 | 状态 |
|---|---|---|---|
| REQ-0001-001 | v1-core-and-combat §Step1 | `tests/test_movement.gd` | todo |
| REQ-0001-002 | v1-core-and-combat §Step3 | `tests/test_combat.gd` | todo |
| REQ-0001-003 | v1-core-and-combat §Step4 | `tests/test_combat.gd` | todo |
| REQ-0001-004 | v1-level-01-and-flow §Step2 | `tests/test_parallax.gd`（L1 风区） | todo |
| REQ-0001-005 | v1-level-01-and-flow §Step5 | `tests/test_debate.gd` | todo |
| REQ-0001-006 | v1-level-01-and-flow §Step1 | `tests/test_parallax.gd` | todo |
| REQ-0001-007 | v1-level-01-and-flow §Step2 | `tests/e2e_l01.gd` | todo |
| REQ-0001-008 | v1-art-pipeline | `assets/qa/qa-l1-batch-a.json` | todo |
| REQ-0001-009 | 文档层（无代码） | `docs/audio/AUDIO-DESIGN.md` | done |
| REQ-0001-010 | v1-level-01-and-flow §Step6 | `tests/test_save.gd` | todo |
| REQ-0001-011 | 全部计划 | `tests/test_runner.gd` | todo |

## ECN 索引

| ECN | 摘要 | 状态 |
|---|---|---|
| （暂无） | | |

## Review 记录

### Tashan Review - v1 / M1

- reviewer_context: fresh
- round: 1
- cost_profile: standard
- verdict: 待填写
- commands_checked: 待填写
- residual_risks: 待填写

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
