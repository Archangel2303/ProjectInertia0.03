extends RefCounted
## Manages the score value and decay accumulator. Configuration (thresholds, costs)
## lives on the GameManager controller and is passed as parameters.

var score: int = 0
var _decay_accumulator: float = 0.0


func reset(starting_score: int) -> void:
	score = max(0, starting_score)
	_decay_accumulator = 0.0


func add(amount: int) -> int:
	score = max(0, score + amount)
	return score


func spend(amount: int) -> int:
	if amount <= 0:
		return score
	return add(-amount)


func apply_decay(delta: float, rate: float) -> int:
	if score <= 0:
		_decay_accumulator = 0.0
		return score
	if rate <= 0.0:
		return score

	_decay_accumulator += rate * maxf(delta, 0.0)
	var decay_whole := int(floor(_decay_accumulator))
	if decay_whole <= 0:
		return score

	_decay_accumulator -= float(decay_whole)
	return spend(decay_whole)


static func get_kill_score(hit_type: String, head: int, torso: int, limb: int, extremity: int) -> int:
	match hit_type:
		"head":
			return head
		"torso":
			return torso
		"arm", "leg":
			return limb
		"hand", "foot":
			return extremity
		_:
			return torso


static func get_star_count(value: int, s1: int, s2: int, s3: int) -> int:
	var stars := 0
	if value >= s1:
		stars = 1
	if value >= s2:
		stars = 2
	if value >= s3:
		stars = 3
	return stars
