# Bug Tracker

## Active Bugs

_暂无待修复bug_

---

## Fixed Bugs

### [BUG-001] 神像回复内容与其身份不符
**状态**: 已修复 ✓
**优先级**: 中
**发现时间**: 2026-03-10
**修复时间**: 2026-03-10

**描述**:
神像的回复和其本身身份目前不符。不同神明应该有不同的回复风格和内容，所有神明都表现得像索露恩。

**原因**:
prayer房间配置中缺少 `god_id` 字段，导致 `_guess_god_id_for_room()` 函数通过 `deity_name` 匹配失败：
- 房间的 `deity_name` 是 "索露恩神像"、"妮拉神像"（包含"神像"）
- gods.json中的 `name` 是 "索露恩"、"妮拉"（不包含"神像"）
- 字符串精确匹配失败，所有神明都fallback到默认值 "solune"

**修复方案**:
在 `data/dungeon_layout.json` 的所有prayer房间中添加 `god_id` 字段：
- r10: 添加 `"god_id": "solune"`
- r12: 添加 `"god_id": "nyra"`

**相关文件**:
- `data/dungeon_layout.json` (房间配置)
- `scripts/dungeon/dungeon_run.gd:1834-1844` (_guess_god_id_for_room函数)

**验证**:
每个神明都有完整的配置系统：
- gods.json: 包含4个神明的persona、speech_style等配置
- data/prompts/*.prompt.txt: 每个神明都有专属AI提示词
- narrative_generator.gd: 本地fallback也实现了神明差异化

---

### [BUG-000] 与神像交互后玩家自动移动
**状态**: 已修复 ✓
**优先级**: 高
**发现时间**: 2026-03-10
**修复时间**: 2026-03-10
**修复提交**: 54ef232

**描述**:
玩家与神像交互的第一次对话后，玩家会自动朝一个方向移动很长一段距离，对话还没结束。

**原因**:
1. 输入锁定释放太快（仅0.1秒grace period）
2. 祷告面板可见时没有阻止玩家移动

**修复方案**:
1. 将INPUT_UNLOCK_GRACE_PERIOD从0.1秒增加到0.5秒
2. 在_is_game_input_locked()中添加_prayer_panel.visible检查

**相关文件**:
- `scripts/dungeon/dungeon_run.gd:143` (grace period常量)
- `scripts/dungeon/dungeon_run.gd:2237` (输入锁定逻辑)
