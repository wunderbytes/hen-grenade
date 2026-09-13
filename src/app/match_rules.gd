class_name MatchRules
extends Resource
## Best-of-3 and the beats around it, as data. See docs/milestone-3-brief.md §7.
##
## **Deliberately not part of Balance.** These numbers are read above the
## simulation and the simulation never sees them, so they must not be in the
## replay's rules fingerprint — changing how long the scoreboard sits should not
## invalidate every committed replay. Keeping them in Balance would mean fields
## deliberately excluded from that resource's own fingerprint, which is a trap
## for whoever adds the next one.

## Round wins that take the match. Best of 3 means first to 2 (game design §5.3).
@export var round_wins_to_take_match: int = 2

## Hard ceiling on rounds, so a pathological run of draws cannot play forever.
## A level match plays a decider (game design §5.3) and deciders are rounds, so
## without this there is no upper bound at all.
@export var max_rounds: int = 7

## How long the scoreboard sits before the next round starts itself. 4 s, and
## skippable — four people on a sofa should not have to agree to press a button
## between rounds (game design §3).
@export var scoreboard_ticks: int = 240
