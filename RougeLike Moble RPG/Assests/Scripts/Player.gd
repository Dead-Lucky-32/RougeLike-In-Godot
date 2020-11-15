extends Sprite

signal attemptMovement(Direction)

func _on_Up_pressed():
	emit_signal("attemptMovement", "Up")

func _on_Left_pressed():
	emit_signal("attemptMovement", "Left")

func _on_Down_pressed():
	emit_signal("attemptMovement", "Down")

func _on_Right_pressed():
	emit_signal("attemptMovement", "Right")

func _on_BaseGame_setPlayerPosition(x, y):
	self.position.x = x
	self.position.y = y
