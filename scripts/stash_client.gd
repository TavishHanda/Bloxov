class_name StashClient
extends Node
## The game server's line to the Stash API (Stash update, 0.31; server/ in the repo): one JSON POST per call over
## 127.0.0.1 with the service token. Only the server uses it; players never reach the API. `request` is a coroutine:
## `var reply: Dictionary = await api.request("login", {...})`. A failed call comes back as {"error": "..."}; a good
## one has no "error". FakeStash (below) stands in for it in the smoke test, without a database.
##
## Set on the host by server/start.sh: STASH_API_URL (http://127.0.0.1:9091) and STASH_API_TOKEN.

var url := ""
var token := ""


## The API from the host's settings, or null when there is none (no database: PvP accounts are off).
static func from_environment() -> StashClient:
	var api_url := OS.get_environment("STASH_API_URL").strip_edges()
	var api_token := OS.get_environment("STASH_API_TOKEN").strip_edges()
	if api_url == "" or api_token == "":
		return null
	var client := StashClient.new()
	client.name = "StashAPI"
	client.url = api_url.trim_suffix("/")
	client.token = api_token
	return client


func request(action: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var err := http.request("%s/v1/%s" % [url, action],
		PackedStringArray(["content-type: application/json", "x-service-token: " + token]),
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"error": "unavailable"}
	var result: Array = await http.request_completed
	http.queue_free()
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if result[0] != HTTPRequest.RESULT_SUCCESS or not parsed is Dictionary:
		return {"error": "unavailable"}
	return parsed
