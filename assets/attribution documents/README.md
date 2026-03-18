# Recoil

**Target Platforms:** Steam, iOS, Android  
**Engine:** Godot 4  
**Editor:** VS Code + Copilot

## Current Milestone

A playable prototype is implemented with:

- Main menu
- Level mode and endless mode
- Modular gun-controller architecture
- 4 enemy variants (basic, armored, shielded, armored+shielded)
- Score + persistent high scores
- Reward-ad placeholders and banner-ad placeholder
- Skin cycling for gun/bullet/trail colors
- Procedural endless difficulty scaling (burst cadence, enemy mix, alive caps)
- Platform-aware ad provider architecture (mock/mobile/steam stubs)

## Controls

- **Left side touch / Left mouse / Shift:** Slow time
- **Right side touch / Right mouse / Space:** Fire

## Core Gameplay Rules

- Gun constantly spins on Y-axis
- Spin direction flips every shot
- Gun has slight bounce motion
- Limited ammo
- +1 ammo on headshot
- Once per run, an extra-bullet rewarded ad can be claimed when empty

## Project Structure

- `scenes/ui/main_menu.tscn` — Main menu
- `scenes/main/game.tscn` — Gameplay scene
- `scenes/ui/hud.tscn` — HUD + touch zones
- `scenes/enemies/enemy.tscn` — Enemy prefab
- `scenes/player/bullet.tscn` — Bullet prefab
- `scripts/game/game_controller.gd` — Run flow, scoring, ads, high-score handling
- `scripts/game/enemy_spawner.gd` — Level/endless spawning logic
- `scripts/player/gun.gd` — Gun container orchestrating independent modules
- `scripts/player/components/*` — Spin, fire, ammo, bounce modules
- `scripts/core/*` — Session state, ad stub, skin palette, high-score persistence

## Running

1. Open/import project in Godot.
2. Run project (main scene is `scenes/ui/main_menu.tscn`).

## Notes

- Ad service now routes through provider stubs:
	- `scripts/ads/providers/mock_ad_provider.gd`
	- `scripts/ads/providers/mobile_ad_provider.gd`
	- `scripts/ads/providers/steam_ad_provider.gd`
- `scripts/ads/providers/mobile_ad_provider.gd` now includes plugin-ready call sites:
	- Singleton detection attempts: `GodotAdMob`, `AdMob`, `MobileAds`, `GodotMobileAds`
	- Rewarded methods fallback order: `show_rewarded_ad`, `show_rewarded`, `showRewarded`
	- Banner methods fallback order: `show_banner_ad`, `show_banner`, `showBanner`
	- Optional signal hooks: rewarded loaded/failed/closed/rewarded
- Mobile plugin config is now exposed in `project.godot` under `[recoil]`:
	- `ads/use_test_ids` (default `true`)
	- `ads/plugin_singleton` (optional explicit singleton name)
	- `ads/android_rewarded_unit_id`, `ads/ios_rewarded_unit_id`
	- `ads/android_banner_unit_id`, `ads/ios_banner_unit_id`
- Steam plugin config is now exposed in `project.godot` under `[recoil]`:
	- `ads/steam/plugin_singleton`
	- `ads/steam/rewarded_offer_id`
	- `ads/steam/banner_placement`
	- `ads/steam/fallback_rewarded_available`
	- `ads/steam/fallback_grants_reward`
- Production switch checklist:
	1. Install your mobile ads plugin and confirm its singleton name.
	2. Set `ads/plugin_singleton` if auto-detection does not pick it up.
	3. Set `ads/use_test_ids=false`.
	4. Fill real Android/iOS rewarded + banner unit IDs.
- Steam switch checklist:
	1. Install your Steam monetization plugin and confirm singleton name.
	2. Set `ads/steam/plugin_singleton` if needed.
	3. Set `ads/steam/rewarded_offer_id` to your live offer identifier.
	4. Optionally set `ads/steam/banner_placement` for overlay positioning.
- If your ad plugin uses different names, update only `mobile_ad_provider.gd`; game code should keep using `AdService.show_rewarded_ad(...)`, `show_banner_ad(...)`, and `hide_banner_ad(...)` unchanged.
- If your Steam plugin uses different names, update only `steam_ad_provider.gd`; game code remains unchanged.
- Endless mode uses procedural scaling in `scripts/game/enemy_spawner.gd` based on run time and kill count.
- Endless mode now also streams procedural map chunks around the player via `scripts/game/endless_chunk_manager.gd`.
- Chunking controls (chunk size, active radius, cleanup radius, floor height/thickness) are exported on `EndlessChunkManager` in `scenes/main/game.tscn`.

## License

Code: MIT — see `LICENSE`.

Third-party 3D assets are licensed separately under CC BY 4.0 and are documented in `THIRD_PARTY_NOTICES.md`.

## Third-Party Assets

This project uses Sketchfab assets under Creative Commons Attribution 4.0 International (CC BY 4.0):

- Proportional Low Poly Man | FREE Download | — Robin Butler — https://skfb.ly/6QV6X
- Bullet 9 mm — Y2JHBK — https://skfb.ly/6QSxx
- Smith & Wesson 500 Magnum — Ole Gunnar Isager — https://skfb.ly/6zQIx

See `THIRD_PARTY_NOTICES.md` for complete attribution details and license links.

## Naming + Typing Conventions

- Use `snake_case` for function, method, and variable names in GDScript.
- Use `PascalCase` for `class_name` declarations and enums.
- Prefer explicit types on stateful fields and exported tuning values.
- Prefer typed containers when possible (for example `Array[Node]`, `Dictionary[Vector2i, Node3D]`).
- When reading dynamic values (`Dictionary.get`, scene instantiation, node lookup), cast or annotate to avoid `Variant` inference warnings.
- Keep gameplay systems modular: isolate score logic, spawning logic, camera logic, and movement/recoil logic in separate scripts/helpers.
