extends Node

# ==================== 信号 ====================
signal inventory_changed(inventory: Dictionary)
signal tech_unlocked(tech_id: String)
signal robot_selected(robot: Node)              # 新增
signal ore_memory_shared(patch: Node)           # 机器人间共享记忆的矿区（信息交流能力）
signal furnace_heat_empty(furnace: Node)        # 精炼炉温度降到 0（供剧情引导等监听）


# ==================== 音效 ====================
const SFX_GRAB := preload("res://sfx/grab_sound.wav")
const SFX_DROP := preload("res://sfx/drop.mp3")
const SFX_AMBIENT := preload("res://sfx/ambient.wav")
const SFX_STOVE := preload("res://sfx/stove_work_sound.wav")
const BGM_START := preload("res://sfx/start_bgm.wav")   # 开始界面背景音乐
const BGM_GAME := preload("res://sfx/game_bgm.mp3")     # 游戏界面背景音乐

const SILENT_DB := -80.0                         # 视为静音的音量（db），fade 起止点
const SFX_FADE_IN := 0.04                        # 一次性音效渐入时长（秒）
const AMBIENT_FADE := 1.0                        # 环境音 / 炉火声渐入渐出时长（秒）

# ---- 采矿音效（2D 空间化 + 限频 + 密度压音） ----
const GRAB_BASE_DB := -5.0                       # grab 基础音量（挖矿动作声）
const DROP_BASE_DB := -1.0                       # drop 基础音量（挖矿掉落声）
const GRAB_MIN_INTERVAL := 0.12                  # grab 全局最小间隔（秒，方案一：限频节流）
const SFX2D_MAX_DISTANCE := 1500.0               # 2D 音效最大衰减距离（超出即静音，方案六）
const SFX2D_ATTENUATION := 0.4                    # 2D 音效衰减指数（越小近处衰减越平缓）
const DUCK_FREE_COUNT := 3                       # 挖矿机器人 <= 此数量时不压音（方案三）
const DUCK_PER_ROBOT_DB := 0.8                   # 每多一个挖矿机器人额外压低的分贝
const DUCK_MAX_DB := 12.0                        # ducking 最多额外压低的分贝
const SFX2D_POOL_MAX := 32                       # 2D 音效播放器池上限，超出时丢弃本次音效，避免无限扩容

var _sfx_players: Array[AudioStreamPlayer] = []   # 一次性全局音效播放器池（动态扩容，不打断正在播的）
var _sfx2d_players: Array[AudioStreamPlayer2D] = []  # 2D 采矿音效播放器池（带距离衰减）
var _ambient_player: AudioStreamPlayer = null     # 环境音（全局循环）
var _ambient_db: float = -2.0
var _bgm_player: AudioStreamPlayer = null         # 背景音乐（开始界面 / 游戏界面各一首）
var _bgm_db: float = -6.0
var _stove_player: AudioStreamPlayer = null       # 炉火声（任一炉燃烧时循环）
var _stove_db: float = -12.0
var _burning_furnaces: int = 0                    # 正在燃烧的炉子计数

var _mining_count: int = 0                        # 正在挖矿的机器人数（ducking 依据）
var _duck_timer: float = 0.0                      # ducking 低频统计计时
var _last_grab_time: int = -1_000_000             # 上次 grab 播放时间（毫秒，限频）

var _ambient_volume: float = 1.0                  # 环境音音量（0~1）
var _sfx_volume: float = 1.0                      # 其他声音音量（0~1，grab/drop/炉火）
var _master_volume: float = 1.0                   # 总音量（0~1，同时缩放环境音与其他声音）


func _ready() -> void:
	load_options()
	_setup_audio()


func _process(delta: float) -> void:
	if PLAYER_MINE_LIMIT_ENABLED:
		_tick_player_mine_cooldown(delta)
	_duck_timer -= delta
	if _duck_timer <= 0.0:
		_duck_timer = 0.3
		_update_mining_count()


# 低频统计正在挖矿的机器人数（ducking 用，无需瞬时响应）
func _update_mining_count() -> void:
	var n := 0
	for r in get_tree().get_nodes_in_group("robots"):
		if r.has_method("is_mining") and r.is_mining():
			n += 1
	_mining_count = n


# 初始化音频播放器（环境音 + 炉火循环 + 一次性音效池）
func _setup_audio() -> void:
	# 环境音与炉火声都是循环片段，必须显式开启循环，否则只播一遍就静音
	_enable_loop(SFX_AMBIENT)
	_enable_loop(SFX_STOVE)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.stream = SFX_AMBIENT
	_ambient_player.volume_db = SILENT_DB
	add_child(_ambient_player)
	_ambient_player.play()
	_fade_to(_ambient_player, _ambient_target_db(), AMBIENT_FADE)

	_stove_player = AudioStreamPlayer.new()
	_stove_player.stream = SFX_STOVE
	_stove_player.volume_db = SILENT_DB
	add_child(_stove_player)

	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.volume_db = SILENT_DB
	add_child(_bgm_player)


# ==================== 音量控制 ====================
# 把 0~1 的音量换算成 db 偏移：1.0 → 0dB，0.0 → 静音
func _vol_offset_db(vol: float) -> float:
	if vol <= 0.0:
		return SILENT_DB
	return maxf(linear_to_db(vol), SILENT_DB)


# 环境音当前目标音量（基础 db + 音量偏移 × 总音量）
func _ambient_target_db() -> float:
	return _ambient_db + _vol_offset_db(_ambient_volume * _master_volume)


# 其他声音（炉火）当前目标音量
func _stove_target_db() -> float:
	return _stove_db + _vol_offset_db(_sfx_volume * _master_volume)


# 背景音乐当前目标音量（受「音乐」与「总音量」滑块控制）
func _bgm_target_db() -> float:
	return _bgm_db + _vol_offset_db(_ambient_volume * _master_volume)


# 设置总音量（0~1），同时缩放环境音与其他声音，立即平滑过渡
func set_master_volume(vol: float) -> void:
	_master_volume = clampf(vol, 0.0, 1.0)
	if _ambient_player != null and _ambient_player.playing:
		_fade_to(_ambient_player, _ambient_target_db(), 0.15)
	if _stove_player != null and _stove_player.playing:
		_fade_to(_stove_player, _stove_target_db(), 0.15)
	if _bgm_player != null and _bgm_player.playing:
		_fade_to(_bgm_player, _bgm_target_db(), 0.15)


func get_master_volume() -> float:
	return _master_volume


# 设置环境音音量（0~1），立即平滑过渡
func set_ambient_volume(vol: float) -> void:
	_ambient_volume = clampf(vol, 0.0, 1.0)
	if _ambient_player != null and _ambient_player.playing:
		_fade_to(_ambient_player, _ambient_target_db(), 0.15)
	if _bgm_player != null and _bgm_player.playing:
		_fade_to(_bgm_player, _bgm_target_db(), 0.15)


# 设置其他声音音量（0~1），炉火声立即平滑过渡，一次性音效在下次播放时生效
func set_sfx_volume(vol: float) -> void:
	_sfx_volume = clampf(vol, 0.0, 1.0)
	if _stove_player != null and _stove_player.playing:
		_fade_to(_stove_player, _stove_target_db(), 0.15)


func get_ambient_volume() -> float:
	return _ambient_volume


func get_sfx_volume() -> float:
	return _sfx_volume


# ==================== 通用渐入渐出 ====================
# 把某个播放器的音量平滑渐变到 target_db（linear 域插值，听感更自然）
# player 可以是 AudioStreamPlayer 或 AudioStreamPlayer2D（都有 volume_db / play / stop）
func _fade_to(player, target_db: float, duration: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	# 打断该播放器上一个 fade tween，避免新旧渐变互相打架
	if player.has_meta("fade_tween"):
		var old: Tween = player.get_meta("fade_tween")
		if old != null and old.is_valid():
			old.kill()
	var from_db: float = player.volume_db
	var tween := create_tween()
	player.set_meta("fade_tween", tween)
	var from_lin := db_to_linear(from_db)
	var to_lin := db_to_linear(target_db)
	tween.tween_method(
		func(v: float): player.volume_db = linear_to_db(v),
		from_lin, to_lin, duration
	)


# 渐出到静音后真正停止（用于循环音效的平滑停止）
func _fade_out_then_stop(player, duration: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if player.has_meta("fade_tween"):
		var old: Tween = player.get_meta("fade_tween")
		if old != null and old.is_valid():
			old.kill()
	var tween := create_tween()
	player.set_meta("fade_tween", tween)
	tween.tween_method(
		func(v: float): player.volume_db = linear_to_db(v),
		db_to_linear(player.volume_db), db_to_linear(SILENT_DB), duration
	)
	tween.tween_callback(func():
		if player != null and is_instance_valid(player):
			player.stop()
	)


# ==================== 一次性音效 ====================
# 播放一次性音效（grab / drop 等）：
# - 从池里找空闲播放器，全忙则新建一个，绝不打断正在播放的音效
# - 播放时从静音渐入到目标音量
func play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var p := _acquire_free_player()
	p.stream = stream
	p.volume_db = SILENT_DB
	p.play()
	_fade_to(p, _vol_offset_db(_sfx_volume * _master_volume), SFX_FADE_IN)


# 找一个空闲的一次性播放器，全忙则新建（动态扩容）
func _acquire_free_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if p != null and is_instance_valid(p) and not p.playing:
			return p
	var p := AudioStreamPlayer.new()
	add_child(p)
	_sfx_players.append(p)
	return p


# ==================== 采矿音效（2D 空间化 + 限频 + 密度压音） ====================
# 播放「挖矿动作」音效：全局限频（方案一）+ 密度压音（方案三）+ 低音量（方案五）+ 距离衰减（方案六）
func play_grab_at(world_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_grab_time < int(GRAB_MIN_INTERVAL * 1000.0):
		return  # 限频：过密直接丢弃
	_last_grab_time = now
	var duck_db := _get_duck_db()
	play_sfx_at(SFX_GRAB, world_pos, GRAB_BASE_DB - duck_db)


# 播放「矿物掉落」音效（重要事件，不限频，仅距离衰减 + 密度压音）
func play_drop_at(world_pos: Vector2) -> void:
	var duck_db := _get_duck_db()
	play_sfx_at(SFX_DROP, world_pos, DROP_BASE_DB - duck_db)


# 当前 ducking 压音量：挖矿机器人数超过阈值后，越多压得越狠（封顶）
func _get_duck_db() -> float:
	if _mining_count <= DUCK_FREE_COUNT:
		return 0.0
	return minf(DUCK_MAX_DB, float(_mining_count - DUCK_FREE_COUNT) * DUCK_PER_ROBOT_DB)


# ==================== 玩家手动挖掘节奏 ====================
# 间隔总开关：false = 代码保留但不生效（玩家可连续挖，无冷却，与加此功能前一致）
const PLAYER_MINE_LIMIT_ENABLED := false
const PLAYER_MINE_INTERVAL := 0.6      # 玩家两次手动挖掘之间的最短间隔（秒），调小=挖得更快

var _player_mine_cooldown: float = 0.0 # 剩余冷却时间，>0 时玩家挖不动


# 玩家现在能不能手动挖（冷却结束返回 true）
func can_player_mine() -> bool:
	if not PLAYER_MINE_LIMIT_ENABLED:
		return true
	return _player_mine_cooldown <= 0.0


# 冷却恢复进度：0=刚挖完不可用，1=随时可挖（给光标上方进度条用）
func get_player_mine_ratio() -> float:
	if not PLAYER_MINE_LIMIT_ENABLED or PLAYER_MINE_INTERVAL <= 0.0:
		return 1.0
	return 1.0 - clampf(_player_mine_cooldown / PLAYER_MINE_INTERVAL, 0.0, 1.0)


# 玩家挖完一次，立刻进入冷却
func start_player_mine_cooldown() -> void:
	if not PLAYER_MINE_LIMIT_ENABLED:
		return
	_player_mine_cooldown = PLAYER_MINE_INTERVAL


# 每帧推进冷却
func _tick_player_mine_cooldown(delta: float) -> void:
	if _player_mine_cooldown > 0.0:
		_player_mine_cooldown = maxf(0.0, _player_mine_cooldown - delta)


# 在指定世界坐标播放一个 2D 音效（带距离衰减，超出 max_distance 自动静音）
func play_sfx_at(stream: AudioStream, world_pos: Vector2, target_db: float) -> void:
	if stream == null:
		return
	var p := _acquire_free_2d_player()
	if p == null:
		return
	p.stream = stream
	p.global_position = world_pos
	p.volume_db = SILENT_DB
	p.play()
	# 基础音量 + 其他声音音量偏移（grab/drop 受「其他声音」滑块控制）
	_fade_to(p, target_db + _vol_offset_db(_sfx_volume * _master_volume), SFX_FADE_IN)


# 找一个空闲的 2D 播放器，全忙则新建（动态扩容）
func _acquire_free_2d_player() -> AudioStreamPlayer2D:
	for p in _sfx2d_players:
		if p != null and is_instance_valid(p) and not p.playing:
			return p
	if _sfx2d_players.size() >= SFX2D_POOL_MAX:
		return null   # 并发已达上限：丢弃本次音效，防止池无限膨胀
	var p := AudioStreamPlayer2D.new()
	p.max_distance = SFX2D_MAX_DISTANCE
	p.attenuation = SFX2D_ATTENUATION
	add_child(p)
	_sfx2d_players.append(p)
	return p


# ==================== 背景音乐 ====================
# 切换到指定背景音乐（同一首正在播则不重播）：淡入播放，受「音乐」与「总音量」控制
func play_bgm(stream: AudioStream) -> void:
	if stream == null or _bgm_player == null:
		return
	if _bgm_player.stream == stream and _bgm_player.playing:
		return
	_enable_loop(stream)
	_bgm_player.stop()
	_bgm_player.stream = stream
	_bgm_player.volume_db = SILENT_DB
	_bgm_player.play()
	_fade_to(_bgm_player, _bgm_target_db(), AMBIENT_FADE)


# 让 BGM 循环播放（WAV 与 MP3 的循环参数不同）
func _enable_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


# ==================== 环境音 ====================
func play_ambient() -> void:
	if _ambient_player != null and not _ambient_player.playing:
		_ambient_player.volume_db = SILENT_DB
		_ambient_player.play()
		_fade_to(_ambient_player, _ambient_target_db(), AMBIENT_FADE)


func stop_ambient() -> void:
	if _ambient_player != null:
		_fade_out_then_stop(_ambient_player, AMBIENT_FADE)


# ==================== 炉火声 ====================
# 任一精炼炉在烧就循环播放，最后一炉停烧时停止
func furnace_burning_started() -> void:
	_burning_furnaces += 1
	if _stove_player == null:
		return
	if not _stove_player.playing:
		_stove_player.volume_db = SILENT_DB
		_stove_player.play()
	# 无论是否正在播放都重新淡入：可取消上一次「淡出后停止」的 tween，避免新炉开烧时被旧回调停掉
	_fade_to(_stove_player, _stove_target_db(), AMBIENT_FADE)


func furnace_burning_stopped() -> void:
	_burning_furnaces = maxi(0, _burning_furnaces - 1)
	if _burning_furnaces <= 0 and _stove_player != null:
		_fade_out_then_stop(_stove_player, AMBIENT_FADE)

# ==================== 数据 ====================
var inventory: Dictionary = {}
var tech_levels: Dictionary = {}                # 科技等级，替代 unlocked_techs
var _tech_max_level_overrides: Dictionary = {}  # 运行时改写的科技等级上限（如精炼炉数量取决于场景里预放置的炉子数）
var selected_robot: Node = null                 # 当前选中的机器人
var lab_stage: int = 0                          # 研究所阶段（0~5）
var lab_open: bool = false                      # 科技树（研究所）面板是否打开：打开时屏蔽游戏世界交互（相机移动等）
var intro_playing: bool = false                 # 开局剧情提示框是否在播放：播放期间屏蔽游戏世界交互

const LAB_STAGE_UPGRADE_COSTS := [              # 研究所升级消耗（铜锭）
	{"copper_ingot": 50},    # 0→1
	{"copper_ingot": 150},   # 1→2
	{"copper_ingot": 250},   # 2→3
	{"copper_ingot": 350},   # 3→4
	{"copper_ingot": 450},   # 4→5
]

# ==================== 科技定义 ====================
# category: 分类（供 UI 展示 / 后续筛选使用）
# max_level>1 表示可重复升级（如扩展矿区每级解锁一块）；默认 1 为一次性解锁
# prereq: 前置科技，需全部已解锁才能研究

const TECHS := {
	#能力升级
	"memory_auto": {"category": "能力升级", "name": "坐标点记忆、自动寻路", "desc": "机器人记忆矿点与仓库，空闲时自动前往（开局自带，无需研究）", "cost": {"copper_ingot": 70}, "prereq": ["add_robot"], "lab_stage": 0},
	"fallow": {"category": "能力升级", "name": "休耕意识", "desc": "矿点耐久低于15%时跳过，恢复到80%以上才继续开采", "cost": {"copper_ingot": 40}, "prereq": ["memory_auto", "add_robot"], "lab_stage": 1},
	"priority_sort": {"category": "能力升级", "name": "优先排序能力", "desc": "机器人优先前往最近的矿点或仓库", "cost": {"copper_ingot": 50}, "prereq": ["fallow", "add_robot"], "lab_stage": 2},
	"density": {"category": "能力升级", "name": "密度感知能力", "desc": "机器人感知周围密度，避免拥堵（占位）", "cost": {"copper_ingot": 60}, "prereq": ["fallow", "add_robot"], "lab_stage": 2},
	"info_share": {"category": "能力升级", "name": "信息交流能力", "desc": "机器人之间共享记忆的坐标点", "cost": {"copper_ingot": 150}, "prereq": ["fallow", "add_robot"], "lab_stage": 4},
	"resource_swap": {"category": "能力升级", "name": "资源交换", "desc": "背包空余的机器人可接收同伴的矿物", "cost": {"copper_ingot": 100}, "prereq": ["fallow", "add_robot"], "lab_stage": 3},
	"reproduce": {"category": "能力升级", "name": "繁殖能力", "desc": "满足条件时自动生成新机器人（受「机器人数量上限」限制）", "cost": {"copper_ingot": 500}, "prereq": ["fallow", "density", "info_share", "resource_swap", "add_robot"], "lab_stage": 5},
	#资源点升级
	"regen_speed": {"category": "资源点升级", "name": "资源再生速度", "desc": "提升矿点耐久恢复速度（每级 ×2，满级总倍率 ×32）", "cost": {"copper_ingot": 15}, "prereq": ["add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stage": 0},
	"ore_durability": {"category": "资源点升级", "name": "资源点耐久度", "desc": "提升矿点初始耐久（每级 ×1.5）", "cost": {"copper_ingot": 30}, "prereq": ["regen_speed", "add_robot"], "max_level": 2, "dynamic_cost": true, "lab_stage": 1},
	"unlock_more_ores": {"category": "资源点升级", "name": "新的资源点", "desc": "每次升级 Reveal 3 个预放置的矿点区域", "cost": {"copper_ingot": 50}, "prereq": ["regen_speed", "add_robot"], "max_level": 3, "dynamic_cost": true, "lab_stages": [1, 2, 3]},
	#机器人升级
	"move_speed": {"category": "机器人升级", "name": "移动速度", "desc": "提升机器人移动速度（每级 +60/+100/+160）", "prereq": ["add_robot"], "max_level": 3, "costs": [{"copper_ingot": 8}, {"copper_ingot": 40}, {"copper_ingot": 150}], "lab_stages": [0, 1, 2]},
	"backpack_capacity": {"category": "机器人升级", "name": "背包容量", "desc": "提升机器人背包容量（每级 +1）", "cost": {"copper_ingot": 60}, "prereq": ["move_speed", "add_robot"], "max_level": 4, "dynamic_cost": true, "lab_stage": 1},
	"mine_speed": {"category": "机器人升级", "name": "采集速度", "desc": "缩短机器人采矿耗时（每级 -0.25 秒）", "cost": {"copper_ingot": 12}, "prereq": ["move_speed", "add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stages": [0, 0, 0, 2, 2]},
	"robot_count": {"category": "机器人升级", "name": "机器人数量上限", "desc": "提升可拥有的机器人数量上限（初始20，每级+40）", "prereq": ["move_speed", "add_robot"], "max_level": 3, "costs": [{"copper_ingot": 100}, {"copper_ingot": 250}, {"copper_ingot": 600}], "lab_stages": [2, 3, 4]},
	# 注意：add_robot 不写 max_level —— 它的等级上限 = GameManager.get_robot_max()，
	# 随「机器人数量上限」科技实时变化（见 get_tech_max_level）。
	"add_robot": {"category": "机器人升级", "name": "添加机器人", "desc": "每升一级立即获得一个机器人（上限跟随「机器人数量上限」）", "cost": {"copper_ingot": 3}, "prereq": [], "dynamic_cost": true, "cost_growth": 1.15, "lab_stage": 0},
	#精炼炉升级
	"smelt_speed": {"category": "精炼炉升级", "name": "煅烧速度", "desc": "提升精炼炉的烧制速度（每级 -0.25 秒）", "cost": {"copper_ingot": 20}, "prereq": ["add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stage": 0},
	"double_smelt": {"category": "精炼炉升级", "name": "无中生有", "desc": "精炼炉有 15% 概率一次烧出两个铜锭", "cost": {"copper_ingot": 120}, "prereq": ["smelt_speed", "add_robot"], "lab_stage": 1},
	"smelt_crit": {"category": "精炼炉升级", "name": "暴击率", "desc": "提升精炼炉一次烧出两个铜锭的概率（每级 +15%）", "cost": {"copper_ingot": 150}, "prereq": ["double_smelt", "add_robot"], "max_level": 4, "dynamic_cost": true, "lab_stage": 2},
	"sync_fan": {"category": "精炼炉升级", "name": "同步鼓风", "desc": "点击一个精炼炉即可为所有精炼炉同步鼓风", "cost": {"copper_ingot": 200}, "prereq": ["smelt_crit", "add_robot"], "lab_stage": 3},
	"add_furnace": {"category": "精炼炉升级", "name": "扩建精炼炉", "desc": "启用场景里预放置的下一个精炼炉，并行烧制（共 5 次）", "cost": {"copper_ingot": 100}, "prereq": ["unlock_more_ores", "add_robot"], "max_level": 5, "dynamic_cost": true, "lab_stage": 1},
	}

# 开局自带、无需研究的科技：机器人天生就会记忆矿点坐标并自动寻路。
# 这些科技的等级恒为满级，科技树里显示成「初始自带」，不能再花铜锭购买（购买入口被 can_unlock_tech 拦掉）。
const DEFAULT_TECHS: Array[String] = ["memory_auto"]


# 是否开局自带（科技树里不可购买、等级恒满）
func is_default_tech(tech_id: String) -> bool:
	return DEFAULT_TECHS.has(tech_id)

# ==================== 机器人数量上限 ====================
# 注意：「机器人数量上限」科技是后期才解锁的（lab_stages=[2,3,4]），
# 所以基础上限必须足够撑起研究所阶段 0~1 的中前期产能，不能设得太低。
const ROBOT_MAX_BASE := 20           # 基础上限（阶段 0~1 期间可用，足够支撑早期爬升）
const ROBOT_MAX_PER_LEVEL := 40      # 「机器人数量上限」科技每级增加的数量（3 级 → 20/60/100/140）

func get_robot_max() -> int:
	return ROBOT_MAX_BASE + ROBOT_MAX_PER_LEVEL * get_tech_level("robot_count")


# ==================== 资源 ====================
func add_item(item_type: String, amount: int) -> void:
	if amount <= 0:
		return
	inventory[item_type] = inventory.get(item_type, 0) + amount
	inventory_changed.emit(inventory)

func remove_item(item_type: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if inventory.get(item_type, 0) < amount:
		return false
	inventory[item_type] -= amount
	if inventory[item_type] <= 0:
		inventory.erase(item_type)
	inventory_changed.emit(inventory)
	return true

func get_count(item_type: String) -> int:
	return inventory.get(item_type, 0)

# 全场所有精炼炉内「待烧铜矿」的总量。
# 只统计已启用的炉子：未启用的炉子已退出 "furnace" 分组（见 RefiningFurnace.set_active）。
# 炉子烧制会持续消耗矿量，所以这个值需要 UI 定时轮询，没有变化信号可用。
func get_furnace_ore_total() -> int:
	var total: int = 0
	for node in get_tree().get_nodes_in_group("furnace"):
		if node.has_method("get_ore_stock"):
			total += node.get_ore_stock()
	return total

# ==================== 科技等级 ====================
func get_tech_level(tech_id: String) -> int:
	var lv: int = tech_levels.get(tech_id, 0)
	# 开局自带的科技等级恒为满级（不写进 tech_levels，避免与存档 / 重置逻辑混淆）
	if DEFAULT_TECHS.has(tech_id):
		return maxi(lv, get_tech_max_level(tech_id))
	return lv

func get_tech_max_level(tech_id: String) -> int:
	# 「添加机器人」的等级上限 = 当前机器人数量上限，随「机器人数量上限」科技实时同步。
	# 所以 TECHS 里不写死 max_level，否则会和 ROBOT_MAX_* 两处各说各话。
	if tech_id == "add_robot":
		return get_robot_max()
	if _tech_max_level_overrides.has(tech_id):
		return _tech_max_level_overrides[tech_id]
	return TECHS.get(tech_id, {}).get("max_level", 1)

# 运行时改写某科技的等级上限（用于让「扩建精炼炉」的级数自动匹配场景里预放置的炉子数量）
func set_tech_max_level(tech_id: String, max_level: int) -> void:
	_tech_max_level_overrides[tech_id] = maxi(0, max_level)

# 获取某科技下一次升级所需的消耗（支持动态消耗，如「添加机器人」「背包容量」随等级递增）
#   - costs 数组：固定阶梯消耗，按等级索引取值
#   - dynamic_cost：公式 C = C0 × r^n 逐项向上取整（C0 = cost 基础值，r = cost_growth 默认 1.5，n = 当前等级，第 1 次升级 n=0）
func get_tech_cost(tech_id: String) -> Dictionary:
	var tech: Dictionary = TECHS.get(tech_id, {})
	var n: int = get_tech_level(tech_id)
	# 固定阶梯消耗：costs 数组按等级索引取值（第 1 次升级用 costs[0]）
	var costs: Array = tech.get("costs", [])
	if costs.size() > 0:
		return costs[clampi(n, 0, costs.size() - 1)]
	if tech.get("dynamic_cost", false):
		var growth: float = tech.get("cost_growth", 1.5)
		var result := {}
		for item_type in tech.get("cost", {}):
			result[item_type] = int(ceil(float(tech["cost"][item_type]) * pow(growth, float(n))))
		return result
	return tech.get("cost", {})

# 是否已满级
func is_tech_unlocked(tech_id: String) -> bool:
	return get_tech_level(tech_id) >= get_tech_max_level(tech_id)

# 是否可以解锁（存在 + 没满级 + 前置满足 + 资源够）
func can_unlock_tech(tech_id: String) -> bool:
	if not TECHS.has(tech_id):
		return false
	# 开局自带：无需研究，也不允许再花铜锭购买
	if is_default_tech(tech_id):
		return false
	if is_tech_unlocked(tech_id):
		return false
	var tech: Dictionary = TECHS[tech_id]
	# add_robot 购买前拦截：机器人数量已达上限时不可购买
	if tech_id == "add_robot":
		if get_tree().get_nodes_in_group("robots").size() >= get_robot_max():
			return false
	# 前置科技必须至少解锁1级（无需满级）
	for pre in tech.get("prereq", []):
		if get_tech_level(pre) < 1:
			return false
	# 研究所阶段门槛：该科技下一级 lab_stage 必须 <= 当前研究所阶段
	# 支持 lab_stages 数组（每级不同阶段）或单一 lab_stage
	var n: int = get_tech_level(tech_id)
	var tech_lab_stage: int = 0
	var lab_stages_arr: Array = tech.get("lab_stages", [])
	if lab_stages_arr.size() > 0:
		tech_lab_stage = lab_stages_arr[clampi(n, 0, lab_stages_arr.size() - 1)]
	else:
		tech_lab_stage = tech.get("lab_stage", 0)
	if tech_lab_stage > lab_stage:
		return false
	for item_type in get_tech_cost(tech_id):
		if get_count(item_type) < get_tech_cost(tech_id)[item_type]:
			return false
	return true

# 解锁一次（等级 +1）
func unlock_tech(tech_id: String) -> bool:
	if not can_unlock_tech(tech_id):
		return false
	var cost := get_tech_cost(tech_id)
	for item_type in cost:
		remove_item(item_type, cost[item_type])
	tech_levels[tech_id] = get_tech_level(tech_id) + 1
	tech_unlocked.emit(tech_id)
	return true

# ==================== 研究所升级 ====================
func can_upgrade_lab() -> bool:
	if lab_stage >= LAB_STAGE_UPGRADE_COSTS.size():
		return false
	var cost: Dictionary = LAB_STAGE_UPGRADE_COSTS[lab_stage]
	for item_type in cost:
		if get_count(item_type) < cost[item_type]:
			return false
	return true

func upgrade_lab() -> bool:
	if not can_upgrade_lab():
		return false
	var cost: Dictionary = LAB_STAGE_UPGRADE_COSTS[lab_stage]
	for item_type in cost:
		remove_item(item_type, cost[item_type])
	lab_stage += 1
	return true

# ==================== 机器人选中 ====================
func select_robot(robot: Node) -> void:
	selected_robot = robot
	robot_selected.emit(robot)

func deselect_robot() -> void:
	selected_robot = null
	robot_selected.emit(null)

# ==================== 清空 ====================
func clear() -> void:
	inventory.clear()
	tech_levels.clear()
	selected_robot = null
	_player_mine_cooldown = 0.0
	# 场景级音频状态也要复位，否则重开一局时炉火计数会沿用旧值
	_burning_furnaces = 0
	_mining_count = 0
	if _stove_player != null:
		_stove_player.stop()
	inventory_changed.emit(inventory)


# 返回主菜单 / 退出到开始界面前调用：清理只在当前场景有效的状态
func reset_scene_state() -> void:
	_burning_furnaces = 0
	_mining_count = 0
	if _stove_player != null:
		_stove_player.stop()
	selected_robot = null
	lab_open = false
	intro_playing = false


# ==================== 存档系统 ====================
# 存档内容：库存 / 科技等级 / 研究所阶段 / 机器人（位置、背包、记忆）/
# 精炼炉状态（待烧矿、炉温、烧制进度）/ 矿点耐久 / 音量设置。
# 矿点显示数量（1 + unlock_more_ores×3）与炉子启用数量（1 + add_furnace）
# 可由科技等级直接推导，不单独存，由 wolrd.gd 在恢复时重建。
const SAVE_PATH := "user://savegame.json"

# 音量设置独立存档：开始界面也能读写，且不会覆盖游戏进度
const OPTIONS_PATH := "user://settings.json"


func load_options() -> void:
	if not FileAccess.file_exists(OPTIONS_PATH):
		return
	var f := FileAccess.open(OPTIONS_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		return
	_ambient_volume = clampf(float(parsed.get("ambient_volume", 1.0)), 0.0, 1.0)
	_sfx_volume = clampf(float(parsed.get("sfx_volume", 1.0)), 0.0, 1.0)
	_master_volume = clampf(float(parsed.get("master_volume", 1.0)), 0.0, 1.0)


func save_options() -> void:
	var f := FileAccess.open(OPTIONS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"ambient_volume": _ambient_volume,
		"sfx_volume": _sfx_volume,
		"master_volume": _master_volume,
	}))
	f.close()

# wolrd.gd 的 _ready 检测：为 true 时按存档重建世界（机器人 / 矿点 / 炉子），完成后清除
var restore_mode: bool = false
var _restore_robot_count: int = 0        # 恢复时需要生成的机器人数（繁殖产生的机器人也计入）
var _restore_robot_memory: Array = []    # 旧版存档字段：按机器人生成顺序对应的已记忆矿区名
var _restore_robots: Array = []          # 新版存档：每个机器人的 {memory, pos, carry}
var _restore_furnaces: Array = []        # 每个炉子的 {name, ore, heat, smelt}
var _restore_patch_durability: Dictionary = {}  # 矿点节点名 -> 耐久
var _restore_drops: Array = []           # 地上未回收的掉落物 {type, amount, pos}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


# 保存当前进度（JSON）。退出游戏 / 自动保存时由 wolrd.gd 调用。
func save_game() -> void:
	# 机器人：记忆 + 位置 + 背包。逐条整体保存，避免依赖分组顺序与生成顺序对齐
	var robots: Array = []
	for robot in get_tree().get_nodes_in_group("robots"):
		robots.append({
			"memory": robot.get_known_patch_names() if robot.has_method("get_known_patch_names") else [],
			"x": robot.global_position.x,
			"y": robot.global_position.y,
			"carry": robot.get_carry_count() if robot.has_method("get_carry_count") else 0,
		})
	# 精炼炉：按节点名保存待烧矿 / 炉温 / 烧制进度
	var furnaces: Array = []
	for node in get_tree().get_nodes_in_group("furnace"):
		if node is RefiningFurnace:
			furnaces.append({
				"name": String(node.name),
				"ore": node.get_ore_stock(),
				"heat": node.get_heat(),
				"smelt": node.get_smelt_timer(),
			})
	# 矿点耐久：按节点名保存
	var patches: Dictionary = {}
	for node in get_tree().get_nodes_in_group("ore_patch"):
		if node is OrePatch and node.has_method("get_durability"):
			patches[String(node.name)] = node.get_durability()
	# 地上未回收的掉落物（飞行中的不存，它们马上会入炉）
	var drops: Array = []
	for node in get_tree().get_nodes_in_group("dropped_items"):
		if node is DroppedItem and node.input_pickable:
			drops.append({
				"type": node.item_type,
				"amount": node.amount,
				"x": node.global_position.x,
				"y": node.global_position.y,
			})
	var data := {
		"version": 2,
		"inventory": inventory,
		"tech_levels": tech_levels,
		"lab_stage": lab_stage,
		"robot_count": robots.size(),
		"robots": robots,
		"furnaces": furnaces,
		"patches": patches,
		"drops": drops,
		"ambient_volume": _ambient_volume,
		"sfx_volume": _sfx_volume,
		"master_volume": _master_volume,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("存档写入失败：%s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data))
	f.close()
	# 音量同时也写入独立设置文件，保证下次启动在开始界面就能恢复
	save_options()


# 读取存档到当前状态，成功后置 restore_mode = true（等待 wolrd 场景消费）。
func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary:
		push_warning("存档格式损坏，忽略")
		return false
	# JSON 反序列化的数字都是 float：库存 / 科技等级 / 机器人数量逐项转回 int
	var raw_inv = parsed.get("inventory", {})
	if not raw_inv is Dictionary:
		push_warning("存档库存字段损坏，忽略")
		return false
	var inv: Dictionary = {}
	for k in raw_inv:
		inv[String(k)] = maxi(0, int(raw_inv[k]))
	inventory = inv
	var raw_tl = parsed.get("tech_levels", {})
	if not raw_tl is Dictionary:
		push_warning("存档科技字段损坏，忽略")
		return false
	var tl: Dictionary = {}
	for k in raw_tl:
		tl[String(k)] = int(raw_tl[k])
	tech_levels = {}
	lab_stage = clampi(int(parsed.get("lab_stage", 0)), 0, LAB_STAGE_UPGRADE_COSTS.size())
	# 第一轮：除 add_robot 外按各自上限夹紧（add_robot 上限依赖 robot_count，必须先恢复 robot_count）
	for k in tl:
		var tid := String(k)
		if tid == "add_robot" or not TECHS.has(tid):
			continue
		tech_levels[tid] = clampi(int(tl[k]), 0, get_tech_max_level(tid))
	if tl.has("add_robot"):
		tech_levels["add_robot"] = clampi(int(tl["add_robot"]), 0, get_tech_max_level("add_robot"))
	# 新版存档：机器人记录（位置 / 背包 / 记忆）
	_restore_robots = []
	var raw_robots = parsed.get("robots", [])
	if raw_robots is Array:
		for r in raw_robots:
			if not r is Dictionary:
				continue
			var mem: Array = []
			var raw_mem = r.get("memory", [])
			if raw_mem is Array:
				for n in raw_mem:
					mem.append(String(n))
			_restore_robots.append({
				"memory": mem,
				"pos": Vector2(float(r.get("x", 0.0)), float(r.get("y", 0.0))),
				"carry": maxi(0, int(r.get("carry", 0))),
			})
	_restore_robot_count = maxi(0, int(parsed.get("robot_count", _restore_robots.size())))
	if not _restore_robots.is_empty():
		_restore_robot_count = mini(_restore_robot_count, _restore_robots.size())
	# 旧版存档兼容：只有 robot_memory（按生成顺序）
	_restore_robot_memory = []
	var raw_memories = parsed.get("robot_memory", [])
	if raw_memories is Array:
		for arr in raw_memories:
			var names: Array = []
			if arr is Array:
				for n in arr:
					names.append(String(n))
			_restore_robot_memory.append(names)
	# 精炼炉状态
	_restore_furnaces = []
	var raw_furnaces = parsed.get("furnaces", [])
	if raw_furnaces is Array:
		for st in raw_furnaces:
			if not st is Dictionary:
				continue
			_restore_furnaces.append({
				"name": String(st.get("name", "")),
				"ore": maxi(0, int(st.get("ore", 0))),
				"heat": clampf(float(st.get("heat", RefiningFurnace.HEAT_MAX)), 0.0, RefiningFurnace.HEAT_MAX),
				"smelt": maxf(0.0, float(st.get("smelt", 0.0))),
			})
	# 矿点耐久
	_restore_patch_durability = {}
	var raw_patches = parsed.get("patches", {})
	if raw_patches is Dictionary:
		for patch_name in raw_patches:
			_restore_patch_durability[String(patch_name)] = maxf(0.0, float(raw_patches[patch_name]))
	# 地上掉落物
	_restore_drops = []
	var raw_drops = parsed.get("drops", [])
	if raw_drops is Array:
		for d in raw_drops:
			if not d is Dictionary:
				continue
			_restore_drops.append({
				"type": String(d.get("type", "copper")),
				"amount": maxi(1, int(d.get("amount", 1))),
				"pos": Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0))),
			})
	set_ambient_volume(float(parsed.get("ambient_volume", 1.0)))
	set_sfx_volume(float(parsed.get("sfx_volume", 1.0)))
	set_master_volume(float(parsed.get("master_volume", 1.0)))
	# 切场景前清掉旧场景残留的运行时状态
	selected_robot = null
	lab_open = false
	intro_playing = false
	restore_mode = true
	inventory_changed.emit(inventory)
	return true


func get_restore_robot_count() -> int:
	return _restore_robot_count


func get_restore_robot_memory() -> Array:
	return _restore_robot_memory


func get_restore_robots() -> Array:
	return _restore_robots


func get_restore_furnaces() -> Array:
	return _restore_furnaces


func get_restore_patch_durability() -> Dictionary:
	return _restore_patch_durability


func get_restore_drops() -> Array:
	return _restore_drops


func clear_restore_mode() -> void:
	restore_mode = false


# 删除存档（开始新游戏覆盖旧存档前调用，语义更明确）
func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# 开始新游戏：清空全部进度（等价旧存档被覆盖的起点状态）
func reset_progress() -> void:
	clear()
	_tech_max_level_overrides = {}
	lab_stage = 0
	_restore_robot_count = 0
	_restore_robot_memory = []
	_restore_robots = []
	_restore_furnaces = []
	_restore_patch_durability = {}
	_restore_drops = []
	restore_mode = false
