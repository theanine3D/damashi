Music tracks for Damashi
========================
The selector scans TWO locations for BGM files.  Use whichever fits your purpose.

-------------------------------------------------------------------
LOCATION 1 — Packaged tracks (shipped with the gamemode)
-------------------------------------------------------------------
  gamemodes/damashi/sound/damashi/

  Place files here if you are distributing the gamemode and want music
  included by default.  These tracks are loaded FIRST and take priority
  if a file with the same name exists in both locations.

  This is the folder you are reading this README from.

-------------------------------------------------------------------
LOCATION 2 — User-added custom tracks
-------------------------------------------------------------------
  [GarrysMod install]/garrysmod/sound/damashi/

  For a typical Steam install:
    C:\Program Files (x86)\Steam\steamapps\common\GarrysMod\garrysmod\sound\damashi\

  Create the "damashi" sub-folder if it does not exist.
  Tracks placed here supplement the packaged ones and do not override them.

-------------------------------------------------------------------
Naming convention
-------------------------------------------------------------------
  bgm_<name>.mp3   (or .wav / .ogg)

Examples:
    bgm_rolling.mp3
    bgm_big_bounce.wav
    bgm_upbeat_chase.ogg

The display name shown in the selector is derived from the filename:
underscores become spaces and the first letter is capitalised.
"bgm_big_bounce.wav" → "Big Bounce"

-------------------------------------------------------------------
Technical notes
-------------------------------------------------------------------
- Music is entirely client-side; only the player who selects a track
  hears it.  Other players are unaffected.
- Supported formats: MP3, WAV, OGG Vorbis.
