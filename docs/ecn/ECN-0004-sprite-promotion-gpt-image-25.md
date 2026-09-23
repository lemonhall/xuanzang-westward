# ECN-0004：正式精灵资源回切 GPT Image 2.5 透明总表

## 基本信息

- **ECN 编号**：ECN-0004
- **关联 PRD**：PRD-0001（REQ-0001-008 美术资产）
- **关联 Req ID**：REQ-0001-008
- **发现阶段**：v1 资源接入复查（用户实测游戏仍加载旧帧）
- **日期**：2026-09-23
- **取代**：ECN-0003 中关于“精灵动画统一使用 Seedream”的当前实施口径；ECN-0003 保留为历史记录。

## 变更原因

用户明确要求精灵模型只能使用 GPT Image 2.5，因为本项目需要模型原生输出真实透明背景。之前 Seedream 方案虽然能生成更多姿态，但其透明度需要本地抠图，且旧帧已经造成游戏里新旧资源混用，不能作为当前正式资源链路。

## 变更内容

### 原设计

正式精灵从 Seedream 多姿态总表生成，再通过品红底抠图进入 `assets/sprites`。

### 新设计

1. 背景、特效和全部正式精灵都登记为 `openai/gpt-image-2.5-sunburst`，精灵请求使用 `background=transparent` 与 PNG 输出。
2. 2.5 精灵总表控制为 2×2、最多四个姿态；每个姿态保留明确的透明隔离带，切片后再进入正式目录。
3. `tools/promote_latest_sprites.py` 是 `assets/manifests/canonical.json` 指定的唯一提升入口。它会验证画布尺寸、真实 alpha、脚底基线、脚/爪锚点和共享缩放比，并将旧帧移入 `assets/raw/superseded/latest-promotion-legacy/`。
4. 当前正式目录使用玄奘 8 帧（待机、行走、攻击、诵经、跳起、下落、落地、受击）和狼 3 帧（待机、行走、奔跑）。狼跃起候选因贴近总表边界暂不接入，攻击/受击需要新的 2.5 总表后再提升。

## 影响范围

- **代码**：`tools/promote_latest_sprites.py`、`tools/rebuild_sprites.py`、`scripts/player/player.gd`、`scripts/enemies/enemy.gd`。
- **清单与证据**：`assets/manifests/canonical.json`、`assets/qa/latest-sprite-promotion.json`、`assets/qa/latest-sprites-contact.png`。
- **正式资源**：`assets/sprites/xuanzang/` 8 帧、`assets/sprites/wolf/` 3 帧；旧帧仅保存在 `assets/raw/superseded/`。
- **验证**：`python tools/asset_pipeline.py verify`、Godot `--headless --import`、`tests/test_scene.tscn`。

## 处置方式

- [x] PRD 已同步更新（REQ-0001-008 标注本 ECN）
- [x] v1 计划与追溯矩阵已同步更新
- [x] canonical manifest 已切换到 GPT Image 2.5 提升脚本
- [x] 最新资源已接入 Godot 动态帧加载器
- [x] 资源闸门与 Godot headless 回归通过
- [ ] 狼跃起、攻击、受击的下一批 2.5 透明总表待生成并复查
