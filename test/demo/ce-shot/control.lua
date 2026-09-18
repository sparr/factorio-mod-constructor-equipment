--- Photograph the showroom bays whose faults are in how they look rather than in what they
--- do.
---
--- The probe beside this says what the arms did; some of the walk round's complaints are
--- about where a claw is drawn, and there is no reading that off a log. So this stands a
--- player on a mark, waits for the arms to be out and working, and takes a picture.
---
--- Pictures land in script-output/shots.
local SETTLE = 240   -- long enough for the kit, the teleport and an arm to be out working

--- Which marks to photograph, by the title the showroom gives the bay, and how close.
local WANTED = {
  { title = "Arms on the legs", zoom = 2.5 },
  { title = "Arms on a train", zoom = 2 },
  { title = "Arms on the hull", zoom = 2.5 },
  { title = "Four arms, four reaches", zoom = 1.2 },
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
    player.teleport({ found.x, found.y },
      game.surfaces[remote.call("ce-demo", "surface")])
    state.waited = 1
    return
  end

  state.waited = state.waited + 1
  if state.waited < SETTLE then return end

  local wanted = WANTED[state.at]
  local mark = state.mark
  if mark then
    local name = wanted.title:lower():gsub("[^%w]+", "-")
    game.take_screenshot{
      player = player,
      surface = game.surfaces[remote.call("ce-demo", "surface")],
      position = { mark.x + 4, mark.y },
      resolution = { 1000, 800 },
      zoom = wanted.zoom,
      path = "shots/" .. name .. ".png",
      show_gui = false,
      show_entity_info = false,
      daytime = 0,
      water_tick = 0,
    }
    say(("took %s at %.1f,%.1f"):format(name, mark.x, mark.y))
  end
  state.waited = 0
end)
