extends SceneTree
func _initialize() -> void:
	_go.call_deferred()
func _go() -> void:
	var net = root.get_node_or_null("Net")
	var addr := OS.get_environment("PROBE_ADDR")
	net.go_online(addr, "probe")
	var res = []
	net.account_result.connect(func(a, b = null, c = null): res.append([a, b, c]))
	for i in 300:
		await process_frame
		if net.accounts_on: break
	print("PROBE accounts_on=", net.accounts_on)
	net.account("sign_up", {"username": "probe%d" % (randi() % 100000), "password": "longpassword1"})
	for i in 300:
		await process_frame
		if not res.is_empty(): break
	print("PROBE result=", str(res).left(200), " signed_in=", net.signed_in())
	if net.signed_in():
		var d: Dictionary = net.online_profile.duplicate(true)
		net.save_online(d)
		for i in 120: await process_frame
		net.set_queued(true)
		for i in 300: await process_frame
	net.go_offline()
	quit()
