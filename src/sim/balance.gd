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
## 6.0 t/s cap from the power-up table. Unused until M3.
@export var max_speed_units: int = 26
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
	h = SimHash.mix_int(h, corner_assist_units)
	h = SimHash.mix_int(h, bomb_fuse_ticks)
	h = SimHash.mix_int(h, flame_ticks)
	h = SimHash.mix_int(h, start_blast_radius)
	h = SimHash.mix_int(h, start_bomb_capacity)
	h = SimHash.mix_int(h, round_ticks)
	h = SimHash.mix_int(h, respawn_ticks)
	h = SimHash.mix_int(h, spawn_protect_ticks)
	return h
