# ECN-0003：精灵动画管线改为 Seedream + 本地抠图，并修正归一化口径

## 基本信息

- **ECN 编号**：ECN-0003
- **关联 PRD**：PRD-0001（REQ-0001-008 美术资产）
- **关联 Req ID**：REQ-0001-008
- **发现阶段**：v1 美术管线返工（用户实测：安全策略误拦过多、角色忽大忽小）
- **日期**：2026-09-23

## 变更原因

1. **2.5 的内容安全策略对精灵图不可用**：一张图 6/12 姿态必被拒；4 帧行走循环被拒；同一动作换三次措辞仍被拒（横挥锡杖）；持戟呼喝被拒。精灵图天然需要多姿态，so 2.5 不适合做动画。
2. **用户明确指定**：背景继续用 2.5，**所有精灵动画改用 Seedream + 本地抠图**。
3. **归一化口径有缺陷**：逐帧各自缩放（人按高、兽按宽）会让同一角色的帧看起来忽大忽小；画布太窄还会触发"缩到能放下"的钳制，进一步破坏一致性。

## 变更内容

### 原设计（ECN-0001 时期）

> 精灵图用 `openai/gpt-image-2.5-sunburst`；一张图 ≤5 姿态；多姿态不够时用参考图编辑补；逐帧按各自包围盒归一。

### 新设计

1. **模型分工**：背景/场景/特效底图 = `openai/gpt-image-2.5-sunburst`；**精灵动画 = `volcengine/doubao-seedream-5.0-pro`**。已写入 `~/.codex/AGENTS.md`。
2. **Seedream 不给透明底**（实测返回 RGB，且会把 1536×1024 放大到 2496×1664）：一律**要求纯品红 #FF00FF 平坦底 + 本地抠图**。
3. **抠图不是阈值**：按 `观测 = α×前景 + (1-α)×底色` 解混反解前景，软边缘的品红溢色被真正去除（实测残留溢色 18 像素 / 1 像素）。
4. **一个角色一张图**：Seedream 接受 12 姿态总表（2.5 必拒），身份一致性问题从根上消失，不再需要参考图编辑补帧。
5. **归一化口径（防忽大忽小）**：
   - **同一张图只用一个缩放比**（以中立姿态为基准），禁止逐帧各自缩放；
   - 水平锚定用**脚/爪质心**，垂直锚定用**脚底基线**；不再用包围盒中心（锡杖一伸身体就横移）；
   - **画布宁宽不缩**：玄奘画布 512 → 768，保证宽动作也不被钳制；
   - 四足按**体长**定基准、直立按**身高**定基准。
6. **机器闸门**：`slice` 写入 `assets/qa/normalization-<actor>.json`（每帧缩放比），`normalize --verify` 断言 ①脚底基线一致 ②脚底质心居中（±6px）③**同一角色只有一个缩放比且无钳制**。

## 影响范围

- 代码：`tools/matte.py`（新增）、`tools/asset_pipeline.py`（spec_scale/feet_anchor_x/_paste_subject/切片账本/新校验）
- 资产：`assets/raw/ofox/doubao-seedream-5.0-pro/run-90..91`（玄奘 12 姿态、狼 5 姿态）、`assets/sprites/xuanzang`（12 帧）、`assets/sprites/wolf`（5 帧）
- 引擎：`scripts/player/player.gd` 画布常量 512→768
- 文档：`~/.codex/AGENTS.md`、`docs/art/ART-BIBLE.md`、`~/.codex/skills/ofox-imagegen/SKILL.md`

## 处置方式

- [x] PRD 已同步（REQ-0001-008 补充"精灵用 Seedream + 本地抠图"）
- [x] v1 计划与追溯矩阵已同步
- [x] ART-BIBLE / AGENTS.md / SKILL 已回写
- [x] 验证：`normalize --verify` 三条闸门全 OK；Godot `ALL TESTS PASSED`
