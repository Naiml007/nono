class_name UserFilesHelper
## Snapshot/restore the user:// persistence files so headless tests never
## clobber real player progress. Call snapshot() before mutating state and
## restore() before quitting.

const FILES := [
	"user://nono_save.cfg",
	"user://nono_settings.cfg",
	"user://nono_achievements.cfg",
]

static func snapshot() -> Dictionary:
	var out := {}
	for path in FILES:
		out[path] = _read(path)
	return out

static func restore(backup: Dictionary) -> void:
	for path in FILES:
		var data: PackedByteArray = backup.get(path, PackedByteArray())
		if data.is_empty():
			_remove(path)
		else:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(data)
				f.close()

static func _read(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var data := f.get_buffer(f.get_length())
	f.close()
	return data

static func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
