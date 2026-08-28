class_name Elements
enum Id { NONE, FIRE, ICE, POISON, SHOCK }
const NAMES := {Id.NONE: "none", Id.FIRE: "fire", Id.ICE: "ice", Id.POISON: "poison", Id.SHOCK: "shock"}

static func from_name(s: String) -> int:
	for k: int in NAMES:
		if NAMES[k] == s:
			return k
	return Id.NONE
