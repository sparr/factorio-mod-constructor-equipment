--- Equipment grids for the two vehicles the base game gives none.
---
--- A car and a locomotive cannot carry the equipment in vanilla, but plenty of mods give
--- them grids and the showroom gives them one of its own, so the arms have to work on them.
--- Supported rather than tuned for: what the tests here ask is that nothing breaks, not that
--- anything is quick.
---
--- Safe to do from here for the same reason the fixtures are registered from here: ce-tests
--- is never published, so this can never reach a player's game. The showroom does the same
--- thing in test/demo/ce-demo, and deliberately says so on its bays.
local grid = {
  type = "equipment-grid",
  name = "ce-tests-vehicle-grid",
  width = 8,
  height = 6,
  equipment_categories = { "armor" },
}

data:extend{ grid }

for kind, name in pairs{ car = "car", locomotive = "locomotive" } do
  local vehicle = data.raw[kind] and data.raw[kind][name]
  if vehicle then vehicle.equipment_grid = grid.name end
end

--- Copies of a fourth tier arm with different pickup and insert positions written into the
--- prototype, so that a test can ask whether where a freshly built hand sits depends on
--- them. Setting either end from script does not move it; the question left is whether the
--- prototype's own vectors do.
---
--- The last two are the control. The arms set starting_distance small enough that a fresh
--- hand sits on the arm's own base, and a test that only ever sees that cannot tell "the
--- vectors do not move it" from "nothing moves it at all": born-far and born-near ask for a
--- radius of their own and are the pair that shows the one field which does. Every other
--- copy keeps whatever the fourth tier arm itself asks for, so the six of them stay with it
--- if that number ever moves.
---
--- Test only, and safe here for the same reason the grids above are: ce-tests is never
--- published.
local util = require("util")

local ORIGINAL = data.raw.inserter["constructor-equipment-4-inserter"]
if ORIGINAL then
  local VARIANTS = {
    { name = "ce-tests-arm-plain",      pickup = { 0, 0 },  insert = { 0, 1 } },
    { name = "ce-tests-arm-far-insert", pickup = { 0, 0 },  insert = { 0, 3 } },
    { name = "ce-tests-arm-far-pickup", pickup = { 0, -3 }, insert = { 0, 1 } },
    { name = "ce-tests-arm-both-far",   pickup = { 0, -2 }, insert = { 0, 2 } },
    { name = "ce-tests-arm-sideways",   pickup = { 1, 0 },  insert = { -1, 0 } },
    { name = "ce-tests-arm-tiny",       pickup = { 0, 0 },  insert = { 0, 0.2 } },
    { name = "ce-tests-arm-born-far",   pickup = { 0, 0 },  insert = { 0, 1 }, born = 1.5 },
    { name = "ce-tests-arm-born-near",  pickup = { 0, 0 },  insert = { 0, 1 }, born = 0.25 },
  }
  local made = {}
  for _, variant in ipairs(VARIANTS) do
    local copy = util.table.deepcopy(ORIGINAL)
    copy.name = variant.name
    copy.pickup_position = variant.pickup
    copy.insert_position = variant.insert
    if variant.born then copy.starting_distance = variant.born end
    made[#made + 1] = copy
  end
  data:extend(made)
end
