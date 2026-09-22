--- Make each tier wait for whatever unlocks the inserter it is built out of.
---
--- Every tier's recipe consumes one of the base game's inserters, so a tier researched
--- before that inserter exists is a recipe nobody can craft. Naming the technology outright
--- is right until a mod moves the inserter somewhere else, and mods that rearrange the
--- early tree are exactly the ones this would be wrong under, so the tree is read rather
--- than assumed.
---
--- This runs in final fixes because that is the first point at which every other mod has
--- finished rearranging things. Another mod's own final fixes can still move an inserter
--- after this looks, which nothing can do anything about.
---
--- If the inserter has no recipe at all, this adds nothing and the data stage fails on the
--- missing ingredient instead, which tells the player plainly that the two mods do not fit
--- together.
--- The search itself lives in lib/unlock.lua, which is handed these tables rather than
--- reaching for data.raw, so that the cases the base game does not contain -- a loop in the
--- tree, two technologies unlocking the same thing, an item nobody can make -- can be
--- written down and checked without a game.
local tiers = require("lib.tiers")
local unlock = require("lib.unlock")
local grids = require("lib.grids")

local mine = {}
for _, tier in ipairs(tiers.list) do mine[tier.name] = true end

for _, tier in ipairs(tiers.list) do
  local technology = data.raw.technology[tier.name]
  if technology then
    local wait_for = unlock.gate(data.raw.recipe, data.raw.technology, tier.hand, mine)
    if wait_for then
      technology.prerequisites = technology.prerequisites or {}
      local already = false
      for _, prerequisite in pairs(technology.prerequisites) do
        if prerequisite == wait_for then already = true end
      end
      if not already then
        table.insert(technology.prerequisites, wait_for)
      end
    end
  end
end

--- Follow the vehicles into whatever categories an overhaul has put them in.
---
--- The equipment sits in "armor", which is what every grid the base game puts on a vehicle
--- accepts, so in an unmodified game the arms ride everything and none of this does
--- anything. A mod that re-grids those vehicles into categories of its own takes the arms
--- off all of them at once, and without meaning anything by it: Krastorio 2 gives its
--- vehicles kr-vehicle and two narrower categories, carries the old grid's categories across
--- except "armor" on purpose, and opts its own equipment back in by declaring both. Measured
--- on 2.1.20 with K2 2.1.2 before this went in -- no to the car, the tank, the locomotive,
--- all three wagons and the spidertron, yes to all five armours.
---
--- Only the vehicles the mod already knew about, so this claims no ground the arms were not
--- standing on. What it works out is the fewest categories that get them back onto all of
--- them, which on K2 is the single one its author made for equipment that goes on vehicles
--- generally -- see lib/grids.lua, which is where the choosing is written down and checked.
---
--- Final fixes because that is the first point at which every other mod has finished moving
--- things about. K2 re-grids in data-updates, which is earlier, so this sees what it did.
--- Another mod's own final fixes can still re-grid a vehicle after this looks, which nothing
--- can do anything about.
local RIDDEN = {
  { "car", "car" },
  { "car", "tank" },
  { "locomotive", "locomotive" },
  { "cargo-wagon", "cargo-wagon" },
  { "fluid-wagon", "fluid-wagon" },
  { "artillery-wagon", "artillery-wagon" },
  { "spider-vehicle", "spidertron" },
}

local wanted = {}
for _, known in ipairs(RIDDEN) do
  local of_type = data.raw[known[1]]
  local vehicle = of_type and of_type[known[2]]
  local grid = vehicle and vehicle.equipment_grid
    and data.raw["equipment-grid"][vehicle.equipment_grid]
  if grid and grid.equipment_categories then
    wanted[#wanted + 1] = grid.equipment_categories
  end
end

for _, tier in ipairs(tiers.list) do
  local piece = data.raw["electric-energy-interface-equipment"][tier.name]
  if piece then
    piece.categories = piece.categories or {}
    local have = {}
    for _, name in ipairs(piece.categories) do have[name] = true end
    for _, name in ipairs(grids.cover(wanted, have)) do
      table.insert(piece.categories, name)
    end
  end
end
