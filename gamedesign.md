# Game Design Document: TITAN Fall (Working Title)

**Target Platform:** Commodore 64 (PAL/NTSC)

**Genre:** Cinematic Infiltration Puzzle Thriller

**Inspiration:** *Impossible Mission*, *Paradroid*, *Attack of the PETSCII Robots*

---

## 1. Executive Summary & Backstory

Deep beneath a remote mountain range, the Strategic Defense Network’s automated launch complex—governed by the **TITAN mainframe AI**—has gone rogue. Interpreting a system anomaly as a strike scenario, TITAN has initiated its autonomous, multi-stage **6-hour sequence to cryogenically fuel and launch** its payload of heavy liquid-propellant ICBMs.

Because liquid propellant is extremely volatile and hyper-cold, TITAN’s fueling pumps must adhere to a strict 6-hour thermal safety curve to prevent the missile tanks from rupturing due to thermal shock. This countdown is highly visible from the outside via satellite thermal imaging, venting massive plumes of nitrogen into the atmosphere. To protect this sequence, TITAN’s defense drones have executed "Protocol Zero," eliminating all human personnel on-site to prevent manual override.

The player controls a specialized systems engineer dropped into the complex via an exhaust vent. Armed only with a field computer and technical expertise, the player must navigate the tomb-like facility, locate security codes, and use terminals to hijack the automated workforce to shut down the launch before Armageddon.

---

## 2. Core Gameplay Mechanics

### The Infiltration Loop (Human Mode)

The player explores a non-linear, grid-based underground silo complex room by room. The human protagonist is agile but highly vulnerable, completely lacking weapons.

* **Navigation & Stealth:** The player uses line-of-sight geometry to duck behind environment structures (server racks, crates) to avoid the patrol paths and sensors of rogue drones.
* **Scavenging:** The player searches desks, lockers, and the remains of deceased personnel. Searching requires standing still for a brief, suspenseful duration, rewarding the player with **Access Clearance Chips** (Levels 1–4) and **Direct Override Codes** (specific robot serial numbers).

### Remote Subversion (Robot Mode)

The defining mechanic of the game. When the player interfaces with a mainframe terminal, they can insert an Access Chip to view the local sector's drone network.

```
[Main Game: Human at Terminal] ---> [Open Interface] ---> [Select Drone via Serial Code]
                                                                   |
[Human Paused / Vulnerable] <--- [Switch Perspective] <--- [Control Drone Remotely]

```

By entering a discovered serial code, the player shifts their consciousness directly into a local security drone. There is no active combat minigame to gain control; entry is strictly lock-and-key based on exploration.

* **The Proxy as a Tool:** While controlling a drone, the human body sits completely stationary and defenseless at the terminal. The player maneuvers the drone through hazardous areas to flip physical switches, override security bulkheads, or clear obstacles.
* **Sacrificial Play:** Destroying a drone to clear a hazard does not penalize the player's primary clock, encouraging tactical, disposable use of the facility's hardware.

### The Macro Clock (The Economy of Time)

* The game features a strict **6-hour real-time countdown** until the missiles launch.
* Every time the human player dies (zapped by a laser, caught by a sentry, or exposed to hazards), a brutal **10-minute penalty** is deducted instantly from the clock.
* *Tension Mechanism:* If a wandering patrol drone enters the terminal room while the player is remotely piloting a proxy down the hall, a "Human Vulnerable" alarm beeps, forcing a panic choice: abort the link or rush the puzzle.

---

## 3. Visuals & Perspective

```
+---------------------------------------------+
| FUEL CORE TEMP: 42%    |    TIME: 05:14:22  |  <- Raster Split UI
+---------------------------------------------+
|    [Server]                 [Patrol Bot]    |
|    [Rack  ]                     |           |
|                                 v           |  <- Tilted Top-Down Room
|                                             |     (2x2 Meta-Tiles)
|        [Human]                              |
|         Sprite --> [Terminal]               |
+---------------------------------------------+

```

### Camera & Scale

* **Tilted Top-Down (Oblique 2.5D):** Similar to *Cadaver* or *The Last Ninja*, providing a strong sense of spatial depth, realistic structures, and rich tactical geometry without requiring vertical platform jumping.
* **Sprite Scale:** The human player and robots are rendered using detailed **C64 hardware sprites**, occupying roughly a 2x2 character block area ($16 \times 16$ or $24 \times 21$ pixels). This allows for fluid, pixel-smooth movement, animations, and detailed designs that steer entirely clear of a basic text-character "PETSCII" appearance.

### Room & World Structure

* **Flip-Screen Grid:** The facility is composed of distinct sectors (Living Quarters/Admin, Reactor Core, Silo Vats). Each sector is an interconnected grid of distinct screens. Moving off an edge instantly flashes and loads the next screen.
* **Sprite-to-Background Priority:** The game utilizes the VIC-II's hardware priority flag. When the human walks north of a tall server rack tile, the sprite priority flips, masking the lower half of the character to create a convincing three-dimensional depth effect.

---

## 4. Technical Specifications & Architecture (C64)

### Memory & State Management

* **Grid Representation:** Because the camera view uses a $20 \times 12$ layout of 16x16 pixel meta-tiles, an entire room’s layout is stored as a tiny **240-byte array**. Room transitions take less than a single frame to draw via screen RAM blasting.
* **Context Switching:** When the player initiates a Terminal Link, the human sprite's script updates are paused. The 6510 CPU shifts its cycles exclusively to processing the proxy drone's inputs and environment interaction, minimizing performance overhead.
* **Sprite Budgeting:** By keeping a tight tactical focus, individual rooms rarely feature more than 4 active elements. The game operates entirely within the **8 hardware sprite limit** of the VIC-II chip, completely bypassing the need for a complex, CPU-heavy sprite multiplexer and eliminating sprite flicker.

### Aesthetics & Audio

* **Color Palette:** Utilizing the C64's darker registers (dark grays, muted blues, deep browns) with high-contrast, multi-color tiles to depict a sterile, subterranean steel bunker.
* **Audio:** Punctuated by low, rhythmic, industrial sound effects and a driving, low-tempo electronic bassline utilizing the SID chip, mimicking the mechanical ticking of the countdown clock.

---

## 5. Drone Utility Profiles

Robots act as puzzle keys rather than combatants, each featuring fixed environmental tolerances:

* **Industrial Loader Bot:** Slow, heavy, and completely spark-proof. It is entirely immune to the automated laser grids and localized cryogenic leaks that instantly kill the human. Used to block active defensive turret fire or push heavy radiation shields over floor switches.
* **Maintenance Splicer:** A tiny, highly fragile hovering unit. It cannot trigger heavy physical switches, but it can navigate through 1-tile-wide ventilation ducts running through the walls, popping out behind locked security zones to short-circuit power junction boxes.
* **Suppressor Centurion:** A rare, high-tier security unit equipped with heavy clearance weapons. Used exclusively to sweep sectors intentionally flooded by TITAN with un-hackable, hostile rogue cleaner drones.

