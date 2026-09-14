--- Setting up a character who can build, and taking it all apart again afterwards.
---
--- Every fixture here needs roughly the same thing: one character, wearing armour with
--- the equipment in it and something in the batteries, standing next to a ghost with the
--- right item in their pocket. The interesting differences between tests are which of
--- those to leave out.
--- Required up here rather than where it is used: Factorio only allows require while it
--- is parsing control.lua, so a require inside a function fails at the moment it runs.
local tiers = require("lib.tiers")

local world = {}

--- Far enough from the starting area that nothing generated is in the way, and the same
--- place every time so tests do not drift into each other's leftovers.
---
--- The middle of a tile rather than the corner of one. A one by one ghost snaps to the
--- middle of whichever tile it is asked for, so from a corner an offset of two tiles put
--- the ghost 2.55 tiles away. That did not matter against a reach of four and matters a
--- great deal against a reach of two: offsets here now mean the distance they say.
world.ORIGIN = { x = 200.5, y = 200.5 }

--- What the mod is willing to reach, from control.lua.
world.BUILD_RANGE = 2

--- Roughly how long a first tier arm takes to reach a ghost at the edge of its two tiles.
---
--- The swing is the inserter entity's own, at the base game's extension and rotation speeds
--- for a plain inserter, so this is measured rather than set. Measured at two tiles, a
--- reach starts on tick 6, delivers on tick 37 and is home by tick 77.
world.SWING_TICKS = 31

--- Comfortably after a swing has reached its target and delivered.
world.DELIVERED = world.SWING_TICKS + 20

--- A whole out and back, with room to spare. Generous: the return leg is quicker than the
--- reach out, because the claw retracts along its own bearing rather than swinging round.
world.CYCLE = world.SWING_TICKS * 2 + 20

--- A convenient stretch of time, from when the mod still capped its own build rate at two
--- a second. Nothing caps it now, so this is only a duration tests find handy.
world.BUILD_INTERVAL = 30

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
  -- Orphaned characters go too. A test that swaps controllers can leave a body behind, and
  -- they pile up on the arena floor where they block anything from being built: several
  -- tests were quietly measuring a spot that already had two dead-eyed copies standing in
  -- it. Only bodies nobody is driving are removed.
  local driven = {}
  for _, other in pairs(game.players) do
    if other.character then driven[other.character.unit_number] = true end
  end
  for _, entity in pairs(surface.find_entities_filtered{ area = area }) do
    if entity.valid then
      if entity.type ~= "character" then
        entity.destroy()
      elseif not driven[entity.unit_number] then
        entity.destroy()
      end
    end
  end
  local main = player.get_inventory(defines.inventory.character_main)
  if main then main.clear() end
  local armour = player.get_inventory(defines.inventory.character_armor)
  if armour then armour.clear() end
  -- All of it. A test that left an arm out handed the next one a character who was still
  -- counted as busy, so the next test began by putting an arm on someone who had asked
  -- for nothing -- and paying for the swing it took to settle.
  storage.constructor_arms = {}
  storage.constructor_ramped = {}
  storage.constructor_saved_running_speed_modifier = {}
end

---Put armour on the character, with whatever equipment the test wants in it.
---@param player LuaPlayer
---@param equipment string[] names to place in the grid
---@param charged boolean whether to fill the batteries
---@param armour string? which armour, defaulting to modular
---@return LuaEquipmentGrid
function world.equip(player, equipment, charged, armour)
  player.insert{ name = armour or "modular-armor" }
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

---Armour with several copies of the equipment in it, and a charged battery.
---
---A modular armour's grid is five by five and the equipment is two by four, so two of them
---and a battery is as much as will fit there. Power armour is six by eight and takes six.
---@param player LuaPlayer
---@param n integer how many copies
---@param armour string? which armour, defaulting to modular
---@return LuaEquipmentGrid
function world.equipped_with(player, n, armour)
  local wanted = { "battery-equipment" }
  for _ = 1, n do table.insert(wanted, "constructor-equipment") end
  return world.equip(player, wanted, true, armour)
end

---Take one copy of a piece of equipment out of the character's armour.
---@param player LuaPlayer
---@param name string
---@return boolean whether there was one to take
function world.unequip(player, name)
  local grid = player.character.grid
  for _, equipment in pairs(grid.equipment) do
    if equipment.name == name then
      grid.take{ equipment = equipment }
      return true
    end
  end
  return false
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

--- Spots for several ghosts, all of them inside the arm's reach and none of them under
--- the character's feet. In this order, so the first n of them are n distinct places.
---
--- Furthest first. The arm is mounted half a tile above the character, so a ghost one tile
--- north of them starts less than half a tile from the claw and is delivered to within a
--- few ticks. That is correct, but it makes a poor stand-in for a reach in a test.
world.SPOTS = {
  { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 },
  { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 },
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
}

---Put several ghosts within reach, for tests about a run of building rather than one.
---@param player LuaPlayer
---@param name string
---@param n integer
function world.several(player, name, n)
  assert(n <= #world.SPOTS, "no room for " .. n .. " ghosts inside the range")
  for i = 1, n do
    world.ghost(player, name, world.SPOTS[i][1], world.SPOTS[i][2])
  end
end

---Put ghosts back at every one of the spots, clearing whatever is standing there first.
---
---For a test that needs the building to go on longer than one batch of ghosts lasts.
---Unlike world.several this does not mind a spot being occupied: it clears it. Only belts
---and ghosts are cleared, so the arms on the character's back are left alone.
---@param player LuaPlayer
---@param name string
---@param n integer
function world.top_up(player, name, n)
  for i = 1, math.min(n, #world.SPOTS) do
    local at = {
      x = world.ORIGIN.x + world.SPOTS[i][1],
      y = world.ORIGIN.y + world.SPOTS[i][2],
    }
    for _, entity in pairs(player.surface.find_entities_filtered{
        position = at, radius = 0.4, name = { name, "entity-ghost" } }) do
      if entity.valid then entity.destroy() end
    end
    player.surface.create_entity{
      name = "entity-ghost", inner_name = name,
      position = { at.x, at.y }, force = player.force,
    }
  end
end

---How many real entities of this name are standing in the arena.
---@param player LuaPlayer
---@param name string
---@return integer
function world.count(player, name)
  return player.surface.count_entities_filtered{ name = name }
end

--- The mod's own slowdown, from prototypes/sticker.lua. There are two of them on the way
--- down: a ramp that eases the character from full speed to a quarter of it, and a flat
--- one that holds them there once the ramp has run out.
world.SLOWDOWN = "constructor-equipment-slowdown"
world.SLOWING = "constructor-equipment-slowing"
world.RECOVERY = "constructor-equipment-recovery"

--- How long the sticker lasts after the build that applied it, from control.lua.
world.SLOWDOWN_TICKS = 240

--- How long the ramp into the slowdown lasts, from prototypes/sticker.lua. The flat
--- sticker does not appear until this has run its course.
world.RAMP_TICKS = 60

---The mod's slowdown sticker on this character, if it is there.
---@param player LuaPlayer
---@return LuaEntity?
---Either half of the slowdown, whichever is on the character.
---@param player LuaPlayer
---@return LuaEntity?
function world.slowed_by(player)
  return world.slowdown(player, world.SLOWING) or world.slowdown(player, world.SLOWDOWN)
end

---@param name string? which sticker, defaulting to the flat slowdown
function world.slowdown(player, name)
  name = name or world.SLOWDOWN
  for _, sticker in pairs(player.character.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---Every inserter on this character, found by name rather than through storage so a
---fixture can look at what the engine has them doing.
---@param player LuaPlayer
---@return LuaEntity[]
function world.arms(player)
  local names = {}
  for _, tier in ipairs(tiers.list) do
    table.insert(names, tier.inserter)
  end
  return player.surface.find_entities_filtered{
    name = names,
    position = player.position,
    radius = 3,
  }
end

---The inserter doing the reaching, where there is only meant to be one of them.
---@param player LuaPlayer
---@return LuaEntity?
function world.arm(player)
  return world.arms(player)[1]
end

---What one of the character's arms is reaching for, if anything.
---
---This reads storage, which the fixtures can do because they are required from control.lua
---and share its environment. The alternative is inferring the state of a swing from what
---has been built, which says nothing about what an arm is doing partway through.
---@param player LuaPlayer
---@param slot integer? which arm, defaulting to the first
---@return table?
function world.job(player, slot)
  local list = storage.constructor_arms[player.index]
  if not list then return nil end
  local record = list[slot or 1]
  return record and record.job
end

---How many of the character's arms are reaching for something.
---@param player LuaPlayer
---@return integer
function world.working(player)
  local busy = 0
  for _, record in pairs(storage.constructor_arms[player.index] or {}) do
    if record.job then busy = busy + 1 end
  end
  return busy
end

---What the claw is holding, if anything.
---@param player LuaPlayer
---@return string?
function world.held(player)
  local arm = world.arm(player)
  if not (arm and arm.valid and arm.held_stack.valid_for_read) then return nil end
  return arm.held_stack.name
end

---Which tier's slowdown is on this character, if any, and which of its three it is.
---@param player LuaPlayer
---@return integer? level
---@return string? which "flat", "slowing" or "recovery"
function world.slowed_level(player)
  for _, tier in ipairs(tiers.list) do
    local set = tier.stickers
    if set then
      for _, which in ipairs{ "flat", "slowing", "recovery" } do
        if world.slowdown(player, set[which]) then return tier.level, which end
      end
    end
  end
  return nil
end

---Every sticker of this mod's on the character, by name.
---@param player LuaPlayer
---@return string[]
function world.mod_stickers(player)
  local mine, found = {}, {}
  for _, tier in ipairs(tiers.list) do
    local set = tier.stickers
    if set then
      mine[set.flat] = true
      mine[set.slowing] = true
      mine[set.recovery] = true
    end
  end
  for _, sticker in pairs(player.character.stickers or {}) do
    if sticker.valid and mine[sticker.name] then table.insert(found, sticker.name) end
  end
  return found
end

---How fast the character is walking, as a fraction of what they walk with nothing on them.
---@param player LuaPlayer
---@param full number the speed measured with no stickers
---@return number
function world.share_of(player, full)
  return player.character_running_speed / full
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

---Put a vehicle at the arena and sit the player in it.
---
---Tanks and spidertrons carry an equipment grid in the base game; a car has none, which
---makes it the thing to test a driver with nothing to build from.
---@param player LuaPlayer
---@param name string? which vehicle, defaulting to a tank
---@return LuaEntity
function world.vehicle(player, name)
  local vehicle = player.surface.create_entity{
    name = name or "tank",
    position = world.ORIGIN,
    force = player.force,
    direction = defines.direction.east,
  }
  assert(vehicle, "could not place a " .. (name or "tank"))
  vehicle.insert{ name = "coal", count = 10 }
  vehicle.set_driver(player)
  return vehicle
end

---Fill a vehicle's own grid with equipment, the way world.equip fills an armour's.
---@param vehicle LuaEntity
---@param equipment string[] names to place in the grid
---@param charged boolean whether to fill the buffers
---@return LuaEquipmentGrid
function world.fit(vehicle, equipment, charged)
  local grid = vehicle.grid
  assert(grid, vehicle.name .. " has no equipment grid")
  for _, name in pairs(equipment) do
    assert(grid.put{ name = name }, "the " .. vehicle.name .. " grid would not take " .. name)
  end
  for _, item in pairs(grid.equipment) do
    item.energy = charged and item.max_energy or 0
  end
  return grid
end

--- The usual vehicle case: one arm's equipment and a charged battery in the vehicle's grid.
---@param vehicle LuaEntity
---@return LuaEquipmentGrid
function world.fitted(vehicle)
  return world.fit(vehicle, { "constructor-equipment", "battery-equipment" }, true)
end

---This mod's sticker on anything, character or vehicle.
---@param entity LuaEntity?
---@param name string? which sticker, defaulting to the first tier's flat slowdown
---@return LuaEntity?
function world.sticker_on(entity, name)
  if not (entity and entity.valid) then return nil end
  for _, sticker in pairs(entity.stickers or {}) do
    if sticker.valid and sticker.name == (name or world.SLOWDOWN) then return sticker end
  end
  return nil
end

---Either half of the slowdown on anything, whichever is on it.
---@param entity LuaEntity?
---@return LuaEntity?
function world.slowing_anything(entity)
  for _, tier in ipairs(tiers.list) do
    local set = tier.stickers
    if set then
      for _, which in ipairs{ set, set.legs } do
        local on = world.sticker_on(entity, which.flat) or world.sticker_on(entity, which.slowing)
        if on then return on end
      end
    end
  end
  return nil
end

---A surface with nothing on it, for measuring how fast something goes.
---
---Made rather than borrowed. A vehicle at speed covers hundreds of tiles in a run, and the
---arena's own surface has trees, cliffs and water out there: a free run that hits a tree
---stops dead and reads as a slowdown of everything. This one generates flat grass and
---nothing else, so the only thing in the way is the measurement.
---@return LuaSurface
function world.flats()
  local made = game.surfaces["ce-flats"]
  if made then return made end
  return game.create_surface("ce-flats", {
    water = 0,
    cliff_settings = { cliff_elevation_0 = 1000, richness = 0 },
    autoplace_settings = {
      entity = { treat_missing_as_default = false, settings = {} },
      decorative = { treat_missing_as_default = false, settings = {} },
      tile = { treat_missing_as_default = false, settings = { ["grass-1"] = {} } },
    },
    property_expression_names = { cliffiness = 0, moisture = 0.5, aux = 0.5, elevation = 10 },
  })
end

---Get the player out of whatever they are riding, and take it away.
---@param player LuaPlayer
function world.unseat(player)
  local vehicle = player.vehicle
  if player.driving then player.driving = false end
  if vehicle and vehicle.valid then vehicle.destroy() end
end

return world
