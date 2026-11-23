extends SceneTree
# Pictures of the Riptide gray box (map 2) from fixed spots, plus a check that every player spawn stands on
# something.
# xvfb-run -a godot --rendering-driver opengl3 --resolution 1280x720 -s tools/riptide_view.gd -- out=/tmp/rip
# Writes <out>-<view>.png.

const VIEWS := {
	"cannery-out": [Vector3(-126, 4.5, -115), Vector3(-116, 9, -130)],
	"cannery-in": [Vector3(-97.5, 5.5, -163), Vector3(-130, 4, -140)],
	"cannery-deck": [Vector3(-131, 8.6, -133), Vector3(-140, 7, -160)],
	"cannery-under": [Vector3(-136, 4.2, -154), Vector3(-141, 3.5, -160)],
	"fuel-depot": [Vector3(-56, 8, -128), Vector3(-82, 5, -145)],
	"lighthouse": [Vector3(-44, 5, -140), Vector3(-62, 9, -158)],
	"s_passe": [Vector3(63, -2.3, -20), Vector3(62, -2.6, -60)],
	"s_passw2": [Vector3(33, -2.3, -36), Vector3(34, -2.6, -80)],
	"s_pier": [Vector3(33.5, -2.3, 32), Vector3(34.4, -0.5, 10)],
	"s_bramp": [Vector3(64, -2.3, -60), Vector3(61.7, -0.3, -80)],
	"s_passw": [Vector3(33, -2.3, -50), Vector3(33, -2.6, -10)],
	"s_hold": [Vector3(48, -1.8, -40), Vector3(46, -3, -10)],
	"s_eng": [Vector3(48, -6.2, 36), Vector3(50, -6.8, 70)],
	"s_pump": [Vector3(48, -6.2, -50), Vector3(46, -6.8, -80)],
	"s_stern": [Vector3(48, -2, 88), Vector3(48, -2.5, 106)],
	"s_fore": [Vector3(36.5, 5.8, -76), Vector3(33, 6.8, -90)],
	"s_drill": [Vector3(38, 6.5, -42), Vector3(33, 7.5, -20)],
	"s_lab": [Vector3(53.5, -16.4, -40), Vector3(53.5, -13.5, -26)],
	"sbox_in": [Vector3(-140, 4.3, 82), Vector3(-142, 3.3, 72)],
	"barge_in": [Vector3(-55, 4.3, 113), Vector3(-45, 3.3, 120)],
	"workshop_in": [Vector3(-87, 4.3, 120), Vector3(-101, 3.3, 107)],
	"weigh_in": [Vector3(-141, 4.3, -36), Vector3(-151, 3.3, -41)],
	"bow": [Vector3(48, 11, -82), Vector3(48, 8, -100)],
	"loader": [Vector3(4, 8, 30), Vector3(25, 10, 49)],
	"tug": [Vector3(90, 8, 30), Vector3(72, 1, 52)],
	"pilot": [Vector3(52, 6, -108), Vector3(64, 1, -122)],
	"railside": [Vector3(-132, 5, 18), Vector3(-150, 3, 50)],
	"barge": [Vector3(-34, 4.5, 102), Vector3(-51, 3, 116)],
	"weigh": [Vector3(-128, 4.5, -54), Vector3(-145, 3, -39)],
	"hut": [Vector3(-14, 6, -108), Vector3(3, 2, -127)],
	"roofs2": [Vector3(-60, 14, 120), Vector3(-90, 4, 140)],
	"grainstore": [Vector3(-64, 7, 106), Vector3(-92, 5, 90)],
	"silos": [Vector3(-64, 12, 14), Vector3(-92, 18, 46)],
	"tshed3": [Vector3(-82, 6, 98), Vector3(-53, 5, 80)],
	"grain_in": [Vector3(-75, 4.5, 89), Vector3(-104, 3, 70)],
	"cannery_s": [Vector3(-96, 13, -114), Vector3(-122, 5, -132)],
	"roofs": [Vector3(-124, 16, 102), Vector3(-92, 8, 76)],
	"lh-top": [Vector3(-62, 32.1, -157), Vector3(-100, 4, -100)],
	"lh-balcony": [Vector3(-58.4, 32.1, -155.0), Vector3(-30, 10, -120)],
	"lh-far": [Vector3(-40, 6, -120), Vector3(-62, 18, -158)],
	"lh-lamp": [Vector3(-48, 32, -144), Vector3(-62, 30, -158)],
	"north-street": [Vector3(-128, 4.3, -110), Vector3(-60, 4, -122)],
	"north-shed": [Vector3(-112.5, 4.2, -114), Vector3(-104, 3.5, -121)],
	"north-high": [Vector3(-30, 40, -100), Vector3(-110, 2, -150)],
	"t0-nw": [Vector3(-122.5, 4.2, -21.4), Vector3(-110, 3.1, -29)],
	"t0-ne": [Vector3(-106.6, 4.2, -21.4), Vector3(-94, 3.1, -29)],
	"t0-sw": [Vector3(-123.2, 4.2, -12.5), Vector3(-105, 3.1, -12.5)],
	"t0-se": [Vector3(-103.2, 4.2, -12.5), Vector3(-93, 3.1, -12.5)],
	"t0-hall": [Vector3(-93, 4.2, -17.7), Vector3(-123, 3.9, -17.7)],
	"t1-nw": [Vector3(-122.5, 7.7, -21.4), Vector3(-110, 6.6, -29)],
	"t1-ne": [Vector3(-106.6, 7.7, -21.4), Vector3(-94, 6.6, -29)],
	"t1-sw": [Vector3(-123.2, 7.7, -12.5), Vector3(-105, 6.6, -12.5)],
	"t1-se": [Vector3(-103.2, 7.7, -12.5), Vector3(-93, 6.6, -12.5)],
	"t1-hall": [Vector3(-93, 7.7, -17.7), Vector3(-123, 7.4, -17.7)],
	"t2-nw": [Vector3(-122.5, 11.2, -21.4), Vector3(-110, 10.1, -29)],
	"t2-ne": [Vector3(-106.6, 11.2, -21.4), Vector3(-94, 10.1, -29)],
	"t2-sw": [Vector3(-123.2, 11.2, -12.5), Vector3(-105, 10.1, -12.5)],
	"t2-se": [Vector3(-103.2, 11.2, -12.5), Vector3(-93, 10.1, -12.5)],
	"t2-hall": [Vector3(-93, 11.2, -17.7), Vector3(-123, 10.9, -17.7)],
	"t3-nw": [Vector3(-122.5, 14.7, -21.4), Vector3(-110, 13.6, -29)],
	"t3-ne": [Vector3(-106.6, 14.7, -21.4), Vector3(-94, 13.6, -29)],
	"t3-sw": [Vector3(-123.2, 14.7, -12.5), Vector3(-105, 13.6, -12.5)],
	"t3-se": [Vector3(-103.2, 14.7, -12.5), Vector3(-93, 13.6, -12.5)],
	"t3-hall": [Vector3(-93, 14.7, -17.7), Vector3(-123, 14.4, -17.7)],
	"t4-nw": [Vector3(-122.5, 18.2, -21.4), Vector3(-110, 17.1, -29)],
	"t4-ne": [Vector3(-106.6, 18.2, -21.4), Vector3(-94, 17.1, -29)],
	"t4-sw": [Vector3(-123.2, 18.2, -12.5), Vector3(-105, 17.1, -12.5)],
	"t4-se": [Vector3(-103.2, 18.2, -12.5), Vector3(-93, 17.1, -12.5)],
	"t4-hall": [Vector3(-93, 18.2, -17.7), Vector3(-123, 17.9, -17.7)],
	"t5-nw": [Vector3(-122.5, 21.7, -21.4), Vector3(-110, 20.6, -29)],
	"t5-ne": [Vector3(-106.6, 21.7, -21.4), Vector3(-94, 20.6, -29)],
	"t5-sw": [Vector3(-123.2, 21.7, -12.5), Vector3(-105, 20.6, -12.5)],
	"t5-se": [Vector3(-103.2, 21.7, -12.5), Vector3(-93, 20.6, -12.5)],
	"t5-hall": [Vector3(-93, 21.7, -17.7), Vector3(-123, 21.4, -17.7)],
	"tower-roof": [Vector3(-100, 25.3, -12), Vector3(-126, 25.5, -28)],
	"customs-ladder": [Vector3(-44, 5, 26), Vector3(-51, 8, 16)],
	"customs-out": [Vector3(-36, 5, 6), Vector3(-62, 6, 0)],
	"bay-wall": [Vector3(-150, 4.2, 4), Vector3(-138, 3.5, -10)],
	"truck-1": [Vector3(-148, 6, 12), Vector3(-138, 4, 2)],
	"plaza-high": [Vector3(-30, 45, 45), Vector3(-100, 5, -15)],
	"plaza-tower": [Vector3(-108, 4.2, 6), Vector3(-108, 14, -20)],
	"tower-office": [Vector3(-121, 7.7, -27), Vector3(-96, 7, -13)],
	"tower-ground": [Vector3(-121, 4.2, -12), Vector3(-96, 3.5, -27)],
	"customs-hall": [Vector3(-73, 4.2, -11), Vector3(-52, 4.5, 12)],
	"canteen-in": [Vector3(-122, 4.2, 10), Vector3(-104, 3.5, 22)],
	"garage-in": [Vector3(-94, 4.2, 14), Vector3(-82, 3, 28)],
	"gatehouse": [Vector3(-160, 4.2, -2), Vector3(-170, 3.5, -9)],
	"mid": [Vector3(-12, 22, 60), Vector3(-34, 2, 100)],
	"stern": [Vector3(46.5, 3.2, 121), Vector3(48, 0.8, 106)],
	"aft-top": [Vector3(48, 45, 75), Vector3(48, 4, 40)],
	"overview": [Vector3(-215, 150, 175), Vector3(-30, -10, 0)],
	"overview-ship": [Vector3(130, 90, -150), Vector3(10, 0, 20)],
	"road": [Vector3(-160, 4.2, -2), Vector3(-60, 4, 0)],
	"terminal": [Vector3(-136, 4.2, -99.4), Vector3(-60, 4, -99.4)],
	"boat-deck": [Vector3(76, 11, 106), Vector3(66, 7, 91)],
	"boat-in": [Vector3(62.6, 9.2, 85.2), Vector3(67, 7.5, 96)],
	"bow-cab": [Vector3(62.3, 4.3, -122.3), Vector3(66.9, 3.4, -119)],
	"impound": [Vector3(-99.5, 7.8, -21.3), Vector3(-94.5, 7.0, -25)],
	"impound-open": [Vector3(-98.5, 8.2, -20.8), Vector3(-95.0, 6.6, -25.5)],
	"stair-gap": [Vector3(58.1, 9.3, 77.8), Vector3(60.1, 4.0, 88.0)],
	"stair-door": [Vector3(51.0, 5.6, 79.5), Vector3(55.0, 4.0, 77.5)],
	"impound-in": [Vector3(-96.6, 7.9, -25.6), Vector3(-93, 6.3, -29.5)],
	"clinic-out": [Vector3(-101, 4.4, -127.0), Vector3(-108, 4.4, -122)],
	"clinic-south": [Vector3(-118, 4.4, -106.0), Vector3(-112, 4.4, -112)],
	"clinic-wait": [Vector3(-115.3, 4.4, -112.8), Vector3(-104, 3.0, -120)],
	"clinic-bay": [Vector3(-104.4, 4.2, -118.2), Vector3(-100.4, 3.0, -121)],
	"yard-open": [Vector3(-128.5, 4.2, -97.0), Vector3(-122, 3.5, -100.3)],
	"yard-in": [Vector3(-126.5, 4.0, -100.3), Vector3(-116, 3.8, -100.3)],
	"yard-high": [Vector3(-130, 14, -112), Vector3(-110, 2, -90)],
	"yard-a": [Vector3(-131, 4.2, -101.5), Vector3(-118, 3.2, -101.0)],
	"yard-b": [Vector3(-100, 4.2, -86.5), Vector3(-112, 3.2, -87.5)],
	"yard-c": [Vector3(-112, 4.2, -57.0), Vector3(-126, 3.0, -55.6)],
	"yard-top": [Vector3(-125, 18, -112), Vector3(-105, 2, -80)],
	"yard-s0": [Vector3(-112, 5.5, -99.0), Vector3(-126, 2.0, -100.8)],
	"yard-s5": [Vector3(-114, 5.5, -57.8), Vector3(-128, 2.0, -56.0)],
	"yard-s1": [Vector3(-98, 5.5, -99.6), Vector3(-84, 2.0, -98.0)],
	"yard-s3": [Vector3(-136, 5.5, -71.6), Vector3(-121, 2.0, -70.0)],
	"yard-d": [Vector3(-112, 4.2, -73.0), Vector3(-124, 3.0, -69.6)],
	"yard-e": [Vector3(-84, 4.2, -55.5), Vector3(-94, 3.0, -58.5)],
	"apron": [Vector3(-36, 4.2, -66), Vector3(-36, 4, 60)],
	"plaza": [Vector3(-66, 4.2, 30), Vector3(-108, 14, -20)],
	"gallery": [Vector3(-34, 15.6, 43.5), Vector3(20, 15.6, 43.5)],
	"from-quay": [Vector3(-34, 4.2, 30), Vector3(48, 8, 0)],
	"mole": [Vector3(-26, 4.1, -121), Vector3(40, 3, -116)],
	"barges": [Vector3(-26, 2.8, 124.5), Vector3(50, 2, 116)],
	"fore-deck": [Vector3(39, 5.6, -87), Vector3(50, 6, 0)],
	"drill-floor": [Vector3(33, 13.6, -12.5), Vector3(62, 13, 12)],
	"aft-deck": [Vector3(62, 5.6, 70), Vector3(40, 5, 18)],
	"shipyard": [Vector3(-40, 12, 128), Vector3(-100, 3, 150)],
	"hold": [Vector3(48, -2.5, -88), Vector3(48, -3, 0)],
	"moon-pool": [Vector3(39, -6.3, -7.7), Vector3(56, -17, 4)],
	"moon-pool-up": [Vector3(44, -10.6, 4), Vector3(50, 6, -4)],
	"core": [Vector3(48, -15.6, 41), Vector3(48, -17, 56)],
	"moon": [Vector3(39.5, -6.3, -7.5), Vector3(52, -12, 6)],
	"dock": [Vector3(48, -10.5, 4), Vector3(48, -11.5, 26)],
	# the Leviathan's outside (art step 1)
	"ship-bow": [Vector3(100, 12, -135), Vector3(56, 3, -96)],
	"ship-bow-west": [Vector3(12, 7, -120), Vector3(34, 3, -94)],
	"ship-east": [Vector3(120, 12, -40), Vector3(60, 2, -10)],
	"ship-stern": [Vector3(80, 10, 150), Vector3(48, 2, 105)],
	"ship-west": [Vector3(4, 8, -70), Vector3(30, 3, -40)],
	"ship-deck-fore": [Vector3(48, 22, -100), Vector3(48, 2, -40)],
	"ship-deck-aft": [Vector3(30, 20, 72), Vector3(52, 3, 30)],
	"ship-derrick": [Vector3(80, 30, -30), Vector3(48, 22, 0)],
	"ship-crane": [Vector3(42, 6, -55), Vector3(36, 10, -62)],
	"ship-under-drill": [Vector3(60, 5.6, -20), Vector3(40, 7, 6)],
	"ship-containers": [Vector3(56, 6, -40), Vector3(44, 6, -70)],
	"ship-drill-top": [Vector3(52, 14, -12), Vector3(44, 14, 11)],
	# its signs close up (every sign gets a close-up before it ships)
	"sign-drill-w": [Vector3(36.6, 13.4, -18.5), Vector3(36.6, 12.7, -14)],
	"sign-drill-e": [Vector3(59.4, 13.4, 18.5), Vector3(59.4, 12.7, 14)],
	"sign-driller": [Vector3(40.5, 14.4, 11), Vector3(43.8, 14.6, 11)],
	"sign-shack": [Vector3(49.9, 13.4, 5.5), Vector3(49.9, 13.2, 8.3)],
	"sign-focsle": [Vector3(36.6, 5.5, -85.5), Vector3(36.6, 5.4, -90)],
	"sign-draft": [Vector3(71, 1.6, -99.5), Vector3(66, 1.2, -102.4)],
	"sign-stern": [Vector3(48, 3.8, 121), Vector3(48, 3.2, 110)],
	"sign-name-e": [Vector3(80, 3, -73), Vector3(66, 2.5, -73)],
	"ship-top-bow": [Vector3(48, 55, -62), Vector3(48, 0, -100)],
	"ship-top-stern": [Vector3(48, 45, 72), Vector3(48, 0, 106)],
	"ship-high": [Vector3(150, 100, -190), Vector3(48, 0, -30)],
	"ship-bow-high": [Vector3(100, 38, -142), Vector3(46, 0, -92)],
	"ship-stern-high": [Vector3(98, 30, 150), Vector3(48, 0, 100)],
	"focsle": [Vector3(36, 10.5, -90.5), Vector3(52, 7.5, -104)],
	"fore-peak": [Vector3(48, -1.5, -93), Vector3(36, -3, -101)],
	"bow-store": [Vector3(48, 5.8, -91), Vector3(42, 4.5, -103)],
	"aft-corner": [Vector3(56, 7.5, 107.5), Vector3(66, 4.5, 107)],
	# the bridge tower (art step 2)
	"tower-front": [Vector3(48, 14, 48), Vector3(48, 10, 80)],
	"tower-sea": [Vector3(92, 16, 78), Vector3(58, 10, 92)],
	"tower-stern": [Vector3(76, 16, 134), Vector3(48, 10, 102)],
	"tower-port": [Vector3(6, 14, 104), Vector3(34, 10, 88)],
	"tower-helideck": [Vector3(36, 21, 104), Vector3(58, 17.5, 78)],
	# (0.36.19 layout) inside, room by room
	"in-stores": [Vector3(36, 5.7, 88.5), Vector3(42, 4.5, 75)],
	"in-armory": [Vector3(50.3, 5.7, 88.5), Vector3(45, 4.8, 75)],
	"in-hall": [Vector3(52.5, 5.9, 74.6), Vector3(52.5, 5, 93)],
	"in-workshop": [Vector3(35, 5.7, 94), Vector3(53, 4.8, 105)],
	"in-bosun": [Vector3(55, 5.7, 94), Vector3(61, 4.8, 105)],
	"in-mess": [Vector3(35, 9.2, 88.5), Vector3(43, 8, 75)],
	"in-galley": [Vector3(53, 9.2, 89), Vector3(45, 8, 75)],
	"in-corridor": [Vector3(34.6, 9.2, 91.5), Vector3(62, 8.6, 91.5)],
	"in-bunks": [Vector3(35, 9.2, 94), Vector3(43, 8, 105.5)],
	"in-lounge": [Vector3(44, 9.2, 94), Vector3(53, 8, 104)],
	"in-washroom": [Vector3(55, 9.2, 94), Vector3(61, 8, 105)],
	"in-sickbay": [Vector3(43, 12.7, 89), Vector3(35, 11.5, 75)],
	"in-office": [Vector3(50.3, 12.7, 89), Vector3(45, 11.5, 75)],
	"in-chief": [Vector3(35, 12.7, 94), Vector3(43, 11.5, 105)],
	"in-captain": [Vector3(44, 12.7, 94), Vector3(53, 11.5, 104)],
	"in-meeting": [Vector3(55, 12.7, 94), Vector3(61, 11.5, 105)],
	"in-bridge": [Vector3(53, 16.2, 89), Vector3(36, 15.2, 74)],
	"in-bridge-w": [Vector3(35, 16.2, 89), Vector3(53, 15.2, 75)],
	"in-chart": [Vector3(35, 16.2, 94), Vector3(43, 15.2, 105)],
	"in-radio": [Vector3(44, 16.2, 94), Vector3(53, 15.2, 105)],
	# below decks (art step 3)
	"in-hold-fore": [Vector3(38, -1.4, -90), Vector3(50, -3.5, -50)],
	"in-hold-mid": [Vector3(40, -1.6, 22), Vector3(50, -3.5, 50)],
	"in-hold-cargo": [Vector3(48.5, -2.2, -36), Vector3(42, -3.5, -52)],
	"in-hold-aft": [Vector3(48, -1.6, 72), Vector3(48, -3, 20)],
	"in-passage-w": [Vector3(33, -2.3, -90), Vector3(33, -3, -20)],
	"in-passage-e": [Vector3(63, -2.3, 72), Vector3(63, -3, 0)],
	"in-workshop-w": [Vector3(40, -2.3, 75), Vector3(40, -3, 96)],
	"in-workshop-e": [Vector3(46, -2.3, 76), Vector3(56, -3.5, 98)],
	"in-pump": [Vector3(53, -6.3, -58), Vector3(40, -7.5, -90)],
	"in-pump-e": [Vector3(40, -6.3, -90), Vector3(58, -7.5, -62)],
	"in-bilge": [Vector3(35, -6.3, -54), Vector3(48, -7, 10)],
	"in-engine": [Vector3(48, -6.3, 32), Vector3(48, -7, 90)],
	"in-engine-close": [Vector3(48, -6.3, 52), Vector3(40, -7.2, 62)],
	"in-tank": [Vector3(36, -6.3, -30), Vector3(50, -7.5, -5)],
	"in-bow-stairs": [Vector3(45.5, -2.3, -76.5), Vector3(50, -5, -86)],
	"bow-head": [Vector3(36, 6.5, -62), Vector3(48, 5, -82)],
	"in-lathe": [Vector3(33, -2.3, 92.5), Vector3(36.5, -3.6, 85)],
	"in-engine-back": [Vector3(60, -6.3, 100), Vector3(44, -7, 40)],
	# the extracts at eye height (0.36.25: floor shimmer check)
	"ex-boathouse": [Vector3(-42, 4.4, 158), Vector3(-38, 2.8, 164)],
	"ex-boathouse-in": [Vector3(-44.5, 4.1, 166), Vector3(-34, 2.6, 160)],
	"plaza-floor": [Vector3(-75, 4.1, 14), Vector3(-50, 2.5, -12)],
	"door-hold-36": [Vector3(33.2, -2.4, -36.6), Vector3(44, -2.6, -34)],
	"door-hold-40": [Vector3(33.2, -2.4, 39.4), Vector3(44, -2.6, 42)],
	"door-jamb-40": [Vector3(35.0, -2.4, 40.3), Vector3(40, -2.6, 37.5)],
	"door-jamb-40b": [Vector3(37.2, -2.4, 39.6), Vector3(30, -2.6, 41.5)],
	"door-ramp-a": [Vector3(32.5, -2.4, 24), Vector3(36, -2.6, 12)],
	"door-ramp-b": [Vector3(31.5, -2.4, 27), Vector3(38, -2.2, 14)],
	"door-ramp-c": [Vector3(34.4, -1.2, 20.5), Vector3(37, -2, 15.5)],
	"door-ramp-d": [Vector3(34.6, -0.6, 18.5), Vector3(37, -2, 15.2)],
	"bow-stair-door": [Vector3(47.5, -2.4, -84.5), Vector3(40, -2.6, -85.5)],
	"bow-stair-door-b": [Vector3(46.5, -2.4, -85.6), Vector3(40, -2.4, -82.5)],
	"bow-stair-jamb": [Vector3(42.3, -2.3, -87.3), Vector3(44.6, -2.4, -84.6)],
	"companion-ramp": [Vector3(31.9, 5.8, -61), Vector3(32.6, -2.5, -42)],
	"companion-ramp-low": [Vector3(34.8, -2.4, -38), Vector3(32, 0, -56)],
	"ex-cove": [Vector3(-46, 4.4, -164), Vector3(-40, 2.8, -170)],
	"ex-road": [Vector3(-166, 4.4, 4), Vector3(-174, 2.8, 0)],
	"ex-bowboat": [Vector3(58, 4.4, -114), Vector3(64, 2.8, -120)],
	"ex-stern": [Vector3(54, 2.4, 108), Vector3(60, 0.8, 112)],
	"ex-subbay": [Vector3(55, -10.6, 12), Vector3(61, -12.25, 17)],
	# the shore, art pass 1 (quay_front): the quay edge, the cranes, the pier, the pontoon, the barges
	"quay-from-ship": [Vector3(31.5, 6.0, -30), Vector3(-30, 6, -40)],
	"quay-from-deck-high": [Vector3(34, 16, 10), Vector3(-34, 4, -50)],
	"quay-edge": [Vector3(-26, 2.0, -70), Vector3(-30, 2.5, -20)],
	"quay-apron": [Vector3(-44, 4.2, -110), Vector3(-34, 6, -60)],
	"quay-crane": [Vector3(-10, 6, -30), Vector3(-34, 16, -16)],
	"pier-deck": [Vector3(-26, 3.2, 2.6), Vector3(20, 2.5, 2.6)],
	"pier-gallery": [Vector3(-22, 3.2, 5.8), Vector3(20, 3, 5.8)],
	"pier-side": [Vector3(-6, 4, -16), Vector3(0, 1, 4)],
	"pontoon": [Vector3(-24, 2.6, 34), Vector3(10, 0.6, 39)],
	"barge-line": [Vector3(-27, 3.4, 121), Vector3(10, 1.5, 121)],
	"barges-side": [Vector3(0, 6, 104), Vector3(10, 1, 121)],
	"quay-wide": [Vector3(20, 20, -60), Vector3(-34, 2, 20)],
	# Site Zero (art step 4)
	"lab-intake": [Vector3(50, -16.6, -72), Vector3(44, -17.5, -50)],
	"lab-security": [Vector3(57, -16.6, -58), Vector3(64, -17.5, -70)],
	"lab-lockers": [Vector3(36, -16.6, -66), Vector3(31, -17.5, -48)],
	"lab-decon": [Vector3(38.75, -16.6, -59), Vector3(38.75, -17.5, -44)],
	"lab-main": [Vector3(31.5, -13.5, -45), Vector3(52, -17.5, -14)],
	"lab-main-s": [Vector3(42, -15.0, -11.5), Vector3(44, -17.5, -44)],
	"lab-mezz": [Vector3(64.5, -10.6, -41), Vector3(48, -16, -22)],
	"lab-cleanroom": [Vector3(43, -16.6, -27.5), Vector3(43, -17.5, -36)],
	"lab-director": [Vector3(60.5, -10.6, -21), Vector3(64, -11.5, -12)],
	"lab-hub": [Vector3(39, -16.6, -12), Vector3(50, -17.5, 6)],
	"lab-washroom": [Vector3(36, -16.6, 0), Vector3(31, -17.5, -8)],
	"lab-break": [Vector3(59.5, -16.6, -7), Vector3(64, -17.5, 3)],
	"lab-holding": [Vector3(48, -16.6, 10.6), Vector3(48, -17.5, 32)],
	"lab-receiving": [Vector3(36, -16.6, 31), Vector3(32, -16.5, 12)],
	"lab-medbay": [Vector3(60, -16.6, 11), Vector3(64, -17.5, 30)],
	"lab-ring": [Vector3(38.75, -16.6, 33), Vector3(38.75, -17.5, 68)],
	"lab-hall": [Vector3(37.5, -14.5, 39.5), Vector3(56, -17.5, 58)],
	"lab-hall-s": [Vector3(48, -15.6, 61), Vector3(48, -16, 40)],
	"lab-obs": [Vector3(48, -10.6, 28.5), Vector3(48, -13, 40)],
	"lab-dock": [Vector3(40, -10.6, 8), Vector3(58, -11.5, 24)],
	"lab-control": [Vector3(47, -16.6, 69.5), Vector3(47, -17.5, 84)],
	"lab-ops": [Vector3(38.75, -16.6, 69), Vector3(38.75, -17.5, 99)],
	"lab-quarters": [Vector3(36, -16.6, 70), Vector3(31, -17.5, 82)],
	"lab-server": [Vector3(41.5, -16.6, 96), Vector3(64, -17.5, 96)],
	"lab-power": [Vector3(57, -16.6, 72), Vector3(65, -17.5, 72)],
	"lab-lobby": [Vector3(41.5, -16.6, 86), Vector3(54, -17.5, 88)],
	"lab-door-decon": [Vector3(57.25, -16.6, -60), Vector3(57.25, -16, -56)],
	"lab-door-hall": [Vector3(48, -16.6, 34), Vector3(48, -16, 38)],
	"lab-door-cells": [Vector3(48, -16.6, 22), Vector3(44, -16.5, 21)],
	"lab-door-main": [Vector3(38.75, -16.6, -6), Vector3(38.75, -16, -10)],
	"lab-door-tube": [Vector3(47.2, -16.6, -59), Vector3(47.2, -16.5, -63)],
	"lab-door-med": [Vector3(57, -16.6, 14), Vector3(59, -16, 14)],
	"lab-door-dir": [Vector3(61, -10.6, -26), Vector3(61, -10, -22)],
	"lab-stairs-bow": [Vector3(50, -16.6, -66), Vector3(50, -16, -74)],
	"lab-stairs-tower": [Vector3(47, -16.6, 88.5), Vector3(54, -16, 88.5)],
	"lab-moon": [Vector3(48, -10.6, 20), Vector3(48, -10, 5)],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "/tmp/rip"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
		if a.begins_with("view="): only = a.substr(5)
	RaidMap.scene_path = "res://scenes/maps/riptide.tscn"
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	for i in 10: await process_frame
	var spawner := main.get_node_or_null("EnemySpawner")
	if spawner != null:
		spawner.queue_free()
	for node in get_nodes_in_group("enemies"):
		node.queue_free()
	var hud := main.get_node_or_null("HUD")
	if hud != null:
		hud.visible = false
		hud.process_mode = Node.PROCESS_MODE_DISABLED   # (it pauses the raid with nobody at the keys; the rain needs time to run)
		paused = false
		for c in hud.get_children():
			if c is CanvasItem: c.visible = false
			if c is CanvasLayer: c.visible = false
	var player := main.get_node("Player") as Node3D
	# Every player spawn: drop the player there and see where they end up.
	var spawns := [] if "nospawn" in OS.get_cmdline_user_args() else main.get_node("PlayerSpawns").get_children()
	for s: Node3D in spawns:
		player.global_position = s.global_position + Vector3(0, 0.2, 0)
		player.set("velocity", Vector3.ZERO)
		for i in 40: await physics_frame
		var fell := s.global_position.y - player.global_position.y
		print("spawn %s at %s -> y %.2f%s" % [s.name, s.global_position, player.global_position.y, "  FELL" if fell > 1.0 else ""])
	player.global_position = Vector3(-170, 3, -100)
	var cam := Camera3D.new()
	cam.far = 900.0
	main.add_child(cam)
	cam.current = true
	if "norain" in OS.get_cmdline_user_args() and main.get_node_or_null("Rain") != null:
		main.get_node("Rain").free()   # (clearer pictures of the art)
	if "opendoors" in OS.get_cmdline_user_args():   # (the key doors swung open)
		for d in get_nodes_in_group(&"key_doors"):
			d.call("open")
	await create_timer(2.0).timeout   # (the raid's opening fade)
	for view: String in VIEWS:
		if only != "" and not view in only.split(","):
			continue
		var at: Vector3 = VIEWS[view][0]
		var target: Vector3 = VIEWS[view][1]
		cam.global_position = at
		cam.look_at(target)
		for i in 8: await process_frame
		if main.get_node_or_null("Rain") != null: await create_timer(1.2).timeout   # (time for the rain to fall into view)
		root.get_viewport().get_texture().get_image().save_png("%s-%s.png" % [out, view])
		var rain := main.get_node_or_null("Rain")
		print("saved ", view, "" if rain == null else "  (rain %s)" % ("falling" if rain.get_child(0).emitting else "stopped: under cover"))
	quit()
