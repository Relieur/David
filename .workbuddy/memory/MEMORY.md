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

### 设计分辨率（2026-10-14 起）
- **viewport = 1920×1080**（project.godot `window/size/viewport_*`，
  stretch=canvas_items + aspect=expand）。素材全部按 1920×1080 原始尺寸 1:1 摆放。
- 旧约定「×0.6 / 1152×648」已作废，新增 UI 不要再缩放素材尺寸。

### HUD（hud_ui）
- `scene/hud_ui.tscn` + `script/hud_ui.gd`，挂在 `UILayer/HudUI`
  （顺序：**HudUI** → ResearchLabUI → RobotPopup，让研究所全屏面板能盖住 HUD）。
- 内容与职责：
  - 顶栏 `UI_HUD_top`（1920×96）：中央深色条放**资源数量**（铜锭 / 铜矿等，
    `hud_ui.gd::_refresh_resources`，炉内铜矿每帧轮询 `get_furnace_ore_total()`）。
    资源是**单个 Label**，用 `" | "` 拼接分隔（用户不要并排的空隙），节点是
    `TopBar/Resources`（Label，不是 HBoxContainer）。
  - 右上角齿轮=设置（`UI_HUD_Gear`）→ 设置面板（**纯色 StyleBoxFlat，不用图片**，
    用户明确说 UI_Dialogue_BG 不是给设置界面用的）：继续/主菜单/退出。
  - 右上装饰面板 `UI_HUD_Right`；其下方 `UI_RightText_BG` = **「研究所目标」面板**
    （LabGoalPanel，显示当前阶段 / 升级目标 / 所需资源，`_refresh_goal()`）。
  - 左下角 LAB 按钮（`UI_Btn_Lab` 用 **AtlasTexture Rect2(0,470,344,393)** 裁透明区）
    → 调 `ResearchLabUI.toggle()`。
  - 目标面板正下方 **StageProgress 进度条**（`UI_HUD_ProgressBar_Frame/Fill`，
    Frame 307×24、Fill 297×16 内缩 5/4px）：到达下一研究所阶段的进度 =
    铜锭 / `LAB_STAGE_UPGRADE_COSTS[lab_stage]`，满级常亮满条；
    随 `_refresh_goal()`（inventory_changed / tech_unlocked）刷新。
  - **TopFade 渐变遮罩**：HudUI 第一个子节点（最底层），GradientTexture2D
    （1920×540，自上而下黑→透明）盖在游戏画面上、HUD 元素之下。
- **旧的 WarehouseUI 已从 wolrd.tscn 移除**（资源显示并入顶栏）；
  `inventory_ui.tscn/gd` 文件还在但无实例。右下角 CopperIngotSetter 仍在。
- 研究所旧入口 `OpenButton` 已 `visible=false`，R 键快捷键仍可用。

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

### 音效系统（2026-10-14 接入）
音频播放统一走 **`GameManager`（autoload）**，别在各自脚本里新建 AudioStreamPlayer：
- `play_sfx(stream)`：一次性音效（grab/drop），内部动态播放器池，全忙则新建，**不打断正在播的**。
- 环境音 `ambient.wav`：GameManager `_ready` 即循环播放（-6dB）。
- 炉火 `stove_work_sound.wav`：`furnace_burning_started()/stopped()` 计数驱动，
  任一炉燃烧即循环播（-4dB），最后一炉停才停。
- 音效常量：`GameManager.SFX_GRAB / SFX_DROP / SFX_AMBIENT / SFX_STOVE`。
- 交互音效（grab/drop）在 `ore_patch.gd::_register_interaction()` 触发：未掉落播 grab，掉落播 drop。
- **所有音效都有渐入渐出**：`_fade_to()` / `_fade_out_then_stop()`，linear 域插值，
  fade tween 存在 `player` 的 meta `"fade_tween"`，重触发先 kill 旧 tween。
  一次性音效 0.04s 渐入；环境音/炉火 1.0s 渐入渐出。fade 起止点 `SILENT_DB=-80`。
- **采矿音效降噪（2D 空间化 + 限频 + ducking + 调低）**：
  - grab/drop 走 `AudioStreamPlayer2D`（`play_sfx_at` / `play_grab_at` / `play_drop_at`），
    在矿点位置播放，`max_distance=600` 距离衰减；**相机须挂 AudioListener2D**（camera_2d.gd 已加）。
  - grab 全局限频 0.12s（`GRAB_MIN_INTERVAL`）；ducking 按 `is_mining()` 数量，
    超 3 个每多一个 -0.8dB、封顶 -12dB；grab 基础 -10dB、drop -3dB。
  - 采矿音效入口统一在 `ore_patch.gd::_register_interaction()`。
- **音量调节**：设置面板（齿轮）里两个 HSlider——「环境音」→ `set_ambient_volume`、
  「其他声音」→ `set_sfx_volume`（grab/drop/炉火）。音量 0~1 存 `_ambient_volume`/`_sfx_volume`，
  通过 `_vol_offset_db()` 换算 db 偏移叠加到各播放点；setter 用 0.15s fade 即时过渡循环音。
  滑块节点路径：`SettingsRoot/Panel/VBox/AmbientVol/Slider`、`.../SfxVol/Slider`。

## 已知告警（无害，但别误判为本次改动引入）
- `scene/refining_furnace.tscn:4` 的 `uid://bmqxnm700bvf4` 失效（指向 `textures/house.png`），
  Godot 自动回退文本路径。有空在编辑器里重设一次外部资源引用即可。
- headless 强退时的 `Unreferenced static string` / RID leak 日志是引擎自身行为。

## 注意
`.workbuddy/memory/` 下的文件偶尔会被外部清掉（已发生两次），
重要约定要同时体现在本文件里，不要只依赖当日日志。
