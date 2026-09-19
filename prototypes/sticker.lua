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
---
--- Six, in fact, because a vehicle is slowed by the same sticker and not by the same
--- number. A sticker states a movement modifier and a vehicle speed modifier separately and
--- the engine applies whichever suits what the sticker landed on, so one prototype would
--- serve a character and a car -- were it not that the two kinds of vehicle take the figure
--- differently.
---
--- A wheeled vehicle's modifier is its engine, and its top speed is where its engine
--- balances a drag that grows with the square of its speed, so a fraction of the engine is
--- the square root of that fraction of speed. A spider vehicle has no such balance: its
--- legs simply carry it at the figure it is given.
---
--- Measured at a steady speed, with the same sticker on each. At 0.625 a tank ran at 0.7918
--- of its top speed and a car at 0.7909, against a square root of 0.7906, while a
--- spidertron ran at 0.627. At 0.3906, which is 0.625 squared, the tank ran at 0.6276 and
--- the car at 0.6256, and the spidertron at 0.390. So the wheeled figure is squared and the
--- legged one is not, and which of the two a wearer gets is control.lua's to pick.
---
--- Top speed, that is. A vehicle still picking up speed is down by more than its share,
--- because what it is short of is acceleration, and it comes back to the tier's figure as
--- the vehicle settles. That is the right way round for a penalty: putting your foot down
--- while the arms are working is the thing the slowdown is there to discourage.
local tiers = require("lib.tiers")

---What to write in the prototype for a wheeled vehicle, given the share of speed the tier
---asks for. See above: a wheeled vehicle's top speed goes with the square root of it.
---@param modifier number
---@return number
local function wheeled(modifier)
  return modifier * modifier
end

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
      target_movement_modifier = set.modifier,
      -- the same penalty again, for a wearer that is driven rather than walked
      vehicle_speed_modifier = wheeled(set.modifier)
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
      target_movement_modifier_to = set.modifier,
      vehicle_speed_modifier_from = 1.0,
      vehicle_speed_modifier_to = wheeled(set.modifier)
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
      target_movement_modifier_to = 1.0,
      vehicle_speed_modifier_from = wheeled(set.modifier),
      vehicle_speed_modifier_to = 1.0
    })

    -- The legged three. Nothing walks about wearing these, so they carry no movement
    -- modifier at all: a spider vehicle is the only thing control.lua puts them on.
    local legs = set.legs
    table.insert(stickers, {
      type = "sticker",
      name = legs.flat,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 240,
      vehicle_speed_modifier = legs.modifier
    })
    table.insert(stickers, {
      type = "sticker",
      name = legs.slowing,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 30,
      vehicle_speed_modifier_from = 1.0,
      vehicle_speed_modifier_to = legs.modifier
    })
    table.insert(stickers, {
      type = "sticker",
      name = legs.recovery,
      flags = {"not-on-map"},
      hidden = true,
      duration_in_ticks = 45,
      vehicle_speed_modifier_from = legs.modifier,
      vehicle_speed_modifier_to = 1.0
    })
  end
end

-- Nothing at all when the penalty is switched off, and data:extend refuses an empty list
-- rather than shrugging at one. See tiers.SLOWS.
if #stickers > 0 then data:extend(stickers) end
