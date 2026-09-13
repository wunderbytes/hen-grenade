class_name Balance
extends Resource
## Every number the game design marks (tune), in the simulation's native units.
## See docs/milestone-1-brief.md §3.1 and docs/technical-design.md §6.
##
## The design document speaks in tiles per second and seconds; the simulation
## speaks in integer units per tick and ticks. This resource is where the
## conversion is made once and written down, so no other file has to do the
## arithmetic (or accidentally use a float).
##
##   units per tick = tiles per second * UNITS_PER_TILE / TICK_HZ
##   ticks          = seconds * TICK_HZ
##
## Tests construct Balance.new() directly and override fields — notably
## round_ticks — so a scoring test does not have to simulate 7200 ticks.

# --- Movement ---------------------------------------------------------------
## 3.5 t/s -> 3.5 * 256 / 60 = 14.93, quantised to 15 (3.516 t/s).
@export var move_speed_units: int = 15
## 6.0 t/s cap from the power-up table.
@export var max_speed_units: int = 26
## One Speed Up. The design says +0.6 t/s, which is 0.6 * 256 / 60 = 2.56 units
## and the simulation has no fractions, so a step is 3 units (0.70 t/s) and four
## of them reach the cap. Same quantisation the base speed took above.
@export var speed_step_units: int = 3
## Corner assist reach: 6 px -> 6 * 256 / 20 = 76.8, quantised to 77.
## This is the parameter a playtest will move; see the M1 brief §5.
@export var corner_assist_units: int = 77

# --- Bombs ------------------------------------------------------------------
## 2.5 s fuse.
@export var bomb_fuse_ticks: int = 150
## Flames persist 0.4 s.
@export var flame_ticks: int = 24
@export var start_blast_radius: int = 1
@export var start_bomb_capacity: int = 1

# --- Power-up caps ----------------------------------------------------------
## From the power-up table in game design §6. A power-up at its cap is still
## consumed (brief §3.1) — a pickup nobody can pick up is a blocked tile that
## looks like a bug.
@export var max_bomb_capacity: int = 8
@export var max_blast_radius: int = 8

# --- Abilities and curses ---------------------------------------------------
## A kicked bomb advances one whole tile this often: 6 ticks is ~10 tiles/s.
## Bombs stay tile-quantised, so everything that indexes them by tile still
## works (brief §4.1).
@export var kick_ticks_per_tile: int = 6
## How far a Toss lobs a bomb, in tiles.
@export var toss_tiles: int = 2
## 8 s of Dud. Long enough to be a real problem, short enough to survive.
@export var curse_ticks: int = 480

# --- Kit loss on death ------------------------------------------------------
## The most important balance dial in the game (game design §6.1), and therefore
## one number. 500 = the stacking upgrades above the starting loadout are halved,
## rounded down; the abilities go regardless.
@export var kit_loss_permille: int = 500
## How far from the body a lost item will look for a free tile. Anything that
## cannot land inside this is lost rather than placed somewhere silly.
@export var scatter_radius: int = 4

# --- Crate regeneration -----------------------------------------------------
## Every 20 s. Set to 0 to switch regeneration off entirely, which is also the
## fallback game design §6.2 names if it plays as interference.
@export var crate_regen_ticks: int = 1200
## Crates per wave, before the cap and the exclusion rules take their cut.
@export var crate_regen_wave: int = 6
## Ceiling on total crates, in permille of the eligible interior (the interior
## minus the lattice pillars — 233 tiles on a 25 x 15 grid, so 450 is 104
## crates). The arena *starts* above this, so regeneration does nothing until the
## round has genuinely thinned out: it is a floor under the supply, not a tide.
@export var crate_cap_permille: int = 450
## A regenerating crate is refused if it would leave a living player able to
## reach fewer free tiles than this. The never-seal-a-player-in guarantee.
@export var min_escape_tiles: int = 3

# --- Round ------------------------------------------------------------------
## 2:00 at 60 Hz. The sole round-ending condition.
@export var round_ticks: int = 7200
## 1.5 s respawn delay.
@export var respawn_ticks: int = 90
## 2 s of spawn protection, cleared early by dropping a bomb.
@export var spawn_protect_ticks: int = 120

## Hash of every field above. A replay stores this so that playing one back
## against retuned balance is a loud, obvious mismatch instead of a desync
## nobody can explain.
func fingerprint() -> int:
	var h: int = SimHash.start()
	h = SimHash.mix_int(h, move_speed_units)
	h = SimHash.mix_int(h, max_speed_units)
	h = SimHash.mix_int(h, speed_step_units)
	h = SimHash.mix_int(h, corner_assist_units)
	h = SimHash.mix_int(h, bomb_fuse_ticks)
	h = SimHash.mix_int(h, flame_ticks)
	h = SimHash.mix_int(h, start_blast_radius)
	h = SimHash.mix_int(h, start_bomb_capacity)
	h = SimHash.mix_int(h, max_bomb_capacity)
	h = SimHash.mix_int(h, max_blast_radius)
	h = SimHash.mix_int(h, kick_ticks_per_tile)
	h = SimHash.mix_int(h, toss_tiles)
	h = SimHash.mix_int(h, curse_ticks)
	h = SimHash.mix_int(h, kit_loss_permille)
	h = SimHash.mix_int(h, scatter_radius)
	h = SimHash.mix_int(h, crate_regen_ticks)
	h = SimHash.mix_int(h, crate_regen_wave)
	h = SimHash.mix_int(h, crate_cap_permille)
	h = SimHash.mix_int(h, min_escape_tiles)
	h = SimHash.mix_int(h, round_ticks)
	h = SimHash.mix_int(h, respawn_ticks)
	h = SimHash.mix_int(h, spawn_protect_ticks)
	return h
