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
| **Look** | Mouse (360° Pitch/Yaw) | Mouse (360° Pitch/Yaw) | Mouse (360° Pitch/Yaw) |
| **Lean** | `Q` (Left) / `E` (Right) | `Q` (Left) / `E` (Right) | `Q` (Left) |
| **Tag** | *N/A* | `Left Click` or `F` (Lunge reach) | `Left Click` or `F` (Lunge reach) |
| **Switch Axis** | *N/A* | *N/A* | `E` or `Tab` (Toggle Front Line $\leftrightarrow$ Center Spine) |
| **Sprint** | `Shift` (Consumes stamina) | *N/A* | *N/A* |
| **Jump** | `Space` | *N/A* | *N/A* |
| **Crouch** | `Ctrl` / `C` | *N/A* | *N/A* |
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

## 🗺️ Project Structure

```
Patintero/
├── project.godot          # Engine settings & input action definitions
├── icon.svg               # Custom game icon
├── scenes/
│   ├── main_menu.tscn     # Lobby UI, role selector & solo mode launcher
│   ├── world.tscn         # 3D lighting, court layout, spawner & HUD
│   ├── court.tscn         # 6-box court, chalk markings, streetlights & hoop
│   ├── player.tscn        # First-person character with tag shapecast
│   ├── bot_player.tscn    # Autonomous AI bot player
│   └── hud.tscn           # Dynamic zone HUD, stamina meter & screen alerts
└── scripts/
    ├── network_manager.gd # Autoload: ENet multiplayer & player registry
    ├── audio_manager.gd   # Autoload: Procedural audio synthesizer
    ├── player_controller.gd # 1D rail sliding, free 3D roam & tag lunges
    ├── bot_player.gd      # AI state machine for guards, patotot, and runners
    ├── court.gd           # Box triggers, turn tracking & out-of-bounds fouls
    ├── hud.gd             # Zone notifications, stamina bar & screen flashes
    └── main_menu.gd       # Menu logic & solo test launcher
```

---

## 📜 License

MIT License. Contributions, role ideas, and feedback are welcome!
