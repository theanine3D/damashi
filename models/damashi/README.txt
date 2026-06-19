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
- The model should be roughly sphere-shaped and ideally close in size
  to the default ball (models/hunter/misc/sphere075x075.mdl, r~37 units)
  so the selector preview looks sensible.
- Pack all required model files (.mdl, .vvd, .vtx, .phy, .vtf, .vmt)
  into the BSP or distribute them alongside the gamemode.
- The display name shown in the selector is derived from the filename:
  underscores become spaces and the first letter is capitalised.
  "ball_beach_ball.mdl" → "Beach Ball"
