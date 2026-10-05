package game

// The game's own randomness, xorshift64*: the same numbers on every machine from the
// same seed. The world has one, and each soldier its own.
Rng :: struct {
	state: u64,
}

rng_next :: proc(rng: ^Rng) -> u64 {
	x := rng.state
	if x == 0 {
		x = 0x9E3779B97F4A7C15
	}
	x ~= x >> 12
	x ~= x << 25
	x ~= x >> 27
	rng.state = x
	return x * 0x2545F4914F6CDD1D
}

// Uniform in [0, 1).
rng_float :: proc(rng: ^Rng) -> f32 {
	return f32(rng_next(rng) >> 40) / f32(1 << 24)
}

// Uniform in [0, n); 0 when n is not positive.
rng_below :: proc(rng: ^Rng, n: int) -> int {
	if n <= 0 {
		return 0
	}
	return int(rng_next(rng) % u64(n))
}
