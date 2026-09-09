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
--- The duration matters: it is what makes the slowdown end. Builds come at most every
--- BUILD_INTERVAL ticks and are looked for every CHECK_INTERVAL, so anything longer than
--- their sum survives a continuous run of building and expires shortly after the last
--- one. Nothing has to remember to take it off, which is the other half of the point:
--- before this, a crash between building and finishing left the player at quarter speed
--- for good.
data:extend(
{
  {
    type = "sticker",
    name = "constructor-equipment-slowdown",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = 45,
    -- a quarter speed, which is what character_running_speed_modifier = -0.75 gave
    target_movement_modifier = 0.25
  },
  {
    -- The tail: once there is nothing left to build, this takes over and lets the
    -- character back up to speed over its lifetime rather than all at once.
    type = "sticker",
    name = "constructor-equipment-recovery",
    flags = {"not-on-map"},
    hidden = true,
    duration_in_ticks = 30,
    target_movement_modifier_from = 0.25,
    target_movement_modifier_to = 1.0
  }
})
