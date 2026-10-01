class_name HashNoise
extends RefCounted
## Deterministic integer noise (bible §8.4). Everything here is integer math,
## so results are bit-identical on every platform and Godot version — worlds
## regenerate exactly from their seed, chunk by chunk, in any order.
##
## Values are 16-bit: 0..ONE-1 (think "0.0 to just under 1.0").

const ONE := 65536
const _MASK_32 := 0xFFFFFFFF
const _T_ONE := 1024 # fixed-point 1.0 for interpolation weights


## 32-bit hash of a lattice point. Any ints (including negatives) are fine.
static func hash2(x: int, y: int, salt: int) -> int:
	var h := ((x * 0x27D4EB2D) ^ (y * 0x165667B1) ^ salt) & _MASK_32
	h = ((h ^ (h >> 15)) * 0x2C1B3C6D) & _MASK_32
	h = ((h ^ (h >> 12)) * 0x297A2D39) & _MASK_32
	return h ^ (h >> 15)


## Uniform value 0..ONE-1 for a single tile (no smoothing) — per-tile decisions.
static func tile_value(x: int, y: int, salt: int) -> int:
	return hash2(x, y, salt) & 0xFFFF


## Smooth value noise 0..ONE-1. `period` is the lattice spacing in tiles (>= 1).
static func value2(x: int, y: int, period: int, salt: int) -> int:
	if period <= 1:
		return tile_value(x, y, salt)
	var cx := (x - posmod(x, period)) / period
	var cy := (y - posmod(y, period)) / period
	var tx := _smooth(posmod(x, period) * _T_ONE / period)
	var ty := _smooth(posmod(y, period) * _T_ONE / period)
	var v00 := hash2(cx, cy, salt) & 0xFFFF
	var v10 := hash2(cx + 1, cy, salt) & 0xFFFF
	var v01 := hash2(cx, cy + 1, salt) & 0xFFFF
	var v11 := hash2(cx + 1, cy + 1, salt) & 0xFFFF
	var top := v00 + (v10 - v00) * tx / _T_ONE
	var bottom := v01 + (v11 - v01) * tx / _T_ONE
	return top + (bottom - top) * ty / _T_ONE


## Fractal noise 0..ONE-1: octaves at period, period/2, period/4, ... with
## halving weights.
static func fbm2(x: int, y: int, period: int, octaves: int, salt: int) -> int:
	var total := 0
	var weight_sum := 0
	var weight := 1 << maxi(octaves - 1, 0)
	var p := period
	for octave in octaves:
		total += value2(x, y, maxi(p, 1), salt + octave * 0x9E3779B1) * weight
		weight_sum += weight
		weight >>= 1
		p >>= 1
		if weight == 0:
			break
	return total / weight_sum if weight_sum > 0 else 0


## Integer smoothstep on 0.._T_ONE.
static func _smooth(t: int) -> int:
	return t * t * (3 * _T_ONE - 2 * t) / (_T_ONE * _T_ONE)


## Integer smoothstep of `value` between edge0 and edge1, result 0..1024.
static func smoothstep_fixed(edge0: int, edge1: int, value: int) -> int:
	if edge1 <= edge0:
		return _T_ONE if value >= edge1 else 0
	var t := clampi((value - edge0) * _T_ONE / (edge1 - edge0), 0, _T_ONE)
	return _smooth(t)
