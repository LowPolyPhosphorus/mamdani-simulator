class_name GameEvent
extends Resource

@export var title: String = ""
@export_multiline var description: String = ""
@export var choice_a: EventChoice
@export var choice_b: EventChoice
@export_enum("Any", "Bronx", "Brooklyn", "Manhattan", "Queens", "Staten Island") var borough: String = "Any"
