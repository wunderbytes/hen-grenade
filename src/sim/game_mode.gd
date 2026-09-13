class_name GameMode
extends Resource
## How this round is scored and generated. See docs/milestone-3.5-brief.md §3
## and docs/technical-design.md §6.
##
## The simulation sees this resource. Deathmatch is the default: a null passed
## to MatchState.create() becomes these deathmatch numbers, so every existing
## test keeps meaning what it meant. Names and the path to MatchRules are not
## in the fingerprint — a display rename must not invalidate a replay, and
## MatchRules lives above the sim by construction.

enum Id { DEATHMATCH = 0, HEN = 1 }
enum Scoring { KILLS = 0, HEN_TICKS = 1 }

const DEATHMATCH_PATH: String = "res://data/balance/modes/deathmatch.tres"
const HEN_PATH: String = "res://data/balance/modes/hen.tres"
const DEATHMATCH_RULES_PATH: String = "res://data/balance/match.tres"
const HEN_RULES_PATH: String = "res://data/balance/match_hen.tres"

@export var id: Id = Id.DEATHMATCH
@export var display_name: String = "DEATHMATCH"
## 0 means inherit Balance.round_ticks. A 5:00 deathmatch is not a thing we
## want a designer to do by editing the shared fuse file.
@export var round_ticks: int = 0
## Applied to the arena's crate_permille at generation. 1000 = as written.
@export var crate_scale_permille: int = 1000
## 0 means inherit Balance.crate_cap_permille.
@export var crate_cap_permille: int = 0
## Effective speed while living as the Hen. Unused in deathmatch.
@export var hen_speed_units: int = 8
@export var scoring: Scoring = Scoring.KILLS
## Above the sim. Not fingerprinted.
@export var match_rules_path: String = DEATHMATCH_RULES_PATH

func is_hen() -> bool:
	return id == Id.HEN

func effective_round_ticks(balance: Balance) -> int:
	if round_ticks > 0:
		return round_ticks
	return balance.round_ticks if balance != null else 7200

func effective_crate_permille(def: ArenaDef) -> int:
	var base: int = def.crate_permille if def != null else 700
	return base * crate_scale_permille / 1000

func effective_crate_cap_permille(balance: Balance) -> int:
	if crate_cap_permille > 0:
		return crate_cap_permille
	return balance.crate_cap_permille if balance != null else 450

## Every field the sim reads, and none of the ones above it.
func fingerprint() -> int:
	var h: int = SimHash.start()
	h = SimHash.mix_int(h, int(id))
	h = SimHash.mix_int(h, round_ticks)
	h = SimHash.mix_int(h, crate_scale_permille)
	h = SimHash.mix_int(h, crate_cap_permille)
	h = SimHash.mix_int(h, hen_speed_units)
	h = SimHash.mix_int(h, int(scoring))
	return h

## Code defaults matching data/balance/modes/deathmatch.tres, so a test that
## never touches a file still plays deathmatch.
static func deathmatch() -> GameMode:
	var mode: GameMode = GameMode.new()
	mode.id = Id.DEATHMATCH
	mode.display_name = "DEATHMATCH"
	mode.round_ticks = 0
	mode.crate_scale_permille = 1000
	mode.crate_cap_permille = 0
	mode.hen_speed_units = 8
	mode.scoring = Scoring.KILLS
	mode.match_rules_path = DEATHMATCH_RULES_PATH
	return mode

## Code defaults matching data/balance/modes/hen.tres. The numbers live here so
## a --script test can construct a Hen round without loading the resource; the
## .tres is the designer-facing copy of the same values.
static func hen() -> GameMode:
	var mode: GameMode = GameMode.new()
	mode.id = Id.HEN
	mode.display_name = "HEN GRENADE"
	mode.round_ticks = 18000
	mode.crate_scale_permille = 500
	mode.crate_cap_permille = 250
	mode.hen_speed_units = 8
	mode.scoring = Scoring.HEN_TICKS
	mode.match_rules_path = HEN_RULES_PATH
	return mode
