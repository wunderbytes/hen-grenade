class_name SimHash
## FNV-1a, 32-bit, hand-rolled. Used for MatchState.fingerprint() and
## Balance.fingerprint(). See docs/milestone-1-brief.md §8.
##
## Hand-rolled for the same reason SimRng is: a golden replay test is only
## meaningful if the hash is pinned to our source. An engine-provided hash could
## change its algorithm in a point release and turn every golden file into a
## false failure.
##
## 32-bit is plenty: this guards against accidental non-determinism, not against
## an adversary looking for collisions.

const OFFSET_BASIS: int = 0x811C9DC5
const PRIME: int = 0x01000193
const MASK: int = 0xFFFFFFFF

static func start() -> int:
	return OFFSET_BASIS

## Mixes the low 8 bits of `b`. The multiply cannot overflow int64:
## 0xFFFFFFFF * 0x01000193 is about 7.2e16, well inside the 9.2e18 range.
static func mix_byte(h: int, b: int) -> int:
	var acc: int = h ^ (b & 0xFF)
	return (acc * PRIME) & MASK

## Mixes a 32-bit little-endian view of `v`. Negative values are mixed as their
## two's-complement bit pattern, so scores of -1 hash stably.
static func mix_int(h: int, v: int) -> int:
	var u: int = v & MASK
	var acc: int = mix_byte(h, u)
	acc = mix_byte(acc, u >> 8)
	acc = mix_byte(acc, u >> 16)
	acc = mix_byte(acc, u >> 24)
	return acc

static func mix_bool(h: int, v: bool) -> int:
	return mix_byte(h, 1 if v else 0)

static func mix_vec(h: int, v: Vector2i) -> int:
	return mix_int(mix_int(h, v.x), v.y)

static func mix_bytes(h: int, bytes: PackedByteArray) -> int:
	var acc: int = h
	for i in range(bytes.size()):
		acc = mix_byte(acc, bytes[i])
	return acc

static func mix_ints(h: int, values: PackedInt32Array) -> int:
	var acc: int = h
	for i in range(values.size()):
		acc = mix_int(acc, values[i])
	return acc

static func to_hex(h: int) -> String:
	return "%08x" % (h & MASK)
