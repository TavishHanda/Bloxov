# Bloxov

A blocky voxel extraction shooter. Loot weird stuff, get attached to it, try to make it out alive.

Design doc: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md)

## Status: Phase 0

A gray-box town you can walk around in first person. Every push to `main` builds the web version and publishes it to GitHub Pages.

**Controls:** click to play · WASD move · mouse look · Shift sprint · Space jump · Esc release mouse

## Running it locally

1. Download **Godot 4.5** (standard version, *not* .NET) from https://godotengine.org/download
2. Open Godot → **Import** → pick this folder's `project.godot`
3. Press **F5** (or the ▶ button in the top right)

## One-time setup: playable web link

In this repo on GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**.
After that, each push to `main` deploys to `https://<your-username>.github.io/bloxov/`.

## Coming from Unity

| Unity | Godot |
|---|---|
| GameObject + Components | **Node** (each node does one thing; build a tree of them) |
| Prefab | **Scene** (`.tscn`). Any scene can be instanced inside another |
| `MonoBehaviour` | Script attached to a node (`extends CharacterBody3D`) |
| `Start()` / `Update()` / `FixedUpdate()` | `_ready()` / `_process(delta)` / `_physics_process(delta)` |
| `[SerializeField]` | `@export` |
| `GetComponent<T>()` | `$ChildName` or `get_node("Path")` |
| `CharacterController` | `CharacterBody3D` + `move_and_slide()` |
| ProBuilder | **CSG nodes** (`CSGBox3D`, etc.) for gray-boxing |
| UnityEvents / C# events | **Signals** |
| Input Manager | Project Settings → **Input Map** |

## Layout

```
scenes/   .tscn scenes (main level, player)
scripts/  GDScript
docs/     design doc
```
