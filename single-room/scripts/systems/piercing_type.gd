class_name PiercingType
extends Resource
## Defines the physical and visual properties of a piercing/jewelry piece.
## Used by PiercingAttachment to configure the joint and body.

@export var piercing_name: String = ""

@export_group("Geometry")
## Shape of the piercing collision body. Determines physics behavior.
@export_enum("Ring", "Barbell", "Stud", "Hook", "Chain") var shape_type: String = "Ring"
## Approximate size of the piercing (meters). Affects collision shape.
@export_range(0.002, 0.05) var size: float = 0.01
## Mass of the piercing (kg). Heavier = more pull on skin.
@export_range(0.001, 0.1) var mass: float = 0.005

@export_group("Spring / Skin Pull")
## How stiff the attachment to skin is. Low = stretchy/dangly, High = tight.
@export_range(0.1, 50.0) var attachment_stiffness: float = 8.0
## Damping of the spring. Prevents endless oscillation.
@export_range(0.0, 5.0) var attachment_damping: float = 1.5
## Maximum stretch distance (meters) before the piercing "tears free" (or caps).
@export_range(0.005, 0.15) var max_stretch: float = 0.04
## Whether the piercing can be torn free if pulled beyond max_stretch.
@export var can_tear: bool = false

@export_group("Appearance")
@export var color: Color = Color(0.8, 0.8, 0.8, 1.0)
@export_range(0.0, 1.0) var metallic: float = 0.9
@export_range(0.0, 1.0) var roughness: float = 0.15


static func create(p_name: String, p_shape: String, overrides: Dictionary = {}) -> PiercingType:
	var pt: PiercingType = PiercingType.new()
	pt.piercing_name = p_name
	pt.shape_type = p_shape
	for key: String in overrides:
		if key in pt:
			pt.set(key, overrides[key])
		else:
			push_warning("[PiercingType] Unknown property '%s' in overrides for '%s'" % [key, p_name])
	return pt
