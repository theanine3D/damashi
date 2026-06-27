Place custom ball model files here.

Any .mdl file whose filename begins with "ball_" will be discovered
automatically when the gamemode loads and offered to players in the
ball selector (damashi_open_selector / bind b damashi_open_selector).

Naming convention
-----------------
  ball_<name>.mdl

Examples:
  ball_soccer.mdl
  ball_beach_ball.mdl
  ball_bowling.mdl

Rules
-----
- The model must have a matching .phy file so it can be spawned as
  a physics object.
- The model should be roughly sphere-shaped.
- Pack all required model files (.mdl, .vvd, .vtx, .phy, .vtf, .vmt)
  into the BSP or distribute them alongside the gamemode.

Display Names
-------------
By default, the display name for a given model is derived from the 
filename and the skin ID. The filename portion omits the "ball_" 
prefix and formats the string using the same rules as string.NiceName() in GLua:
  1. Underscores are replaced with spaces
     ("Deluxe_Ball" -> "Deluxe Ball")
  2. Text is split into sentences based on capitalization 
     ("BallNumber3" -> "Ball Number 3")
  3. The first letter of each word is capitalized.
     ("crazy_ball" -> "Crazy Ball")
Examples:
  ball_tennis.mdl, skin 2/2     -> Tennis (skin 2)
  ball_basketball.mdl, skin 0/0 -> Basketball

Display names for a given model can be overridden with custom ones
by adding a .txt file with the same name as the .mdl, but starting
with "names_" (for example, the names list for 
"ball_soccer.mdl" is named "names_soccer.txt")

Name files are read line-by-line in the following format:
  - Lines starting with "[number]:" set the name for a specific skin.
      (Example: "4: Awesome Ball" sets skin 4's name to "Awesome Ball")
      NOTE: Skin IDs start at 0!
  - Lines starting with "n:" set the name for the model itself, replacing
    the portion generated from the filename.
    (Example: "n: Basket Ball" sets the model's base name to "Basket Ball",
    and any unnamed skins will be named "Basket Ball (skin #)")
  - Empty lines or lines starting with "#" are ignored.