# Project: HellBreaker
# Architect: User
# Lead Developer: Claude

## 1. Game Concept

### Title
**HellBreaker** — displayed in main menu, window title, and all player-facing branding.

### High-Level Vision
- *Genre:* Pixel-art **Rogue-like dungeon crawler** inspired by *The Binding of Isaac*, with co-op (1–4 players) and full single-player support.
- *Theme:* Dark, hell-themed aesthetic. Players escape Hell by climbing floor-by-floor.
- *Mood:* Pixel-art horror-lite — readable, colorful sprites with a grim atmosphere. Not gory, but unsettling.
- *Platforms:* Windows (Steam), Web, Android.

### Player Loop (Lobby → Run → Death → Lobby)
1. **Lobby (Hell hub):** Persistent social/prep area.
2. **Starting Area:** 5-second countdown when all players ready → teleport to dungeon.
3. **Dungeon Run:** Procedural floors. Clear rooms → climb. Each floor ends with a **boss** that spawns stairs.
4. **Death:** Run-loot lost. **Meta-currency** awarded (monsters killed + rooms cleared + highest floor).
5. **Back to Lobby:** Spend meta-currency on permanent unlocks/upgrades.

### Run Scaling with Player Count
- More players (1–4) → more enemies per room and harder stats.
- Drop rates scale to keep co-op fair (tuning TBD).

## 2. Lobby ("Hell" Hub)
- *Shop:* Buy run-prep consumables with meta-currency.
- *Skins:* Unlockable cosmetic character skins.
- *Runes:* Equippable items with active + passive bonuses (designed later).
- *Pets:* Companions with active + passive bonuses (designed later).
- *Starting Skills:* Unlockable abilities to begin a run with.
- *Stat Upgrades:* Permanent meta upgrades to core stats.
- *Starting Area:* 5-second all-present timer → dungeon teleport.

## 3. Dungeon Structure
- *Floors:* Procedurally generated, ends with a boss → stairs.
- *Rooms:* Must be cleared (all enemies dead) before progressing.
- *One-way entry rule:* Entering an uncleared room locks you in; others can still enter to help. Door re-opens on clear.
- *Room types:*
  - Combat (standard), Mini-boss, Boss (floor end)
  - Treasure, Shop (in-run), Minigame (co-op challenges)
  - **PvP minigame:** players fight; stats reset to pre-fight values on exit; winner gets a permanent run-stat-up.
- *Drops:* Monsters drop coins/keys on death. Room clear can also spawn a chest.

## 4. Character Stats
Two layers: **run-stats** (lost on death) and **meta-stats** (persistent lobby upgrades).
- Damage, Attack Speed, Attack Range, Movement Speed
- Critical Chance, Critical Multiplier
- Charisma *(affects shop prices / NPC interactions)*

## 5. Currencies
- *Coins (run):* Found in dungeon, spent at in-run shops. Lost on death.
- *Meta-Currency (lobby):* Earned on death → spent on permanent unlocks.

## 6. Enemies & Bosses
- *Normal enemies:* Skeleton, Hellhound, Cultist, Necromancer, Zombie, Blob.
- *Bosses:* Devil, Succubus, + more TBD.
- *Mini-bosses:* Tougher variants gating special rooms.

## 7. Front-End / UX
### Main Menu
- Play Single Player, Play Co-op, Settings, Exit.

### Co-op Lobby Screen
- Host creates a room; others join via **Steam invite** (desktop) or **6-digit room code** (all platforms).
- Shows connected players, ready states, chat.
- Host has a Start button; auto-start fires after 5-second all-ready timer.

## 8. Core Architecture Goals
- *Modular:* Keep Story, Combat, Networking, and Meta-progression as independent systems.
- *Data-driven:* All stats, enemies, items, rooms in **JSON files** or **Godot Resources**. Never hardcode content in GDScript.
- *Multiplayer model:* **Host-authoritative listen server.** Host owns game state. Clients send input/intent via RPC; never authoritative.
- *Cross-platform transport:* Abstract the network transport so ENet (desktop/Android) and WebSocket (Web) are swappable at startup. Steam social layer (GodotSteam) is desktop-only and optional.
- *Host Migration:* Plan a serializable run-state snapshot from day one. Full impl is a late-phase task.

## 9. Technical Stack
- *Engine:* Godot 4.6 (GL Compatibility renderer — works on Web, Android, Desktop)
- *Language:* GDScript
- *Multiplayer:* Godot High-Level MultiplayerAPI
  - **ENet** (`ENetMultiplayerPeer`) — Desktop + Android
  - **WebSocket** (`WebSocketMultiplayerPeer`) — Web
  - Platform detected at runtime; lobby uses the same game-logic RPC layer regardless.
- *Steam (desktop-only):* GodotSteam for friend invites, overlay, Steam relay transport. 6-digit room code is the fallback / cross-platform path.
- *Data Format:* JSON for narrative/loot tables/localization; `.tres` Resources for designer-tweakable configs (enemies, items, rooms).
- *Audio:* ElevenLabs MCP (`mcp__elevenlabs__*`) for SFX and ambient generation. Saved to `res://assets/audio/`.
- *Pixel Art:* PixelLab MCP (`mcp__pixellab__*`) for sprites, animations, tilesets. Saved to `res://assets/sprites/`.

## 10. Multiplayer & Networking Rules
- *Player count:* 1–4.
- *Connection:*
  1. Steam Friend Invite (desktop) — passes room code via Steam lobby metadata.
  2. Manual 6-digit room code — works on all platforms.
- *Syncing:* Use `@export` `MultiplayerSynchronizer` for continuous state (HP, position). Use `@rpc` for events (attack, open chest, room clear).
- *Authority:* Server (host peer_id = 1) owns enemies, room state, loot rolls, door state, currencies.
- *Difficulty scaling:* Server scales enemy count/stats from `multiplayer.get_peers().size()` at room load.
- *One-way doors:* Server-authoritative. Door opens only when server confirms room cleared.
- *PvP rooms:* Server snapshots HP/stats on entry, restores on exit, awards winner's stat-up.

## 11. Asset Pipeline
- *Sprites/animations:* Generate via PixelLab MCP → save under `res://assets/sprites/<category>/`.
- *SFX:* Generate via ElevenLabs MCP → save under `res://assets/audio/sfx/`.
- *Music:* `res://assets/audio/music/`.
- *Import settings (pixel art):* Filter = Nearest, Mipmaps off, correct PPU per asset class. Set globally in Project Settings → Import Defaults.
- *Tilesets:* PixelLab top-down tilesets for dungeon floors. Store raw PNGs; build `TileSet` resources in Godot.

### Upscaling Pipeline (image-upscaling skill)
Local Real-ESRGAN via `C:\tools\realesrgan-venv\Scripts\python.exe` — no API cost, GPU-accelerated (Vulkan), CPU fallback.

**Two modes:**
- `pixel` — nearest-neighbor, keeps pixel art crisp. Use for in-game sprites that are too low-res as source material.
- `anime` — `realesr-animevideov3` model, tuned for line art/flat colors. Use for menu art, Steam capsule art, loading screens.

**Command:**
```
C:\tools\realesrgan-venv\Scripts\python.exe C:\Users\tomko\.claude\skills\image-upscaling\scripts\upscale.py --mode anime --scale 4 --input "path/in.png" --output "path/out.png"
```
- Batch: add `--batch` flag and pass folder paths.
- Scale options: `2`, `3`, `4` (anime); any integer (pixel).

**When to use:**
- Menu/lobby background: generate ~320×180 via PixelLab → upscale 4× → 1280×720
- Steam capsule / store page art
- Loading screens, cutscene illustrations
- Do NOT upscale in-game sprites — Godot's Nearest filter handles runtime scaling.

## 12. Coding Standards for Claude
- *Node lifecycle:* Cache node references in `_ready()`. Never use `get_node()` / `$` paths in `_process()`.
- *Object pooling:* Pool projectiles, enemies, VFX — avoid `instantiate()` in hot paths.
- *Localization-ready:* Every player-facing string uses `tr("KEY_ID")` with a unique key. No raw strings in code.
- *Dialogue metadata:* Each line carries a `mood` field for future AI voice-over.
- *RNG determinism:* All shared random rolls happen on the server. Clients receive results only.
- *No hardcoded numbers:* All stats, drop chances, prices live in Resource files or JSON.
- *Null safety:* Check nodes with `is_instance_valid()` before access.
- *Signals over tight coupling:* Prefer `signal` + `connect()` to direct cross-node calls.

## 13. Folder Structure
```
res://
├── scenes/
│   ├── player/
│   ├── enemies/
│   ├── rooms/
│   ├── ui/
│   ├── lobby/
│   └── dungeon/
├── scripts/
│   ├── player/
│   ├── enemies/
│   ├── combat/
│   ├── rooms/
│   ├── ui/
│   ├── net/
│   └── data/
├── assets/
│   ├── sprites/
│   │   ├── characters/
│   │   ├── enemies/
│   │   ├── tiles/
│   │   ├── ui/
│   │   └── items/
│   ├── audio/
│   │   ├── sfx/
│   │   └── music/
│   └── fonts/
├── data/
│   ├── enemies/
│   ├── items/
│   ├── rooms/
│   └── stats/
└── addons/
```

## 14. Project Roadmap
### Phase 1 — Foundation (Single-Player Vertical Slice)
- [ ] Player controller + basic combat (top-down twin-stick style).
- [ ] Core stats system (Damage, Attack Speed, Attack Range, Movement Speed, Crit Chance, Crit Multiplier, Charisma).
- [ ] One enemy (Skeleton) with AI (chase + attack).
- [ ] One room template with door logic + clear-to-open rule.
- [ ] Procedural floor generator (linked rooms, single floor).
- [ ] Coin/key/chest pickups.
- [ ] One boss with stairs spawn.
- [ ] Data-driven content (JSON + Resource files).

### Phase 2 — Meta & Lobby
- [ ] Hell lobby hub scene.
- [ ] Meta-currency on death formula.
- [ ] Persistent save (skins, runes, pets, skills, upgrades).
- [ ] Lobby shop UI.
- [ ] 5-second starting-area teleport trigger.

### Phase 3 — Multiplayer
- [ ] ENet + WebSocket transport abstraction.
- [ ] 6-digit room code lobby.
- [ ] Server-authoritative combat/loot/rooms.
- [ ] Player-count enemy scaling.
- [ ] In-game chat.
- [ ] One-way door co-op join-in.

### Phase 4 — Steam Integration (Desktop)
- [ ] GodotSteam bootstrap (AppID 480 dev).
- [ ] Steam Friend Invite carrying room code.
- [ ] Steam overlay + presence.

### Phase 5 — Content Expansion
- [ ] Full enemy roster.
- [ ] Bosses (Devil, Succubus, +).
- [ ] Mini-bosses, treasure rooms, shops, minigames, PvP rooms.
- [ ] Runes + Pets system.
- [ ] Skins.

### Phase 6 — Polish & Endgame
- [ ] Host migration.
- [ ] Localization pass + ElevenLabs voice-over hooks.
- [ ] Story integration.
- [ ] Settings menu (audio, video, controls, accessibility).
- [ ] Balance pass.
