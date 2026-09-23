# 西行·玄奘（xuanzang-westward）

2D 横版平台跳跃：玄奘西行十九年，七关。引擎 Godot 4.7.2。

## 怎么跑

1. 用 Godot 打开本目录（`E:\development\xuanzang-westward`），F5 运行。
2. 画面基准 1280×720；关卡第一关为"出关"（长安 → 凉州），关卡数据在 `data/levels/l01.json`。

### 操作

| 动作 | 键位 |
|---|---|
| 左右移动 | `A` / `D` 或 ← / → |
| 跳跃（可变高度） | `空格` / `W` / ↑ |
| 挥杖 | `J` |
| 诵经（站定持诵 0.8 秒回复心念 +25） | `K` |
| 交互 | `E` / `回车` |
| 暂停 | `Esc` |

手柄同样可用（左摇杆 + A 跳 / X 攻击 / Y 诵经 / B 交互）。

## 怎么验证

```powershell
# 导入（应当没有 ERROR / SCRIPT ERROR）
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . --import

# 自动化测试（移动手感、土狼时间、打击定格、四层视差、存档往返、真实关卡落地与前进）
& 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --path . tests/test_scene.tscn
```

测试必须是**场景**跑法：`--script` 模式下 autoload 单例不注册，引用 `GameState`/`Hitstop` 的脚本无法编译。

## 美术管线（OFOX · GPT Image 2.5 Sunburst）

```powershell
# 生成（manifest 驱动；参考图编辑模式 = 人物一致性）
& .venv\Scripts\python.exe tools\ofox_generate.py --manifest assets/manifests/<file>.json --parallel 3

# 质检 / 规范化 / 精灵图切片 / 抠底
& .venv\Scripts\python.exe tools\asset_pipeline.py qa --batch <name>
& .venv\Scripts\python.exe tools\asset_pipeline.py normalize --verify
& .venv\Scripts\python.exe tools\asset_pipeline.py slice --input <run-dir> --actor xuanzang --aliases idle,walk --frames 2

# 一致性度量与目视验收图
& .venv\Scripts\python.exe tools\consistency_check.py --reference <ref.png> --glob "assets/sprites/**/*.png"
& .venv\Scripts\python.exe tools\contact_sheet.py --glob "assets/sprites/xuanzang/*.png" --out assets/qa/contact-xuanzang.png
```

规矩（详见 `docs/art/ART-BIBLE.md` 与 ECN-0001）：

- 模型只用 `openai/gpt-image-2.5-sunburst`；
- 人物帧一律"定版图 + 参考图编辑"，且 edits 必须带 `background=transparent` 与显式 `size`；
- 一张图最多 5 个姿态，姿态之间不得接触；
- 原始产出永不修改，作废产物归档到 `assets/raw/superseded/`。

## 文档

- 策划：[PRD-0001](docs/prd/PRD-0001-xuanzang-westward.md)（七关结构、苦难机制、文斗、打击感数值）
- 美术：[ART-BIBLE](docs/art/ART-BIBLE.md)｜音频：[AUDIO-DESIGN](docs/audio/AUDIO-DESIGN.md)
- 计划：[v1-index](docs/plan/v1-index.md)｜变更：[ECN-0001](docs/ecn/ECN-0001-art-consistency-route.md)
