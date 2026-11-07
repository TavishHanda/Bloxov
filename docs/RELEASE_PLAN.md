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

## Order of work
Most important first, so if time runs out, what's missing is the least important. Each block is its own update
(own thread, own version). Updates in the same week run side by side **on branches** and are released one after
another (CLAUDE.md: only one phase is current at a time), so their version numbers never clash.

| Week | Track A (systems) | Track B (content / art) | Steam / business |
|---|---|---|---|
| **1** Nov 9-15 | **Characters** (0.32): pick a character in the hideout, traits per character, 3 launch characters on today's body | **Map 2 layout** (blockout, extracts, spawns, loot by place) | Make the free Steamworks account |
| **2** Nov 16-22 | **Crafting + new items** (0.33): workbench in the hideout, recipes, crafting parts as loot | **Map 2 art** (buildings, outdoor pieces, nav bake) | Store page text + screenshots drafted |
| **3** Nov 23-29 | **Expeditions** (0.34): the stages, the money cost, the wipe, upgrade points, the quest line to it | **Map 2 finished**; **more quests** for both maps | **Pay the $100 fee** (see dates) |
| **4** Nov 30-Dec 6 | **Seasons + battle pass** (0.35): free track first, earned in raids | **Skins** for the 3 characters; **pets** if the answers make them small | GodotSteam: Steam build, login, achievements |
| **5-6** Dec 7-20 | Paid gems + paid battle pass track on Steam Wallet (can only be tested once the Steam app exists) | **Map 3** | Store page live as **Coming Soon** (by ~Dec 9) |
| **7+** Dec 21-Jan | Polish, balance (economy sim re-run), bug fixes from playtesters, **web beta** | | Move the server to the OVH VPS; build review; launch |

Why this order:
- **Characters first:** skins, the expedition's upgrade points and the battle pass rewards all hang off them.
- **Crafting before expeditions:** the expedition is built from crafted parts.
- **Battle pass after the content it rewards** (skins, items), and its paid side needs the Steam app.
- **Maps run alongside** because they touch different files (map generator, art) from the systems work.
- **Pets last:** the least tied to anything else, and the easiest to add in an Early Access update.

What clashes if run at the same time: crafting, more loot, quests and battle pass rewards all edit
`scripts/item_db.gd` and the economy numbers, so those go one after another, not side by side.

## Steam dates (the $100 fee)
Steam's rules: after paying the fee there's a **30-day wait** before you can release; the store page must be
**Coming Soon for at least 2 weeks**; Valve reviews the store page and the build first (a few working days each,
slower over the holidays). The **Steam Winter Sale** runs from late December into early January; a new game
launched during it gets buried.
- **Pay the $100 between Nov 23 and Nov 30** (owner's "end of the month" fits; **Dec 1 at the latest**). The 30 days
  then end by ~Dec 31, which leaves room for the store page's 2 weeks and the build review before a January launch.
- **Store page:** submit right after paying, live as Coming Soon by ~Dec 9. Every day it's up collects wishlists,
  which decide how much Steam shows the game at launch.
- **Launch: aim for the week of Jan 11, 2027** (owner wants January; this is just after the Winter Sale).
- **Build review:** submit ~1 week before launch.
- Check the exact Winter Sale dates and Steam's current wait/review times when paying (they can change).
- Option to think about: Steam **Next Fest** (usually February) gives unreleased games with a demo a big wishlist
  boost. Launching in January skips it; waiting for it means launching in late February.

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
6. **What gets crafted?** Only expedition parts, or also gear (meds, ammo, attachments)? Crafting in the hideout
   only (a workbench), with a wait timer or instant?

**Maps (weeks 1-6)**
7. **What are maps 2 and 3?** Ideas so far: the depot, a nearby base, a cargo/military ship, a mall, an underground
   facility. Harder than Frontlines (the roadmap says harder maps come later)? Smaller is faster to build.

**Seasons, battle pass, pets (weeks 4+)**
8. **Seasons:** do expeditions line up with seasons (Arc Raiders style), and how long is a season (8-12 weeks is
   typical)? Does the battle pass reset each season?
9. **Battle pass:** free track + paid track (with gems)? What's on it: skins, gems back, earned money, items?
   (Store rules: no gameplay power for real money is the safe line.)
10. **Pets:** cosmetic only (follows you in the hideout / sits on your back in raids), or do they do something
   (a dog that barks at nearby enemies)? Do other players see them?

**Launch**
11. **Launch day:** the week of January 11 OK, or a later January date?
12. Anything else from the "probably forgetting stuff" list.
