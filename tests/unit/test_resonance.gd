class_name TestResonance
extends GdUnitTestSuite

func test_four_pairs() -> void:
	assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.ICE)).is_equal(Resonance.R.SHATTER)
	assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.POISON)).is_equal(Resonance.R.BLAZE)
	assert_int(Resonance.resolve(Elements.Id.ICE, Elements.Id.SHOCK)).is_equal(Resonance.R.SUPERCONDUCT)
	assert_int(Resonance.resolve(Elements.Id.POISON, Elements.Id.SHOCK)).is_equal(Resonance.R.ELECTROLYSIS)

func test_symmetric_and_negative() -> void:
	assert_int(Resonance.resolve(Elements.Id.ICE, Elements.Id.FIRE)).is_equal(Resonance.R.SHATTER)
	assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.FIRE)).is_equal(Resonance.R.NONE)
	assert_int(Resonance.resolve(Elements.Id.FIRE, Elements.Id.SHOCK)).is_equal(Resonance.R.NONE)
