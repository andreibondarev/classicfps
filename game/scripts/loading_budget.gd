extends RefCounted

## Paces finite loading loops (asset preparation before deployment). Waiting a
## whole frame after every small step made loading take as many frames as it
## had steps: hundreds of frames that each did a few milliseconds of work. A
## loop now keeps working until it has used FRAME_BUDGET_USEC of the current
## frame, then lets one frame render. Use `await LoadingBudget.pace(tree)`.

const FRAME_BUDGET_USEC := 12000

static var _slice_started := 0


static func pace(tree: SceneTree) -> void:
	var now := Time.get_ticks_usec()
	if _slice_started == 0 or now - _slice_started > 1000000:
		# First step, or the first step after a pause in loading.
		_slice_started = now
	if now - _slice_started < FRAME_BUDGET_USEC:
		return
	await tree.process_frame
	_slice_started = Time.get_ticks_usec()
