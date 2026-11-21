extends SceneTree
## Live server pace (perf thread 2026-11-21): joins the lobby (never a raid) and times the queue updates the server
## sends twice a second from its main loop. Late ones = the server's frame ran long (or the network held them).
## With `raid` it then starts a Frontlines raid alone (no body sent, so nothing hunts it) and times the 20-a-second
## state updates instead: the pace players see in a raid.
##   godot --headless -s tools/live_server_probe.gd -- <wss address> [seconds=120] [ca bundle] [raid]
var _times: Array[float] = []
var _start := 0.0
var _seconds := 120.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var address: String = args[0]
	if args.size() > 1: _seconds = float(args[1])
	var net: Node = root.get_node("Net")
	var tls: TLSOptions = null
	if args.size() > 2:
		var cert := X509Certificate.new()
		cert.load(args[2])
		tls = TLSOptions.client(cert)
	if OS.has_environment("NET_VERSION"):
		ProjectSettings.set_setting("application/config/net_version", int(OS.get_environment("NET_VERSION")))
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(address, tls)
	print("connect: ", err)
	net.multiplayer.multiplayer_peer = peer
	net.multiplayer.connected_to_server.connect(net._on_connected.bind("PerfProbe%d" % (randi() % 90 + 10)), CONNECT_ONE_SHOT)
	net.connect_failed.connect(func(reason: String) -> void: print("REFUSED: ", reason))
	net.notice.connect(func(text: String) -> void: print("NOTICE: ", text))
	net.queue_changed.connect(func() -> void: _times.append(Time.get_ticks_usec() / 1000.0))
	_start = Time.get_ticks_msec() / 1000.0
	net.multiplayer.server_disconnected.connect(func() -> void:
		print("DISCONNECTED by the server at %.1f s" % (Time.get_ticks_msec() / 1000.0 - _start))
		_seconds = 0.0)
	var raid := args.size() > 3 and args[3] == "raid"
	var asked := false
	var last_msec := -1
	var threshold := 600.0
	while Time.get_ticks_msec() / 1000.0 - _start < _seconds:
		await process_frame
		if raid and not asked and _times.size() >= 2:
			asked = true
			net.set_map(0)
			net.start_now()
		if raid and net.in_raid:
			if _times.size() > 0 and threshold == 600.0:
				_times.clear()
				threshold = 100.0
			if net.states_msec != last_msec:
				last_msec = net.states_msec
				var t := Time.get_ticks_usec() / 1000.0
				if _times.size() > 0 and t - _times[-1] > 150.0:
					print("  gap %.0f ms at %.1f s" % [t - _times[-1], t / 1000.0 - _start])
				_times.append(t)
	if raid:
		print("raid left at %.1f s, connected=%s" % [Time.get_ticks_msec() / 1000.0 - _start, peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED])
		net.leave_raid()
		for i in 30:
			await process_frame
	peer.close()
	var gaps: Array[float] = []
	for i in range(1, _times.size()):
		gaps.append(_times[i] - _times[i - 1])
	gaps.sort()
	var n := gaps.size()
	if n == 0:
		print("LIVE: no queue updates came (state %d)" % peer.get_connection_status())
		quit()
		return
	var late := gaps.filter(func(g: float) -> bool: return g > threshold).size()
	var big := gaps.filter(func(g: float) -> bool: return g > 250.0).size()
	print("LIVE: %d updates, gap ms p50=%.0f p90=%.0f p99=%.0f max=%.0f min=%.0f, late(>%.0fms)=%d, frozen(>250ms)=%d" % [n, gaps[n / 2], gaps[n * 9 / 10], gaps[n * 99 / 100], gaps[n - 1], gaps[0], threshold, late, big])
	quit()
