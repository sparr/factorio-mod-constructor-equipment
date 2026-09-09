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
--- out and back, which is well over a hundred ticks. Set from the build interval, as it
--- first was, it expired mid-run and the character surged between builds.
---
--- How hard it bites is half what it was. The arm used to be the whole of the trade: you
--- got free building and paid for it in walking speed. It is not, any more -- the swing
--- takes as long as it takes, and that alone stops the equipment from carrying you across
--- a blueprint at a run -- so the walking penalty on top of it only wants to be felt,
--- not endured.
--- Each tier that slows its wearer gets its own three of them, because how much it slows
--- them is baked into the prototype rather than being something script can dial. A tier
--- that asks for none of the penalty has no stickers at all, and control.lua keeps at most
--- one set on a character at a time: they are separate prototypes, so the engine would
--- otherwise keep two and multiply them together.
local tiers = require("lib.tiers")

local stickers = {}

for _, tier in ipairs(tiers.list) do
  local set = tier.stickers
  if set then
    table.insert(stickers, {
      type = "sticker",
      name = set.flat,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 240,
      target_movement_modifier = set.modifier
    })
    table.insert(stickers, {
      -- The head: the first build of a run puts this on, and the character slows from full
      -- speed down to it over the sticker's lifetime rather than dropping in one tick. Once
      -- it runs out the flat sticker above takes over and holds them there.
      type = "sticker",
      name = set.slowing,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 30,
      target_movement_modifier_from = 1.0,
      target_movement_modifier_to = set.modifier
    })
    table.insert(stickers, {
      -- The tail: once there is nothing left to build, this takes over and lets the
      -- character back up to speed over its lifetime rather than all at once.
      type = "sticker",
      name = set.recovery,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 45,
      target_movement_modifier_from = set.modifier,
      target_movement_modifier_to = 1.0
    })
  end
end

data:extend(stickers)
