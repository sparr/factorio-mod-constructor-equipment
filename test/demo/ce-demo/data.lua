--- Two vehicles the base game gives no equipment grid, given one here.
---
--- A tank and a spidertron carry a grid already, so the arms have somewhere to live in them
--- and the showroom has only to fit them out. A car and a locomotive do not, and a row
--- demonstrating arms on either would otherwise be a row demonstrating nothing. Their bays
--- say plainly that the grid is the showroom's doing rather than the mod's or the game's.
local grid = {
  type = "equipment-grid",
  name = "ce-demo-vehicle-grid",
  width = 8,
  height = 6,
  equipment_categories = { "armor" },
}

data:extend{ grid }

for kind, name in pairs{ car = "car", locomotive = "locomotive" } do
  local vehicle = data.raw[kind] and data.raw[kind][name]
  if vehicle then vehicle.equipment_grid = grid.name end
end
