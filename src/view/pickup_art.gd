class_name PickupArt
## Shared programmer-art for pickups: hue plus inner-square size.
## EntityView and the power-up legend both draw from here so they cannot drift.

## Indexed by Powerup.Kind (index 0 is unused). No two kinds share both colour
## and inner size, which is the whole distinguishing vocabulary at 20 px.
const COLORS: Array[Color] = [
	Color8(0, 0, 0),          # NONE
	Color8(250, 170, 60),     # BOMB     orange
	Color8(240, 90, 90),      # BLAST    red
	Color8(110, 220, 250),    # SPEED    cyan
	Color8(140, 230, 130),    # KICK     green
	Color8(200, 150, 250),    # TOSS     violet
	Color8(250, 240, 110),    # REMOTE   yellow
	Color8(255, 255, 255),    # JACKPOT  white
	Color8(120, 100, 110),    # DUD      grey
]
const INNER: Array[float] = [0.0, 2.0, 4.0, 3.0, 2.0, 4.0, 3.0, 5.0, 1.0]
const HALF: float = 6.0
const SHELL: Color = Color8(18, 18, 22)

## The eight kinds that actually drop, in table order.
const KINDS: Array[int] = [
	Powerup.Kind.BOMB,
	Powerup.Kind.BLAST,
	Powerup.Kind.SPEED,
	Powerup.Kind.KICK,
	Powerup.Kind.TOSS,
	Powerup.Kind.REMOTE,
	Powerup.Kind.JACKPOT,
	Powerup.Kind.DUD,
]
