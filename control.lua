local build = require("lib.build")
local pack = require("lib.pack")
local reach = require("lib.reach")

local BUILD_RANGE = 4
local BUILD_PER_SECOND = 2
local CHECK_PER_SECOND = 10
local BUILD_ENERGY_COST = 1000000

--- The slowdown, and how long it lasts after the build that caused it. See
--- prototypes/sticker.lua for why it is a sticker and not a number on the character.
local SLOWDOWN = "constructor-equipment-slowdown"
local RECOVERY = "constructor-equipment-recovery"

local BUILD_INTERVAL = 60 / BUILD_PER_SECOND
local CHECK_INTERVAL = 60 / CHECK_PER_SECOND
local CHECK_TICK = CHECK_INTERVAL / 2

--- What the sticker's duration_in_ticks is set to, kept here so the tests and the
--- prototype agree: long enough to bridge the gap between two builds, so that building
--- steadily is one unbroken slowdown rather than a stutter.
local SLOWDOWN_TICKS = BUILD_INTERVAL + CHECK_INTERVAL + 9

--- How long the claw takes to swing one way. Out and back is a whole build, so the two of
--- them together are what BUILD_PER_SECOND actually buys.
local SWING_TICKS = BUILD_INTERVAL / 2

--- The inserter that does the reaching. See prototypes/inserter.lua.
local INSERTER = "constructor-equipment-inserter"

--- How close the hand has to get to the character to count as home again.
local HOME = 0.4

--- How close the hand has to get to the ghost to count as having arrived.
local ARRIVED = 0.3

--- 2.0 renamed the save table from global to storage, and filling it in at load time is
--- no longer allowed: the file is run before the save is read, so anything put there
--- would be thrown away or would desync. It is set up on_init instead, and again on
--- configuration_changed for a save that predates this.
local function setup()
  storage.constructor_last_build_tick = storage.constructor_last_build_tick or {}
  storage.constructor_inserter = storage.constructor_inserter or {}
  storage.constructor_reach = storage.constructor_reach or {}

  -- Older versions slowed the character by writing character_running_speed_modifier and
  -- remembering what had been there. A save from one of those can be carrying a player
  -- left at quarter speed, because the value was only put back on the tick after a build
  -- that did not happen. Give it back and forget the bookkeeping.
  local saved = storage.constructor_saved_running_speed_modifier
  if saved then
    for index, previous in pairs(saved) do
      local player = game.get_player(index)
      if player and player.character_running_speed_modifier == -0.75 then
        player.character_running_speed_modifier = previous or 0
      end
    end
    storage.constructor_saved_running_speed_modifier = nil
  end
end

---One of this mod's stickers on a character, if it is there.
---@param character LuaEntity
---@param name string
---@return LuaEntity?
local function sticker_on(character, name)
  for _, sticker in pairs(character.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---Slow the character down, or keep them slowed if they already are.
---
---Putting the same sticker on a character who already has it does not give them two: the
---engine keeps the one and starts its life over. So a run of builds is one unbroken
---slowdown without this having to find the old sticker and reset it, and the character
---never speeds up in the middle. test/ft/slowdown.lua pins that, since it is the engine's
---behaviour and not this mod's.
---
---The recovery sticker has to go, though. It is a different prototype, so the engine
---would keep both and multiply them together, and a character who started speeding up and
---then found something else to build would end up slower than one who never stopped.
---@param character LuaEntity
local function slow(character)
  local recovery = sticker_on(character, RECOVERY)
  if recovery then recovery.destroy() end
  character.surface.create_entity{
    name = SLOWDOWN,
    position = character.position,
    target = character,
  }
end

---Let a character who has run out of things to build come back up to speed.
---
---The slowdown is flat while there is work, because its own life keeps being restarted
---and the interpolation would restart with it -- which would read as stuttering rather
---than as effort. The ramp belongs at the end, where there is one of it. So the flat
---sticker is swapped for one that interpolates from a quarter speed back to full over its
---lifetime, and the engine walks it up as its life runs down.
---@param character LuaEntity
local function recover(character)
  local slowdown = sticker_on(character, SLOWDOWN)
  if not slowdown then return end
  slowdown.destroy()
  character.surface.create_entity{
    name = RECOVERY,
    position = character.position,
    target = character,
  }
end

---Whether this character has the equipment in their armour at all.
---
---Separate from being able to use it: the inserter is strapped to their back whether or
---not there is any charge to work it with, so this is what decides whether it is drawn.
---@param character LuaEntity?
---@return boolean
local function wearing(character)
  if not (character and character.valid) then return false end
  local grid = character.grid
  if not (grid and grid.valid) then return false end
  -- 2.0 turned get_contents into a list of { name, count, quality } rather than a
  -- table keyed by name, so it is searched instead of indexed
  for _, equipment in pairs(grid.get_contents()) do
    if equipment.name == "constructor-equipment" then return true end
  end
  return false
end

---Whether this character is wearing the equipment and can afford to use it.
---@param character LuaEntity?
---@return boolean
local function ready(character)
  if not wearing(character) then return false end
  local grid = character.grid
  return grid.available_in_batteries > BUILD_ENERGY_COST
end

---Take the cost of one build out of the batteries in the grid.
---@param grid LuaEquipmentGrid
local function spend(grid)
  local owing = BUILD_ENERGY_COST
  for _, equipment in pairs(grid.equipment) do
    if equipment.energy >= owing then
      equipment.energy = equipment.energy - owing
      return
    end
    owing = owing - equipment.energy
    equipment.energy = 0
  end
end

---Find something to build and what to build it with.
---@param player LuaPlayer
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
local function find_job(player)
  local character = player.character
  if not ready(character) then return nil end

  local nearby_ghosts = player.surface.find_entities_filtered{
    area = {{player.position.x - BUILD_RANGE, player.position.y - BUILD_RANGE},
            {player.position.x + BUILD_RANGE, player.position.y + BUILD_RANGE}},
    type = "entity-ghost"
  }

  -- the separate quickbar went away in 0.17; what is left is the character's own
  -- inventory, and the quickbar is a set of references into it
  local inventory = player.get_inventory(defines.inventory.character_main)
  if not inventory then return false end
  local function carried(name) return inventory.get_item_count(name) end

  for _, ghost in pairs(nearby_ghosts) do
    -- 2.0 turned items_to_place_this into a list of { name, count } rather than a table
    -- keyed by item name
    local item, needed = build.placing_item(ghost.ghost_prototype.items_to_place_this, carried)
    if item then
      return ghost, item, needed
    end
  end

  return nil
end

---Where the claw hangs when it is at rest, which is the shoulder the arm swings from.
---@param character LuaEntity
---@return {x: number, y: number}
local function shoulder(character)
  local at = character.position
  return { x = at.x, y = at.y + pack.HEIGHT }
end

---The inserter belonging to a character, made if it is not there yet.
---@param player LuaPlayer
---@return LuaEntity?
local function arm_of(player)
  local character = player.character
  local arm = storage.constructor_inserter[player.index]
  if not (arm and arm.valid) then
    arm = character.surface.create_entity{
      name = INSERTER,
      position = character.position,
      force = player.force,
    }
    storage.constructor_inserter[player.index] = arm
  end
  return arm
end

---Take the inserter away, emptying its hand first so nothing is conjured out of it.
---@param player LuaPlayer
local function put_away(player)
  local arm = storage.constructor_inserter[player.index]
  if arm and arm.valid then
    if arm.held_stack.valid_for_read then arm.held_stack.clear() end
    arm.destroy()
  end
  storage.constructor_inserter[player.index] = nil
end

---Keep the inserter on the character and pointed at whatever it is reaching for.
---
---Both ends are set every tick. The pickup end is the character, so the hand comes home to
---them rather than to wherever they were standing when the swing began. The drop end has to
---be re-aimed as well, because an inserter's drop position travels with the inserter: move
---the entity and the target moves with it, so a fixed vector would drift off the ghost as
---the character walked.
---@param player LuaPlayer
---@param job table? what it is reaching for, if anything
---@return LuaEntity? the inserter
local function aim(player, job)
  local character = player.character
  local arm = arm_of(player)
  if not (arm and arm.valid) then return nil end

  local here = character.position
  local offset = pack.offset(character.direction)
  arm.teleport({ here.x + offset.x, here.y + offset.y })
  arm.pickup_position = { here.x, here.y }
  if job then
    arm.drop_position = { job.target.x, job.target.y }
  end
  return arm
end

---Give up on a reach without building anything.
---
---The item in the hand was never taken out of the inventory, so letting go of it is enough:
---nothing has to be given back.
---@param player LuaPlayer
---@param job table
local function abandon(player, job)
  local arm = storage.constructor_inserter[player.index]
  if arm and arm.valid and arm.held_stack.valid_for_read then
    arm.held_stack.clear()
  end
  job.going = "back"
  job.ghost = nil
end

---Put the thing down: revive the ghost, pay for it, and let the arm start coming home.
---@param player LuaPlayer
---@param job table
local function deliver(player, job)
  local character = player.character
  local inventory = player.get_inventory(defines.inventory.character_main)
  local ghost = job.ghost

  -- The hand is emptied here rather than by the engine. An inserter will not drop onto a
  -- tile something is standing on, and a ghost counts: left to itself it swings out, finds
  -- the ghost in the way, and waits there holding the item for ever. So arriving is what
  -- counts as delivery, and the item is taken out of the hand at that moment.
  local arm = storage.constructor_inserter[player.index]
  if arm and arm.valid and arm.held_stack.valid_for_read then
    arm.held_stack.clear()
  end

  if ghost and ghost.valid and inventory
      and inventory.get_item_count(job.item) >= job.count then
    local _, built = ghost.revive()
    if built then
      inventory.remove({ name = job.item, count = job.count })
      spend(character.grid)
      slow(character)
    end
  end
  job.going = "back"
  job.ghost = nil
end

---Move a reach on by one tick.
---
---The swing is the inserter's own, so this does not drive it. It watches: the hand empties
---when the engine drops what it was carrying, which is the moment of delivery, and the
---hand coming back to the character is the end of the job.
---@param player LuaPlayer
local function advance(player)
  local job = storage.constructor_reach[player.index]
  local character = player.character

  if not (character and character.valid) then
    storage.constructor_reach[player.index] = nil
    return
  end

  local arm = aim(player, job)
  if not (arm and job) then return end

  if job.going == "out" then
    -- the character can walk off mid swing, and an arm that stretched to follow would be
    -- no kind of inserter
    if not (job.ghost and job.ghost.valid)
        or reach.out_of_range(character.position, job.ghost.position, BUILD_RANGE) then
      abandon(player, job)
    elseif reach.distance(arm.held_stack_position, job.target) < ARRIVED then
      -- the hand has got there, which is as far as the engine will take it
      deliver(player, job)
    end
  elseif reach.distance(arm.held_stack_position, character.position) < HOME then
    storage.constructor_reach[player.index] = nil
  end
end

---@param event EventData.on_tick
local function on_tick(event)
  for _, player in pairs(game.players) do
    if player.character and wearing(player.character) then
      advance(player)
    elseif storage.constructor_inserter[player.index] then
      -- taken off, or the character is gone: no arm and no half finished swing
      storage.constructor_reach[player.index] = nil
      put_away(player)
    end
  end

  if event.tick % CHECK_INTERVAL ~= CHECK_TICK then return end

  for _, player in pairs(game.players) do
    -- A build that was due and did not happen means there is nothing left in reach, which
    -- is when the character starts getting their speed back. Nothing of anyone else's is
    -- touched either way.
    local last = storage.constructor_last_build_tick[player.index]
    if player.character and not storage.constructor_reach[player.index]
        and build.due(event.tick, last, BUILD_INTERVAL) then
      local ghost, item, count = find_job(player)
      if ghost then
        -- counted from the start of the swing rather than the end of it, so the rate is
        -- BUILD_PER_SECOND as it always was: the claw gets home exactly as the next one
        -- falls due
        storage.constructor_last_build_tick[player.index] = event.tick
        storage.constructor_reach[player.index] = {
          ghost = ghost,
          target = ghost.position,
          item = item,
          count = count,
          going = "out",
        }
        -- filled from nothing, not from the inventory: the item is only really spent if
        -- it arrives, so walking away costs nothing
        local arm = aim(player, storage.constructor_reach[player.index])
        if arm then arm.held_stack.set_stack{ name = item, count = count } end
      else
        recover(player.character)
      end
    end
  end
end

script.on_init(setup)
script.on_configuration_changed(setup)
script.on_event(defines.events.on_tick, on_tick)

--- ce-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["ce-tests"] then
  require("__factorio-test__/init")({
    "test.ft.building",
    "test.ft.delivering",
    "test.ft.characterless",
    "test.ft.slowdown",
    "test.ft.interpolation",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
