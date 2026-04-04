extends Node

const SFX_GUNSHOT: AudioStream = preload("res://assets/Audio/SFX/Gun/gunshot/gunshot.wav")
const SFX_BULLET_WALL_IMPACT: AudioStream = preload("res://assets/Audio/SFX/Bullet/collides with wall/446126__justinvoke__collision-1.wav")
const SFX_ENEMY_ARMOR_BREAK: AudioStream = preload("res://assets/Audio/SFX/Enemy/armour break/486068__craigsmith__r12-29-gun-shot-through-window.wav")
const SFX_ENEMY_DEATH: AudioStream = preload("res://assets/Audio/SFX/Enemy/death/661617__solar01__glass-marbles-dropping-into-singing-bowl.wav")
const SFX_UI_INTERACTION: AudioStream = preload("res://assets/Audio/SFX/UI/menu interaction/540568__eminyildirim__ui-pop-up.wav")

const MUSIC_COLD_FIRE: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/cold-fire-neozoic-main-version-37473-02-16.mp3")
const MUSIC_COSMIC_LOVE: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/cosmic-love-aavirall-main-version-27447-02-17.mp3")
const MUSIC_FEEL_THE_EARTH_SPINNING: AudioStream = preload("res://assets/Audio/Soundtrack/World 1/feel-the-earth-spinning-euchmad-main-version-34276-03-36.mp3")

const BASE_AUDIO_GAIN_LINEAR := 0.6696
const MIX_BOOST_GAMEPLAY_SFX_DB := 3.0
const MIX_BOOST_UI_SFX_DB := 4.0

var _music_player: AudioStreamPlayer = null
var _menu_music_playlist: Array[AudioStream] = []
var _menu_last_track_index: int = -1
var _music_mode: String = ""
var _active_sfx_players: Array[AudioStreamPlayer3D] = []
var _music_default_volume_db: float = linear_to_db(BASE_AUDIO_GAIN_LINEAR)
var _sfx_default_volume_db: float = linear_to_db(BASE_AUDIO_GAIN_LINEAR)
var _music_volume_percent: float = 100.0

func setup() -> void:
    randomize()
    _menu_music_playlist = [MUSIC_COLD_FIRE, MUSIC_COSMIC_LOVE, MUSIC_FEEL_THE_EARTH_SPINNING]
    _music_player = AudioStreamPlayer.new()
    _music_player.name = "MusicPlayer"
    _music_player.bus = _get_existing_bus_or_default("Music")
    add_child(_music_player)
    _apply_music_volume_setting()
    if not _music_player.finished.is_connected(_on_music_finished):
        _music_player.finished.connect(_on_music_finished)

func _get_existing_bus_or_default(bus_name: String) -> String:
    if AudioServer.get_bus_index(bus_name) != -1:
        return bus_name
    return "Master"

func _apply_music_volume_setting() -> void:
    var target_db := _volume_percent_to_db(_music_volume_percent)
    var music_bus_index := AudioServer.get_bus_index("Music")
    if music_bus_index != -1:
        AudioServer.set_bus_volume_db(music_bus_index, target_db)
        if _music_player != null:
            _music_player.volume_db = _music_default_volume_db
        return
    if _music_player != null:
        _music_player.volume_db = _music_default_volume_db + target_db

func _volume_percent_to_db(value: float) -> float:
    if value <= 0.0:
        return -80.0
    return linear_to_db(clampf(value / 100.0, 0.0, 1.0))

func _on_music_finished() -> void:
    if _music_mode == "menu":
        _play_random_menu_track()

func _ensure_menu_music_playing() -> void:
    _music_mode = "menu"
    if _music_player == null:
        return
    if _music_player.playing:
        return
    _play_random_menu_track()

func fade_out_music_and_stop(duration: float) -> void:
    if _music_player == null or not _music_player.playing:
        return
    if duration <= 0.0:
        _music_player.stop()
        _apply_music_volume_setting()
        return

    var tween := create_tween()
    tween.tween_property(_music_player, "volume_db", -60.0, duration)
    tween.finished.connect(func() -> void:
        if _music_player == null:
            return
        _music_player.stop()
        _apply_music_volume_setting())

func _play_random_menu_track() -> void:
    if _music_player == null:
        return
    if _menu_music_playlist.is_empty():
        return

    var next_index := 0
    if _menu_music_playlist.size() == 1:
        next_index = 0
    else:
        next_index = randi_range(0, _menu_music_playlist.size() - 1)
        if next_index == _menu_last_track_index:
            next_index = (next_index + 1) % _menu_music_playlist.size()

    _menu_last_track_index = next_index
    var stream := _menu_music_playlist[next_index]
    if stream == null:
        return
    _music_player.stream = stream
    _apply_music_volume_setting()
    _music_player.play()

func _select_level_music_stream(level_path: String) -> AudioStream:
    var tracks: Array[AudioStream] = _menu_music_playlist
    if tracks.is_empty():
        tracks = [MUSIC_COLD_FIRE, MUSIC_COSMIC_LOVE, MUSIC_FEEL_THE_EARTH_SPINNING]
    if tracks.is_empty():
        return null

    # Simple stable selection: hash the path
    if level_path.is_empty():
        return tracks[0]
    var stable_index := posmod(level_path.hash(), tracks.size())
    return tracks[stable_index]

func play_level_music_for_path(level_path: String) -> void:
    if _music_player == null:
        return
    var stream := _select_level_music_stream(level_path)
    if stream == null:
        return
    var should_switch := (_music_mode != "level") or (_music_player.stream != stream)
    _music_mode = "level"
    if not should_switch and _music_player.playing:
        return
    _music_player.stream = stream
    _apply_music_volume_setting()
    _music_player.play()

func set_music_volume_percent(value: float) -> void:
    _music_volume_percent = clampf(value, 0.0, 100.0)
    _apply_music_volume_setting()

func get_music_volume_percent() -> float:
    return _music_volume_percent

func _track_sfx_player(player: AudioStreamPlayer3D) -> void:
    _active_sfx_players.append(player)
    if not player.finished.is_connected(func() -> void:
        _active_sfx_players.erase(player)
        if is_instance_valid(player):
            player.queue_free()):
        player.finished.connect(func() -> void:
            _active_sfx_players.erase(player)
            if is_instance_valid(player):
                player.queue_free())

func _stop_all_sfx() -> void:
    for player in _active_sfx_players:
        if not is_instance_valid(player):
            continue
        player.stop()
        player.queue_free()
    _active_sfx_players.clear()

func _play_sfx_3d(
    stream: AudioStream,
    origin: Vector3,
    bus_name: String,
    volume_db: float = 0.0,
    pitch_min: float = 0.98,
    pitch_max: float = 1.02,
    volume_jitter_db: float = 0.6,
    start_time: float = 0.0
) -> void:
    if stream == null:
        return
    var player := AudioStreamPlayer3D.new()
    player.top_level = true
    player.stream = stream
    player.bus = _get_existing_bus_or_default(bus_name)
    player.volume_db = _sfx_default_volume_db + volume_db + randf_range(-absf(volume_jitter_db), absf(volume_jitter_db))
    player.pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
    add_child(player)
    player.global_position = origin
    _track_sfx_player(player)
    player.play(maxf(0.0, start_time))

func _play_sfx_ui(
    stream: AudioStream,
    bus_name: String,
    volume_db: float = 0.0,
    pitch_min: float = 0.98,
    pitch_max: float = 1.02,
    volume_jitter_db: float = 0.6,
    start_time: float = 0.0
) -> void:
    if stream == null:
        return
    var player := AudioStreamPlayer.new()
    player.stream = stream
    player.bus = _get_existing_bus_or_default(bus_name)
    player.volume_db = _sfx_default_volume_db + volume_db + randf_range(-absf(volume_jitter_db), absf(volume_jitter_db))
    player.pitch_scale = randf_range(minf(pitch_min, pitch_max), maxf(pitch_min, pitch_max))
    add_child(player)
    if not player.finished.is_connected(player.queue_free):
        player.finished.connect(player.queue_free)
    player.play(maxf(0.0, start_time))

func play_gunshot_at(origin: Vector3) -> void:
    _play_sfx_3d(SFX_GUNSHOT, origin, "SFX", -3.0 + MIX_BOOST_GAMEPLAY_SFX_DB, 0.98, 1.02, 0.6, 0.57)

func play_bullet_wall_impact_at(origin: Vector3) -> void:
    _play_sfx_3d(SFX_BULLET_WALL_IMPACT, origin, "SFX", -2.0 + MIX_BOOST_GAMEPLAY_SFX_DB)

func play_enemy_death_at(origin: Vector3) -> void:
    if SFX_ENEMY_DEATH == null:
        return

    var start_time := 1.18
    var fade_anchor_time := 4.0
    var fade_delay := maxf(0.0, fade_anchor_time - start_time)
    var fade_duration := 0.55

    var player := AudioStreamPlayer3D.new()
    player.top_level = true
    player.stream = SFX_ENEMY_DEATH
    player.bus = _get_existing_bus_or_default("SFX")
    player.volume_db = _sfx_default_volume_db - 1.0 + MIX_BOOST_GAMEPLAY_SFX_DB + randf_range(-0.5, 0.5)
    player.pitch_scale = randf_range(0.98, 1.02)
    add_child(player)
    player.global_position = origin
    _track_sfx_player(player)
    player.play(start_time)

    get_tree().create_timer(fade_delay).timeout.connect(func() -> void:
        if not is_instance_valid(player):
            return
        var tween := create_tween()
        tween.tween_property(player, "volume_db", -60.0, fade_duration))

    get_tree().create_timer(fade_delay + fade_duration + 0.05).timeout.connect(func() -> void:
        if not is_instance_valid(player):
            return
        _active_sfx_players.erase(player)
        player.stop()
        player.queue_free())

func play_enemy_armor_break_at(origin: Vector3) -> void:
    _play_sfx_3d(SFX_ENEMY_ARMOR_BREAK, origin, "SFX", -3.0 + MIX_BOOST_GAMEPLAY_SFX_DB)

func play_ui_interaction() -> void:
    _play_sfx_ui(SFX_UI_INTERACTION, "UI", -8.0 + MIX_BOOST_UI_SFX_DB, 0.98, 1.02, 0.5)
