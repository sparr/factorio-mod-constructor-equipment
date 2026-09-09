--- The slowdown, as a sticker rather than as a number on the character.
---
--- character_running_speed_modifier is one value shared by every mod that wants to change
--- how fast you walk, so setting it means overwriting whatever somebody else put there,
--- and putting it back afterwards means guessing what that was. This mod used to do
--- exactly that, and the 2017 readme admitted it would fight ProgressiveRunning.
---
--- A sticker is a mod's own. The engine multiplies the modifiers of every sticker on a
--- character together, and multiplies that by character_running_speed_modifier on top, so
--- each mod's effect lands and none of them has to know about the others. Two stickers of
--- the same name do not stack, so this cannot double up on itself either.
---
--- The duration is a safety net rather than a timer. What normally ends the slowdown is
--- the recovery sticker taking over, the moment a build falls due and finds nothing left
--- to do. The duration only matters if the mod stops running altogether, which is the
--- failure it is here to prevent: before any of this, a crash between starting and
--- finishing a build left the player at quarter speed for good.
---
--- So it has to outlast the gap between two builds, and that gap is the arm's own swing
--- out and back, which at four tiles of reach is well over a hundred ticks. Set from the
--- build interval, as it first was, it expired mid-run and the character surged between
--- builds.
data:extend(
{
  {
    type = "sticker",
    name = "constructor-equipment-slowdown",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = 240,
    -- a quarter speed, which is what character_running_speed_modifier = -0.75 gave
    target_movement_modifier = 0.25
  },
  {
    -- The head: the first build of a run puts this on, and the character slows from full
    -- speed to a quarter of it over its lifetime rather than dropping to a crawl in one
    -- tick. Once it runs out the flat sticker above takes over and holds them there.
    type = "sticker",
    name = "constructor-equipment-slowing",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = 60,
    target_movement_modifier_from = 1.0,
    target_movement_modifier_to = 0.25
  },
  {
    -- The tail: once there is nothing left to build, this takes over and lets the
    -- character back up to speed over its lifetime rather than all at once.
    type = "sticker",
    name = "constructor-equipment-recovery",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = 45,
    target_movement_modifier_from = 0.25,
    target_movement_modifier_to = 1.0
  }
})
