--- Setting up a character who can build, and taking it all apart again afterwards.
---
--- Every fixture here needs roughly the same thing: one character, wearing armour with
--- the equipment in it and something in the batteries, standing next to a ghost with the
--- right item in their pocket. The interesting differences between tests are which of
--- those to leave out.
local world = {}

--- Far enough from the starting area that nothing generated is in the way, and the same
--- place every time so tests do not drift into each other's leftovers.
world.ORIGIN = { x = 200, y = 200 }

--- What the mod is willing to reach, from control.lua.
world.BUILD_RANGE = 4

--- Two builds a second, so a little over half a second between them.
world.BUILD_INTERVAL = 30

--- How long the claw takes to swing one way. Out and back fills a whole build interval,
--- so nothing lands the instant a job starts: the item has to get there first.
world.SWING_TICKS = 15

--- Comfortably after a swing has reached its target and delivered.
world.DELIVERED = world.SWING_TICKS + 14

---The player the harness gives us, put back into a known state.
---@return LuaPlayer
function world.player()
  local player = game.players[1]
  assert(player, "the harness provided no player")
  if not player.character then
    -- create_character refuses from anything but a player or god controller, so a
    -- spectator has to be brought back through god first
    player.set_controller{ type = defines.controllers.god }
    player.create_character()
    player.set_controller{ type = defines.controllers.character, character = player.character }
  end
  player.teleport(world.ORIGIN, game.surfaces[1])
  player.character_running_speed_modifier = 0
  return player
end

---Clear the ground around the arena, and the player's pockets with it.
---@param player LuaPlayer
function world.clear(player)
  local surface = player.surface
  local half = 30
  local area = {
    { world.ORIGIN.x - half, world.ORIGIN.y - half },
    { world.ORIGIN.x + half, world.ORIGIN.y + half },
  }
  for _, entity in pairs(surface.find_entities_filtered{ area = area }) do
    if entity.valid and entity.type ~= "character" then entity.destroy() end
  end
  local main = player.get_inventory(defines.inventory.character_main)
  if main then main.clear() end
  local armour = player.get_inventory(defines.inventory.character_armor)
  if armour then armour.clear() end
  storage.constructor_last_build_tick = {}
  storage.constructor_saved_running_speed_modifier = {}
end

---Put armour on the character, with whatever equipment the test wants in it.
---@param player LuaPlayer
---@param equipment string[] names to place in the grid
---@param charged boolean whether to fill the batteries
---@return LuaEquipmentGrid
function world.equip(player, equipment, charged)
  player.insert{ name = "modular-armor" }
  local armour = player.get_inventory(defines.inventory.character_armor)[1]
  local grid = armour.grid
  for _, name in pairs(equipment) do grid.put{ name = name } end
  for _, item in pairs(grid.equipment) do
    item.energy = charged and item.max_energy or 0
  end
  return grid
end

--- The usual case: equipment and a charged battery.
---@param player LuaPlayer
---@return LuaEquipmentGrid
function world.equipped(player)
  return world.equip(player, { "constructor-equipment", "battery-equipment" }, true)
end

---Put a ghost on the ground, offset from the character.
---@param player LuaPlayer
---@param name string what the ghost is of
---@param dx number
---@param dy number
---@return LuaEntity
function world.ghost(player, name, dx, dy)
  local ghost = player.surface.create_entity{
    name = "entity-ghost",
    inner_name = name,
    position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
    force = player.force,
  }
  assert(ghost, "could not place a " .. name .. " ghost")
  return ghost
end

---How many real entities of this name are standing in the arena.
---@param player LuaPlayer
---@param name string
---@return integer
function world.count(player, name)
  return player.surface.count_entities_filtered{ name = name }
end

--- The mod's own slowdown, from prototypes/sticker.lua.
world.SLOWDOWN = "constructor-equipment-slowdown"

--- How long the sticker lasts after the build that applied it, from control.lua.
world.SLOWDOWN_TICKS = 45

---The mod's slowdown sticker on this character, if it is there.
---@param player LuaPlayer
---@return LuaEntity?
---@param name string? which sticker, defaulting to the slowdown
function world.slowdown(player, name)
  name = name or world.SLOWDOWN
  for _, sticker in pairs(player.character.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---How many stickers of any kind are on the character.
---@param player LuaPlayer
---@return integer
function world.stickers(player)
  return #(player.character.stickers or {})
end

---How many ghosts are left in the arena.
---@param player LuaPlayer
---@return integer
function world.ghosts(player)
  return player.surface.count_entities_filtered{ type = "entity-ghost" }
end

return world
