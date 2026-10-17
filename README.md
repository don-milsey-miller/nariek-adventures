# Nariek Adventures

Nariek Adventures is an early-stage 3D online cooperative action RPG. The long-term direction combines the explorable world, characters, and quests of games such as *World of Warcraft* and *Anarchy Online* with fast, position-based hack-and-slash combat inspired by *Diablo*.

The project is deliberately starting small. Our first goal is a fun, understandable prototype—not a full MMO.

## Current prototype

The project currently contains a small 3D movement sandbox with:

- A third-person placeholder character
- Camera-relative WASD movement
- Double-tap-and-hold W running
- Mouse-controlled camera orbit and wheel zoom
- Jumping, gravity, and collision
- A greybox arena with several obstacles

The next milestone is the first combat interaction: one basic melee attack, a training target, health, and damage feedback. Networking will be added after the basic movement and combat feel good. The first multiplayer target will be two players in one small area.

## Technology

- Godot 4.7.2 Standard
- Typed GDScript
- 3D Forward+ renderer
- Git and GitHub for version control

## Getting started

1. Download and extract Godot 4.7.2 Standard.
2. Open Godot's Project Manager.
3. Select **Import**, then choose this repository's `project.godot` file.
4. Open the project and press **F6** or **F5** to run it.

The project opens directly into the movement sandbox. Controls are displayed in the upper-left corner.

## Project structure

```text
assets/          Art, models, textures, sound, and music
scenes/          Godot scenes, beginning with the main scene
scenes/player/   The reusable player scene
scripts/         Reusable typed GDScript source files
```

More folders will be added only when the project needs them.

## Development principles

- Prefer small playable improvements over large unfinished systems.
- Use placeholder assets until the gameplay is enjoyable.
- Keep scripts typed and focused on one responsibility.
- Make frequent, understandable Git commits.
- Treat the server as authoritative when multiplayer is introduced.
- Never commit credentials, private keys, tokens, or player data.

## Repository

<https://github.com/don-milsey-miller/nariek-adventures>

