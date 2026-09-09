--- One piece of equipment per tier. Each is a whole arm of its own once worn: control.lua
--- counts them and puts that many inserters on the character's back.
local tiers = require("lib.tiers")
local art = require("prototypes.art")

local equipment = {}

for _, tier in ipairs(tiers.list) do
  table.insert(equipment, {
    -- An interface rather than a movement bonus. This used to be a movement-bonus-equipment
    -- with a bonus of nought, which is what the mod has always done, and its tooltip said
    -- so: a movement bonus of nought per cent, and a maximum consumption of one watt. Both
    -- were nonsense. This type is inert, and it is the only one that lets a mod say what
    -- its tooltip shows: all three lines are turned off, because what this costs is neither
    -- a steady draw nor a stored amount, and the real figures are in the description where
    -- they can be stated properly.
    type = "electric-energy-interface-equipment",
    name = tier.name,
    sprite = art.equipment_sprite(tier),
    shape =
    {
      width = tier.width,
      height = tier.height,
      type = "full"
    },
    -- A buffer of its own, which the armour fills the way it fills a night vision unit or
    -- a shield. The arm is fed out of this rather than out of whatever batteries happen to
    -- be in the grid: the equipment is the thing the player installed, so it should be the
    -- thing that holds the charge, and an armour that cannot keep it filled starves its own
    -- arm without anything having to check.
    energy_source =
    {
      type = "electric",
      usage_priority = "secondary-input",
      -- Exactly what an arm wants in hand before it sets off, because that is the whole
      -- of the rule: the arm waits for a full buffer. Two numbers, a capacity and a
      -- separate reserve to check against, said the same thing twice.
      buffer_capacity = tier.reserve .. "J"
    },
    show_power_usage_in_tooltip = false,
    show_power_production_in_tooltip = false,
    show_stored_energy_in_tooltip = false,
    categories = {"armor"}
  })
end

data:extend(equipment)
