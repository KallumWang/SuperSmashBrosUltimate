class_name Emotes
extends RefCounted
## The emote wheel's contents and the taunt pop-up lines.
##
## SLOTS are the 8 wedges of the wheel, clockwise from the top. They are
## BLANK for now (an empty Dictionary = nothing happens when you pick it).
## To fill one in, give it a "text" (shown in the pop-up bubble over the
## player's stock) and, later, an "icon" (a texture path for your reference
## art - the wheel already draws it if the file exists):
##     {"text": "GG!", "icon": "res://emotes/gg.png"}
## The online game sends only the text, so everyone sees the same bubble.

const SLOTS: Array[Dictionary] = [
	{}, {}, {}, {},
	{}, {}, {}, {},
]

# One of these pops up (with a dance) every time you taunt, Mario Party style.
const TAUNT_LINES := ["WOOO!", "YEAH!", "HA HA!", "COME ON!", "TOO EASY!", "LET'S GO!"]

static func taunt_line() -> String:
	return TAUNT_LINES[randi() % TAUNT_LINES.size()]

static func is_filled(slot: int) -> bool:
	return slot >= 0 and slot < SLOTS.size() and str(SLOTS[slot].get("text", "")) != ""
