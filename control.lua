local build = require("lib.build")

local BUILD_RANGE = 4
local BUILD_PER_SECOND = 2
local CHECK_PER_SECOND = 10
local BUILD_ENERGY_COST = 1000000
local BUILD_RUNNING_SPEED_MODIFIER = -0.75

local BUILD_INTERVAL = 60 / BUILD_PER_SECOND
local CHECK_INTERVAL = 60 / CHECK_PER_SECOND
local CHECK_TICK = CHECK_INTERVAL / 2

--- 2.0 renamed the save table from global to storage, and filling it in at load time is
--- no longer allowed: the file is run before the save is read, so anything put there
--- would be thrown away or would desync. It is set up on_init instead, and again on
--- configuration_changed for a save that predates this.
local function setup()
  storage.constructor_last_build_tick = storage.constructor_last_build_tick or {}
  storage.constructor_saved_running_speed_modifier =
    storage.constructor_saved_running_speed_modifier or {}
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
    local item = build.placing_item(ghost.ghost_prototype.items_to_place_this, carried)
    if item then
      -- FIXME reviving nearby_ghosts[1] rather than ghost is wrong: the item is taken for
      -- whichever ghost matched and the first ghost in the list is built instead. Left as
      -- it was written so that this tier changes no behaviour; test/ft has the case,
      -- skipped, for 2.1.2.
      local _, built = nearby_ghosts[1].revive()
      if built then
        storage.constructor_last_build_tick[player.index] = game.tick
        inventory.remove({ name = item, count = 1 })
        spend(character.grid)
        if player.character_running_speed_modifier ~= BUILD_RUNNING_SPEED_MODIFIER then
          storage.constructor_saved_running_speed_modifier[player.index] =
            player.character_running_speed_modifier
        end
        player.character_running_speed_modifier = BUILD_RUNNING_SPEED_MODIFIER
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
    local last = storage.constructor_last_build_tick[player.index]
    if player.character and build.due(event.tick, last, BUILD_INTERVAL) then
      local built = build_one(player)
      --TODO smoothly accelerate
      --TODO make compatible with ProgressiveRunning and other mods that change
      --     character_running_speed_modifier
      if (not built)
          and player.character_running_speed_modifier == BUILD_RUNNING_SPEED_MODIFIER then
        player.character_running_speed_modifier =
          storage.constructor_saved_running_speed_modifier[player.index] or 0
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
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
