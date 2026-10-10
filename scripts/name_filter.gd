class_name NameFilter
extends RefCounted
## Cleans player names before other players see them (App Store / Google Play user-content rules, see
## docs/STORE_RULES.md). The server runs every name through clean(), so a client can't skip it.
## Only plain letters, digits, spaces and _ - . are kept, and a name with a rude or hateful word in it
## (also spelled with numbers/symbols, or with spaces between letters) is replaced by the fallback.
## Matching is on parts of words, so the list only holds words that rarely appear inside innocent ones.

const MAX_LENGTH := 16
const ALLOWED := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-."
## Number/symbol look-alikes, read as letters before matching.
const LOOKALIKES := {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b", "9": "g", "@": "a", "$": "s"}
const BLOCKED: PackedStringArray = [
	"fuck", "fuk", "fck", "shit", "cunt", "bitch", "whore", "slut", "dick", "pussy", "penis",
	"vagina", "porn", "sex", "rapist", "nigg", "niga", "fag", "retard", "tranny", "kike",
	"chink", "gook", "wetback", "nazi", "hitler", "heil", "kkk", "jihad", "pedophile", "paedo", "molest",
	"wank", "jizz", "asshole", "bastard", "twat", "nude", "naked", "killyourself",
]


## The name as other players will see it, or `fallback` if nothing usable is left or it's not allowed.
static func clean(player_name: String, fallback: String) -> String:
	var kept := ""
	for c in player_name:
		kept += c if ALLOWED.contains(c) else ""
	while kept.contains("  "):
		kept = kept.replace("  ", " ")
	kept = kept.strip_edges().left(MAX_LENGTH).strip_edges()
	if kept == "" or is_blocked(kept):
		return fallback
	return kept


## True if the name has a blocked word in it, however it's spaced or spelled.
static func is_blocked(player_name: String) -> bool:
	var squashed := ""
	for c in player_name.to_lower():
		if LOOKALIKES.has(c):
			squashed += LOOKALIKES[c]
		elif c >= "a" and c <= "z":
			squashed += c
	for word in BLOCKED:
		if squashed.contains(word):
			return true
	return false
