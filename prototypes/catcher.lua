--- An invisible box that stands on a ghost's own tile to catch what an arm brings it.
---
--- The engine decides for itself what an inserter's drop position means. A ghost of
--- something that could have taken the item makes it wait; a ghost of something that could
--- not is either built from the claw or has the load dumped on the floor beside it. None of
--- those is what the mod wants, and which one happens is not the mod's to choose.
---
--- A real container standing on the same tile settles it: an inserter puts things into
--- containers, so the arrival becomes a thing the engine does rather than a distance the
--- mod has to measure once a tick and hope not to step over.
---
--- It collides with nothing, so the ghost it sits on can still be revived, and it is not
--- selectable, minable or blueprintable, so nobody can interact with it.
local catcher = table.deepcopy(data.raw.container["wooden-chest"])

catcher.name = "constructor-equipment-catcher"
catcher.inventory_size = 1
catcher.collision_mask = { layers = {} }
-- An inserter finds a container as its drop target only if the container's collision box
-- overlaps the tile the drop position resolves to by at least three sixty-fourths of a
-- tile. Measured: a half width of 0.046875 is found and 0.04687 is not, which is 12/256
-- and so a fixed point constant rather than a tolerance. Below it the inserter does not
-- see the box at all and stalls, or puts its load on the floor beside it.
--
-- A box centred at distance d inside a tile overlaps it by d plus its half width, so a
-- half width at or above that threshold is enough wherever the drop position falls,
-- including exactly on a tile boundary, which is where rail ghosts put theirs. This is a
-- little over twice the threshold and still far smaller than a tile.
catcher.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
catcher.selection_box = nil
catcher.selectable_in_game = false
-- No no-automated-item-insertion here, obviously: that flag is exactly the instruction to
-- inserters to keep out, and with it set the arm ignored the box and went on dropping its
-- load on the floor.
catcher.flags = { "not-on-map", "not-blueprintable", "not-deconstructable",
  "placeable-off-grid", "not-flammable" }
catcher.minable = nil
catcher.picture = { filename = "__core__/graphics/empty.png", size = 1, priority = "low" }
catcher.icon = "__base__/graphics/icons/wooden-chest.png"
catcher.icon_size = 64
catcher.next_upgrade = nil
catcher.fast_replaceable_group = nil
catcher.open_sound = nil
catcher.close_sound = nil

data:extend{ catcher }
