class_name Settings
extends RefCounted
## Persistent user settings (user://settings.cfg).

static var _cfg: ConfigFile
const PATH := "user://settings.cfg"


static func _load() -> void:
	if _cfg:
		return
	_cfg = ConfigFile.new()
	_cfg.load(PATH)


static func get_val(key: String, default: Variant) -> Variant:
	_load()
	return _cfg.get_value("game", key, default)


static func set_val(key: String, v: Variant) -> void:
	_load()
	_cfg.set_value("game", key, v)
	_cfg.save(PATH)
