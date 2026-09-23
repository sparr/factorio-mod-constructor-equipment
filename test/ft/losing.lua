--- Belts that went missing, and the fixtures that caught them going.
---
--- Every belt in the arena counted on every tick, while a train builds a line of them, and
--- then one deterministic case that needs no driving at all.
---
--- A census taken only at the end of a run says a belt went; it does not say when, or
--- where, and the two faults this fixture was written to find were both invisible to one.
--- Counting on every tick names the tick exactly, and a failure dumps the few ticks up to
--- it along with a sweep of everything in the arena that is holding a belt -- including the
--- transport lines, which is where one of the two turned out to be.
---
--- How the train is driven matters more than how long it runs for. Whether a load goes
--- astray is a question of two arms' guesses landing on the same tile at the same moment,
--- so it is a coin flip on timing: of a dozen driving patterns tried, half found it and
--- half never did, and the one the steering fixture uses is one of the half that did not.
--- The six kept here are those six, and which of them lands depends on how long the run is.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"
local BELTS = 200
local RAILS_FROM, RAILS_TO = -60, 320
local ARENA = 320
local RUN = 1800

--- Where a belt can be, counted every tick.
---
--- The cheap half of the question: two filtered searches and a walk of eight arms, which is
--- what makes it affordable to ask on every tick of a thirty second run.
---@return integer, table<string, integer>
local function census(surface, player, wagon)
  local where = {}
  where.built = surface.count_entities_filtered{ name = BELT, position = world.ORIGIN,
    radius = ARENA }
  where.loose = 0
  for _, item in ipairs(surface.find_entities_filtered{ name = "item-on-ground",
        position = world.ORIGIN, radius = ARENA }) do
    if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
      where.loose = where.loose + item.stack.count
    end
  end
  where.wagon = wagon.valid
    and wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count(BELT) or 0
  where.hands, where.boxes, where.escrow = 0, 0, 0
  for _, record in pairs(storage.constructor_arms[player.index] or {}) do
    local arm = record.entity
    if arm and arm.valid and arm.held_stack.valid_for_read
        and arm.held_stack.name == BELT then
      where.hands = where.hands + arm.held_stack.count
    end
    -- Both of an arm's boxes. The keeper was left out of this for a long time, on the
    -- grounds that it is shut whenever a claw is resting on it and so can never be holding
    -- anything -- which is true right up until a claw gives its job up on the way home and
    -- arrives at the rest point with a load still in it. That belt read as destroyed here
    -- while it was sitting in a box nobody was counting, and it was about to be.
    for _, box in ipairs{ record.catcher, record.keeper } do
      if box and box.valid then
        where.boxes = where.boxes
          + box.get_inventory(defines.inventory.chest).get_item_count(BELT)
      end
    end
    if record.job and record.job.item == BELT then
      where.escrow = where.escrow + (record.job.escrow or 0)
    end
  end
  where.pockets = player.get_main_inventory().get_item_count(BELT)
  local cursor = player.cursor_stack
  if cursor and cursor.valid and cursor.valid_for_read and cursor.name == BELT then
    where.pockets = where.pockets + cursor.count
  end
  local total = 0
  for _, n in pairs(where) do total = total + n end
  return total, where
end

--- Everywhere else a belt could possibly be, asked once, when one has already gone missing.
---
--- The expensive half. Every entity in the arena is walked and every inventory it owns is
--- read, along with every transport line of every belt -- which is the hiding place an end
--- of run census never looked in, and the one place the engine can put a load without
--- anybody asking it to. A lane swallows a stack whole and leaves nothing on the ground to
--- find, so a belt riding one reads exactly like a belt destroyed.
---@return string[]
local function sweep(surface, player)
  local found = {}
  local mine = {}
  for _, record in pairs(storage.constructor_arms[player.index] or {}) do
    if record.entity and record.entity.valid then
      mine[record.entity.unit_number] = "arm"
    end
    if record.catcher and record.catcher.valid then
      mine[record.catcher.unit_number] = "box"
    end
  end
  for _, entity in ipairs(surface.find_entities_filtered{ position = world.ORIGIN,
        radius = ARENA }) do
    if entity.valid then
      local label = ("%s(%s)%s at %.2f,%.2f"):format(entity.name, entity.type,
        mine[entity.unit_number] and (" [" .. mine[entity.unit_number] .. "]") or "",
        entity.position.x, entity.position.y)
      if entity.type == "inserter" and entity.held_stack.valid_for_read
          and entity.held_stack.name == BELT then
        found[#found + 1] = ("hand of %s holds %d"):format(label, entity.held_stack.count)
      end
      local lanes = 0
      if entity.type == "transport-belt" or entity.type == "loader"
          or entity.type == "loader-1x1" then lanes = 2
      elseif entity.type == "underground-belt" then lanes = 4
      elseif entity.type == "splitter" or entity.type == "lane-splitter" then lanes = 8 end
      for line = 1, lanes do
        local items = entity.get_transport_line(line)
        if items and items.get_item_count(BELT) > 0 then
          found[#found + 1] = ("lane %d of %s carries %d"):format(line, label,
            items.get_item_count(BELT))
        end
      end
      for which = 1, 12 do
        local inventory = entity.get_inventory(which)
        if inventory and inventory.get_item_count(BELT) > 0 then
          found[#found + 1] = ("inventory %d of %s holds %d"):format(which, label,
            inventory.get_item_count(BELT))
        end
      end
    end
  end
  return found
end

--- What each arm is doing, in one line, for the ring buffer.
---@return string
local function snapshot(player, tick, total, where)
  local lines = { ("tick %d: total %d = built %d loose %d wagon %d hands %d boxes %d"
    .. " escrow %d pockets %d"):format(tick, total, where.built, where.loose, where.wagon,
    where.hands, where.boxes, where.escrow, where.pockets) }
  for slot, record in pairs(storage.constructor_arms[player.index] or {}) do
    local arm, box, job = record.entity, record.catcher, record.job
    local live = arm and arm.valid
    local hand = live and arm.held_stack.valid_for_read
      and ("%s x%d"):format(arm.held_stack.name, arm.held_stack.count) or "empty"
    local at = live and arm.held_stack_position or { x = 0, y = 0 }
    lines[#lines + 1] = ("  arm %d hand=%s at %.3f,%.3f base %.3f,%.3f drop %.3f,%.3f"
      .. " box=%s job=%s"):format(
      slot, hand, at.x, at.y,
      live and arm.position.x or 0, live and arm.position.y or 0,
      live and arm.drop_position.x or 0, live and arm.drop_position.y or 0,
      box and box.valid and ("%.3f,%.3f holds %d"):format(box.position.x, box.position.y,
        box.get_inventory(defines.inventory.chest).get_item_count(BELT)) or "none",
      job and ("%s going=%s left=%s carried=%s escrow=%s target=%.2f,%.2f ghost=%s"):format(
        tostring(job.item), tostring(job.going), tostring(job.left),
        tostring(job.carried), tostring(job.escrow),
        job.target and job.target.x or 0, job.target and job.target.y or 0,
        job.ghost and job.ghost.valid and "valid" or "gone") or "none")
  end
  return table.concat(lines, "\n")
end

--- How the train is driven. A dozen ways were tried against the faults before they were
--- fixed and half of them found nothing at all -- including the one the steering fixture
--- drives -- so which six are here is measured rather than chosen. At the length this runs
--- for, three of the six catch it; all six caught it over a run twice as long through twice
--- as many ghosts, and they are all kept because which of them lands is a coin flip on
--- timing and the timings will change again.
local PATTERNS = {
  { name = "a steady quarter", speed = function() return 0.25 end },
  { name = "a steady half",    speed = function() return 0.5 end },
  {
    name = "back and forth",
    speed = function(phase) return phase % 200 < 120 and 0.3 or -0.3 end,
  },
  {
    name = "speeding up and slowing down",
    speed = function(phase)
      local along = (phase % 240) / 240
      return 0.05 + 0.4 * (along < 0.5 and along * 2 or (1 - along) * 2)
    end,
  },
  {
    name = "a jerk every few seconds",
    speed = function(phase)
      local beat = phase % 47
      if beat < 5 then return 0.45 elseif beat < 9 then return -0.2 end
      return 0.12
    end,
  },
  {
    name = "ramping to a stop and away again",
    speed = function(phase)
      local along = (phase % 180) / 180
      return 0.5 * (1 - math.abs(along * 2 - 1)) - 0.02
    end,
  },
}

--- world.clear only reaches thirty tiles and this arena is hundreds long, so a run left its
--- rails, its ghosts and its belts standing for the next one, which found the track
--- occupied and failed before it had driven anywhere.
local function clear_arena(player)
  world.unseat(player)
  local driven = {}
  for _, other in pairs(game.players) do
    if other.character then driven[other.character.unit_number] = true end
  end
  for _, entity in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
        radius = ARENA + 80 }) do
    if entity.valid and not (entity.type == "character" and driven[entity.unit_number]) then
      entity.destroy()
    end
  end
  world.clear(player)
end

describe("a train building a line of belts", function()
  local player

  before_each(function()
    player = world.player()
    clear_arena(player)
  end)

  after_each(function()
    for _, sticker in pairs(player.character and player.character.stickers or {}) do
      sticker.destroy()
    end
    clear_arena(player)
  end)

  for _, pattern in ipairs(PATTERNS) do
    it("keeps every belt while it is driven " .. pattern.name, function()
      local surface, y = player.surface, world.ORIGIN.y
      for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + RAILS_TO, 2 do
        surface.create_entity{ name = "straight-rail", position = { x, y },
          direction = defines.direction.east, force = player.force }
      end
      local loco = surface.create_entity{ name = "locomotive",
        position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
        force = player.force }
      local wagon = surface.create_entity{ name = "cargo-wagon",
        position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
        force = player.force }
      loco.insert{ name = "nuclear-fuel", count = 5 }
      wagon.insert{ name = BELT, count = BELTS }
      -- the showroom's own locomotive kit and its own layout: eight of the second tier, and
      -- ghosts two tiles either side of the rail, one tile apart
      local grid = {}
      for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
      grid[#grid + 1] = "battery-equipment"
      world.fit(loco, grid, true)
      loco.train.manual_mode = true
      loco.set_driver(player)
      for x = 6, 150 do
        for _, dy in ipairs{ -2, 2 } do world.ghost(player, BELT, x, dy) end
      end

      local began = game.tick
      local ring, RING = {}, 14
      local least, said = BELTS, false
      world.once(function()
        local tick = game.tick
        loco.train.speed = pattern.speed(tick - began)
        local total, where = census(surface, player, wagon)
        ring[#ring + 1] = snapshot(player, tick, total, where)
        while #ring > RING do table.remove(ring, 1) end

        if total < least and not said then
          said = true
          log(("LOST %d belts on tick %d of the run, driven %s"):format(
            least - total, tick - began, pattern.name))
          log("  the ticks up to it:\n" .. table.concat(ring, "\n"))
          log("  everything in the arena holding a belt:")
          for _, line in ipairs(sweep(surface, player)) do log("    " .. line) end
        end
        least = math.min(least, total)
        return tick - began > RUN
      end, function()
        loco.train.speed = 0
        local total, where = census(surface, player, wagon)
        assert.are.equal(BELTS, total,
          ("%d belts of %d: built %d loose %d wagon %d hands %d boxes %d escrow %d"
            .. " pockets %d"):format(total, BELTS, where.built, where.loose, where.wagon,
            where.hands, where.boxes, where.escrow, where.pockets))
        assert.is_true(where.built > 50, ("only %d belts went down"):format(where.built))
      end, "the run never ended", RUN + 100)
    end)
  end
end)

--- An arm that takes a job with something already in its hand.
---
--- A claw rests a little way out from where the arm is bolted on, which on a vehicle is
--- inside the hull, and a hull with a hold of its own is a container as far as the engine is
--- concerned. So it helps itself to a belt out of the boot between one tick and the next,
--- unasked, and the loading that follows used to write straight over the hand.
---
--- Found on a tank turning through a field of ghosts, where it cost one belt in a hundred
--- and twenty and only at some timings. Reproduced here by putting the belt in the hand
--- directly, out of the same hold the engine would have taken it from, so that it happens
--- every run and on a vehicle that never moves.
describe("an arm holding something it was never given", function()
  local player
  local STOCK = 20

  before_each(function()
    player = world.player()
    world.clear(player)
  end)

  after_each(function()
    if player.vehicle then world.unseat(player) end
    world.clear(player)
  end)

  it("keeps the belt the engine put in its hand", function()
    local surface = player.surface
    local tank = world.vehicle(player, "tank")
    world.fit(tank, { tiers.by_level[4].name, "battery-equipment" }, true)
    tank.insert{ name = BELT, count = STOCK }

    local function everything()
      local total = tank.valid and tank.get_item_count(BELT) or 0
      total = total + surface.count_entities_filtered{ name = BELT,
        position = world.ORIGIN, radius = 40 }
      for _, item in ipairs(surface.find_entities_filtered{ name = "item-on-ground",
            position = world.ORIGIN, radius = 40 }) do
        if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
          total = total + item.stack.count
        end
      end
      for _, belt in ipairs(surface.find_entities_filtered{ type = "transport-belt",
            position = world.ORIGIN, radius = 40 }) do
        for line = 1, 2 do
          total = total + belt.get_transport_line(line).get_item_count(BELT)
        end
      end
      for _, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm, box, job = record.entity, record.catcher, record.job
        if arm and arm.valid and arm.held_stack.valid_for_read
            and arm.held_stack.name == BELT then
          total = total + arm.held_stack.count
        end
        if box and box.valid then
          total = total + box.get_inventory(defines.inventory.chest).get_item_count(BELT)
        end
        if job and job.item == BELT then total = total + (job.escrow or 0) end
      end
      return total + player.get_main_inventory().get_item_count(BELT)
    end

    -- One ghost to bring the arm out and get it building, so that what follows happens to a
    -- settled arm rather than to one that has never had a job.
    world.ghost(player, BELT, 3, 0)

    -- The moment its round is over and it is standing idle, and no later: an arm left idle
    -- long enough is put away, and putting one away hands back whatever is in its hand,
    -- which is the path that never lost anything.
    local set_up = false
    world.once(function()
      local record = (storage.constructor_arms[player.index] or {})[1]
      local arm = record and record.entity
      return arm ~= nil and arm.valid and record.job == nil
        and not arm.held_stack.valid_for_read
        and surface.count_entities_filtered{ name = BELT, position = world.ORIGIN,
              radius = 40 } > 0
    end, function()
      local arm = (storage.constructor_arms[player.index] or {})[1].entity
      -- what the engine would have done by itself, done on purpose and out of the same hold
      assert.are.equal(1, tank.remove_item{ name = BELT, count = 1 },
        "the tank would not give up a belt")
      arm.held_stack.set_stack{ name = BELT, count = 1 }
      assert.are.equal(STOCK, everything(), "the setup itself lost a belt")
      -- and now, on this same tick, give it something to do
      world.ghost(player, BELT, -3, 0)
      set_up = true
    end, "the arm never finished its first round", world.CYCLE * 2)

    after_ticks(world.CYCLE * 4, function()
      assert.is_true(set_up, "the fixture never got a belt into the hand")
      assert.are.equal(STOCK, everything(),
        "a belt went missing when the arm took a job with a full hand")
    end)
  end)
end)


--- Belts that end up on the ground rather than in a ghost, and then ride away on the belts
--- that did get built.
---
--- A different fault from the one above and it needs a different census. The runs above ask
--- whether every belt is still somewhere; this asks whether any of them is somewhere it has
--- no business being. A belt lying loose is paid for and not placed, and once a line has been
--- built through the tile it was dropped on the engine feeds it to a lane -- measured
--- elsewhere, create_entity on a belt lane is swallowed in the same tick -- so it stops being
--- litter anybody would notice and becomes cargo travelling up the line.
---
--- The layout is what was reported: two rows of ghosts on each side rather than one, which
--- is what puts a built belt between the claw and the row beyond it, and a train driven back
--- and forth at full speed on nuclear fuel until the whole field is up.
local LITTER_FROM, LITTER_TO = 6, 160
local LITTER_RAILS = 900
local LITTER_RUN = 24000

---Every belt riding a lane anywhere in the arena.
local function on_lanes(surface)
  local carried = 0
  for _, entity in ipairs(surface.find_entities_filtered{ position = world.ORIGIN,
        radius = ARENA }) do
    if entity.valid then
      local lanes = 0
      if entity.type == "transport-belt" or entity.type == "loader"
          or entity.type == "loader-1x1" then lanes = 2
      elseif entity.type == "underground-belt" then lanes = 4
      elseif entity.type == "splitter" or entity.type == "lane-splitter" then lanes = 8 end
      for line = 1, lanes do
        local items = entity.get_transport_line(line)
        if items then carried = carried + items.get_item_count(BELT) end
      end
    end
  end
  return carried
end

describe("a train driven back and forth over a field of ghosts", function()
  local player

  before_each(function()
    player = world.player()
    clear_arena(player)
  end)

  after_each(function()
    for _, sticker in pairs(player.character and player.character.stickers or {}) do
      sticker.destroy()
    end
    clear_arena(player)
  end)

  --- Both ways round, because the showroom's train is not the obvious way round and the
  --- report came from the showroom. Its wagon goes on the nearest rail at least six tiles
  --- from the locomotive, and its rails start four tiles west of where the locomotive
  --- stands, so the first candidate is always east: the wagon leads and the arms trail.
  --- And one that runs dry part way, which is the state a showroom train was in when this
  --- was first reported as "nothing gets built": a hold with fewer belts in it than the
  --- field wants. What is asked of that one is only that nothing escapes; how much of the
  --- field goes up is decided by how much it was given.
  for _, consist in ipairs{ { name = "wagon behind", at = -27 },
                            { name = "wagon in front", at = -13 },
                            { name = "running dry", at = -13, stock = 300 } } do
  it("leaves nothing lying on the ground or riding the line, " .. consist.name, function()
    local surface, y = player.surface, world.ORIGIN.y
    -- Well past the turning points at both ends. A train reversed into the end of its track
    -- stops dead and stays there, which an earlier version of this spent eighteen thousand
    -- ticks doing: the wagon leads when it backs up, so the west end has to clear the whole
    -- train and then some.
    for x = world.ORIGIN.x - 220, world.ORIGIN.x + LITTER_RAILS, 2 do
      surface.create_entity{ name = "straight-rail", position = { x, y },
        direction = defines.direction.east, force = player.force }
    end
    local loco = surface.create_entity{ name = "locomotive",
      position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
      force = player.force }
    local wagon = surface.create_entity{ name = "cargo-wagon",
      position = { world.ORIGIN.x + consist.at, y }, direction = defines.direction.east,
      force = player.force }
    assert.is_not_nil(wagon, "the wagon would not go on the rail")
    -- Nuclear, for the acceleration: the point is to spend as much of the run as possible at
    -- the top rather than getting there.
    loco.insert{ name = "nuclear-fuel", count = 10 }
    local grid = {}
    for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
    grid[#grid + 1] = "battery-mk2-equipment"
    world.fit(loco, grid, true)
    loco.train.manual_mode = true
    loco.set_driver(player)

    -- Two rows on each side, measured off the rail the train really sits on. Rails lie on a
    -- grid half a tile from the one a belt sits on, so rows asked for by eye come out
    -- lopsided -- minus two and a half and minus one and a half on one side against plus two
    -- and a half and plus three and a half on the other, and a second tier arm reaches
    -- three. An earlier version of this laid exactly that and spent a long time reading the
    -- unreachable row as a fault in the arms.
    local middle = loco.position.y - world.ORIGIN.y
    local ghosts = {}
    for x = LITTER_FROM, LITTER_TO do
      for _, off in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
        local ghost = world.ghost(player, BELT, x, middle + off)
        if ghost then ghosts[#ghosts + 1] = ghost end
      end
    end
    do
      local seen = {}
      for i = 1, 4 do
        seen[i] = ("%+.2f"):format(ghosts[i].position.y - loco.position.y)
      end
      log(("LITTER | the rows really sit at %s from the train"):format(
        table.concat(seen, ", ")))
    end
    -- Comfortably more than the field needs, so that running dry is never the explanation --
    -- except in the case that is about exactly that.
    wagon.insert{ name = BELT, count = consist.stock or (#ghosts + 400) }
    local stocked = wagon.get_inventory(defines.inventory.cargo_wagon)
      .get_item_count(BELT)

    local began, going = game.tick, "east"
    local worst_loose, worst_lanes, first_at = 0, 0, nil
    local left, passes, fastest, was_at = #ghosts, 0, 0, loco.position.x
    world.once(function()
      local at = loco.position.x - world.ORIGIN.x
      local moved = math.abs(loco.position.x - was_at)
      was_at = loco.position.x
      if moved > fastest then fastest = moved end
      -- Back and forth over the whole field, turned round well past either end so that the
      -- braking and the reversing happen off it rather than among the ghosts.
      if going == "east" and at > LITTER_TO + 120 then going = "west" passes = passes + 1
      elseif going == "west" and at < -140 then going = "east" passes = passes + 1 end
      player.riding_state = {
        acceleration = going == "east" and defines.riding.acceleration.accelerating
          or defines.riding.acceleration.reversing,
        direction = defines.riding.direction.straight }

      -- Counted twice a second rather than every tick. Walking six hundred ghosts and
      -- sweeping the arena for loose items on every one of eighteen thousand ticks is a
      -- great deal more work than the thing being measured, and it is what made an earlier
      -- version of this run take longer than the harness would wait.
      if (game.tick - began) % 30 ~= 0 then
        return game.tick - began > LITTER_RUN
      end
      local loose = surface.count_entities_filtered{ name = "item-on-ground",
        position = world.ORIGIN, radius = ARENA }
      if loose > worst_loose then worst_loose = loose end
      if loose > 0 and not first_at then first_at = game.tick - began end

      local standing = 0
      for _, ghost in ipairs(ghosts) do if ghost.valid then standing = standing + 1 end end
      left = standing
      -- Said out loud every so often, because the harness gives up on a game that has not
      -- printed anything for fifteen seconds and a run this long is otherwise silent.
      if (game.tick - began) % 2000 == 0 then
        log(("LITTER ... tick %d: %d of %d still standing, %d loose, %d passes, at %.0f")
          :format(game.tick - began, standing, #ghosts, loose, passes, at))
      end
      return (standing == 0 and loose == 0 and not consist.stock)
        or game.tick - began > LITTER_RUN
    end, function()
      player.riding_state = { acceleration = defines.riding.acceleration.nothing,
                              direction = defines.riding.direction.straight }
      local loose = surface.count_entities_filtered{ name = "item-on-ground",
        position = world.ORIGIN, radius = ARENA }
      local riding = on_lanes(surface)
      local built = surface.count_entities_filtered{ name = BELT, position = world.ORIGIN,
        radius = ARENA }
      local spare = wagon.valid and wagon.get_inventory(defines.inventory.cargo_wagon)
        .get_item_count(BELT) or 0
      -- Which ones are left, because "a quarter of them never went up" is a different
      -- question depending on whether they are the far rows, the ends of the field, or
      -- scattered through it.
      local by_row, lowest, highest = {}, nil, nil
      for _, ghost in ipairs(ghosts) do
        if ghost.valid then
          local off = ("%+.1f"):format(ghost.position.y - loco.position.y)
          by_row[off] = (by_row[off] or 0) + 1
          local dx = ghost.position.x - world.ORIGIN.x
          if not lowest or dx < lowest then lowest = dx end
          if not highest or dx > highest then highest = dx end
        end
      end
      local rows = {}
      for _, off in ipairs{ "-2.5", "-1.5", "+1.5", "+2.5" } do
        rows[#rows + 1] = ("%s: %d of %d"):format(off, by_row[off] or 0,
          LITTER_TO - LITTER_FROM + 1)
      end
      log(("LITTER rows left | %s | from x %s to %s"):format(table.concat(rows, ", "),
        tostring(lowest), tostring(highest)))
      log(("LITTER | %s | %d ghosts, %d still standing, %d built | %d passes, top speed"
        .. " %.3f | loose now %d, worst %d, first seen at %s | riding a lane %d | %d belts"
        .. " left of %d"):format(consist.name, #ghosts, left, built, passes, fastest, loose,
        worst_loose, tostring(first_at), riding, spare, stocked))
      for _, line in ipairs(sweep(surface, player)) do log("    " .. line) end
      if not consist.stock then
        assert.is_true(spare > 0, "the train ran out of belts, so this measured nothing")
      end
      assert.are.equal(0, riding, ("%d belts are riding the line"):format(riding))
      assert.are.equal(0, loose, ("%d belts are lying on the ground"):format(loose))
    end, "the run never ended", LITTER_RUN + 200)
  end)
  end
end)


--- The same four rows, with the train standing still.
---
--- The run above finds that every ghost three tiles north of the rail survives a field that
--- is otherwise finished -- 155 of 155, against nothing left in the other three rows. That
--- is an asymmetry rather than a reach limit, since three tiles south is built. This asks
--- whether it is there when nothing is moving, which separates what an arm can reach from
--- what it can be led to.
describe("a train standing among four rows of ghosts", function()
  local player

  before_each(function()
    player = world.player()
    clear_arena(player)
  end)

  after_each(function()
    for _, sticker in pairs(player.character and player.character.stickers or {}) do
      sticker.destroy()
    end
    clear_arena(player)
  end)

  it("reaches all four rows when it is standing still", function()
    local surface, y = player.surface, world.ORIGIN.y
    -- The same offsets the runs above use. Rolling stock goes where a rail is rather than
    -- where the tape measure says, and these are known to take one.
    for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + 60, 2 do
      surface.create_entity{ name = "straight-rail", position = { x, y },
        direction = defines.direction.east, force = player.force }
    end
    local loco = surface.create_entity{ name = "locomotive",
      position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
      force = player.force }
    assert.is_not_nil(loco, "the locomotive would not go on the rail")
    local wagon = surface.create_entity{ name = "cargo-wagon",
      position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
      force = player.force }
    loco.insert{ name = "nuclear-fuel", count = 5 }
    wagon.insert{ name = BELT, count = 400 }
    local grid = {}
    for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
    grid[#grid + 1] = "battery-mk2-equipment"
    world.fit(loco, grid, true)
    loco.train.manual_mode = true
    loco.set_driver(player)
    loco.train.speed = 0

    -- Alongside the hull rather than ahead of it, since nothing is going to move: the
    -- locomotive is about seven tiles long and its arms are spread down it.
    -- About the train rather than about world.ORIGIN. Rolling stock sits on the rail grid,
    -- which is not the tile grid the ghosts are measured from: the rail here comes out half
    -- a tile north of the line the fixture thinks it laid, so rows at plus and minus three
    -- are really at minus three and a half and plus two and a half. Measured before this was
    -- noticed: the whole northern row of a field was left standing and read as a fault in
    -- the arms, when it was simply three and a half tiles from a three tile reach.
    local rail_dy = loco.position.y - world.ORIGIN.y
    log(("ROWS | the train sits %+.2f off the line the ghosts are measured from"):format(
      rail_dy))
    local ghosts = {}
    local seen = {}
    for x = -24, -16 do
      for _, dy in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
        local ghost = world.ghost(player, BELT, x, rail_dy + dy)
        if ghost then
          ghosts[#ghosts + 1] = { thing = ghost, dy = dy }
          -- Where it really landed. A belt ghost snaps to a tile centre, and asking for a
          -- half tile offset from the rail lands it on a tile edge, which rounds one way on
          -- one side of the train and the other way on the other.
          seen[dy] = ghost.position.y - loco.position.y
        end
      end
    end
    local where = {}
    for _, dy in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
      where[#where + 1] = ("asked %+.1f, got %+.2f"):format(dy, seen[dy] or 0)
    end
    log("ROWS | " .. table.concat(where, " | "))

    -- Where each arm sits and how far it is from a ghost in each row, which is what says
    -- whether a row is out of reach or merely never chosen.
    local said = false
    local began = game.tick
    world.once(function()
      if not said then
        said = true
        for slot, record in pairs(storage.constructor_arms[player.index] or {}) do
          local arm = record.entity
          if arm and arm.valid then
            local aways = {}
            for _, dy in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
              aways[#aways + 1] = ("%+.1f: %.2f"):format(dy, reach.distance(arm.position,
                { x = loco.position.x, y = loco.position.y + dy - (record.lift or 0) }))
            end
            log(("ROWS arm %d at %+.2f,%+.2f lift %.2f | %s"):format(slot,
              arm.position.x - loco.position.x, arm.position.y - loco.position.y,
              record.lift or 0, table.concat(aways, ", ")))
          end
        end
      end
      local left = 0
      for _, ghost in ipairs(ghosts) do if ghost.thing.valid then left = left + 1 end end
      if (game.tick - began) % 1000 == 0 then
        local by_row = {}
        for _, ghost in ipairs(ghosts) do
          if ghost.thing.valid then by_row[ghost.dy] = (by_row[ghost.dy] or 0) + 1 end
        end
        local rows = {}
        for _, dy in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
          rows[#rows + 1] = ("%+.1f: %d"):format(dy, by_row[dy] or 0)
        end
        log(("ROWS ... tick %d: %d left | %s"):format(game.tick - began, left,
          table.concat(rows, ", ")))
      end
      return left == 0 or game.tick - began > world.CYCLE * 60
    end, function()
      local by_row = {}
      for _, ghost in ipairs(ghosts) do
        if ghost.thing.valid then by_row[ghost.dy] = (by_row[ghost.dy] or 0) + 1 end
      end
      local rows, left = {}, 0
      for _, dy in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
        rows[#rows + 1] = ("%+.1f: %d of 9 left"):format(dy, by_row[dy] or 0)
        left = left + (by_row[dy] or 0)
      end
      log(("ROWS | standing still, after %d ticks: %s"):format(game.tick - began,
        table.concat(rows, ", ")))
      -- All four, which is the point. Two rows either side of a track at a tile and a half
      -- and two and a half are inside a second tier arm's three, and a row that never goes
      -- up is either a reach that has shrunk or a row laid where nothing can touch it.
      assert.are.equal(0, left,
        ("%d ghosts were left standing beside a parked train"):format(left))
    end, "never settled", world.CYCLE * 61)
  end)
end)


--- What happens to a belt the hold will not take back.
---
--- give_to() is the "put it where it came from" path, and when the pockets are full it does
--- what the game does with what a character cannot hold: it spills. That is right, and the
--- item is left unmarked on purpose because it is the player's own rather than something the
--- arms should come back for.
---
--- Where it spills is the question. On a train the wearer is the locomotive, which stands on
--- the rail, and the rows an arm builds are a tile and a half off it -- so a spill scattered
--- round the hull lands on belts the arms have just put down. spill_item_stack defaults
--- allow_belts to true, and a lane swallows a stack whole: the belt stops being litter
--- anybody can see and becomes cargo riding up the line, which is indistinguishable from a
--- belt destroyed until somebody reads the lanes.
---
--- The hold is barred rather than filled, which is the same refusal arrived at in one line.
describe("a train whose hold will not take a belt back", function()
  local player

  before_each(function()
    player = world.player()
    clear_arena(player)
    storage.constructor_off = {}
  end)

  after_each(function()
    storage.constructor_off = {}
    for _, sticker in pairs(player.character and player.character.stickers or {}) do
      sticker.destroy()
    end
    clear_arena(player)
  end)

  it("does not feed it to the belts it has just built", function()
    local surface, y = player.surface, world.ORIGIN.y
    for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + 60, 2 do
      surface.create_entity{ name = "straight-rail", position = { x, y },
        direction = defines.direction.east, force = player.force }
    end
    local loco = surface.create_entity{ name = "locomotive",
      position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
      force = player.force }
    assert.is_not_nil(loco, "the locomotive would not go on the rail")
    local wagon = surface.create_entity{ name = "cargo-wagon",
      position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
      force = player.force }
    loco.insert{ name = "nuclear-fuel", count = 5 }
    wagon.insert{ name = BELT, count = 50 }
    local grid = {}
    for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
    grid[#grid + 1] = "battery-mk2-equipment"
    world.fit(loco, grid, true)
    loco.train.manual_mode = true
    loco.set_driver(player)
    loco.train.speed = 0

    -- Belts already standing where a spill round the hull will land, which is what the
    -- rows either side of a track are by the time any of this happens.
    local middle = loco.position.y - world.ORIGIN.y
    local dx = loco.position.x - world.ORIGIN.x
    for step = -3, 3 do
      for _, off in ipairs{ -2.5, -1.5, 1.5, 2.5 } do
        surface.create_entity{ name = BELT,
          position = { world.ORIGIN.x + dx + step, world.ORIGIN.y + middle + off },
          direction = defines.direction.east, force = player.force }
      end
    end
    -- And a ghost or two for an arm to set off with a belt for, clear of the belts laid
    -- above and inside what an arm at the end of the hull can reach.
    world.ghost(player, BELT, dx + 4, middle + 1.5)
    world.ghost(player, BELT, dx + 4, middle - 1.5)

    local began, barred, pressed = game.tick, false, false
    world.once(function()
      local holding = false
      for _, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm = record.entity
        if arm and arm.valid and arm.held_stack.valid_for_read
            and arm.held_stack.name == BELT then holding = true end
      end
      -- The moment a claw is carrying one, shut the hold and take the arms away. What it is
      -- holding has nowhere to go but the ground.
      if holding and not barred then
        wagon.get_inventory(defines.inventory.cargo_wagon).set_bar(1)
        barred = true
      end
      if barred and not pressed then
        press(player)
        pressed = true
      end
      return (pressed and game.tick - began > 240) or game.tick - began > 900
    end, function()
      assert.is_true(barred, "no claw ever picked a belt up, so this measured nothing")
      local riding = on_lanes(surface)
      local loose = surface.count_entities_filtered{ name = "item-on-ground",
        position = world.ORIGIN, radius = ARENA }
      log(("HANDBACK | after the hold was shut: %d riding a lane, %d lying on the ground")
        :format(riding, loose))
      for _, line in ipairs(sweep(surface, player)) do log("    " .. line) end
      -- On the ground is honest -- it is the player's own belt and they can see it. Riding
      -- the line is not: it is gone.
      assert.are.equal(0, riding,
        ("%d belts were fed to the lanes rather than left on the ground"):format(riding))
    end, "the arms never went away", 1000)
  end)
end)
