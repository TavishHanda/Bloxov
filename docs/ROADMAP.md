# Roadmap

The plan from here, as milestones. Each one has a goal and a clear "done when".
Every milestone ends with someone other than the owner playing the build.
(Replaces the phase table in `GAME_DESIGN.md` §11; phases 0–2 there are done.)

**Where we are (2026-10-24):** 0.18.12: World art merged (0.18.0) plus the owner's fix list and two draw-call passes; Look is next. (Older note, 2026-10-12: 0.16.14.) Done: Map & Spawn (0.10), Scorched Earth (0.11), Scavs 2.0 (0.12), Movement
(0.13), Items (0.14), Guns (0.15, mechanics only; gun models wait for the art updates) and Economy (0.16, closed at
0.16.14; trader names and the owner's playtest of prices and quests still open). M1-M3 are done (co-op + PvP is live).
Next: the M4 art updates (World art, Look, Sound), below.

### Up next, in order
1. **Playtest the big map** (0.10 Map & Spawn, done through 0.10.3). Still untested live:
   extracting one at a time, the downed timer running out, squads spawning together, the 0.10.1 places
   (hunting stands, bell tower, junkyard, bunker, vault), AI on the big map. Layout fixes from it ship as 0.11.x.
2. ~~**Code cleanup (0.11):**~~ done in 0.11.0.
3. ~~**Scavs 2.0 (0.12):**~~ closed at 0.12.39 (owner: "feeling really good"). AI zones, snipers, Bon + guards (trips
   to the bank), one-plan fight brain (shoot first, chase in range, cover with intent, hurt AI fight from cover),
   tracking after losing sight, callouts. Left over, not blocking: step 2 of the AI rebuild (patrol/investigate/search
   on the one-plan pattern), Bon's spawn chance before launch (100% while testing), difficulty tuning (accuracy and
   bursts only), and playtesting the bell tower, hunting stands, junkyard, bunker, vault and rival fights.
4. **Movement update (owner, 2026-10-10; small; 0.13.0 vaulting done):** mainly **vaulting**: vault or mantle over low cover (fences,
   sandbags, the trench, walls) and climb onto ledges. Candidates for the owner to pick from: ladders, fall damage
   (both parked in `BACKLOG.md`), prone, crouch-walk speed tuning. (Leaning and stamina already exist.) Right after
   Scavs 2.0, so the AI's paths can use the same vaultable cover. (AI vaulting was scrapped in 0.14.20, owner: AI walk round.)
5. **Items update (0.14: keys, loot by place, descriptions, helmets; durability moved to its own later update, owner 2026-10-11):** keys (bunker, bank vault), loot by place (`MAP_PLAN.md` table), item descriptions, and
   **durability** (owner, 2026-10-10) for armor and helmets: hits wear them down and protect less as they do, shown
   on the item, so worn gear is worth less. Other gear only where it makes sense (keys could have limited uses).
6. **Guns update (owner, 2026-10-10):** gun categories (e.g. pistols, SMGs, rifles, shotguns, marksman), a real set
   of guns in each, attachments (sights, muzzles, grips, mags, stocks), and gun models: each gun its own model on the
   characters' `GunSocket` (see `BACKLOG.md`), owner in Blender. After the Items update, since guns, attachments and
   their loot spots build on it. **Gun durability** (owner, 2026-10-10): guns wear with use and a worn gun
   jams or misfires more often, shown on the item. Made-up gun names and looks only (`STORE_RULES.md`: no real brands or models).
7. **Economy update (owner, 2026-10-10):** after the Items and Guns updates, when there's a full set of things to
   price: trader buy/sell prices, what's worth looting and where, money in vs. money out (sinks), and how traders and
   their stock fit in (more traders are on the wishlist). **Repairs** for worn armor and guns (a trader or repair
   kits) as a money sink. Earned money only (`STORE_RULES.md`: no real-money trading).
   **Started 2026-10-12 as 0.16** (plan: project file `economy/plan.md`). Owner's answers: trader levels that
   unlock gear (yes); five traders: guns, meds, supplies, valuables, and **Ming**, a gambling trader (earned
   money only, odds shown; never the premium currency); limited stock/restocks not now (keep the idea); a real
   stash size with upgrades bought with money (later, bigger expansions also with the premium currency, via IAP);
   medium pace (a good kit = 2-3 normal raids); no insurance. Repairs moved to the durability update.
8. **Then (M4, vertical slice), split into three updates (owner, 2026-10-11), in this order:**
   1. **World art:** starts with a quick **neutral lighting baseline** (less saturated, plain sun and sky; owner
      asked which comes first, 2026-10-11) and **one test building** finished under it. Models and lighting change
      each other, so lock the baseline and the test piece first, then model everything else against them.
      Then building models fitted to the proven layout, ground textures, props.
      **Map pass in the same update (owner, 2026-10-12):** fill Bloxov Battlegrounds with a lot more stuff (debris,
      wrecks, rubble, fences, clutter) so you can't snipe across the map or see lots of scavs at once, above all
      right at the start of a raid.
      **Loot spots will move and change in number (owner, 2026-10-12):** afterwards re-run `tools/economy_sim.gd`
      and re-tune prices (0.16.1 tuned them so a good kit costs about 2-3 normal raids).
      **Secret waterfall room (owner, 2026-10-12):** a waterfall by the creek; walk through it into a hidden room
      with a couple of safes. Build it in this map pass (count its safes in the economy re-run).
   2. **Look:** the final **lighting overhaul** (owner, 2026-10-10: today's look is too saturated; tune it once, against the
      real models and ground textures, within what the web build supports), plus the loading screen.
      **Graphics settings (owner, 2026-10-24, after the 0.18.11-0.18.12 draw-call passes):** a low/high (or
      low/medium/high) setting: shadows on/off and distance, far-view distances, grass/bush density, render scale.
      The next biggest cost after draw calls is triangles (~1.8M on screen in a busy view, `tools/perf_view.gd`).
      Matters most for phones and weak laptops. Settings change looks only, never what you can see through.
      **Item pictures (owner, 2026-10-24, done in 0.19.4):** every item gets a small rendered picture in the inventory,
      stash, gear slots, trader and hand-in screens, like Tarkov / Arc Raiders (look C: slight angle, dark edge).
      Models in `tools/item_models.gd`, rendered by `tools/render_icons.gd`. Later: a wider inventory/stash restyle
      (owner, 2026-10-24: "the whole inventory/stash look needs a bit of an update").
   3. **Sound (owner, 2026-10-10):** only ADDING new sounds (owner, 2026-10-11: keep today's sounds,
      at most small tweaks, never replace them): a sound per gun (shot, reload, empty click, distant shot), footsteps by surface
      (grass, wood, metal, concrete), directional and distance audio you can play PvP by (where shots and steps come
      from, muffled through walls), scav and Raider voice lines, map ambience, UI sounds, and a final mix. Last, since footsteps by surface and ambience
      need the final ground and buildings.
   After that M5 content (characters with perks, more traders, more maps) and the M6 public release.
   - **Harder maps later (owner, 2026-10-12):** Bloxov Battlegrounds is the base map, so it should stay friendly to
     new players. Harder maps come later (M5 more maps).
   - **Character prestige (owner, 2026-10-11):** play a character a lot and you can "prestige" it to unlock skill
     points that slightly boost that character's own traits (e.g. sprint 2% longer per point, up to 20%). Comes with
     the characters work. Keep the boosts small: the design doc's rule is "progression = access, not power", so
     this is the one place a little power is earned, and only on that character.
   - **The escape: the long-term goal (owner, 2026-10-13; planned, not built; with the characters work, after a
     crafting system):** the point of all the raids, money, trader favours and quests is to **craft an escape
     vehicle** and get out of the war to a **safe haven** (maybe a bunker) that also costs a lot of money to get
     into, in the lore and in the game. Pieces: (1) a **crafting system** (and more items to craft from); (2) a long
     **quest line**, with the traders helping you get there (their favours and contacts); (3) the vehicle built from
     crafted parts; (4) paying the haven's entry price; (5) a final **escape raid**: extract with that character in
     the vehicle and the character earns a **skill point to prestige** (see Character prestige above), spent on its
     traits. Lore: `docs/LORE.md` "The escape". Open questions for the owner are listed there.
   - **Walkable hideout (owner, 2026-10-12; after World art, since it needs a hideout model):** open the game,
     press PLAY, and you're standing in a 3D hideout. Walk up to the traders, the stash and a **shooting range**
     (try guns and attachments) and use them there, or open a menu that takes you to today's hideout screen
     (stash, loadout, traders, START RAID), which stays as the quick way to do everything. Touch-friendly on phones.
   - **Crosshair customization (owner, 2026-10-11; later):** pick your own crosshair (style, size, color) in settings.
   - **Skin boxes (owner, 2026-10-12; with skins and the premium currency near release, after the art updates,
     since skins need the final character models):** a **free skin box** bought with earned money (basic skins) and
     a **paid skin box** bought with gems (the premium currency). Rules (`STORE_RULES.md` section 5): odds shown
     before every purchase on every platform; gems sold only through Apple IAP / Google Play Billing / Steam
     Wallet; the rating gets "In-Game Purchases (Includes Random Items)"; a per-region switch turns paid boxes off
     where paid loot boxes are banned (e.g. Belgium), with direct purchase instead. Design: the paid box's skins
     never come from the free box; duplicate protection; some skins also sold directly for gems; skins are
     cosmetic only; gems never buy Ming's boxes and never turn into earned money.
- **Stash update (planned, before the store/Steam release; owner 2026-10-10: wait until closer to shipping, solo and
  online share one stash while we playtest):** solo and online get **separate stashes** (each with its own money,
  loadout and stats), picked with a SOLO / ONLINE switch in the hideout. Solo stays on the device and works
  offline with no account. The **online stash moves onto the server** so it can't be edited to cheat: the server
  owns the stash, loadout and money, checks what you take in and saves what you bring out. Needs: a player
  identity (owner chose a **device account**: made silently on the device, no email or login, a transfer code
  moves it to another device; Steam login can be linked later), a database (Heroku's disk is wiped on restart), and the store rules on accounts
  (`STORE_RULES.md` §4: delete account in-game, Sign in with Apple if other logins are offered, no forced
  account for solo). The current save becomes the solo stash.
- **Online security update (before the web beta / Steam; owner 2026-10-12, from a friend's checklist):** a server
  authority audit plus free, home-made anti-cheat (no paid anti-cheat service). Already on the server: what every
  shot and knife hits (map blocks shots, damage from the server's weapon stats, lag compensated for players and,
  since 0.15.28, AI), fire-rate and shot-origin checks, the AI, loot containers' rolls, grenades, doors, kill and
  dog tag credit. Still trusting the player's game (fix these): movement and position (no speed/teleport/fly
  checks), their own health and armor (the server can't stop god mode), which gun they fire (not checked against
  what they carry, so ammo and gun choice are on trust), what they put into a container or drop (items could be
  made up), extracting, and the stash/money (the Stash update moves the online stash onto the server). Plan:
  server-side health/armor, carried-loadout tracking (guns, ammo, items in/out), movement sanity checks, server
  extract check, rate limits on every request, and logging/flagging suspicious players (simple kick/ban list).
  Detecting aimbots/wallhacks on the client isn't possible in a browser; the server checks above are the defense.
- **Platform plugins (owner, 2026-10-12: "make sure we have this, we will need it"). All free and open source;
  only the store fees cost money. Check each is still maintained and works with our Godot version when we start.**
  - **Steam (Steam early access prep):** [GodotSteam](https://codeberg.org/godotsteam/godotsteam) for
    achievements, the overlay, Steam login and linking a Steam account to the web account, and Steam Wallet
    payments for the premium currency (Steam Microtransactions; Steam must use these), plus friends, invites,
    cloud saves and leaderboards. Steam build only; the web build doesn't use it.
  - **Android (mobile release):** the official [Google Play Billing plugin](https://github.com/godot-sdk-integrations/godot-google-play-billing)
    (in-app purchases; Play requires its billing for digital items) and
    [Google Play Games Services](https://github.com/godot-sdk-integrations/godot-play-game-services) (sign-in,
    achievements, leaderboards, cloud saves). Both from the godot-sdk-integrations group.
  - **iOS (mobile release):** [Godot Apple Plugins](https://github.com/migueldeicaza/GodotApplePlugins) (MIT):
    StoreKit 2 (in-app purchases; Apple requires its IAP for digital items), Game Center (achievements,
    leaderboards) and Sign in with Apple (required if we offer any other login on iOS, `STORE_RULES.md`).
  - Purchases are always checked on our server with the store before the currency is given (see the premium
    currency notes: ledger, no double credit, refunds).
Parked 0.9 leftovers (teammate-down alert, squad line on the end screen, rejoin after disconnect) can slot in
between updates. Lore is the owner's.

| # | Milestone | Goal | Done when |
|---|---|---|---|
| **M1** | **Complete loop** (0.4) | Inventory redesign, persistent stash, simple trader (sell loot, buy gear), pick a loadout before a raid | The owner plays 5 raids in a row because they *want* to |
| **M2** | **First playtest round** | 3–5 friends play the web link while the owner watches without explaining | A ranked list of the top problems |
| **M3** | **Multiplayer spike** | Throwaway prototype: 2 players in one raid, moving, shooting scavs, seeing each other, and able to shoot each other (owner wants **co-op and PvP**) | We know: how browsers connect (hosted server vs. WebRTC + signaling), who runs the game state (host vs. server), and roughly how much work each system takes to sync. **Decide:** how to build co-op + PvP (PvP needs a server that owns the game state, against cheating) and when |
| **M4** | **Vertical slice** | One small part of the game at near-final quality: Blender art pipeline, real sounds, polished gun feel and scav, clean UI | It looks and feels like the real game; good enough to show people |
| **M5** | **Production** | More content: map areas, guns, enemy types, events (plus real co-op if M3 said go) | Content matches the MVP list in the design doc |
| **M6** | **Release** | Public web release (itch.io), then iterate; mobile after | Strangers play it and come back |

## Version phases (middle number)
0.5 guns · 0.6 scavs · 0.7 multiplayer (0.7.0-0.7.11: connect, matchmaking, PvP, shared AI and loot) ·
0.8 HUD & inventory (owner's designer session; started as 0.7.12-0.7.15) · 0.9 raid flow (downed/revive,
per-player extract, spectate; paused at 0.9.5) · **0.10 Map & Spawn** (Bloxov Battlegrounds) · **0.11 Scorched Earth** (cleanup, war-torn map, hills) ·
**0.12 Hot Zone** (Scavs 2.0, closed at 0.12.39) · **0.13 Over the Top** (Movement, to 0.13.9) · **0.14 Spoils of War** (Items) (the Stash update waits until closer to release).

## Rules while we go
- **Co-op-friendly code, even before M3.** Don't add new "there is exactly one player" assumptions.
  Existing ones to fix in the spike: scavs target the first node in the `player` group; HUD, loot screen and
  Raid are each bound to one player; extracting ends the raid for everyone.
- **One area at a time.** Owner-driven reviews of each mechanic (movement done in 0.3.1–0.3.2).
- Notes and parked ideas live in `docs/BACKLOG.md`.
