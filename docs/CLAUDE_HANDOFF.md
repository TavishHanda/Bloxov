# Claude Code context handoff

What the owner's Claude Code sessions knew that isn't written down in the repo. Recovered on 2026-11-04 from
Claude Code's session store (`~/.claude/projects/<project path, with separators as dashes>`, found on the owner's PC):
five sessions from 2026-10-07 to
2026-11-01, 53.7 MB of transcripts, about 122 KB once tool output is stripped out. The raw transcripts stayed off the
repo; this file is the digest.

Read this next to `CLAUDE.md` (rules) and `docs/DEV_HANDOFF.md` (code map). This is the part neither covers: why
things were built the way they were, how the owner works, and what was measured rather than guessed.

---

## How the work was split

The owner ran **two Claude Code sessions on the same checkout**: one for art (Blender, models, textures) and one for
game code. They did not talk to each other; the owner relayed messages between them ("tell the other session…") and
pushed with **GitHub Desktop**. That explains the history: art commits and code commits arriving separately, with the
code session pulling and rebasing before continuing.

Practical consequences:

- The art session built models **by driving the owner's open Blender** through an MCP extension (`mcp__Blender__…`),
  with a headless fallback: `"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe" --background …`.
  The owner was warned, once, that the extension runs unsandboxed Python as their user. That is expected here; don't
  re-litigate it, but don't run anything outside the project either.
- The owner pushes. When a change is ready, give them a **file list and a commit message** rather than trying to
  commit for them. (In this repo, OpenCode commits directly; that's fine too.)
- Both sessions may edit the same files within minutes. Pull/rebase before starting, as `CLAUDE.md` says.

## How the owner works

- Short, lowercase replies: "yea", "hmm", "its good but…". They react to **what they can see**, not to architecture.
  Offer two or three concrete options with a recommendation instead of open-ended questions.
- They play the web build and report very specific defects ("the top of the crate is glitching with the four grey
  corners and the green at the top", "the roof is broken, you can see through it"). Reproduce, find the real cause,
  explain it in one plain sentence, then fix.
- They explicitly asked to be told before **big or structural changes** ("any insane big changes please tell me
  first"). Gameplay changes need a proposal first (`CLAUDE.md`); bug fixes restoring intended behaviour are fine.
- They like seeing **before/after renders** and short screen captures. `tools/render_*.gd`, `tools/*_view.gd` and the
  in-app browser preview are how the previous sessions showed work. Use them.
- They use GitHub Desktop; their commits sometimes land under the GitHub no-reply address instead of
  `tavishhanda@hotmail.com`. It still links to the account. Not worth fixing unless they ask.

## Art direction: the decisions and why

The pipeline itself is in `docs/ART_SPEC.md` §1 and `docs/DEV_HANDOFF.md` (models section). What matters here is the
taste, which is only in the transcripts:

- **Military / post-collapse. Not fantasy, not cartoony, not "goofy".** The owner rejected two crate designs in a row
  on exactly this ground: a wooden fantasy crate, then an olive "military" version that still read as toy-like.
- **The crate became a hard transport case, long and low: 1.1 × 0.5 × 0.6 m.** At 1.0 × 0.75 × 0.7 it read as "a cube
  with a lid" (the owner: "its too square"). The fix was proportions, not detail. The owner knowingly accepted that a
  0.5 m case is **not usable as low cover**; rocks, walls and cars do that job.
- **Small emblems fail at 16 px/m.** The lid gives about 7 × 6 pixels. A skull read clearly; a star came out mushy and
  was dropped. Front lettering ("B-07") was removed for the same reason. Judge art at player distance, not zoomed in.
- **Factions must read at a glance:** Scavs are mismatched civilians, PMCs are tan/green kit, Raiders are dark with a
  red armband and skull/gas masks. The PMC model is for **real players only**; AI "PMCs" are Raiders.
- **The Python build scripts are the source of truth**, not hand edits in `.blend`. `REGENERATE_TEXTURE = False` keeps
  hand-painted textures.
- **Unresolved: character height.** The models are ~2.05 m (inherited from the old box Scav) but `player.tscn`'s
  capsule is 1.8 m. Scaling them changes hitboxes, so it stayed a gameplay call for the owner. Nobody has decided.

## Performance: what was measured

The 2026-10-24 pass (0.18.11) established the shape of all later optimisation work, and it is why 0.29.x focused on
loading, shaders and draw calls:

- A fixed-spawn frame test on the real map was used instead of guessing. **Draw calls dominate, not script time**, on
  web and phones.
- Busiest view: **3,413 draw calls**. Shadows were ~40–50% of them. Doors alone were ~106 visible at 4 calls each, and
  loot crates ~79 at 4–5, both with no distance cutoff.
- Fix: doors stop drawing past **150 m**, loot containers past **100 m** (`PixelModel.hide_beyond`). Worst view went
  to **2,426** calls (−29%), frame time 3.16 → 2.86 ms on the owner's PC.
- CPU was already cheap: 32 scavs cost ~**1.6 ms/frame**; the suspected group lookups made no measurable difference and
  the code was deliberately left alone.
- Deferred at the time, still worth remembering: shortening shadow distance (biggest remaining win, but visible),
  graphics presets (Low/Medium/High, Low on phones/web), and merging each door model's 3–4 materials (an art job).

## Release and marketing state

- The target release is framed as the **web beta** at **bloxov.com** (the site moved there in 0.25.x per `CHANGELOG`).
  The owner wants "web beta" said out loud on the site, the trailer and store copy.
- A **32-second trailer** was produced on 2026-11-01 from real gameplay capture (Godot's movie writer, 1080p30):
  title card, stash, hideout, drone shot, scav patrol, a real fight, an extract, and the game's own
  "KILLED IN ACTION — LOST $14,300" screen. Audio mixed to about −16 LUFS.
  - Title: **"Bloxov: No Man's Land | Web Beta Trailer"**.
  - A hazard-yellow **WEB BETA** tag sits above the logo on the title and end cards (frame 0 is the title card, so it
    is also the thumbnail).
  - A YouTube description was drafted from `README.md`; it leads with the play link and the tagline.
  - Captions use the game's Jersey and Silkscreen fonts and the Ammo Can palette. Silkscreen's **W is 5 px wide and
    reads as a squiggle** — that is why the "WEB BETA" tag and the end-card line use Jersey instead.
- `brag-output/` was the trailer workspace. It is now **gitignored and empty**: the video, poster, storyboard and share
  copy were discarded, so the trailers exist only outside the repo (or nowhere). If they are wanted again, they have to
  be re-recorded; the method is described in the transcripts, not in code.

## Loose ends the owner left open

- **Inventory/stash restyle.** The owner: "the whole inventory/stash look needs a bit of an update". They started to ask
  whether to keep polishing the inventory until happy, then interrupted the session. Nothing was decided.
- **Phone tutorial.** Touch controls are done (0.29.9/0.29.10); the tutorial still skips phones because its wording is
  about mouse and keys. `BACKLOG.md` lists it as the remaining touch job.
- **Live playtest of the big map.** Still never done properly: one-at-a-time extraction, downed timer expiring, squads
  spawning together, AI on the big map.
- **Sound 2.0 is built** (0.30.0-0.30.3); only the optional 0.30.4 hi-fi pass is left, and it waits for the owner to
  pick sounds after listening. The 0.30.2 bunker ambience is approved (owner, 2026-11-04: "ambience sounds good").
- **Stash update** is the gate before the beta/Steam release: PvE and PvP modes, the current stash becoming the solo
  stash, and a server-owned online stash with real PvP accounts (PvE stays accountless) and a database. It also
  unblocks bans and finishes the anti-cheat story. **Plan: `docs/archive/STASH_UPDATE_PLAN.md`** (written 2026-11-04, plan
  only). The owner said they do not want to build it next, but wanted an in-depth plan; the plan's §15 lists the
  decisions still open.

## Environment facts worth keeping

- Local Godot for testing: `%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
  The previous sessions ran `--headless --import` and the smoke test from here.
- Local Blender: `C:\Program Files\Blender Foundation\Blender 5.2\blender.exe`.
- `docs/ROADMAP.md`'s "Where we are" line is stale (it still says 0.18.12). `CHANGELOG.md` and `project.godot` are the
  truth.

---

Source sessions (for anyone who wants to re-mine them): `f71376df` (2026-10-07 → 10-09, art pipeline, crate, Scav,
PMC, Raider), `9ae275a4` (2026-10-24, performance), `36df8b83` / `3a21fca5` (2026-10-12, tooling dead ends),
`67ff42a7` (2026-10-31 → 11-01, trailer).
