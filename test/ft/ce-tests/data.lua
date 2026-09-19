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
