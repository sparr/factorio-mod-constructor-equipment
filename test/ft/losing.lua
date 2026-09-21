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
    local arm, box = record.entity, record.catcher
    if arm and arm.valid and arm.held_stack.valid_for_read
        and arm.held_stack.name == BELT then
      where.hands = where.hands + arm.held_stack.count
    end
    if box and box.valid then
      where.boxes = where.boxes
        + box.get_inventory(defines.inventory.chest).get_item_count(BELT)
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
