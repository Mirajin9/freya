# Freya

Freya is a Mirajin prequel action RPG built in Godot. This public source study covers how the current opening handles movement and the player's session.

- [Movement controller](pawn.gd) handles acceleration, braking, on-the-spot turns, and movement on slopes.
- [Body lean](locomotion_lean.gd) responds to acceleration before the [foot solver](foot_placement.gd) plants or lifts each foot.
- [World loop](src/chapters/opening/application/world_loop.gd) shows how the opening orders simulation and presentation.
- [Checkpoint validation](src/chapters/opening/persistence/checkpoint_rules.gd) and [JSON storage](src/framework/persistence/json_save_store.gd) separate game state from file I/O.
- [HUD policy](src/chapters/opening/presentation/hud_policy.gd) controls when the chapter overlay and held items appear.

These are selected GDScript files from the working game. To run the opening, they need the surrounding Godot project, rig, audio, terrain, and story data.

The original code in this repository is released under the [MIT license](LICENSE).
