--- A game laid out for trying the equipment by hand, rather than for a test to measure.
---
--- What it sets up is the whole of what the mod does, in one place: the arms on a
--- character's back, the arms on the three kinds of vehicle that can carry them, and enough
--- ghosts to watch any of them work. Everything is researched and everything is stocked, so
--- a session begins with the thing being tried rather than with an hour of setting up.
---
--- Loaded only by test/play.sh, which is the only thing that puts this mod in a mod list.

--- How far out from the spawn each vehicle stands, and how far apart they are. Far enough
--- apart that one vehicle's arms cannot reach another's ghosts, so what built what is never
--- in question.
local SPACING = 16

--- What goes in a vehicle that has a grid: as many arms as its grid has room for beside a
--- battery, and something for them to build with.
---
--- Two tiers rather than one, because a mixture is the interesting case: each arm keeps its
--- own reach and its own pace.
local FITTING = { "constructor-equipment", "constructor-equipment-3", "battery-equipment" }

--- A plain belt is the thing to watch an arm build: cheap, one item per ghost, and the
--- claw's load is visible in its hand all the way out.
local GHOST = "transport-belt"

---The first of these the game has heard of.
---
---The harness runs with the expansion or without it, and the expansion has the better
---batteries and the better reactor. Asking for the best of them by name and falling back
---rather than naming the base game's own everywhere means one line changes when a session
---is run the other way, which is none.
---@param names string[] best first
---@param known table<string, any> the prototypes to look them up in
---@return string?
local function best_of(names, known)
  for _, name in ipairs(names) do
    if known[name] then return name end
  end
  return nil
end

---Put a piece of equipment in a grid, if there is such a piece in this game.
---@param grid LuaEquipmentGrid
---@param names string[] best first
local function fit(grid, names)
  local name = best_of(names, prototypes.equipment)
  if name then grid.put{ name = name } end
end

--- What keeps the arms fed. A reactor rather than solar panels, because an arm that stops
--- at dusk is a play test that stops at dusk.
local REACTOR = { "fusion-reactor-equipment", "fission-reactor-equipment" }
local BATTERY = { "battery-mk3-equipment", "battery-mk2-equipment", "battery-equipment" }

---Make room. A spawn is full of trees and rocks, and a vehicle asked for a spot one is
---standing in is not placed at all: the first version of this laid out a tank that was
---never there, and a ring of ghosts that nothing could build because the trees between them
---were still up.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param radius number
local function clear(surface, at, radius)
  for _, thing in pairs(surface.find_entities_filtered{
        position = at, radius = radius,
        type = { "tree", "simple-entity", "cliff", "fish", "item-entity" } }) do
    thing.destroy()
  end
  surface.destroy_decoratives{ position = at, radius = radius }
end

---Ghosts in a ring around something, which is the arrangement that shows which arm reached
---for what: every arm has ground on its own side of the hull.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param force LuaForce
---@param radius number
---@param count integer
local function ring(surface, at, force, radius, count)
  for step = 0, count - 1 do
    local angle = step / count * 2 * math.pi
    surface.create_entity{
      name = "entity-ghost",
      inner_name = GHOST,
      position = { at.x + math.cos(angle) * radius, at.y + math.sin(angle) * radius },
      force = force,
    }
  end
end

---Put a vehicle down, fit it out, and give it something to build.
---@param player LuaPlayer
---@param name string
---@param at {x: number, y: number}
---@return LuaEntity?
local function vehicle(player, name, at)
  local surface = player.surface
  clear(surface, at, 8)
  local spot = surface.find_non_colliding_position(name, at, 16, 0.5) or at
  local made = surface.create_entity{
    name = name, position = spot, force = player.force, raise_built = true }
  if not made then
    player.print("ce-play could not put down a " .. name)
    return nil
  end
  -- Only what burns anything: a spidertron runs off its own grid and would take the fuel
  -- into its boot, where it is nothing but clutter in a hold the arms spend out of.
  if made.burner then
    made.insert{ name = best_of({ "nuclear-fuel", "rocket-fuel", "solid-fuel", "coal" },
      prototypes.item) or "coal", count = 10 }
  end

  -- A car has no equipment grid in the base game, which is worth having here rather than
  -- leaving out: it is the case where a driver's own armour goes quiet and nothing takes
  -- over, and a player who has not read the changelog will meet it first.
  local grid = made.grid
  if grid then
    for _, piece in pairs(FITTING) do grid.put{ name = piece } end
    fit(grid, REACTOR)
    fit(grid, BATTERY)
    for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
    -- the vehicle's own hold is what its arms spend
    made.insert{ name = GHOST, count = 200 }
  end

  ring(surface, made.position, player.force, 4, 16)
  return made
end

---Everything a player needs to try the mod, on themselves and on wheels.
---@param player LuaPlayer
local function lay_out(player)
  local force = player.force
  force.research_all_technologies()

  -- The character's own kit, which is the mod as it was before any of this: an armour with
  -- an arm in it, a battery to work it, and a pocketful of belts.
  player.insert{ name = "power-armor-mk2", count = 1 }
  local armour = player.get_inventory(defines.inventory.character_armor)[1]
  if armour and armour.grid then
    for _, piece in pairs(FITTING) do armour.grid.put{ name = piece } end
    fit(armour.grid, REACTOR)
    fit(armour.grid, BATTERY)
    for _, piece in pairs(armour.grid.equipment) do piece.energy = piece.max_energy end
  end
  player.insert{ name = GHOST, count = 400 }

  -- Spares, so a session can try other tiers, more arms, or a vehicle of its own without
  -- going to a chest for them.
  for level = 1, 4 do
    player.insert{ name = level == 1 and "constructor-equipment"
      or ("constructor-equipment-" .. level), count = 5 }
  end
  player.insert{ name = best_of(BATTERY, prototypes.item) or "battery-equipment", count = 5 }
  player.insert{ name = "car", count = 1 }
  player.insert{ name = "tank", count = 1 }
  player.insert{ name = "spidertron", count = 1 }

  local at = player.position
  clear(player.surface, at, 8)
  ring(player.surface, at, force, 4, 16)
  vehicle(player, "car", { x = at.x + SPACING, y = at.y })
  vehicle(player, "tank", { x = at.x + SPACING * 2, y = at.y })
  vehicle(player, "spidertron", { x = at.x + SPACING * 3, y = at.y })

  player.print("Constructor Equipment play test: a ring of ghosts here, then a car, a tank"
    .. " and a spidertron to the east, each in a ring of its own. The car has no equipment"
    .. " grid, so your armour goes quiet while you drive it. The toolbar button switches"
    .. " your arms off.")
end

script.on_init(function()
  -- Freeplay makes the crashed ship in on_player_created rather than on_init, so that mods
  -- can call in first, and the cutscene is what would otherwise reposition the player after
  -- everything below has been laid out.
  if remote.interfaces["freeplay"] then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if player then lay_out(player) end
end)
