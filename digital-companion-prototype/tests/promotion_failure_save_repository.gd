class_name PromotionFailureSaveRepository
extends SaveRepository

## Test double that fails exactly one staged-candidate promotion while allowing
## restoration of the previous primary generation.

var fail_next_promotion := true


func _rename(from_path: String, to_path: String) -> bool:
	if fail_next_promotion and from_path == temp_path and to_path == primary_path:
		fail_next_promotion = false
		return false
	return super._rename(from_path, to_path)
