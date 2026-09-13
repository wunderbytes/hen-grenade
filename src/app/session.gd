class_name Session
## The lobby's choice of GameMode, as a static. See docs/milestone-3.5-brief.md §3.
##
## Not an autoload: tests set it, the lobby writes it, MatchScene reads it.
## Quitting to the lobby keeps the last choice, which is what rematch-from-the-
## lobby-after-B should feel like. Deathmatch is the default so a sofa that
## never touches LB/RB gets the M3 game.

const MODE_DEATHMATCH: String = "DEATHMATCH"
const MODE_HEN: String = "HEN"
const MODE_IDS: Array[String] = [MODE_DEATHMATCH, MODE_HEN]

static var mode_id: String = MODE_DEATHMATCH

static func cycle(delta: int) -> void:
	var i: int = MODE_IDS.find(mode_id)
	if i < 0:
		i = 0
	var n: int = MODE_IDS.size()
	i = (i + delta) % n
	if i < 0:
		i += n
	mode_id = MODE_IDS[i]

static func is_hen() -> bool:
	return mode_id == MODE_HEN

static func load_mode() -> GameMode:
	var path: String = GameMode.HEN_PATH if is_hen() else GameMode.DEATHMATCH_PATH
	var res: Resource = load(path)
	if res is GameMode:
		return res as GameMode
	return GameMode.hen() if is_hen() else GameMode.deathmatch()

static func reset() -> void:
	mode_id = MODE_DEATHMATCH
