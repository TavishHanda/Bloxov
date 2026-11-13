# Road to Steam: release plan

Written 2026-11-07 from the owner's wishlist. Planning only: nothing here is built yet.
The owner's target: **most of the list built by early December, Steam Early Access in January 2027** (owner, 2026-11-07).
This plan orders the work for that pace, says what can run side by side, and says plainly what is at risk.
Answers to the open questions at the bottom go into this file as they come in.

## What the owner wants before Steam (2026-11-07)
1. **Two more maps** (three in total with Bloxov Frontlines).
2. **Characters like Valorant / Apex:** named characters with their own stats and traits.
3. **Skins** for those characters.
4. **Expeditions** (like Arc Raiders): a big goal you build towards with crafted parts and money; when you go, your
   progress is wiped and the character earns **points to upgrade** it.
5. **Crafting** for some items (feeds the expedition).
6. **Battle pass.**
7. **Pets.**
8. **More loot / items** and **more quests.**
"I'm probably forgetting stuff": anything new gets added here and placed in the order below.

## How it fits what's already planned
- **The escape = the expedition.** `docs/LORE.md` "The escape" (2026-10-13) already planned this: craft an escape
  vehicle from parts, a long trader quest line leading to it, pay a safe haven's entry price, extract in the vehicle,
  and the character earns a skill point to prestige. The new wish adds the **wipe** (Arc Raiders style): leaving
  resets your progress in return for permanent rewards. One system, not two. Its open questions (what the vehicle
  is, what the haven is, which traders help, solo or squad) are merged into the questions below.
- **Character prestige** (`ROADMAP.md`, 2026-10-11) = the "points to upgrade that character". Rule kept from then:
  boosts stay small (e.g. sprint 2% longer per point, up to 20%), because the design doc's rule is "progression =
  access, not power". A fresh player with a good gun must still be able to beat a veteran.
- **Characters** (`BACKLOG.md`): named characters with lore and personality, not "scout/tank" classes; traits
  are **tradeoffs**, not pure buffs.
- **Skins, skin boxes, gems, battle pass** (`ROADMAP.md`, `STORE_RULES.md` §5): the money rules are already
  written: gems sold only through Steam Wallet (Steam), Apple / Google billing (phones), a web processor later;
  odds shown on every paid box; skins cosmetic only; gems never buy Ming's boxes or earned money.
- **Release order stays:** web beta, then Steam Early Access, then phones (separate game).

## Where it stands (2026-11-13, at 0.34.15)
A whole-plan review was done on 2026-11-13 (project Claude Doc "Bloxov plan review"). What it found, against the
wishlist above:

| Wishlist item | State | For a January launch |
|---|---|---|
| Crafting | **Shipped** 0.32.0 (11 recipes, instant) | done |
| More quests | **Shipped** 0.31.15 (19 trader jobs) | done |
| Map 2, **Riptide** | Gray box finished on branch `claude/project-thread-kkimzo` (0.33.0-0.33.6: layout, storm, swimming, boss Zero and his loot). No art, not online, no map picker; renumber at release | doable; the biggest job left |
| Characters with traits | not started | doable if it starts now |
| Expeditions | not started; open questions 3-5 below | a lean first version |
| Steam build (GodotSteam, Steam sign-in linked to the account, cloud save for PvE, overlay) | not started; the Windows build is tested in CI | **must** happen; needs the app from the paid fee |
| Server move + growth (OVH, several processes, stress test) | planned, not started | **must** happen before launch |
| Battle pass, paid gems, skins, pets, map 3 | not started | review recommends after launch (owner hasn't decided) |

Also found: **a lone PvP player waits forever** (`Matchmaker.MIN_PLAYERS` 2, no START NOW when signed in). Owner's
idea (2026-11-13): if no game is found in ~2 minutes, fill the raid with **AI PMCs**; PvP and PvE stay separate.
To be planned and proposed (gameplay change).

**Version numbers:** the numbers first given here (Characters 0.32, Crafting 0.33, Expeditions 0.34, Seasons 0.35)
are void. 0.32 = Crafting, 0.33 = held by Riptide's branch, 0.34 = Lively hideout. Each new update takes the next
free middle number when it starts.

## Order of work (revised 2026-11-13)
Most important first. Launch blockers (Steam build, server) no longer wait until the end. Dates are a guide, not
strict (owner, 2026-11-09).

| When | Systems | Content / art | Steam / business |
|---|---|---|---|
| **Now-Nov 15** | Characters **plan** (numbers to the owner); lone PvP queue plan | | **Owner pays the $100 fee** + Steam's tax/bank forms; store page kit (text, screenshots, capsule images; reuse `itch/`) |
| **Nov 16-29** | **Characters** built (3 launch characters, shared stats + one passive each) | **Riptide online** (map picker, server-synced switch, swim vs move checks, Zero online, lift), merged and renumbered | Store page sent to Valve, **Coming Soon** by ~end of November; wishlist button on the title screen and bloxov.com |
| **Nov 30-Dec 16** | **Expeditions**, lean v1 (one vehicle from crafted parts, entry price, wipe, one upgrade point); new-player counts (numbers only) | **Riptide art** | **Steam build**: GodotSteam on 4.7.2, Steam sign-in linked to the account, cloud save, overlay, first achievements |
| **Dec 17-Jan 4** (Winter Sale) | **Server move** to OVH, several processes, stress test | Riptide live on the web beta; playtest round on everything new (`notes/untested.md`) | Build review sent ~1 week before launch |
| **Jan 5 on** | Fixes and balance from the playtest | | **Launch** (see dates) |
| **After launch** (recommended, owner to confirm) | Paid gems + battle pass, more characters | Skins, pets, map 3 | |

What clashes if run at the same time: crafting, loot, quests and battle pass rewards all edit `scripts/item_db.gd`
and the economy numbers, so those go one after another. Characters, Riptide, the Steam build and the server touch
different files and can run two at a time.

## Steam dates (the $100 fee)
Steam's rules: after paying the fee there's a **30-day wait** before you can release; the store page must be
**Coming Soon for at least 2 weeks**; Valve reviews the store page and the build first (a few working days each,
slower over the holidays). The **Steam Winter Sale** runs from late December into early January; a new game
launched during it gets buried.
- **Pay the $100 as soon as possible** (owner, 2026-11-13: "soon"; **Dec 1 at the very latest**). Same cost, and
  the 30-day wait and the wishlist count both start sooner; the store page also gets reviewed before Valve slows
  down for the holidays.
- **Store page:** submit right after paying, live as Coming Soon by ~end of November. Every day it's up collects wishlists,
  which decide how much Steam shows the game at launch.
- **Launch: January 10-11, 2027, or up to two weeks later** (owner, 2026-11-13; just after the Winter Sale,
  Dec 17-Jan 4).
- **Build review:** submit ~1 week before launch.
- Check the exact Winter Sale dates and Steam's current wait/review times when paying (they can change).
- Steam **Next Fest** (Feb 22-Mar 1, 2027; sign-up closes Jan 10; unreleased games only, once per game) gives a
  wishlist boost. The owner chose January (2026-11-13), which skips it. If the launch slips past January anyway,
  look at it again before Jan 10.

## What's at risk (plain)
- **Maps are the biggest risk.** Bloxov Frontlines' art took several weeks of threads (0.17-0.28). Map 2 by early
  December is tight but doable if it's smaller; **map 3 by Steam is unlikely** at the same quality. Fallback: launch
  with 2 maps, map 3 as the first Early Access update (that's what Early Access is for).
- **Skins need character models.** Today's characters share one body. Skins can be colors/outfits on that body
  now; fully different characters (shape, silhouette, body animations) wait for new character models, which the
  roadmap already put after the art updates.
- **Paid battle pass / gems** can't be tested on Steam until the app exists (after the fee), and need the server's
  payment ledger (`docs/ROADMAP.md` premium currency notes). If it slips, launch with the free track and add the paid
  track in the first update.
- **Balance:** characters with stats, crafting and expedition rewards all add power. Each needs the economy sim
  re-run and a playtest; the 2026-10 rule "boosts stay small" protects PvP.
- **Server:** Heroku Basic holds ~24 raiding at once. The move to the OVH VPS is planned before Steam; a launch
  spike needs the multi-process setup in `docs/HOSTING_CAPACITY.md`.
- **Store rules** (`STORE_RULES.md`): battle pass and gems sold only through each store's billing; show exactly
  what each tier gives and the price; paid random rewards show odds; a per-region switch for paid boxes; the age
  rating gets "In-Game Purchases". Pets and characters raise no store issue.

## Owner's answers so far
- **Stats + passives (2026-11-07):** every character has the same set of **base stats** (stamina, sprint speed,
  reload speed, etc.), tuned differently per character, **plus a unique passive** each. No pressed abilities for now.
- **Names:** placeholders for now: the wardrobe's operators (`scripts/operators.gd`: Rook, Dune, Ghost, Viper,
  Bishop, Hawk). Owner likes chess-piece style names; real names come later.
- **Wipe (owner OK'd 2026-11-08):** PvP and PvE **both have expeditions, kept fully separate**. A
  PvE expedition wipes only the PvE stash and upgrades only the PvE character; a PvP one only the PvP side. Nothing
  earned in PvE ever reaches PvP, not even cosmetics, because the PvE save lives on the device and can be edited.
  Going on an expedition is always the player's choice, in both modes.

## Open questions for the owner
Answer any order; the first five are needed before their week starts.

**Characters (week 1)**
1. **Passive traits only, or abilities too?** Valorant / Apex characters have abilities you press (a smoke, a scan,
   a dash). Passive traits (move faster but carry less, heal faster but less armor) are much less work and much
   safer for PvP balance. Suggestion: passive traits for Steam, maybe one small ability each later.
2. **Who are the first 3 characters?** Name, one line of who they are, and their traits (tradeoffs). Do players
   start with all of them, or unlock them (and how: money, quests, levels)?

**Expeditions + crafting (weeks 2-3)**
3. **What's the vehicle and the haven?** (from LORE.md) Truck, boat, helicopter...? Bunker, island, city?
4. **What does the wipe reset?** Stash, money, trader levels, quests? What carries over besides the character's
   upgrade points (a bit more stash space, a badge or skin)? Does it reset **PvP only** (the server stash), or PvE
   too?
5. **Once per character, or again and again?** And does the squad leave together, or each player on their own?
6. ~~What gets crafted?~~ **Answered, built 0.32.0:** gear recipes from existing items, hideout workbench,
   instant (no timers), heavy armor / combat helmet / large backpack stay loot-only. Expedition parts are new items,
   proposed with the Expeditions update.

**Maps (weeks 1-6)**
7. ~~What are maps 2 and 3?~~ **Answered:** map 2 = **Riptide** (ship Leviathan over the lab Site Zero, boss
   Zero, the hardest map at release); map 3 later = an amusement park with the sniper boss Volt.

**Seasons, battle pass, pets (weeks 4+)**
8. **Seasons:** do expeditions line up with seasons (Arc Raiders style), and how long is a season (8-12 weeks is
   typical)? Does the battle pass reset each season?
9. **Battle pass:** free track + paid track (with gems)? What's on it: skins, gems back, earned money, items?
   (Store rules: no gameplay power for real money is the safe line.)
10. **Pets:** cosmetic only (follows you in the hideout / sits on your back in raids), or do they do something
   (a dog that barks at nearby enemies)? Do other players see them?

**Launch**
11. ~~Launch day~~ **Answered 2026-11-13:** January 10-11, or one to two weeks later.
13. **Riptide's art bar** (review, 2026-11-13): a clean flat-colour pass in a few big pieces and onto the web beta in
    December, or Frontlines-level detail first?
14. **After launch?** OK to move paid gems, the battle pass, pets, map 3 and most skins to Early Access updates?
15. **New-player counts:** OK to count (numbers only) tutorial finished, first raid, second raid, first extract?
12. Anything else from the "probably forgetting stuff" list.
