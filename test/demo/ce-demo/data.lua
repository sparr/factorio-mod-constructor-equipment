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

--- And the same for whichever of AAI's vehicles are installed, for the same reason and with
--- the same admission on their bays. They are here because their hulls are shapes the base
--- game does not have -- a chaingunner is a tile and a half square, an ironclad is twice as
--- long as it is wide -- and where an arm ends up bolted to one is a thing lib/pack.lua has
--- an opinion about that nothing else tests.
---
--- Whichever are installed: each is its own mod and none of them is a dependency, so this
--- adds a grid to the ones that are here and says nothing about the ones that are not. An
--- ironclad already carries a medium grid of its own and is left with it.
for _, name in ipairs{ "vehicle-hauler", "vehicle-chaingunner", "vehicle-miner",
                       "vehicle-warden" } do
  local vehicle = data.raw.car and data.raw.car[name]
  if vehicle and not vehicle.equipment_grid then vehicle.equipment_grid = grid.name end
end
