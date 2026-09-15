--- A character that exists for the length of one swap, to be handed what the swap displaces.
---
--- Replacing a thing with its upgrade puts the thing that came off, and whatever the
--- replacement cannot hold, somewhere. The engine decides where inside the one call, and it
--- has to be handed to somebody: name nobody and it destroys the lot, measured on 2.1.17 at
--- sixteen hundred plates. Name the player and it goes to their pockets, or to the floor
--- when those are full, or onto the very belt that replaced it -- which is the game's own
--- behaviour when a player fast replaces by hand, warning and all.
---
--- Nothing is lost either way, so this is not a rescue. It is about who decides. Handing it
--- to the player means the mod takes what it wants back out of their pockets afterwards and
--- hopes it put them back as it found them; handing it here means the mod holds everything
--- and chooses, and the player's own pockets are never opened at all. No snapshot, no
--- arithmetic, and nothing for the game's own inventory sorting to interfere with.
---
--- What it buys on top is the shed: the claw carries the thing itself home and the rest goes
--- on the floor marked for deconstruction, which is what a construction robot does with what
--- it cannot carry, and what the engine's own spilling does not do.
---
--- It is a copy of the base game's character because a character is what create_entity will
--- accept, and writing one from nothing means writing every animation a character needs.
--- Everything that would make it a thing in the world is taken off it.
local porter = table.deepcopy(data.raw.character.character)

porter.name = "constructor-equipment-porter"
-- Collides with nothing, so it can stand on the very tile being replaced without being in
-- the way of the replacement.
porter.collision_mask = { layers = {} }
porter.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
porter.selection_box = nil
porter.selectable_in_game = false
porter.hidden = true
porter.hidden_in_factoriopedia = true
porter.minable = nil
porter.mined_sound = nil
porter.healing_per_tick = 0
porter.character_corpse = nil
-- It never walks, reaches, mines or picks anything up: it is an inventory with a name.
porter.build_distance = 0
porter.reach_distance = 0
porter.reach_resource_distance = 0
porter.drop_item_distance = 0
porter.item_pickup_distance = 0
porter.loot_pickup_distance = 0
porter.running_speed = 0
porter.distance_per_frame = 0
porter.mining_speed = 0
porter.flags = {
  "not-on-map",
  "not-blueprintable",
  "not-deconstructable",
  "placeable-off-grid",
  "not-flammable",
  "not-repairable",
  "not-in-made-in",
}

data:extend{ porter }
