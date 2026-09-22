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
--- for the inserter the tier borrows from, so this is measured rather than set. Measured at
--- two tiles, six runs: the claw sets off within a check tick of the ghost appearing and
--- delivers 37 ticks after that, so a ghost put down at an arbitrary tick is built between
--- tick 38 and tick 43, and the claw is home again by tick 89.
---
--- It was 26 for a while, when an arm's hand extended half again as fast as the inserter's
--- and turned a third slower. That was worth having only while an arm was built facing
--- north whatever it was about to reach for: an arm pointed at what it is reaching for
--- hardly turns at all, so the faster extension was buying back a cost that no longer
--- exists, and the tiers are on the inserters' own numbers again. Every window in the tests
--- is built from this one, so re-measuring it is what a change to the tiers' speeds costs.
world.SWING_TICKS = 41

--- Comfortably after a swing has reached its target and delivered, and before it is home
--- again. Both ends matter: tests wait this long to see what was delivered, and others wait
--- this long to see what the claw is still holding on its way back.
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
  -- The cursor too, which is a pocket as far as the arms are concerned: a stack held there
  -- is out of the inventory and still gets spent. A test that left one there handed the
  -- next a character who looked empty-handed and was not, so every test about an arm with
  -- nothing to pay with quietly built something.
  local cursor = player.cursor_stack
  if cursor and cursor.valid and cursor.valid_for_read then cursor.clear() end
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
---The smallest armour every one of these will fit in.
---
---Asked rather than assumed, because the equipment does not all fit the same grid: the
---fourth tier is two by six and a modular armour is five by five, so a test naming modular
---armour by habit would get an armour with no room in it and an arm that never appeared.
---@param equipment string[]
---@return string
local function armour_for(equipment)
  local tall, wide = 0, 0
  for _, name in pairs(equipment) do
    local shape = prototypes.equipment[name] and prototypes.equipment[name].shape
    if shape then
      tall = math.max(tall, shape.height)
      wide = math.max(wide, shape.width)
    end
  end
  for _, try in ipairs{ "modular-armor", "power-armor", "power-armor-mk2" } do
    local grid = prototypes.item[try] and prototypes.item[try].equipment_grid
    if grid and grid.width >= wide and grid.height >= tall then return try end
  end
  return "power-armor-mk2"
end

function world.equip(player, equipment, charged, armour)
  player.insert{ name = armour or armour_for(equipment) }
  local armour = player.get_inventory(defines.inventory.character_armor)[1]
  local grid = armour.grid
  -- A name, or { name, quality } for a piece that is not the ordinary one.
  for _, want in pairs(equipment) do
    if type(want) == "table" then
      grid.put{ name = want[1] or want.name, quality = want[2] or want.quality }
    else
      grid.put{ name = want }
    end
  end
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

---What an inventory looks like, slot by slot, for a test that cares where things are.
---
---Only worth asserting against with the game's own sorting turned off: left on, it
---rearranges the character's pockets by itself between one tick and the next.
---@param inventory LuaInventory
---@param upto integer how many slots to describe
---@return string
function world.picture(inventory, upto)
  local slots = {}
  for index = 1, upto do
    local stack = inventory[index]
    slots[#slots + 1] = index .. "=" .. (stack.valid_for_read
      and (stack.name .. "x" .. stack.count) or "-")
  end
  return table.concat(slots, " ")
end

---A thing standing in the arena with an upgrade order hung on it, which is what the
---upgrade planner actually leaves behind.
---
---There is no ghost anywhere in this: the belt stays where it was and the order sits on
---it, which is why none of the ghost fixtures above stand in for one.
---@param player LuaPlayer
---@param name string what is standing there now
---@param target string what it is to become
---@param dx number
---@param dy number
---@return LuaEntity
function world.to_upgrade(player, name, target, dx, dy)
  local entity = player.surface.create_entity{
    name = name,
    position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
    direction = defines.direction.east,
    force = player.force,
  }
  assert(entity, "could not place a " .. name)
  entity.order_upgrade{ force = player.force, target = prototypes.entity[target] }
  assert(entity.to_be_upgraded(), name .. " would not take an upgrade order")
  return entity
end

---A cliff in the arena, marked for deconstruction.
---
---Cliffs are placed rather than generated, so which way it lies is said outright. Returns
---nothing if the game will not put one there, which a test should skip on rather than fail.
---@param player LuaPlayer
---@param dx number
---@param dy number
---@return LuaEntity?
function world.cliff(player, dx, dy)
  -- A cliff cannot be marked at all until the force knows how to blow one up, which is the
  -- game's own gate rather than the mod's.
  local technology = player.force.technologies["cliff-explosives"]
  if technology then technology.researched = true end
  local ok, cliff = pcall(function()
    return player.surface.create_entity{
      name = "cliff",
      position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
      cliff_orientation = "west-to-east",
      force = "neutral",
    }
  end)
  if not (ok and cliff) then return nil end
  cliff.order_deconstruction(player.force)
  return cliff
end

---Fill every free slot of the pockets, so that nothing else will fit in them.
---@param player LuaPlayer
function world.fill_pockets(player)
  local main = player.get_inventory(defines.inventory.character_main)
  assert(main, "the character has no pockets to fill")
  for index = 1, #main do
    if not main[index].valid_for_read then
      main[index].set_stack{ name = "iron-plate", count = 100 }
    end
  end
  assert.are.equal(0, main.count_empty_stacks(), "the pockets did not fill")
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

---Wait for something to be so, rather than for a number of ticks.
---
---A window counted in ticks is a guess about how long an arm takes, and it goes stale the
---moment anything changes what a reach costs: a fixture meaning "while the claw is out"
---that says "on tick thirty" quietly starts measuring an arm that is already home. Where
---what a test is waiting for can be asked of the world, it should be asked.
---
---Gives up after a limit, so a condition that never comes is a failure that says what it
---was waiting for rather than a test that runs to the end of its timeout.
---@param condition fun(): boolean
---@param act fun() what to do on the first tick it holds
---@param complaint string what to say if it never holds
---@param limit integer? how long to wait, defaulting to a whole out and back
function world.once(condition, act, complaint, limit)
  local began = game.tick
  limit = limit or world.CYCLE
  on_tick(function()
    if condition() then
      act()
      return false
    end
    if game.tick - began > limit then
      assert.is_true(false, ("waited %d ticks: %s"):format(limit, complaint))
      return false
    end
  end)
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
