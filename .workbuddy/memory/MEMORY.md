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
- 「扩建精炼炉」等级上限会在开局由 `GameManager.set_tech_max_level()` 自动同步为
  `maxi(1, 场景炉子数 - 1)`。**改科技上限必须走这个 API**，UI 侧用
  `GameManager.get_tech_max_level()` 读取，别直接读 `TECHS[...]["max_level"]`。

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
