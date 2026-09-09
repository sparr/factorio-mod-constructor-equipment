--- The item that becomes each tier of the equipment.
local tiers = require("lib.tiers")
local art = require("prototypes.art")

local items = {}

for _, tier in ipairs(tiers.list) do
  table.insert(items, {
    type = "item",
    name = tier.name,
    icons = art.icons(tier, 64),
    -- Not placed_as_equipment_result, which is what this said from 0.15 until 2.1.0. There
    -- is no such property, Factorio ignores what it does not know, and the equipment could
    -- be crafted and then not put into an armour at all.
    place_as_equipment_result = tier.name,
    -- the goes-to-main-inventory flag went away in 0.17, along with the separate
    -- quickbar it was about
    subgroup = "equipment",
    order = "e[robotics]-c[constructor-equipment]-" .. tier.level,
    stack_size = 5
  })
end

data:extend(items)
