# Deepcore Miner

A grindy, tap-and-idle mining game for iPhone, built with SwiftUI.
It is designed to take **about 2–3 months** to beat, and to work on a foldable phone both **folded** and **unfolded**.

## The game

- **Dig** through 300 layers across 12 biomes (Topsoil → Crystal Caves → Magma Rifts → … → The Core).
- **Tap** to break blocks. Each block drops an ore (common, uncommon or rare) worth coins.
- **Upgrade**: Drill Power (tap damage), Mining Bots (auto damage, also works offline), Ore Refinery (ore value), Sharp Bits (crit chance).
- **Bosses** guard the end of every biome (every 25 layers). You get 30 seconds to break them. Beating a boss for the first time earns a **Relic**: x1.45 damage and value, permanently.
- **Prestige** ("Surface & Smelt") from depth 50 on: reset your run for **Core Shards**, +5% damage and value each, permanently. Shards stack across every prestige.
- **Offline**: bots keep digging at 75% speed for up to 16 hours while the app is closed.
- **Auto Clicker**: taps for you at 1, 2, 5, 10 or 20 taps/sec while the game is open (toggle it on the mine or in Upgrades).
- **Ore Codex & Mastery**: collect all 36 ores; collect 1,000 of one to master it (+1% ore value each).
- **Achievements**: 32 goals, each +2% damage and value forever.
- **Boss Overclock**: upgrade that adds +2s to boss timers (up to +30s).
- **Prestige hint**: after losing to a boss twice, the game suggests prestiging.
- Past depth 300 the shaft keeps going (endless mode).

### Layouts
- **Folded / narrow screen**: the mine is on top, with a tabbed panel (Upgrades / Shaft / Stats) underneath, for one-handed play.
- **Unfolded / wide screen (≥ 600 pt)**: three columns: shaft map | mine | upgrades & stats.

## Run it on your iPhone

Requirements: a Mac with **Xcode 16 or newer**, an iPhone on **iOS 17+**, and a USB cable.

1. Clone this repo on your Mac and open `DeepcoreMiner/DeepcoreMiner.xcodeproj`.
2. Click the **DeepcoreMiner** project in the sidebar, then the **DeepcoreMiner** target, then **Signing & Capabilities**:
   - **Team**: pick your Apple ID. If none is listed, add it under Xcode → Settings → Accounts. A free account works.
   - Team and Bundle Identifier (`com.nicholaswilder.deepcoreminer`) are already set for the owner's Personal Team. Anyone else should pick their own team and a unique bundle ID.
   - A free Apple ID allows only 3 of your own apps on a phone at once; delete one if the install fails with "maximum number of installed apps".
3. Plug in the iPhone and pick it as the run destination at the top of Xcode.
4. On the iPhone, turn on Settings → Privacy & Security → **Developer Mode** (the phone restarts).
5. Press **Run** (▶). The first time, the phone may ask you to trust the developer: Settings → General → VPN & Device Management.

> With a free Apple ID the app expires after 7 days. Just press Run again in Xcode to reinstall; your save is kept.

To test both layouts without the phone, run it in the iPhone simulator (narrow) and an iPad simulator, or rotate to landscape (wide).

## Tuning the grind

All pacing numbers live in `DeepcoreMiner/DeepcoreMiner/Model/Balance.swift`.
`tools/balance_sim.py` simulates a player tapping 40 minutes a day and idling the rest:

```
python3 tools/balance_sim.py             # current tuning: Core on ~day 62
python3 tools/balance_sim.py g0=1.17     # steeper HP growth → longer game
```

Keep the sim and `Balance.swift` in sync when you change numbers.

## Project layout

```
DeepcoreMiner/
  DeepcoreMiner.xcodeproj
  DeepcoreMiner/
    DeepcoreMinerApp.swift
    Model/    Balance, Biomes, Upgrades, GameCore (rules + save), GameModel (loop, saving, effects)
    Views/    ContentView (adaptive layout), MineView, PanelViews (upgrades, shaft, stats, sheets)
    Support/  Haptics, number formatting
tools/balance_sim.py
```

---

# Cubefire

An original blocky, pixel-textured first-person arena shooter (SceneKit + SwiftUI), in `Cubefire/`.

- **3 voxel arenas** (Crate Yard, Neon Temple, Sky Fortress) that unlock as you level up.
- **Endless waves**: Grunts (shoot), Rushers (charge and melee), Brutes (burst fire), and the **Cube King** boss every 5th wave.
- **5 weapons**: Blaster, Scatter Cannon, Pulse Rifle, Railgun (pierces), Cube Launcher (splash). Buy them, equip up to 3, and upgrade each to level 10.
- **Progression**: XP and levels, coins, best wave per arena, headshots (x1.8 damage).
- **Controls**: left side is a floating joystick; drag the right side to look; hold the fire button (drag it to aim while firing); jump, reload, and weapon buttons.

Open `Cubefire/Cubefire.xcodeproj` and run it the same way as Deepcore Miner. Plays best in landscape or with the phone unfolded.
