--- The one reproduction of the standing-still stall, laid out to be watched by hand.
---
--- Eight transport belts marked for deconstruction in a ring round a character wearing a
--- fourth tier arm. Three of them are taken up and then the claw takes a job on a fourth,
--- reports itself working, and never extends towards it. The same eight two tiles further
--- out go in a couple of seconds.
---
--- The stall is invisible in an ordinary game, because everything that decides it is a
--- position nothing draws: where the claw is aimed, where its box is standing, and which of
--- them the engine has resolved. So this draws them. What was traced from the fixtures is
--- all here to be looked at rather than read out of a log:
---
---   white ring    the arm's own base, where its reach is measured from
---   yellow dot    the claw, wherever the engine has actually put it
---   green cross   where the claw is told to pick up from
---   red cross     where it is told to drop
---   green square  the box a fetch fills, which stands at the pickup
---   blue square   the box an idle claw is parked against so it cannot help itself
---   orange line   base to pickup: the journey the hand is refusing to make
---
--- Commands:
---   /ce-stall   lay the ring out again
---   /ce-ring N  lay it out N tiles from the character instead of one, for the case that works
---   /ce-arm     print everything about the arm, once
---   /ce-watch   print that line on every tick it changes
---   /ce-draw    turn the markers on and off
---
--- Loaded only by test/stall.sh, which is the only thing that puts this mod in a mod list.

--- What the ring is made of. A plain belt: one item per pickup, and the claw's load shows
--- in its hand all the way home.
-- Across the mod boundary, which is how one mod reads another's file: a bare path is
-- looked for inside this mod and nowhere else.
local tiers = require("__constructor-equipment__/lib/tiers")

local THING = "transport-belt"
local CATCHER = "constructor-equipment-catcher"

--- The engine's status numbers, by name. A stalled inserter reports itself working, which
--- is the whole reason this is worth printing rather than guessing at.
local STATUS = {}
for name, value in pairs(defines.entity_status) do STATUS[value] = name end

--- The arm the stall was found on, and a battery big enough that power is never the
--- question. The reproduction is a fourth tier arm and nothing else on the character.
local FITTING = { "constructor-equipment-4", "battery-mk2-equipment" }

--- The eight places round a character, which is the layout that stalls.
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 },
               { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }

local WHITE  = { 1, 1, 1 }
local YELLOW = { 1, 0.85, 0.1 }
local GREEN  = { 0.2, 1, 0.3 }
local RED    = { 1, 0.25, 0.2 }
local BLUE   = { 0.35, 0.6, 1 }
local ORANGE = { 1, 0.6, 0.15 }

---Make room. A spawn is full of trees and rocks, and a belt asked for a spot one is standing
---in is not placed at all.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param half number
local function clear(surface, at, half)
  for _, thing in pairs(surface.find_entities_filtered{
        area = { { at.x - half, at.y - half }, { at.x + half, at.y + half } },
        type = { "tree", "simple-entity", "item-entity", "transport-belt" } }) do
    if thing.valid then thing.destroy() end
  end
  for _, cliff in pairs(surface.find_entities_filtered{
        area = { { at.x - half, at.y - half }, { at.x + half, at.y + half } },
        type = "cliff" }) do
    if cliff.valid then cliff.destroy{ do_cliff_correction = true } end
  end
end

---Put the armour and the arm on, if they are not on already.
---@param player LuaPlayer
local function dress(player)
  local worn = player.get_inventory(defines.inventory.character_armor)
  if not worn then return end
  worn.clear()
  -- The reproduction's own armour. A fourth tier piece is one tile by five, so an armour
  -- has to be at least five tall to take it; if the one the fixtures use will not hold it in
  -- this game, the bigger one will.
  for _, kind in ipairs{ "power-armor", "power-armor-mk2" } do
    if prototypes.item[kind] then
      worn.clear()
      player.insert{ name = kind, count = 1 }
      local armour = worn[1]
      local grid = armour and armour.grid
      if grid then
        local all = true
        for _, piece in ipairs(FITTING) do
          if not grid.put{ name = piece } then all = false end
        end
        if all then
          for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
          return
        end
      end
    end
  end
  player.print("ce-stall: no armour in this game will hold a fourth tier arm")
end

---Lay the ring out round wherever the player is standing.
---@param player LuaPlayer
---@param radius number how far out, in tiles. One is the case that stalls.
local function lay_out(player, radius)
  local surface = player.surface
  -- The middle of a tile, and the character put there. A one by one thing snaps to the
  -- middle of whatever tile it is asked for, so a ring laid at whole tile offsets from a
  -- character standing anywhere else is a ring offset by half a tile in both directions --
  -- which puts the character on the north west one of them rather than in the middle. The
  -- fixtures avoid this by working from a fixed spot chosen for being a tile's middle; here
  -- the character is wherever they walked to, so it has to be asked for.
  local at = { x = math.floor(player.position.x) + 0.5,
               y = math.floor(player.position.y) + 0.5 }
  player.teleport(at)
  clear(surface, at, 12)
  dress(player)
  -- Empty, the way the fixture has it: a stall is not a full inventory turning work away.
  local main = player.get_inventory(defines.inventory.character_main)
  if main then main.clear() end

  local made = 0
  for _, offset in ipairs(RING) do
    local thing = surface.create_entity{
      name = THING,
      position = { at.x + offset[1] * radius, at.y + offset[2] * radius },
      direction = defines.direction.east,
      force = player.force,
    }
    if thing then
      thing.order_deconstruction(player.force)
      made = made + 1
    end
  end
  storage.radius = radius
  storage.laid = game.tick
  -- To the log as well as the console, so that a run started from a script can be checked
  -- without a pair of eyes on it.
  log(("ce-stall: laid %d of 8 at a radius of %d round %.1f,%.1f"):format(
    made, radius, at.x, at.y))
  player.print(("ce-stall: %d of 8 marked in a ring %s tile%s out. Stand still and watch."
    .. " Three go and the claw stalls on the fourth. /ce-draw for the markers, /ce-watch"
    .. " for a running commentary, /ce-ring 3 for the spacing that works.")
    :format(made, radius, radius == 1 and "" or "s"))
end

---Everything worth knowing about the first arm, in one line.
---@param player LuaPlayer
---@return string
local function telling(player)
  local arms = remote.interfaces["constructor-equipment"]
    and remote.call("constructor-equipment", "arms", player.index) or {}
  local record = arms[1]
  if not record then return "no arm" end
  local entity
  for _, found in pairs(player.surface.find_entities_filtered{
        position = player.position, radius = 4, type = "inserter" }) do
    if found.valid and found.unit_number == record.arm then entity = found end
  end
  if not entity then return "the arm is in storage but not on the ground" end

  local hand = entity.held_stack_position
  local job = record.job
  return ("status=%s  base %.3f,%.3f  hand %.3f,%.3f (out %.3f)  holding %s\n"
    .. "  pick %.3f,%.3f -> %s   drop %.3f,%.3f -> %s\n"
    .. "  box %s   idle box %s\n  job %s"):format(
    tostring(entity.status),
    entity.position.x, entity.position.y, hand.x, hand.y,
    math.sqrt((hand.x - entity.position.x) ^ 2 + (hand.y - entity.position.y) ^ 2),
    entity.held_stack.valid_for_read
      and ("%s x%d"):format(entity.held_stack.name, entity.held_stack.count) or "nothing",
    entity.pickup_position.x, entity.pickup_position.y,
    entity.pickup_target and entity.pickup_target.valid and entity.pickup_target.name
      or "nothing resolved",
    entity.drop_position.x, entity.drop_position.y,
    entity.drop_target and entity.drop_target.valid and entity.drop_target.name
      or "nothing resolved",
    record.catcher and ("%.3f,%.3f"):format(record.catcher.x, record.catcher.y) or "none",
    record.keeper and ("%.3f,%.3f"):format(record.keeper.x, record.keeper.y) or "none",
    job and ("%s take=%s going=%s left=%s carried=%s escrow=%s crossing=%s met=%s"
      .. " target=%.2f,%.2f ghost=%s leg=%d ticks"):format(
      -- A fetch carries nothing out, so it has no item of its own to name.
      job.item or "(a fetch, so no item)",
      tostring(job.take), tostring(job.going), tostring(job.left),
      tostring(job.carried), tostring(job.escrow), tostring(job.crossing),
      tostring(job.met), job.target and job.target.x or 0, job.target and job.target.y or 0,
      tostring(job.ghost), job.leg and (game.tick - job.leg) or -1) or "none")
end

---Draw where everything the arm is working to actually is.
---@param player LuaPlayer
local function draw(player)
  for _, old in pairs(storage.drawn or {}) do
    if old.valid then old.destroy() end
  end
  storage.drawn = {}
  local kept = storage.drawn

  local arms = remote.interfaces["constructor-equipment"]
    and remote.call("constructor-equipment", "arms", player.index) or {}
  local record = arms[1]
  if not record then return end
  local entity
  for _, found in pairs(player.surface.find_entities_filtered{
        position = player.position, radius = 4, type = "inserter" }) do
    if found.valid and found.unit_number == record.arm then entity = found end
  end
  if not entity then return end

  local surface, where = player.surface, { player }
  local function circle(colour, at, radius, filled)
    kept[#kept + 1] = rendering.draw_circle{ color = colour, radius = radius,
      filled = filled or false, width = 2, target = at, surface = surface, players = where }
  end
  local function cross(colour, at)
    for _, arm in ipairs{ { 0.25, 0.25 }, { 0.25, -0.25 } } do
      kept[#kept + 1] = rendering.draw_line{ color = colour, width = 2,
        from = { at.x - arm[1], at.y - arm[2] }, to = { at.x + arm[1], at.y + arm[2] },
        surface = surface, players = where }
    end
  end
  local function square(colour, at)
    kept[#kept + 1] = rendering.draw_rectangle{ color = colour, width = 2,
      left_top = { at.x - 0.35, at.y - 0.35 }, right_bottom = { at.x + 0.35, at.y + 0.35 },
      surface = surface, players = where }
  end

  local pick, drop = entity.pickup_position, entity.drop_position
  kept[#kept + 1] = rendering.draw_line{ color = ORANGE, width = 1,
    from = entity.position, to = pick, surface = surface, players = where }
  circle(WHITE, entity.position, 0.18)
  circle(YELLOW, entity.held_stack_position, 0.12, true)
  cross(GREEN, pick)
  cross(RED, drop)
  if record.catcher then square(GREEN, record.catcher) end
  if record.keeper then square(BLUE, record.keeper) end

  local job = record.job
  kept[#kept + 1] = rendering.draw_text{
    text = ("%s%s"):format(tostring(entity.status),
      job and ("  %s left=%s %d ticks on this leg"):format(
        job.take and "fetching" or "delivering", tostring(job.left),
        job.leg and (game.tick - job.leg) or -1) or "  idle"),
    surface = surface, target = { entity.position.x, entity.position.y - 2 },
    color = WHITE, scale = 0.9, alignment = "center", players = where }
end

--- The smallest rig that shows the fault, which is the drop end.
---
--- An inserter with somewhere to fetch from and somewhere to put things. Its drop position
--- is on a tile holding a belt marked for deconstruction, and there is no container on that
--- tile. That alone freezes the hand solid: it never moves, and it reports itself *working*
--- the whole time.
---
--- The pickup end has the same fault and is not worth a rig, because naming a pickup_target
--- cures it outright -- measured, and wherever the named box stands. The drop end is the one
--- with no way out from the outside: a drop_target named on another tile is ignored, because
--- the engine reads the drop by its position's tile. Only a container standing on that very
--- tile frees it, and a barred one with no room in it is enough.
---
--- /ce-rig <what> builds each of these:
---   (nothing)  the fault: the drop on a marked belt, bare ground
---   aside      a box named as drop_target on a clear tile nearby -- still stalls
---   box        an open box on the drop tile -- runs
---   bar        a box with its bar down on the drop tile -- runs, waiting for space
---   clear      the same belt, not marked -- runs
local RIGS = { "aside", "box", "bar", "clear" }

---@param player LuaPlayer
---@param what string? one of RIGS, or nothing for the fault itself
local function rig(player, what)
  local surface = player.surface
  local at = { x = math.floor(player.position.x) + 0.5,
               y = math.floor(player.position.y) + 0.5 }
  local base = { x = at.x + 5, y = at.y }
  clear(surface, base, 7)
  for _, old in pairs(surface.find_entities_filtered{ position = base, radius = 7,
        name = { THING, CATCHER, "iron-chest", tiers.by_level[4].inserter } }) do
    if old.valid then old.destroy() end
  end

  local pick = { x = base.x, y = base.y - 2 }
  local drop = { x = base.x, y = base.y + 2 }

  -- The one that does the damage: on the drop tile, and marked.
  local belt = surface.create_entity{ name = THING, position = drop,
    direction = defines.direction.east, force = player.force }
  if belt and what ~= "clear" then belt.order_deconstruction(player.force) end

  local arm = surface.create_entity{ name = tiers.by_level[4].inserter, position = base,
    force = player.force, direction = defines.direction.south }
  if not arm then player.print("ce-stall: the inserter would not go down") return end
  arm.pickup_position = { pick.x, pick.y }
  arm.drop_position = { drop.x, drop.y }

  -- Somewhere to fetch from, on a clear tile, named every tick so the pickup end can never
  -- be what is being watched here.
  local box = surface.create_entity{ name = CATCHER, position = pick, force = player.force }
  if box then box.get_inventory(defines.inventory.chest).insert{ name = THING, count = 50 } end

  -- And whatever this variant puts at the drop end.
  local into, aside
  if what == "box" or what == "bar" then
    into = surface.create_entity{ name = CATCHER, position = drop, force = player.force }
    if into and what == "bar" then
      local inside = into.get_inventory(defines.inventory.chest)
      if inside and inside.supports_bar() then inside.set_bar(1) end
    end
  elseif what == "aside" then
    aside = surface.create_entity{ name = CATCHER, position = { drop.x + 2, drop.y },
      force = player.force }
  end

  storage.rig = { arm = arm, belt = belt, box = box, into = into, aside = aside,
                  pick = pick, drop = drop, what = what or "the fault itself",
                  built = game.tick, went = 0 }
  player.print(("ce-stall: a rig five tiles east -- %s. It fetches from the box north of it"
    .. " and drops south, onto a tile holding a belt %s. %s  /ce-rig-say reports it,"
    .. " /ce-rig aside|box|bar|clear builds the others."):format(
    what or "the fault itself",
    what == "clear" and "that is not marked" or "marked for deconstruction",
    (what == "box" or what == "bar" or what == "clear")
      and "It should run." or "It should sit there doing nothing at all."))
end

---Keep the rig fed and its names asserted, and count how far its hand gets.
local function drive_rig()
  local it = storage.rig
  if not (it and it.arm and it.arm.valid) then return end
  it.arm.energy = it.arm.prototype.get_max_energy_usage() * 100
  -- Every tick: anything that moves an inserter throws the engine's answer away, and these
  -- have to outlive that.
  if it.box and it.box.valid then it.arm.pickup_target = it.box end
  if it.aside and it.aside.valid then it.arm.drop_target = it.aside end
  local hand = it.arm.held_stack_position
  if it.last then
    it.went = it.went + math.sqrt((hand.x - it.last.x) ^ 2 + (hand.y - it.last.y) ^ 2)
  end
  it.last = { x = hand.x, y = hand.y }
end

script.on_event(defines.events.on_tick, function()
  -- A single report ten seconds after the ring goes down, to the log. The reproduction is
  -- the point of this mod, so a run that does not reproduce should say so by itself rather
  -- than leaving somebody watching an arm that was never going to stall.
  if storage.laid and game.tick - storage.laid == 600 then
    for _, player in pairs(game.connected_players) do
      local left = player.surface.count_entities_filtered{
        name = THING, position = player.position, radius = 6 }
      log(("ce-stall: ten seconds in, %d of 8 still standing and %d in the pockets\n%s")
        :format(left, player.get_item_count(THING), telling(player)))
    end
  end
  drive_rig()
  -- The same for a rig: one line to the log ten seconds after it is built, so that a run
  -- started from a script can be checked without a pair of eyes on it.
  local it = storage.rig
  if it and it.built and game.tick - it.built == 600 then
    local loose = 0
    for _, item in ipairs(game.surfaces[1].find_entities_filtered{
          name = "item-on-ground", position = it.drop, radius = 3 }) do
      if item.stack and item.stack.valid_for_read and item.stack.name == THING then
        loose = loose + item.stack.count
      end
    end
    log(("ce-stall rig (%s): hand travelled %.2f in ten seconds, %d left in the source,"
      .. " %d on the ground, %d in the drop box, status %s"):format(
      it.what, it.went,
      it.box and it.box.valid
        and it.box.get_inventory(defines.inventory.chest).get_item_count(THING) or -1,
      loose,
      it.into and it.into.valid
        and it.into.get_inventory(defines.inventory.chest).get_item_count(THING) or -1,
      it.arm and it.arm.valid and (STATUS[it.arm.status] or it.arm.status)
        or "gone"))
  end
  if not (storage.drawing or storage.watching) then return end
  for _, player in pairs(game.connected_players) do
    if storage.drawing then draw(player) end
    if storage.watching then
      local line = telling(player)
      if line ~= storage.said then
        player.print(("[%d] %s"):format(game.tick, line))
        storage.said = line
      end
    end
  end
end)

script.on_init(function()
  storage.drawn = {}
  -- Freeplay makes the crashed ship in on_player_created rather than on_init so that mods
  -- can call in first, and the cutscene is what would otherwise carry the player away from
  -- everything laid out below.
  if remote.interfaces["freeplay"] then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  -- Nothing researched. Inserter capacity is what decides how many pickups a fourth tier
  -- claw takes in one round, and a claw that works a round takes a different path through
  -- the mod entirely -- measured, a force with everything researched does not stall here at
  -- all. The reproduction is a claw that fetches one at a time, which is what a new game
  -- gives you.
  lay_out(player, 1)
  storage.drawing = true
  player.print("ce-stall: markers are on. /ce-draw turns them off.")
end)

commands.add_command("ce-stall", "Lay the ring of eight out again", function(event)
  local player = game.get_player(event.player_index)
  if player then lay_out(player, storage.radius or 1) end
end)

commands.add_command("ce-ring", "Lay the ring out this many tiles from the character",
  function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local radius = tonumber(event.parameter or "") or 1
    lay_out(player, math.max(1, math.floor(radius)))
  end)

commands.add_command("ce-arm", "Say what the arm is doing", function(event)
  local player = game.get_player(event.player_index)
  if player then player.print(telling(player)) end
end)

commands.add_command("ce-watch", "Say what the arm is doing, every tick it changes",
  function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    storage.watching = not storage.watching
    storage.said = nil
    player.print("ce-stall: commentary " .. (storage.watching and "on" or "off"))
  end)

commands.add_command("ce-draw", "Turn the markers on and off", function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  storage.drawing = not storage.drawing
  if not storage.drawing then
    for _, old in pairs(storage.drawn or {}) do
      if old.valid then old.destroy() end
    end
    storage.drawn = {}
  end
  player.print("ce-stall: markers " .. (storage.drawing and "on" or "off"))
end)

commands.add_command("ce-rig", "Build the minimal rig: aside, box, bar, clear, or nothing",
  function(event)
    local player = game.get_player(event.player_index)
    if not player then return end
    local what = event.parameter and event.parameter:match("%a+") or nil
    if what then
      local known = false
      for _, name in ipairs(RIGS) do if name == what then known = true end end
      if not known then
        player.print("ce-stall: that is not one of " .. table.concat(RIGS, ", "))
        return
      end
    end
    rig(player, what)
  end)

commands.add_command("ce-unmark", "Take the deconstruction order off the rig's belt",
  function(event)
    local player = game.get_player(event.player_index)
    local it = storage.rig
    if not player then return end
    if not (it and it.belt and it.belt.valid) then
      player.print("ce-stall: there is no rig. /ce-rig builds one.")
      return
    end
    if it.belt.to_be_deconstructed() then
      it.belt.cancel_deconstruction(player.force)
      player.print("ce-stall: the mark is off. The hand should start moving.")
    else
      it.belt.order_deconstruction(player.force)
      player.print("ce-stall: the mark is back on.")
    end
  end)

commands.add_command("ce-rig-say", "Say what the rig's inserter is doing", function(event)
  local player = game.get_player(event.player_index)
  local it = storage.rig
  if not player then return end
  if not (it and it.arm and it.arm.valid) then
    player.print("ce-stall: there is no rig. /ce-rig builds one.")
    return
  end
  local hand = it.arm.held_stack_position
  local loose = 0
  for _, item in ipairs(player.surface.find_entities_filtered{ name = "item-on-ground",
        position = it.drop, radius = 3 }) do
    if item.stack and item.stack.valid_for_read and item.stack.name == THING then
      loose = loose + item.stack.count
    end
  end
  player.print(("ce-stall rig (%s): status=%s  hand %.3f,%.3f  travelled %.2f since built"
    .. "\n  pickup %.1f,%.1f -> %s   drop %.1f,%.1f -> %s"
    .. "\n  the belt on the drop tile is %s; %d left in the source, %d on the ground"):format(
    it.what, STATUS[it.arm.status] or it.arm.status, hand.x, hand.y, it.went,
    it.arm.pickup_position.x, it.arm.pickup_position.y,
    it.arm.pickup_target and it.arm.pickup_target.valid and it.arm.pickup_target.name
      or "nothing named",
    it.arm.drop_position.x, it.arm.drop_position.y,
    it.arm.drop_target and it.arm.drop_target.valid and it.arm.drop_target.name
      or "nothing named",
    (it.belt and it.belt.valid)
      and (it.belt.to_be_deconstructed() and "marked" or "not marked") or "gone",
    it.box and it.box.valid
      and it.box.get_inventory(defines.inventory.chest).get_item_count(THING) or -1, loose))
end)
