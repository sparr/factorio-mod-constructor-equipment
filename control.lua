local function debug(...)
  if game and game.players[1] then
    game.players[1].print(serpent.block(...,{comment=false}))
  end
end

local BUILD_RANGE = 4
local BUILD_PER_SECOND = 2
local CHECK_PER_SECOND = 10
local BUILD_ENERGY_COST = 1000000
local BUILD_RUNNING_SPEED_MODIFIER = -0.75

local BUILD_INTERVAL = 60 / BUILD_PER_SECOND
local CHECK_INTERVAL = 60 / CHECK_PER_SECOND
local CHECK_TICK = CHECK_INTERVAL / 2

global.constructor_last_build_tick = global.constructor_last_build_tick or {}
global.constructor_saved_running_speed_modifier = global.constructor_saved_running_speed_modifier or {}

local function onTick(event)
  if event.tick % CHECK_INTERVAL == CHECK_TICK then
    for _, player in pairs(game.players) do
      if global.constructor_last_build_tick[player.index] == nil or
         event.tick >= global.constructor_last_build_tick[player.index] + BUILD_INTERVAL then
        local built = false
        if player.character.grid and
           player.character.grid.available_in_batteries > BUILD_ENERGY_COST and
           player.character.grid.get_contents()["constructor-equipment"] ~= nil
           then
          -- find all ghosts in range
          nearby_ghosts = player.surface.find_entities_filtered{
            area = {{player.position.x-BUILD_RANGE,player.position.y-BUILD_RANGE},
                    {player.position.x+BUILD_RANGE,player.position.y+BUILD_RANGE}},
            type = "entity-ghost"
          }
          if #nearby_ghosts > 0 then
            -- loop through all the ghosts
            for _, ghost in ipairs(nearby_ghosts) do
              -- loop through all the items that could place that ghost
              for item, _ in pairs(ghost.ghost_prototype.items_to_place_this) do
                -- loop through all the places the player might have the item
                for _, inv in ipairs({defines.inventory.player_quickbar,defines.inventory.player_main}) do
                  if player.get_inventory(inv).get_item_count(item) > 0 then
                    -- try to build the entity
                    collision_items, new_entity = nearby_ghosts[1].revive()
                    if new_entity ~= nil then
                      -- success
                      global.constructor_last_build_tick[player.index] = event.tick
                      player.get_inventory(inv).remove({name = item, count = 1})
                      local energy_to_consume = BUILD_ENERGY_COST
                      for _, equipment in ipairs(player.character.grid.equipment) do
                        if equipment.energy >= energy_to_consume then
                          equipment.energy = equipment.energy - energy_to_consume
                          break
                        else
                          energy_to_consume = energy_to_consume - equipment.energy
                          equipment.energy = 0
                        end
                      end
                      if player.character_running_speed_modifier ~= BUILD_RUNNING_SPEED_MODIFIER then
                        global.constructor_saved_running_speed_modifier[player.index] = player.character_running_speed_modifier
                      end
                      player.character_running_speed_modifier = BUILD_RUNNING_SPEED_MODIFIER
                      built = true
                      break
                    end
                  end
                end
                if built then break end
              end
              if built then break end
            end
          end
        end
        --TODO smoothly accelerate
        --TODO make compatible with ProgressiveRunning and other mods that change character_running_speed_modifier
        if (not built) and player.character_running_speed_modifier == BUILD_RUNNING_SPEED_MODIFIER then
          player.character_running_speed_modifier = global.constructor_saved_running_speed_modifier[player.index]
        end
      end
    end
  end
end

script.on_event(defines.events.on_tick, onTick)
