# David 项目长期记忆

Godot 4.7.2 机器人采矿游戏。主场景 `scene/wolrd.tscn`（注意拼写就是 wolrd），
逻辑脚本在 `script/`，`GameManager.gd` 是 autoload 单例。地图 128×72 格，TILE_SIZE=64。

## 项目约定

### UI 场景节点命名
所有 UI 场景里，根节点下第一层纵向容器统一命名为 `VBox`，脚本按 `.../VBox/xxx` 取节点。
新增 UI 时保持一致，否则 `@onready` 路径会取到 null（robot_popup 踩过这个坑）。

### 精炼炉（RefiningFurnace）
- 炉子靠 **`get_nodes_in_group("furnace")` + 距离** 被机器人 / 掉落物选中，
  所以「未启用」的炉子必须 `remove_from_group("furnace")`，只 `visible=false` 不够。
- 位置**不再自动生成**：全部按 `wolrd.tscn` 里手动摆放的位置来。
  开局只启用名字顺序（`Furnace` → `Furnace2` → …，按结尾数字自然排序）里的第一个，
  之后每升一级「扩建精炼炉」启用下一个。
- `RefiningFurnace.set_active(bool)` 负责启用/停用。
- 「扩建精炼炉」等级上限 = **固定 5 次**（`wolrd.gd::FURNACE_UPGRADE_MAX`），
  开局由 `GameManager.set_tech_max_level()` 设为
  `maxi(FURNACE_UPGRADE_MAX, 场景炉子数 - 1)`（摆的炉子超过 6 个时自动跟随）。
  当前场景 6 个炉子 = 开局 1 个 + 升级 5 次。
- **改科技上限必须走 `GameManager.set_tech_max_level()`**，UI 侧用
  `GameManager.get_tech_max_level()` 读取，别直接读 `TECHS[...]["max_level"]`。

### 仓库 UI（WarehouseUI）
- 节点是 `wolrd.tscn` 的 `UILayer/WarehouseUI`（`scene/inventory_ui.tscn`），
  锚定屏幕**右上角**（`anchor_left = 1.0`）。
- `Items`（VBox）里**每个物品各占一行**纵向排列；铜锭、炉内铜矿固定在最前面
  （`FIXED_ORDER`）。用户明确要求**不要并排成一行**。
- 「炉内铜矿」这一行 = `GameManager.get_furnace_ore_total()`
  （所有已启用炉子的待烧矿总量），**不是**仓库库存。
  炉内矿量没有变化信号，靠 `_process` 每帧轮询刷新。

### 机器人数量上限
- 统一走 `GameManager.get_robot_max()`：
  `ROBOT_MAX_BASE(20) + ROBOT_MAX_PER_LEVEL(40) × get_tech_level("robot_count")`，
  `robot_count` 的 `max_level = 3` ⇒ 各级上限 20 / 60 / 100 / 140（每级 +40）。
- 别在任何地方硬编码数量文案；`wolrd.gd`（生成 / 繁殖）与
  `research_lab_ui.gd`（拦截文案）都已走这个函数。
- 开局机器人 0 个是设计如此：`wolrd.gd::INITIAL_ROBOT_COUNT := 0`。
- 「添加机器人」(`add_robot`) **不在 TECHS 里写 max_level**：
  它的等级上限 = `get_robot_max()`（`get_tech_max_level()` 里特例处理），
  随「机器人数量上限」科技实时同步。改上限别去 TECHS 里加回写死的值。

### 科技 UI
- 科技树 UI 是 **`script/research_lab_ui.gd`** + `scene/research_lab_ui.tscn`
  （挂在 `wolrd.tscn` 的 `UILayer/ResearchLabUI`）。
  早期的 `tech_tree_ui.gd` 已不存在，别再去改它。
- 卡片等级显示、可买判定都走 `get_tech_level` / `get_tech_max_level` /
  `is_tech_unlocked` / `can_unlock_tech`，不要直接读 `TECHS[...]["max_level"]`。

### 矿点
预放置的矿点由 `wolrd.gd::_collect_placed_patches()` 收集，开局只显示 1 个，
「新的资源点」科技每次 reveal 3 个。

### 音频资源（sfx/）
放进 `sfx/` 的 WAV 若来自 ffmpeg 流式输出，RIFF/data 长度字段会是 `0xFFFFFFFF`，
Godot 会卡在「正在导入资产」。跑项目根目录的 `fix_wav_headers.py` 修一下：
`python fix_wav_headers.py "<项目>/sfx"`。

## 已知告警（无害，但别误判为本次改动引入）
- `scene/refining_furnace.tscn:4` 的 `uid://bmqxnm700bvf4` 失效（指向 `textures/house.png`），
  Godot 自动回退文本路径。有空在编辑器里重设一次外部资源引用即可。
- headless 强退时的 `Unreferenced static string` / RID leak 日志是引擎自身行为。

## 注意
`.workbuddy/memory/` 下的文件偶尔会被外部清掉（已发生两次），
重要约定要同时体现在本文件里，不要只依赖当日日志。
