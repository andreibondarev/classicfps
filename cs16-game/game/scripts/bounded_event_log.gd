extends RefCounted

## Recent diagnostics, not a replay archive. Recording is O(1), and discarding
## old diagnostics never affects simulation, voice ownership, or event signals.
const DEFAULT_CAPACITY := 4096

var capacity: int
var total_events := 0
var _entries: Array[Dictionary] = []
var _oldest := 0


func _init(limit := DEFAULT_CAPACITY) -> void:
	capacity = maxi(1, limit)


func append(event: Dictionary) -> void:
	if _entries.size() < capacity:
		_entries.append(event)
	else:
		_entries[_oldest] = event
		_oldest = (_oldest + 1) % capacity
	total_events += 1


func clear() -> void:
	_entries.clear()
	_oldest = 0
	total_events = 0


func snapshot(deep := true) -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for offset in range(_entries.size()):
		var event := _entries[(_oldest + offset) % _entries.size()]
		ordered.append(event.duplicate(true) if deep else event)
	return ordered
