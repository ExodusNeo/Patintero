# 🏃 Patintero 3D: Street Line Tag (Larong Pinoy)

A first-person, asymmetrical multiplayer game based on **Patintero** (also known as *Tubigan* or *Harangang-Taga*), one of the most iconic traditional Philippine street games (*Larong Lahi*).

Built in **Godot 4.7** using GDScript and Godot's High-Level Multiplayer architecture.

---

## 🎯 Game Overview & Rules

In Patintero, two teams face off on a grid drawn with chalk or water on asphalt pavement:
* **Runners (*Tawid / Laro*):** Advance through all quadrants of the court to the back line, and then successfully return to the entrance (*"Home Run" / Puntos*) without being tagged.
* **Defenders (*Taya*):** Intercept and tag runners. Defenders must keep their feet strictly on their designated chalk lines—stepping into the boxes is an illegal foot-fault.
* **The Patotot (Captain):** The most versatile defender on the court. Controls the Front Line (Entrance) and can pivot onto the **Center Spine rail** that cuts vertically through the entire grid to execute pincer traps with cross guards.

---

## ✨ Features

* **First-Person Spatial Tension:** Limited field of view creates blind spots and genuine stealth-distraction tactics—guards must turn to scan lines, allowing sneaky runners to dash past their shoulder.
* **Physics-Enforced Line Movement:** Defenders are mathematically locked to their chalk lines' axes, guaranteeing adherence to the traditional "both feet on the line" rule while allowing full 360° mouse-look and reaching lunges.
* **Camera Leaning (`Q` / `E`):** Guards can lean and stretch their upper body across the line to tag runners without committing foot-faults.
* **Solo Practice Bot AI:** Intelligent AI state machines for both Defenders (mirroring runner movement and lunging) and Runners (feinting, baiting, and dashing through gaps), allowing single-player practice anytime.
* **Procedural Audio Engine:** Lightweight built-in sound synthesis for asphalt footsteps, slipper slaps (*tsinelas*), referee whistles (*pito*), tag slaps, and home-run victory jingles.
* **High-Level ENet Networking:** Ready for LAN and online room-code multiplayer using Godot 4's `MultiplayerSpawner` and `MultiplayerSynchronizer`.

---

## 🎮 Controls

| Action | Runner (*Tawid*) | Line Guard (*Bantay Linya*) | Patotot (*Captain*) |
| :--- | :--- | :--- | :--- |
| **Move** | `W` `A` `S` `D` (Free 3D) | `A` / `D` (Slide along line) | `A` / `D` (Front Line) or `W` / `S` (Center Spine) |
| **Look** | Mouse / Right Stick (360°) | Mouse / Right Stick (360°) | Mouse / Right Stick (360°) |
| **Lean** | `Q` (Left) / `E` (Right) | `Q` (Left) / `E` (Right) | `Q` (Left) |
| **Tag** | *N/A* | `Left Click` or `F` (Lunge reach) | `Left Click` or `F` (Lunge reach) |
| **Switch Axis** | *N/A* | *N/A* | `E` or `Tab` (Toggle Front Line $\leftrightarrow$ Center Spine) |
| **Sprint** | `Shift` (Consumes stamina) | *N/A* | *N/A* |
| **Jump** | `Space` | *N/A* | *N/A* |
| **Crouch / Slide** | `Ctrl` / `C` | *N/A* | *N/A* |
| **Toggle Mouse** | `ESC` | `ESC` | `ESC` |

---

## 🚀 How to Run the Project

1. Download and install **[Godot 4.7+](https://godotengine.org/)**.
2. Clone or download this repository:
   ```bash
   git clone https://github.com/YOUR_USERNAME/Patintero3D.git
   ```
3. Open Godot Project Manager, click **"Import"**, navigate to this folder, and select `project.godot`.
4. Click **"Import & Edit"**.
5. Press **F5** to run the project!

---

## 🏛️ Architecture & Coding Style Guide (Component-Based Composition)

To maintain clean, readable, and maintainable code, **we strictly forbid monolithic 500+ line scripts**. Every entity (such as the Player or Bot) decomposes distinct responsibilities into modular component scripts housed inside a `components/` subfolder.

```
src/entities/player/
├── player.tscn                  # Visual hierarchy & node tree
├── player_controller.gd         # Coordinator (< 200 lines)
└── components/
    ├── player_movement.gd       # 3D locomotion, 1D/2D line rails, gravity & sliding
    ├── player_camera.gd         # Mouse/joypad look, headbob, lean roll & dynamic FOV
    ├── player_skills.gd         # Sprint slide, lateral jukes, spine burst & stamina
    ├── player_tagger.gd         # Tag lunges, shapecast hit detection, whiff recovery
    └── player_audio.gd          # Footstep cadence, exhaustion breathing & exertion SFX
```

### 🧩 Core Architectural Rules

1. **Strict Line Limit (< 200 Lines Per File):**
   - Individual script files should remain focused and typically not exceed 200 lines. If a script grows larger, split out new sub-behaviors or mechanics into dedicated component nodes.

2. **Coordinator Pattern:**
   - The root entity script (e.g. `player_controller.gd` or `bot_player.gd`) acts solely as a **Coordinator**.
   - It instantiates and wires components, forwards lifecycle hooks (`_ready()`, `_physics_process()`, `_unhandled_input()`), and acts as the public interface for external systems like `HUD`, `Court`, and `MultiplayerSynchronizer`.

3. **Separation of Concerns:**
   - **Movement & Physics:** Handles kinematic integration (`move_and_slide`), rail clamping, friction, and slope/axis constraints.
   - **Camera & View:** Manages view rotation (pitch/yaw clamp), lean tweens, bobbing, and FOV adjustments.
   - **Skills & Abilities:** Owns stamina deduction, cooldown timers, burst vectors, and evasion state.
   - **Combat & Tagging:** Owns shapecasts, reach calculations, whiff stun penalties, and arm swing animations.
   - **Audio:** Handles timing and triggers for footsteps, heartbeat, and audio alerts without mixing audio logic into physics loops.
   - **AI State Machines:** Separated by role (`bot_guard_ai.gd` vs `bot_runner_ai.gd`) with distinct tracking and decision trees.

4. **Preloading Over Bare Type Hints:**
   - Use `const ComponentScript = preload("res://path/to/component.gd")` instead of global `class_name` annotations across interdependent components to avoid circular dependencies and Godot editor cache issues.

5. **External API Preservation:**
   - External systems (`HUD`, `Court`, `NetworkManager`) should not need to reach deep into private sub-components. The Coordinator exposes public getters or properties (e.g. `stamina`, `current_zone`, `is_tagged`), keeping components encapsulated.

---

## 🗺️ Project Structure

```
Patintero/
├── project.godot                     # Engine configuration & input mappings
├── icon.svg                          # Custom game icon
├── src/
│   ├── arena/
│   │   ├── court/
│   │   │   ├── court.tscn            # 6-box court, chalk markings, bounds triggers
│   │   │   └── court.gd              # Zone tracking, foul detection & scoring
│   │   ├── scenery/
│   │   │   ├── sari_sari_store.tscn  # Street corner sari-sari store
│   │   │   ├── tricycle.tscn         # Authentic Filipino tricycle prop
│   │   │   ├── utility_poles.tscn    # Tangled wire utility poles & street lights
│   │   │   └── neighborhood_props.tscn
│   │   └── world/
│   │       ├── world.tscn            # Sun, sky environment, court & UI wrapper
│   │       └── world.gd              # Game flow, role assignments & spawner
│   ├── assets/
│   │   └── models/neighborhood/      # 3D assets (houses, street, trees, vehicles)
│   ├── core/
│   │   ├── network_manager.gd        # Autoload: ENet server/client room connection
│   │   ├── audio_manager.gd          # Autoload: Procedural audio synthesis & SFX
│   │   └── game_manager.gd           # Autoload: Match state, timers & rules
│   ├── entities/
│   │   ├── player/
│   │   │   ├── player.tscn           # CharacterBody3D node tree
│   │   │   ├── player_controller.gd  # Coordinator script (< 180 lines)
│   │   │   └── components/
│   │   │       ├── player_movement.gd # Locomotion & rail physics
│   │   │       ├── player_camera.gd   # View, mouse look, joypad & lean
│   │   │       ├── player_skills.gd   # Slide, juke, stamina & burst
│   │   │       ├── player_tagger.gd   # Tag lunge, reach & whiff stun
│   │   │       └── player_audio.gd    # Footstep cadence & breathing
│   │   └── bot/
│   │       ├── bot_player.tscn       # Bot CharacterBody3D node tree
│   │       ├── bot_player.gd         # Bot Coordinator script (< 110 lines)
│   │       └── components/
│   │           ├── bot_guard_ai.gd   # Line guard reaction & patrol AI
│   │           ├── bot_runner_ai.gd  # Runner probing, feinting & dash AI
│   │           └── bot_tagger.gd     # Bot tag detection, reach & stumbles
│   ├── shaders/
│   │   └── chalk_line.gdshader       # Dynamic chalk line shader with roughness
│   └── ui/
│       ├── hud/
│       │   ├── hud.tscn              # Dynamic zone notifications & stamina bar
│       │   └── hud.gd                # UI updates & screen flashes
│       └── menu/
│           ├── main_menu.tscn        # Matchmaking, role select & solo test
│           └── main_menu.gd          # Menu controller
└── addons/                           # Engine plugins (godot-ai MCP, etc.)
```

---

## 📜 License

MIT License. Contributions, role ideas, and feedback are welcome!
