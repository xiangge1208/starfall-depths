class_name TestSmoke
extends GdUnitTestSuite

func test_autoloads_exist() -> void:
	assert_object(GameDB).is_not_null()
	assert_object(RngSvc).is_not_null()
	assert_object(EventBus).is_not_null()
	assert_object(Fx).is_not_null()

func test_input_actions_registered() -> void:
	for a in ["move_left", "fire", "roll", "switch_weapon"]:
		assert_bool(InputMap.has_action(a)).is_true()
