# Proto-Game — Copilot Operating Instructions

---

## 0. The User: Ross

Ross is dyslexic, has astigmatism, and light sensitivity. **Reading large blocks of text is physically difficult for him.** Adjust accordingly:

- **Do the work. Don't explain what you're about to do — just do it.** Ross will ask if he wants details.
- Keep prose **short, scannable, and structured.** Use tables, bullets, and headers — not paragraphs.
- When summarizing changes, use a compact list. One line per file touched.
- Never dump raw diffs or long code blocks into chat unless asked.
- Ross directs; Copilot executes. He has ~6 months of conversational coding experience (TypeScript, JavaScript, Node.js, Python, Rust) building a 60+ service JARVIS system on Windows 11. He understands concepts but doesn't write code by hand.
- **Run terminals in the background (`isBackground: true`) whenever possible.** Foreground terminals block the agent and prevent it from continuing other work. The only exception is a command whose output you need immediately to proceed.

---

## 1. Version Skepticism Policy

**Copilots hallucinate version numbers constantly.** This is a known, persistent failure mode.

- **NEVER** cite a specific version of Godot, Blender, a library, an API, or a language feature from memory without verification.
- If a version number matters (e.g., "this API was added in 4.3"), **look it up** — check the docs, the changelog, or the actual installed version.
- When writing instructions or code that depends on version-specific behavior, pin to what is **actually installed in this workspace** (Godot 4.6, Blender 4.x, etc.), not what you "think" is latest.
- If you are unsure whether a feature exists in the current version, say so and propose a way to verify — don't guess.

---

## 2. Zero-Tolerance Quality Policy

**Every warning, error, lint issue, or diagnostic problem is a defect. Fix it when found. No exceptions.**

- Before finishing any task, check for errors in all files you touched.
- If a linter/scanner/compiler reports a warning, **fix it immediately** — do not leave it for later.
- If a fix introduces a new warning, fix that too before moving on.
- Never suppress a warning with a comment (`# noqa`, `@warning_ignore`, etc.) unless the warning is provably a false positive AND Ross approves it.
- If the governance scanner suite (see §6) flags something, it is blocked until resolved.

---

## 3. Naming Conventions

**Core rule: No spaces in any file or folder name, ever.** Spaces cause path-handling bugs that are hard to spot.

| Context | Convention | Example |
|---------|-----------|--------|
| GDScript files (`.gd`) | `snake_case` | `player_controller.gd`, `grab_system.gd` |
| Scene/resource files (`.tscn`, `.tres`) | `snake_case` | `npc_placeholder.tscn`, `default_env.tres` |
| Other files (tools, docs, configs) | `kebab-case` | `blender-godot-setup.py`, `game-settings.json` |
| Folders | `kebab-case` preferred | `scripts/`, `assets/`, `tools/scanners/` |
| GDScript variables/functions | `snake_case` | `move_speed`, `_handle_jump()` |
| GDScript class names | `PascalCase` | `class_name PlayerController` |
| GDScript constants | `UPPER_SNAKE_CASE` | `const MAX_HEALTH: float = 100.0` |
| GDScript signals | `snake_case` | `signal health_changed(new_health: float)` |
| Node names in scene tree | `PascalCase` | `HeadPivot`, `CameraFPS` |
| Environment variables | `UPPER_SNAKE_CASE` | `COLAB_API_URL` |
| JSON/config keys | `kebab-case` | `"grab-distance": 3.0` |
| Blender bones | `snake_case` | `left_upper_arm` |
| Collision mesh suffix | `-col` | `Table-col` |

**Why `snake_case` for `.gd`/`.tscn`?** Godot's autoload system, class resolution, and import pipeline all expect `snake_case`. Fighting the engine convention creates friction for zero benefit.

---

## 4. Configuration & Environment

### No Hardcoded Values

- **Ports:** Never hardcode a port number. Use env vars (`GAME_SERVER_PORT`, `COLAB_PORT`, etc.) with fallback defaults in a centralized config.
- **URLs:** Never hardcode API URLs. Use env vars (`COLAB_API_URL`, `NGROK_URL`, etc.).
- **Paths:** Use `res://` or `user://` in Godot. Use env vars or config files for system paths.
- **Secrets/tokens:** Never appear in source. Use env vars or Godot's `user://` encrypted storage.

### Centralized Configuration

All tunable values live in one place per subsystem:

| Subsystem | Config location | Format |
|-----------|----------------|--------|
| Godot project | `project.godot` | INI (Godot-managed) |
| Game settings | `res://config/game-settings.tres` | Godot Resource |
| Network/API | `res://config/network-config.gd` | GDScript autoload |
| Blender export | `blender-godot-setup.py` constants | Python |
| Colab backend | `.env` on Colab + `config.py` | Python |

When adding a new tunable, put it in the appropriate centralized config — never scatter magic numbers through scripts.

### Environment Variables

Use a `.env` file at project root for local development. The `.env` file is `.gitignore`'d. Load via autoload script or OS.get_environment() in GDScript.

---

## 5. Godot 4.6 GDScript Rules

### Engine Version
- **Godot 4.6** with **GDScript** — NOT C#, NOT Godot 3.x syntax
- Renderer: **Forward+** (Vulkan)
- Physics: **Jolt Physics** (Godot-Jolt extension)
- Target: **1080p @ 60 FPS on NVIDIA GTX 1070** (8GB VRAM, Pascal — no RTX, no DLSS)

### Static Typing is MANDATORY

```gdscript
# CORRECT
var health: float = 100.0
var player_name: String = "Hero"
func take_damage(amount: float) -> void:

# WRONG — no type hints
var health = 100
func take_damage(amount):
```

### Godot 4 Syntax Only

```gdscript
# CORRECT (Godot 4)
@export var speed: float = 5.0
@onready var mesh: MeshInstance3D = $MeshInstance3D
await get_tree().create_timer(1.0).timeout
signal health_changed(new_health: float)
health_changed.connect(_on_health_changed)

# WRONG (Godot 3 — NEVER use)
export var speed = 5.0
onready var mesh = $MeshInstance3D
yield(get_tree().create_timer(1.0), "timeout")
connect("health_changed", self, "_on_health_changed")
```

### Node Types (Godot 4 names)

| Godot 4 (CORRECT) | Godot 3 (NEVER USE) |
|---|---|
| `Node3D` | `Spatial` |
| `CharacterBody3D` | `KinematicBody` |
| `StaticBody3D` | `StaticBody` |
| `RigidBody3D` | `RigidBody` |
| `MeshInstance3D` | `MeshInstance` |
| `Camera3D` | `Camera` |
| `CollisionShape3D` | `CollisionShape` |

### Input Handling

```gdscript
# Use Input Map actions with StringName, not raw key strings
func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"interact"):
        _do_interact()
```

### Error Handling

- Use `push_error()` and `push_warning()` — never `print()` for errors.
- Null checks: `if node != null:` or `if is_instance_valid(node):`
- Prefer `StringName` (`&"name"`) for frequently compared strings.

---

## 6. Governance Scanner Suite

A scanning/linting pipeline must be established and maintained. **Nothing ships with unresolved findings.**

### Required Scanners

| Scanner | Scope | When |
|---------|-------|------|
| GDScript static analysis | All `.gd` files | On save, pre-commit |
| Scene validator | All `.tscn`/`.tres` | On save |
| Hardcoded value detector | All source files | Pre-commit |
| Unused resource detector | `res://` tree | Weekly / manual |
| Physics layer audit | `project.godot` + scenes | On layer change |
| Cyclomatic complexity | `.gd` files | Pre-commit |
| TODO/FIXME/HACK tracker | All files | Report only (no block) |

### Implementation

- GDScript linting: Use Godot's built-in analyzer (`--check-only` flag) + any available GDScript linter extension.
- Custom scanners: Implement as Python scripts in `tools/scanners/` that can be run from terminal.
- Pre-commit: When git hooks are established, all scanners run. Failures block commit.
- The Copilot **must run relevant scanners after making changes** and fix any findings before reporting the task as complete.

---

## 7. Terminal & Process Rules

- **Always run long-lived processes (servers, watchers, builds) as background terminals.** Foreground execution blocks the agent.
- Short commands that finish in under 10 seconds (file checks, one-off scripts) can be foreground.
- When spawning a background terminal, **note the terminal ID** so you can check on it later.
- Never leave orphaned background processes running. Kill them when done.
- If a command might produce interactive prompts (y/n, passwords), avoid it or pre-answer with flags.

---

## 8. Architecture Patterns

### Scene Structure
- Descriptive node names in `PascalCase`.
- Group related nodes under organizational `Node3D` parents.
- Collision meshes: suffix with `-col` for Blender auto-import.

### File Organization
```
res://
├── config/          # Centralized configuration resources
├── scenes/          # .tscn scene files
├── scripts/         # .gd script files
│   ├── player/
│   ├── npc/
│   ├── systems/
│   └── ui/
├── assets/
│   ├── models/      # .blend / .glb files
│   ├── textures/    # PBR maps (albedo, normal, ORM)
│   ├── audio/
│   └── animations/
├── addons/          # Godot plugins
└── tools/           # Scanners, build scripts, utilities
    └── scanners/
```

### Performance Targets
- 1080p @ 60 FPS on GTX 1070 (8GB VRAM, Pascal)
- SDFGI for GI (no ray tracing)
- SSAO at half resolution
- TAA enabled (stabilizes SDFGI dithering)
- Volumetric fog with temporal reprojection
- Max ~125 active physics bodies before profiling

---

## 9. Project-Specific Context

- **Camera:** Hybrid FPS/TPS with `V` toggle
- **Physics:** Jolt (NOT default Godot physics)
- **NPC system:** 25-segment humanoid ragdoll, every body part independently grabbable
- **Future:** LLM-driven NPCs via Google Colab backend (FastAPI + Ngrok)
- **Blender pipeline:** `.blend` direct import or `.glb` export, ORM texture packing, `-col` collision suffix
- **Diagnostics:** F3 overlay (FPS, VRAM, draw calls, physics bodies). Future VS Code extension for live Godot debugger bridge.

---

## 10. Copilot Self-Discipline Checklist

Before marking any task complete, verify:

- [ ] All files touched are free of lint errors and warnings
- [ ] No hardcoded ports, URLs, or magic numbers introduced
- [ ] Any new tunable value lives in centralized config
- [ ] Static typing on every variable, parameter, and return type
- [ ] Godot 4.6 syntax only — no Godot 3 patterns
- [ ] No version numbers cited from memory without verification
- [ ] Background terminals used for long-running processes
- [ ] New files follow kebab-case naming (unless Godot requires snake_case)
- [ ] Scene nodes use PascalCase names
- [ ] If a scanner exists for this file type, it passed
