# Hideout life plan

Goal: the hideout should feel like a place people live in, not a level that was built and then left. The owner's note
(2026-11-04) is that it "feels dead". This plan is about **looks and sound only**: no new gameplay, no rewards, no
collision surprises, nothing sent online. It is not scheduled yet; the Stash update (0.31.x) comes first, so the steps
below are 0.32.x and can be cut or reordered.

## What is already there

The hideout is not empty. It has, from 0.21.7 and 0.28.5:

- `scripts/hideout_life.gd`: steam off the stove's pot, the stove fire and ash door glowing, dust drifting in the
  light over the war table, the TV's picture changing, and the projector screen in the hangout.
- `scripts/hideout_toys.gd`: the radio, the hangout jukebox, the bunks' light switch (the whole bunker dims), darts,
  seats, and the TV light that stays on when the lights are off.
- `scripts/hideout_doors.gd`: sliding doors that open as you walk up and close behind you.
- `scripts/swing_lamps.gd`: the mess lamps and hanging bulbs swing when bumped or shot.
- `scripts/kickables.gd`: cans and bottles in the mess get kicked about.
- `scripts/cloth.gd` / `bushes.gd`: curtains part round you.
- `scripts/ambience.gd`: the steady underground bunker ambience (0.30.2, owner-approved; leave it alone).
- `art_source/scripts/make_hideout.py`: five trader bays, the market ledge, the mess, the bunks, the washroom, the
  range, and the hangout.

So the gap is not "add a life system". It is that **the places you spend time in are static**: the traders' counters
have no people, the market has no small motion, and most of the sound is one steady bed.

## Rules for anything added

1. **Looks and sound only.** Nothing collides unless it is already a deliberate toy. Nothing changes the stash,
   loadout, prices or quests.
2. **Local only.** No new network messages. A headless server and the smoke tests must skip all of it
   (`Reacts.wanted(self)`), exactly like `hideout_life.gd`.
3. **Cheap by default.** Prefer a few `CPUParticles3D`, `MultiMeshInstance3D` and shader quads over many animated
   `MeshInstance3D`s. The hideout is one room; it should not cost a raid's frame budget.
4. **Pause-safe.** Animate on the game clock (the 0.29.14 rule), not wall time, so the pause menu does not make
   everything jump when you come back.
5. **Quiet is part of the feel.** New sounds are short, randomised one-shots at low volume, not another loop. They
   should be audible near the thing that makes them and gone by the time you walk away.

## Ideas, in order of impact per hour of work

### 1. Put the traders in their stalls (the big one)

The five bays already exist (`make_hideout.py`, `TRADERS`), the counters are stocked, and `Traders.LIST` already has
the identities. What is missing is the person. This is covered in `docs/TRADER_MODELS_PLAN.md`; it is listed first
here because it will do more for "alive" than every particle in this document combined.

While the bodies are being made, add the small things around them:

- A mug, a thermos, a plate and a paper on each counter, with one steam plume on the Medic's or the cook's.
- A trader's stool, a coat on a hook, a rifle leaning on the rack, a radio on the gunsmith's shelf.
- A hanging bulb over each counter with a slow, tiny sway (the swing system already exists; these are just more
  `SWINGS` entries).
- A cat asleep on the supplies crates, breathing. One small model, one loop, huge payoff. Optional; ask the owner
  first, because a cat is a character and needs its own art direction.

### 2. The market ledge itself

- **Drips:** water off the cave roof into a puddle, with a small expanding ring (a shader quad or a scaled mesh) and
  a quiet `drip` one-shot. Two or three spots, randomly timed.
- **Dust and smoke:** a second dust volume over the market, thinner than the war-table one, and a faint exhaust
  plume from the generator.
- **Cloth:** a tarpaulin or banner on the bay frames that moves a little in the draft (reuse `cloth.gd` if it fits,
  otherwise a vertex shader like `kit_sway`).
- **Cables:** one or two loose cables that sway; the swing system already knows how.
- **Litter:** a few more kickable cans and a bottle near the market, not just the mess.

### 3. Small events, not constant motion

Constant motion becomes wallpaper. Occasional events read as life:

- **The radio changes station:** every few minutes the radio's tune changes (or it cuts to static for a second and
  comes back). Only when it is on.
- **The TV schedule:** the picture shader already changes; add a rare "ad break" (a brighter, flatter picture for a
  few seconds) and a test card late in a long session.
- **The lights dip:** one flicker every few minutes, not a strobe. The bunker is on a generator.
- **A trader shifts:** weight from one foot to the other, scratches their neck, looks at the shelf, turns back to you
  when you come close. This is the idle animation from the trader plan.
- **A door somewhere else closes:** a distant, muffled clang from the tunnels, timed to nothing. The player never
  sees it; it makes the place feel bigger.
- **The range target sways:** the 100 m target moves a hair in the draft, and pings softly when hit (the hit sound
  already exists; this is the visual).
- **Steam and cooking:** the mess pot steams at "dinner" (a session-time state), and a pot lid rattles once in a
  while.

### 4. Sound, used sparingly

The ambience bed is approved and stays. Layer short one-shots on top, each with its own radius:

- water drip into a puddle (market, washroom)
- generator hum, with a slow wobble (a loop, but very quiet and local to the generator)
- metal creak from the cave or the bunker plates, now and then
- a muffled radio or TV from the hangout, audible only near the passage
- footsteps or a cough from "upstairs" (nothing there; it is a sound cue, not an NPC)
- the trader's voice when you open their screen: one short greeting line per trader, subtitled, no new dialogue
  system. This is a nice-to-have and needs the owner's approval on voice/text.

### 5. Time and state

A cheap way to make the hideout feel lived-in is to let it change over a session:

- **Lights:** already switchable. Add a slow warm-up/cool-down when switched, and make the trader bays a little
  dimmer than the mess.
- **The mess:** plates appear/disappear, a pot is on the stove at one point, the card game gains or loses a card.
  Purely local, resets when you leave.
- **The bunk:** the player's own bunk gets a blanket and a kit bag; other bunks stay made or unmade.
- **Weather/outside:** the mine mouth could show a faint change in light or rain sound, so the cave has an outside.
  This is a bigger art change; keep it for later.

### 6. Online hideouts (later)

The roadmap already has shared hideouts. When that happens, the same life pass should work with two players: trader
idles are local, doors and toys stay local, and only deliberate shared state (lights, jukebox) goes online. Do not
build networking for the life pass now.

## What not to do

- Do not fill the hideout with physics props. `kickables.gd` is the exception, not the rule.
- Do not animate every object. A room where everything moves reads as a screensaver, not a place.
- Do not add a hunger/thirst/cleanliness meter or a "the hideout gets dirty" system. That is gameplay, and the
  owner has not asked for it.
- Do not put new sounds on their own bus. Everything uses the existing World/Effects routing.
- Do not add always-on loops in the quiet areas. The bunker ambience is the bed; everything else is an event.

## Steps

Each step is a self-contained 0.32.x change, playable on its own. Stop after any step if the owner is happy.

- [ ] **0.32.0 - Market props and drips.** Counter clutter, stools, coats, a second dust volume, two drip emitters
      with ripple quads and a quiet drip one-shot, more litter. Files: `make_hideout.py`, `hideout_life.gd`,
      `tools/make_sounds.py` if a new drip is needed. Test: a smoke check that the life node still builds nothing
      headless, and that the new emitters are inside the market's bounds.
- [ ] **0.32.1 - Trader bodies, placed and idling.** See `docs/TRADER_MODELS_PLAN.md`. This is the step that changes
      how the room feels.
- [ ] **0.32.2 - Small events.** Radio station changes, TV ad break/test card, rare light flicker, range target sway,
      distant door clang. Files: `hideout_life.gd`, `hideout_toys.gd`, shaders. Test: events are timer-driven and
      can be forced in a smoke check.
- [ ] **0.32.3 - Sound layer.** Drips, generator wobble, creaks, muffled hangout radio, optional trader greeting.
      Files: `tools/make_sounds.py`, `hideout_life.gd`, `hideout_world.gd`. Test: every new sound is on the World bus
      and has a finite radius.
- [ ] **0.32.4 - Session state.** Dinner, plates, bunk blanket, bay lighting. Files: `hideout_world.gd`,
      `make_hideout.py`, `hideout_life.gd`. Test: state resets cleanly on re-entering the hideout and never touches
      the profile.
- [ ] **0.32.5 - Polish and perf pass.** Measure draw calls and frame time in the hideout; merge or instance
      anything that got expensive; ask the owner to walk it and pick what stays.

## Acceptance

- The hideout has at least three things moving or making a small sound wherever the player stands still for a
  minute, and none of them is distracting.
- The five trader stalls read as staffed from the spawn point, before the player reads a sign.
- A headless run and the smoke tests create none of it and stay green.
- No new network traffic, no new input, no change to stash/loadout/economy values.
- The owner walks it and says it feels alive, not busy.
