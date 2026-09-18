--- Photograph the showroom bays whose faults are in how they look rather than in what they
--- do.
---
--- The probe beside this says what the arms did; some of the walk round's complaints are
--- about where a claw is drawn, and there is no reading that off a log. So this stands a
--- player on a mark, waits for the arms to be out and working, and takes a picture.
---
--- Pictures land in script-output/shots.
local SETTLE = 70    -- long enough for an arm to be out and mid reach, short enough that it still is

--- Which marks to photograph, by the title the showroom gives the bay, and how close.
local WANTED = {
  { title = "Arms on the hull", zoom = 4, drive = true, facing = defines.direction.east },
  { title = "Arms on the hull", zoom = 4, drive = true, facing = defines.direction.north },
  { title = "Arms on a train", zoom = 2.5, drive = true },
}

local function marks()
  return remote.call("ce-demo", "marks")
end

local function say(line)
  log("CESHOT " .. line)
end

script.on_event(defines.events.on_tick, function()
  local player = game.players[1]
  if not (player and player.valid) then return end

  storage.shot = storage.shot or { at = 0, waited = 0 }
  local state = storage.shot

  if state.done then return end

  if state.waited == 0 then
    state.at = state.at + 1
    local wanted = WANTED[state.at]
    if not wanted then
      state.done = true
      say("DONE")
      return
    end
    if state.riding and state.riding.valid then state.riding.set_driver(nil) end
    state.riding = nil
    local found
    for _, mark in pairs(marks()) do
      if mark.title == wanted.title then found = mark break end
    end
    if not found then
      say(("no mark called %q"):format(wanted.title))
      state.waited = 0
      return
    end
    state.mark = found
    -- The row's own kit, so the bay has what it needs, and then stand on the mark.
    remote.call("ce-demo", "kit", player.index, found.row)
    local made = game.surfaces[remote.call("ce-demo", "surface")]
    player.teleport({ found.x, found.y }, made)
    -- A vehicle row's arms are the vehicle's, and a vehicle nobody is driving wears none:
    -- the mod works for whoever is at the controls. So get in whatever is standing here.
    if wanted.drive then
      local best, near
      for _, thing in pairs(made.find_entities_filtered{
          position = { found.x, found.y }, radius = 30,
          type = { "car", "spider-vehicle", "locomotive" } }) do
        local away = (thing.position.x - found.x) ^ 2 + (thing.position.y - found.y) ^ 2
        if not near or away < near then best, near = thing, away end
      end
      if best then
        best.set_driver(player)
        state.riding = best
        -- Turned to face the way this shot wants it, since what a hull's arms look like
        -- depends on which way round the hull is.
        if wanted.facing then
          local ok = pcall(function() best.orientation = wanted.facing / 16 end)
          if not ok then best.direction = wanted.facing end
        end
        -- Something for the arms to be doing. A vehicle parked at the end of its row has
        -- either finished its own row or never reached it, and an arm with nothing to do is
        -- an arm nobody can photograph, so fresh ghosts go down along both flanks -- which
        -- is where a hull's arms are bolted and so what they can reach.
        local laid = 0
        for along = -2, 2 do
          for _, side in pairs{ -3, 3 } do
            local spot = { best.position.x + along, best.position.y + side }
            if made.count_entities_filtered{ position = spot, radius = 0.4 } == 0 then
              if made.create_entity{ name = "entity-ghost", inner_name = "transport-belt",
                  position = spot, force = player.force } then
                laid = laid + 1
              end
            end
          end
        end
        -- And something to build them out of, and a full grid: a vehicle standing about has
        -- neither been charging nor been loaded.
        local hold = best.get_inventory(defines.inventory.cargo_wagon)
          or best.get_inventory(defines.inventory.car_trunk)
          or best.get_inventory(defines.inventory.spider_trunk)
        if hold then hold.insert{ name = "transport-belt", count = 50 } end
        for _, wagon in pairs(best.train and best.train.cargo_wagons or {}) do
          wagon.insert{ name = "transport-belt", count = 50 }
        end
        local grid = best.grid
        if grid then
          for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
        end
        say(("driving a %s, %d ghosts laid beside it"):format(best.name, laid))
      else
        say("nothing to drive here")
      end
    end
    state.waited = 1
    return
  end

  state.waited = state.waited + 1
  if state.waited < SETTLE then return end

  local wanted = WANTED[state.at]
  local mark = state.mark
  -- Centred on whatever is being photographed rather than on the mark, since a vehicle is
  -- parked a bay east of it.
  local middle = (state.riding and state.riding.valid) and state.riding.position
    or (mark and { x = mark.x + 4, y = mark.y })
  if mark then
    local name = wanted.title:lower():gsub("[^%w]+", "-")
      .. (wanted.facing and ("-facing-" .. wanted.facing) or "")
    game.take_screenshot{
      player = player,
      surface = game.surfaces[remote.call("ce-demo", "surface")],
      position = { middle.x, middle.y },
      resolution = { 1000, 800 },
      zoom = wanted.zoom,
      path = "shots/" .. name .. ".png",
      show_gui = false,
      show_entity_info = false,
      daytime = 0,
      water_tick = 0,
    }
    say(("took %s at %.1f,%.1f"):format(name, middle.x, middle.y))
  end
  -- Left sitting there. A screenshot is rendered at the end of the tick, and getting out
  -- on the same tick put the character on the grass beside the vehicle in the picture.
  state.waited = 0
end)
