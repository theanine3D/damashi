# Damashi — a Garry's Mod gamemode

A Katamari-inspired arena gamemode. Every player rolls a **sticky ball** that
can attach smaller props around the scene to its surface and roll around with
them. Every absorbed prop makes the ball bigger, letting it pick up bigger and
bigger things — cans, crates, couches, dumpsters, cars…

But this is a competition. Each round runs on a **timer (5 minutes by
default)**, and when it expires, the player with the **largest ball wins**.

You can, however, play in single player mode. This makes it a time attack
game, with a race against the timer to beat your previous highest score.

## Installation

The easiest way to install the gamemode is through the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3748029739).

If you prefer to install it manually, press the big green "Code" button at
the top of the GitHub page, then choose "Download ZIP" to download the addon.
Then extract the ZIP into your Garry's Mod addons folder:
```
<Steam>/steamapps/common/GarrysMod/garrysmod/addons/
```

Then start it from the console / server command line:

```
gamemode damashi
map gm_construct
```

Open, flat sandbox maps (`gm_flatgrass`, `gm_bigcity`, etc.) work best.

## How to play

| Input | Action |
|---|---|
| `W A S D` | Roll the ball (relative to the camera) |
| Mouse | Orbit the camera around the ball |
| `LMB` | Charge attack (forward burst, has cooldown) |
| `SPACE` | Small hop (only while grounded) |
| `N` | Open the ball model selector |
| `M` | Open the background music selector |
| Hold `R` for 10 s | Emergency respawn (see below) |

- Only props **sufficiently smaller than your ball** will stick (40 % of your
  ball's volume by default) — start with cans and melons, work up to cars.
- Props knocked off a ball have a short grace period before they can stick to
  anything again, then they are fair game for everyone.
- Players can not die in this gamemode. Damage simply shrinks your ball's size.

## The charge attack

Press **LMB** to charge: your ball bursts forward in the direction you are
facing.

- **Hit another player's ball** and they take damage: their ball shrinks and
  sheds props, which scatter on the ground and become free for *anyone*
  (including them) to roll up again. The damage scales with **your** ball's
  current size — a big ball hits much harder.
- **Miss and slam into a wall** (or anything too big to roll up) and the
  penalty is yours: your own ball shrinks slightly and drops a few props.
- The charge has a **cooldown** (4 seconds by default) shown as a bar on the
  HUD, so it cannot be spammed.

## Ball models

Each player rides a custom sphere model. The game looks for any `.mdl` files
inside `models/damashi/` whose filename starts with `ball_` and presents them
in a scrollable **ball model selector** panel.

- Open the selector with **N** (or `damashi_open_selector` in the console).
- Each entry shows a spinning 3-D preview of the model.
- On first spawn the game randomly assigns one of the custom models (or the
  default sphere if none are installed).
- To add your own balls, compile a model with the name `ball_<something>.mdl`,
  and compile it into this path: `GarrysMod/garrysmod/models/damashi/`.

The display name is derived automatically from the filename:
`ball_beach_ball.mdl` → "Beach Ball".

## Background music

The music selector panel streams a track from disk while you play.

- Open it with **M** (or `damashi_open_music` in the console).
- Two directories are scanned for tracks:

| Directory | Purpose |
|---|---|
| `gamemodes/damashi/sound/damashi/` | Packaged tracks shipped with the gamemode |
| `garrysmod/sound/damashi/` | Your own custom tracks (drop files here) |

- Files must be named `bgm_<something>.mp3`, `bgm_<something>.wav`, or
  `bgm_<something>.ogg`.
- Both directories are merged into one list; if the same filename exists in
  both, the packaged copy takes priority.
- The display name strips the `bgm_` prefix and converts underscores to spaces:
  `bgm_main_theme.mp3` → "Main Theme".

## Emergency respawn

If your ball becomes permanently stuck (e.g. a large prop is spawned on top of
it in a narrow corridor), you can force a respawn:

1. **Hold R continuously for 10 seconds.**
2. After 3 seconds a red on-screen warning appears with a countdown.
   Releasing R at any point cancels the hold.
3. If UI windows get keyboard focus (chat box, console, a selector panel) the hold
   is automatically cancelled so normal typing never triggers it.
4. On completion the ball is teleported back to the spawn point you first
   appeared at (or the nearest map spawn if that is unavailable) and placed
   safely above the floor.
5. A **20-second server-side cooldown** prevents the option from being abused
   by repeat back-to-back usage.

## Server custom scatter props

Server operators can supply their own physics props for the scatter system by
placing model files in:

```
GarrysMod/garrysmod/models/damashi/scatter/
```

Any `.mdl` file (with a matching `.phy`) found in that directory is
automatically included in the scatter pool when `damashi_propmode_server` is
enabled. When a player connects, the server uses GMod's built-in file transfer
to push the `.mdl`, `.phy`, `.vvd`, and `.vtx` files to the client so no models
are missing mid-game. Place matching material files under
`GarrysMod/garrysmod/materials/models/damashi/scatter/` — the gamemode
recursively queues that directory for download as well.

## Console variables (server)

| ConVar | Default | Meaning |
|---|---|---|
| `damashi_roundtime` | `300` | Round length in seconds; on expiry the largest ball wins |
| `damashi_scatter` | `400` | Extra junk props scattered around spawn points each round |
| `damashi_propmode_hl2` | `1` | `1` = include the built-in HL2 prop list, `0` = disable |
| `damashi_propmode_map` | `0` | `1` = add physics props placed inside the map, `0` = disable |
| `damashi_propmode_server` | `1` | `1` = include props from `models/damashi/scatter/`, `0` = disable |
| `damashi_spawnmult` | `1.0` | Multiplier applied to the scattered prop count |
| `damashi_wave_interval` | `60` | Seconds between mid-round scatter waves; `0` disables waves |
| `damashi_wave_size` | `30` | Props dropped per wave and per expansion pass |
| `damashi_scatter_passes` | `3` | Expansion passes after round-start scatter (see below); `0` disables |

If all three `propmode_*` convars are disabled (or all enabled sources yield an
empty list), the gamemode automatically falls back to the built-in HL2 list so
there are always props available.

## Map entity: `damashi_settings`

Mappers can place a single `damashi_settings` point entity to override the
server convars per-map. Supported keyvalues:

| Keyvalue | Type | Default | Meaning |
|---|---|---|---|
| `roundtime` | integer | `300` | Round length in seconds (0 = use convar) |
| `scatter` | integer | `80` | Extra props per round (−1 = use convar) |
| `propmode_hl2` | choices | `1` | `1` = enable HL2 props, `0` = disable |
| `propmode_map` | choices | `0` | `1` = enable map-packed props, `0` = disable |
| `propmode_server` | choices | `1` | `1` = enable server custom props, `0` = disable |
| `spawnmult` | float | `1.0` | Prop count multiplier (−1 = use convar) |

A game data file (`damashi.fgd`) is provided for Hammer editor support. Add it
to your Hammer FGD list and `damashi_settings` will appear in the entity browser
with full tooltip help.

Further tuning (acceleration, stickiness ratio, growth rate, charge damage,
wall-slam penalty, cooldowns, etc.) lives in the `DAMASHI` table in
`gamemode/shared.lua`.

## File layout

```
damashi/
├── damashi.txt                      gamemode manifest
├── damashi.fgd                      Hammer editor game data
├── sound/damashi/
│   └── README.txt                   instructions for adding custom music tracks
└── gamemode/
    ├── shared.lua                   global DAMASHI config table + ball entity registration
    ├── init.lua                     server: rounds, timer, spawning, prop scatter,
    │                                        charge input, teleport patches, emergency respawn
    ├── scatter_models.lua           built-in HL2 scatter prop list (edit this to change props)
    ├── cl_init.lua                  client: chase camera, HUD (timer, charge meter, leader,
    │                                        nametags, emergency respawn countdown)
    ├── ent_ball.lua                 scripted entity class definition (shared)
    ├── ent_ball_sv.lua              server ball logic: physics, sticking, growth, charge combat,
    │                                        model switching, teleport cooldown + height correction
    ├── cl_ball_selector.lua         ball model selector VGUI panel
    └── cl_music_selector.lua        background music selector VGUI panel
```

*(The `damashi_ball` entity and `damashi_settings` entity are loaded explicitly
from `gamemode/` rather than from `entities/`, since GMod's auto-load only
applies to addon folders, not gamemode folders.)*
