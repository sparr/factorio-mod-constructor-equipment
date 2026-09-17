--- Stand a player on every mark in the showroom in turn and write down what the arms did.
---
--- Three bays have now been reported as "the arm appears and never moves" while the tests
--- covering them pass. That is a difference between the showroom and the replica, and the
--- only way to find it is to work the showroom itself. This does the standing, since a bay
--- takes a few hundred ticks to show what it does and there are twenty six of them.
---
--- Everything goes to the log rather than to script-output, because the log is what a
--- headless run leaves behind and it needs no reading of zip files to get at.
local SETTLE = 30   -- ticks to let the kit and the teleport land before counting
local WATCH = 420   -- how long to stand on each mark
local REACH = 12    -- how far round the mark to count things

local function surface()
  return game.surfaces[remote.call("ce-demo", "surface")]
end

---Everything worth knowing about the ground round a mark.
local function survey(at)
  local made = surface()
  local found = {
    ghosts = 0, upgrades = 0, doomed = 0, loose = 0, tiles = 0, cliffs = 0,
  }
  for _, thing in pairs(made.find_entities_filtered{ position = at, radius = REACH }) do
    if thing.valid then
      if thing.type == "entity-ghost" or thing.type == "tile-ghost" then
        found.ghosts = found.ghosts + 1
      elseif thing.type == "item-entity" then
        found.loose = found.loose + (thing.stack.valid_for_read and thing.stack.count or 0)
      elseif thing.type == "cliff" then
        found.cliffs = found.cliffs + 1
      end
      if thing.type == "deconstructible-tile-proxy" then found.tiles = found.tiles + 1 end
      local ok, marked = pcall(function() return thing.to_be_deconstructed() end)
      if ok and marked and thing.type ~= "item-entity" then found.doomed = found.doomed + 1 end
      local fine, up = pcall(function() return thing.to_be_upgraded() end)
      if fine and up then found.upgrades = found.upgrades + 1 end
    end
  end
  return found
end

---Where the arms are and what they are holding.
local function arms(player)
  local out, held, away = 0, 0, 0
  local from = player.character or player.vehicle
  for _, arm in pairs(surface().find_entities_filtered{
      position = player.position, radius = 10, type = "inserter" }) do
    if arm.valid and arm.name:find("constructor%-equipment") then
      out = out + 1
      if arm.held_stack.valid_for_read then held = held + arm.held_stack.count end
      if from then
        local dx = arm.held_stack_position.x - from.position.x
        local dy = arm.held_stack_position.y - from.position.y
        away = math.max(away, math.sqrt(dx * dx + dy * dy))
      end
    end
  end
  return out, held, away
end

local function say(text)
  log("CEPROBE " .. text)
end

script.on_event(defines.events.on_tick, function()
  local player = game.connected_players[1]
  if not player then return end
  storage.step = storage.step or 0
  storage.at = storage.at or 0
  storage.furthest = storage.furthest or 0

  if storage.step == 0 then
    storage.marks = remote.call("ce-demo", "marks")
    say(("start: %d marks"):format(#storage.marks))
    storage.step = 1
    storage.at = 1
    storage.since = game.tick
    return
  end

  local mark = storage.marks[storage.at]
  if not mark then
    if storage.step ~= 99 then
      say("DONE")
      storage.step = 99
    end
    return
  end

  local age = game.tick - storage.since

  if storage.step == 1 then
    -- kitted, then put down on the mark, then left alone for a moment to settle
    remote.call("ce-demo", "kit", player.index, mark.row)
    player.teleport({ mark.x, mark.y }, surface())
    storage.step = 2
    storage.since = game.tick
    storage.furthest = 0
    return
  end

  if storage.step == 2 then
    if age < SETTLE then return end
    storage.before = survey({ mark.x, mark.y })
    storage.held_before = player.get_main_inventory().get_contents()
    storage.step = 3
    storage.since = game.tick
    return
  end

  if storage.step == 3 then
    local _, _, away = arms(player)
    storage.furthest = math.max(storage.furthest, away)
    if age < WATCH then return end
    local after = survey({ mark.x, mark.y })
    local out, held = arms(player)
    local before = storage.before
    say(("row %d bay %d %-32s ghosts %d>%d upgrades %d>%d doomed %d>%d tiles %d>%d " ..
         "cliffs %d>%d loose %d>%d | arms %d holding %d reached %.1f"):format(
      mark.row, mark.bay, '"' .. mark.title .. '"',
      before.ghosts, after.ghosts, before.upgrades, after.upgrades,
      before.doomed, after.doomed, before.tiles, after.tiles,
      before.cliffs, after.cliffs, before.loose, after.loose,
      out, held, storage.furthest))
    storage.at = storage.at + 1
    storage.step = 1
    storage.since = game.tick
    return
  end
end)
