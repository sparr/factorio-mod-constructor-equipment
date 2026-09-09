local build = require("lib.build")

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

--- 2.0 renamed the save table from global to storage, and filling it in at load time is
--- no longer allowed: the file is run before the save is read, so anything put there
--- would be thrown away or would desync. It is set up on_init instead, and again on
--- configuration_changed for a save that predates this.
local function setup()
  storage.constructor_last_build_tick = storage.constructor_last_build_tick or {}

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

---Whether this character is wearing the equipment, with enough charge to use it.
---@param character LuaEntity?
---@return boolean
local function ready(character)
  if not (character and character.valid) then return false end
  local grid = character.grid
  if not (grid and grid.valid) then return false end
  if grid.available_in_batteries <= BUILD_ENERGY_COST then return false end
  -- 2.0 turned get_contents into a list of { name, count, quality } rather than a
  -- table keyed by name, so it is searched instead of indexed
  for _, equipment in pairs(grid.get_contents()) do
    if equipment.name == "constructor-equipment" then return true end
  end
  return false
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

---Build one ghost near the player, if they are carrying what it takes to place it.
---@param player LuaPlayer
---@return boolean whether anything was built
local function build_one(player)
  local character = player.character
  if not ready(character) then return false end

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
      local _, built = ghost.revive()
      if built then
        storage.constructor_last_build_tick[player.index] = game.tick
        inventory.remove({ name = item, count = needed })
        spend(character.grid)
        slow(character)
        return true
      end
    end
  end

  return false
end

---@param event EventData.on_tick
local function on_tick(event)
  if event.tick % CHECK_INTERVAL ~= CHECK_TICK then return end

  for _, player in pairs(game.players) do
    -- A player without a character is not a rare case: it is every player during the
    -- opening cutscene, and anyone in the map editor or spectating. Reading
    -- character_running_speed_modifier without one raises "No character" outright, which
    -- is what 0.15 never had to think about because a player always had one.
    -- A build that was due and did not happen means there is nothing left in reach, which
    -- is when the character starts getting their speed back. Nothing of anyone else's is
    -- touched either way.
    local last = storage.constructor_last_build_tick[player.index]
    if player.character and build.due(event.tick, last, BUILD_INTERVAL) then
      if not build_one(player) then
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
    "test.ft.characterless",
    "test.ft.slowdown",
    "test.ft.interpolation",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
