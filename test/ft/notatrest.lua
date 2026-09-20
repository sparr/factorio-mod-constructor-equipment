--- An arm that does not start at rest.
---
--- Everything the lead does so far begins with a folded arm whose hand is born where a fresh
--- one is born. A claw part way through a round is not that: its hand is already out, at some
--- radius and on some bearing, and what it can reach from there is a different question --
--- it may have to pull in as readily as push out, and it has to swing round to wherever it
--- is going.
---
--- lib/reach.lua answers the first two of those exactly. It says nothing about the third,
--- and this is where that gets found out, because the engine is the authority on what a hand
--- actually does and the arithmetic is only a model of it.
---
--- The mod is left out of it. No equipment is worn, so control.lua has no arms to run; the
--- arm here is built and driven by the fixture out of the same tier prototype, which is the
--- only way to put a hand at a chosen radius and bearing to begin with.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local pack = require("lib.pack")
local reach = require("lib.reach")

local TIER = tiers.by_level[4]
local BELT = "transport-belt"
local LIFT = pack.lift(1, 1)
local REST = 0.2
local REPORT = "not-at-rest.txt"

local player
local first = true
local function note(line)
  helpers.write_file(REPORT, line .. "\n", not first)
  first = false
end

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

after_each(function()
  player.walking_state = { walking = false }
  for _, tier in ipairs(tiers.list) do
    for _, arm in ipairs(player.surface.find_entities_filtered{ name = tier.inserter,
          position = world.ORIGIN, radius = 200 }) do
      if arm.valid then arm.destroy() end
    end
  end
  for _, thing in ipairs(player.surface.find_entities_filtered{
        name = { BELT, "item-on-ground" }, position = world.ORIGIN, radius = 200 }) do
    if thing.valid then thing.destroy() end
  end
  world.clear(player)
end)

local function unit(v)
  local length = math.sqrt(v.x * v.x + v.y * v.y)
  return { x = v.x / length, y = v.y / length }
end

---Where the arm is drawn, for one arm on a character.
local function mount_at(at)
  return { x = at.x, y = at.y - LIFT }
end

---Hold the arm on its owner, aimed at an offset that travels with them.
local function hold(arm, at, offset)
  arm.energy = arm.electric_buffer_size
  local mount = mount_at(at)
  local bearing = unit(offset)
  arm.teleport(mount)
  arm.pickup_position = { mount.x + bearing.x * REST, mount.y + bearing.y * REST }
  arm.drop_position = { at.x + offset.x, at.y + offset.y - LIFT }
  return mount
end

---How far the hand is out from its own base.
local function hand_out(arm)
  return reach.distance(arm.position, arm.held_stack_position)
end

---Put a hand at a chosen radius on a chosen bearing, then hand over to the real case.
---
---Driven there by aiming at that very spot and waiting, which is the only way there is: a
---hand's position is its own state, and nothing but building the arm again resets it.
---@param radius number
---@param bearing {x: number, y: number}
---@param then_do fun(arm: LuaEntity, settled: number)
local function with_hand_at(radius, bearing, then_do)
  local at = player.position
  local aim = { x = bearing.x * radius, y = bearing.y * radius }
  local arm = player.surface.create_entity{
    name = TIER.inserter, position = mount_at(at), force = player.force,
    direction = pack.towards(bearing.x, bearing.y) }
  assert.is_not_nil(arm, "the arm was not built")
  arm.held_stack.set_stack{ name = BELT, count = 1 }
  hold(arm, at, aim)
  local began = game.tick
  world.once(function()
    hold(arm, player.position, aim)
    -- It lets go on arriving; hand it back so it stays where it is rather than folding.
    if not arm.held_stack.valid_for_read then
      arm.held_stack.set_stack{ name = BELT, count = 1 }
    end
    return math.abs(hand_out(arm) - radius) < 0.06 or game.tick - began > 200
  end, function()
    then_do(arm, hand_out(arm))
  end, "the hand never reached its starting radius", 280)
end

--- What the arithmetic says against what the engine does, with the hand already out.
---
--- Standing still on purpose. A stationary owner takes the lead out of it entirely, so what
--- is left is the one thing reach.earliest does not model: a hand out on one bearing and
--- wanted on another has to swing round, and it swings at its tier's own rate. The fourth
--- tier turns 2.88 degrees a tick, so half a turn is sixty two ticks, against fifty for
--- stretching the whole five tiles.
describe("a hand already out, asked for something at an angle", function()
  local HAND_AT = 3
  --- The same distance out as the hand already is, so there is nothing to stretch or pull
  --- and the only thing between them is the turn.
  local TARGET_AT = 3

  for _, turn in ipairs{ 0, 45, 90, 135, 180 } do
    it(("reaches something %d degrees round"):format(turn), function()
      with_hand_at(HAND_AT, { x = 1, y = 0 }, function(arm, settled)
        local angle = math.rad(turn)
        local offset = { x = math.cos(angle) * TARGET_AT, y = math.sin(angle) * TARGET_AT }
        -- Where the hand actually points, read off the arm rather than assumed: it was
        -- driven out along a bearing, and where it ended up is what it has to turn from.
        local hand = arm.held_stack_position
        local facing = unit{ x = hand.x - arm.position.x, y = hand.y - arm.position.y }
        local said = reach.earliest(
          { range = TIER.range, extension = TIER.extension, out = settled,
            rotation = TIER.rotation, facing = facing },
          { x = 0, y = 0 }, offset, 300)
        local began, arrived, closest = game.tick, nil, math.huge
        world.once(function()
          hold(arm, player.position, offset)
          local want = { x = player.position.x + offset.x,
                         y = player.position.y + offset.y - LIFT }
          local away = reach.distance(arm.held_stack_position, want)
          if away < closest then closest = away end
          if not arrived and away < 0.15 then arrived = game.tick - began end
          return arrived ~= nil or game.tick - began > 250
        end, function()
          note(("%3d degrees round: hand at %.2f, arithmetic t+%-5s engine t+%-5s closest %.3f")
            :format(turn, settled, tostring(said), tostring(arrived), closest))
          assert.is_not_nil(said, "the arithmetic said it could not be reached at all")
          assert.is_not_nil(arrived, "the engine never got the hand there")
          -- The arithmetic is allowed to be a shade early, since the engine's last step
          -- covers whatever gap is left rather than creeping up on it. It is not allowed to
          -- be late, which would mean promising a meeting that cannot be made.
          assert.is_true(said <= arrived + 1,
            ("arithmetic said t+%d and the engine took t+%d"):format(said, arrived))
          assert.is_true(arrived - said <= 6,
            ("arithmetic said t+%d and the engine took t+%d, which is not close")
              :format(said, arrived))
        end, "the hand never got there", 320)
      end)
    end)
  end
end)

--- The whole of it: a hand at some radius on some bearing, asked for something at another
--- radius and another angle, with its owner standing still or walking.
---
--- Held on a lead rather than aimed at the thing itself, and the difference is not a detail.
--- reach.earliest answers what a hand could do: its bearing at tick k may be anything within
--- a turn's worth of where it started, so if the thing's bearing then falls inside that, the
--- hand can be on it. The engine does not plan, though -- it turns towards wherever the drop
--- is this tick and no further -- so aimed at something moving it chases the bearing round
--- instead of taking the short way to where the bearing is going, and arrives later than it
--- needed to. Measured: aimed at the thing, one walking case never arrived at all where the
--- arithmetic said 56 ticks.
---
--- A lead is a fixed point, so the bearing to it does not move, so the chase and the short
--- way are the same thing. That is what the mod holds and it is what makes the arithmetic
--- describe the engine rather than merely bound it.
describe("a hand already out, over radii and angles", function()
  local CASES = {
    { hand = 1.5, turn = 60,  target = 4.0, walking = false },
    { hand = 1.5, turn = 150, target = 2.0, walking = false },
    { hand = 4.0, turn = 60,  target = 1.5, walking = false },
    { hand = 4.0, turn = 150, target = 4.5, walking = false },
    { hand = 1.5, turn = 30,  target = 4.0, walking = true },
    { hand = 4.0, turn = 90,  target = 2.0, walking = true },
    { hand = 4.5, turn = 20,  target = 4.5, walking = true },
  }

  for index, case in ipairs(CASES) do
    it(("case %d: hand %.1f out, %d degrees round to something %.1f out%s")
        :format(index, case.hand, case.turn, case.target,
          case.walking and ", walking" or ""), function()
      with_hand_at(case.hand, { x = 1, y = 0 }, function(arm, settled)
        local at = player.position
        local angle = math.rad(case.turn)
        -- A fixed point in the world, which is what a ghost is.
        local spot = { x = at.x + math.cos(angle) * case.target,
                       y = at.y + math.sin(angle) * case.target }
        local hand = arm.held_stack_position
        local facing = unit{ x = hand.x - arm.position.x, y = hand.y - arm.position.y }
        local drift = case.walking and { x = 0.1484375, y = 0 } or { x = 0, y = 0 }
        local said = reach.earliest(
          { range = TIER.range, extension = TIER.extension, out = settled,
            rotation = TIER.rotation, facing = facing },
          drift, { x = spot.x - at.x, y = spot.y - at.y }, 300)

        -- Where the thing will be, seen from the arm, at the moment the arithmetic says the
        -- hand could be on it. Held constant, which is what makes it a lead.
        --
        -- Where the arithmetic says there is no such moment there is no lead to hold either,
        -- so the claw is simply aimed at the thing and left to chase it. That is a one way
        -- check: a chase arriving would prove the arithmetic wrong, and a chase failing is
        -- only consistent with it, since a chase is the slower way round.
        local lead = said and {
          x = spot.x - at.x - drift.x * said,
          y = spot.y - at.y - drift.y * said } or nil

        local began, arrived, closest = game.tick, nil, math.huge
        world.once(function()
          if case.walking then
            player.walking_state = { walking = true, direction = defines.direction.east }
          end
          local here = player.position
          local aim = lead or { x = spot.x - here.x, y = spot.y - here.y }
          hold(arm, here, aim)
          local want = lead and { x = here.x + lead.x, y = here.y + lead.y - LIFT }
            or { x = spot.x, y = spot.y - LIFT }
          local away = reach.distance(arm.held_stack_position, want)
          if away < closest then closest = away end
          if not arrived and away < 0.15 then arrived = game.tick - began end
          return arrived ~= nil or game.tick - began > 260
        end, function()
          player.walking_state = { walking = false }
          note(("hand %.1f, %3d deg, target %.1f%-9s arithmetic t+%-6s engine t+%-6s closest %.3f")
            :format(case.hand, case.turn, case.target,
              case.walking and ", walking" or "", tostring(said), tostring(arrived), closest))
          if said == nil then
            assert.is_nil(arrived,
              "the arithmetic said there was no meeting and the engine made one anyway")
            return
          end
          assert.is_not_nil(arrived, "the arithmetic promised a meeting the engine never made")
          assert.is_true(said <= arrived + 1,
            ("said t+%d, engine took t+%d: the arithmetic was late"):format(said, arrived))
          assert.is_true(arrived - said <= 8,
            ("said t+%d, engine took t+%d: not close enough to be useful")
              :format(said, arrived))
        end, "the hand never got there", 340)
      end)
    end)
  end
end)

--- And now the same thing through the mod, rather than beside it.
---
--- Everything above drives an arm the fixture built, because that is the only way to put a
--- hand at a chosen radius and bearing. What it cannot show is control.lua doing it: an arm
--- of its own, out on a reach with a load in its claw, handed a different ghost and expected
--- to swing round to it while its owner walks on.
---
--- The way to make that happen without reaching into the mod is to take the ghost away. A
--- reach whose ghost has stopped being work is redirected rather than abandoned, and the
--- claw is holding the belt it set off with, so the arm that takes on the second ghost is an
--- arm that is not at rest.
describe("the mod turning a loaded claw to another ghost", function()
  local BELTS = 5

  local function walking()
    player.walking_state = { walking = true, direction = defines.direction.east }
  end

  ---Every belt there is, wherever it has got to.
  local function belts_anywhere()
    local total = player.get_item_count(BELT)
      + player.surface.count_entities_filtered{ name = BELT, position = world.ORIGIN,
          radius = 120 }
    for _, thing in ipairs(player.surface.find_entities_filtered{
          name = { "item-on-ground", "constructor-equipment-catcher" },
          position = world.ORIGIN, radius = 120 }) do
      if thing.name == "item-on-ground" then
        if thing.stack and thing.stack.valid_for_read and thing.stack.name == BELT then
          total = total + thing.stack.count
        end
      else
        total = total + thing.get_item_count(BELT)
      end
    end
    local record = (storage.constructor_arms[player.index] or {})[1]
    local arm = record and record.entity
    if arm and arm.valid and arm.held_stack.valid_for_read then
      total = total + arm.held_stack.count
    end
    return total
  end

  it("builds the second one, and keeps the belt, without jumping the claw", function()
    world.equip(player, { TIER.name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = BELT, count = BELTS }
    local first = world.ghost(player, BELT, 10, 4)
    world.ghost(player, BELT, 14, 0)

    local began, taken, loaded_out, worst, previous = game.tick, nil, false, 0, nil
    world.once(function()
      walking()
      local since = game.tick - began
      local record = (storage.constructor_arms[player.index] or {})[1]
      local arm = record and record.entity
      if record and record.job and not taken then taken = since end
      if arm and arm.valid then
        local hand = arm.held_stack_position
        if previous then worst = math.max(worst, reach.distance(previous, hand)) end
        previous = { x = hand.x, y = hand.y }
        -- Once the claw is a good way out with the belt in it, take its ghost away.
        if not loaded_out and arm.held_stack.valid_for_read
            and reach.distance(arm.position, hand) > 2.5 then
          loaded_out = true
          if first.valid then first.destroy() end
        end
      else
        previous = nil
      end
      return (loaded_out and world.ghosts(player) == 0) or since > 300
    end, function()
      player.walking_state = { walking = false }
      assert.is_not_nil(taken, "no arm ever set off")
      assert.is_true(loaded_out, "the claw never got out far enough with a belt in it")
      assert.are.equal(0, world.ghosts(player),
        "the second ghost was never built after the first was taken away")
      assert.are.equal(1, world.count(player, BELT), "no belt was put down")
      assert.are.equal(BELTS, belts_anywhere(), "a belt was made or lost")
      assert.is_true(worst < 1,
        ("the claw moved %.2f tiles in one tick, which is a jump rather than a swing")
          :format(worst))
    end, "the walk never ended", 400)
  end)
end)

--- A bulk claw working a round while its owner walks.
---
--- This is the case all of the above was groundwork for. A round is a claw that goes out
--- carrying several and crosses from one ghost to the next rather than coming home between
--- them, so every ghost after the first is reached for by an arm that is already out, with a
--- load in its claw, on whatever bearing the last one left it. Add a walking owner and the
--- lead and the turn are both in play at once.
---
--- A claw only carries more than one once the capacity research is done -- without it every
--- tier makes single trips, which is why the rest of the suite never crosses at all.
local ROUND_RESEARCH = { "bulk-inserter", "inserter-capacity-bonus-1",
                         "inserter-capacity-bonus-2" }

describe("a bulk claw crossing while its owner walks", function()
  local STOCK = 10

  local function research(on)
    for _, name in ipairs(ROUND_RESEARCH) do
      local technology = player.force.technologies[name]
      if technology then technology.researched = on end
    end
  end

  after_each(function()
    research(false)
    player.get_inventory(defines.inventory.character_armor).clear()
    for _, thing in ipairs(player.surface.find_entities_filtered{
          name = { BELT, "item-on-ground", "constructor-equipment-catcher" },
          position = world.ORIGIN, radius = 140 }) do
      if thing.valid then thing.destroy() end
    end
    for _, ghost in ipairs(player.surface.find_entities_filtered{ type = "entity-ghost",
          position = world.ORIGIN, radius = 140 }) do
      if ghost.valid then ghost.destroy() end
    end
  end)

  it("crosses between them, builds them all, and keeps every belt", function()
    research(true)
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { TIER.name, "fission-reactor-equipment", "battery-equipment" },
      true, "power-armor")
    player.insert{ name = BELT, count = STOCK }
    -- A cluster ahead, close enough together that crossing is worth more than coming
    -- home, and near enough the line of travel that all four are inside the cone the
    -- claw can still reach when it sets off. Further out to the side they fall off the
    -- end of the round instead, which is what the abeam test below pins.
    local WHERE = { { 9, 1 }, { 10, 1 }, { 11, 0 }, { 11, 1 } }
    for _, at in ipairs(WHERE) do world.ghost(player, BELT, at[1], at[2]) end

    local began, crossed, worst, previous = game.tick, false, 0, nil
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local record = (storage.constructor_arms[player.index] or {})[1]
      local job = record and record.job
      if job and job.crossing then crossed = true end
      local arm = record and record.entity
      if arm and arm.valid then
        local hand = arm.held_stack_position
        if previous then worst = math.max(worst, reach.distance(previous, hand)) end
        previous = { x = hand.x, y = hand.y }
      else
        previous = nil
      end
      return world.ghosts(player) == 0 or game.tick - began > 400
    end, function()
      player.walking_state = { walking = false }
      note(("crossing while walking: %d of %d built, crossed %s, worst step %.3f")
        :format(#WHERE - world.ghosts(player), #WHERE, tostring(crossed), worst))
      assert.is_true(crossed, "the claw never crossed; it made single trips instead")
      assert.are.equal(0, world.ghosts(player),
        ("%d of %d were walked past"):format(world.ghosts(player), #WHERE))
      assert.are.equal(#WHERE, world.count(player, BELT), "not every belt was put down")
      assert.are.equal(STOCK, player.get_item_count(BELT) + world.count(player, BELT),
        "a belt was made or lost")
      assert.is_true(worst < 1,
        ("the claw moved %.2f tiles in one tick, which is a jump"):format(worst))
    end, "the walk never ended", 500)
  end)

  --- A round is shopped for over its own life, not over the one swing the tick's search
  --- covers. A walking owner reaches about 1.07 tiles abeam, so a row two tiles out to the
  --- side is only ever reachable ahead -- and by the time a claw that took only the near
  --- couple of them was free again, the walk had carried the rest square abeam, where
  --- nothing walking can reach them. Taking the whole row at the outset is the only way to
  --- get it, because a claw refills at home and nowhere else.
  it("sets off carrying the whole row rather than the near end of it", function()
    research(true)
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { TIER.name, "fission-reactor-equipment", "battery-equipment" },
      true, "power-armor")
    player.insert{ name = BELT, count = STOCK }
    -- Ten to thirteen tiles ahead: past what one swing can reach or even see, and well
    -- inside what the round as a whole will cover.
    local WHERE = { { 10, 2 }, { 11, 2 }, { 12, 2 }, { 13, 2 } }
    for _, at in ipairs(WHERE) do world.ghost(player, BELT, at[1], at[2]) end

    local began, sized = game.tick, nil
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local record = (storage.constructor_arms[player.index] or {})[1]
      -- what the round set out to do, before any of it was done
      if not sized and record and record.job and record.job.left then
        sized = record.job.left
      end
      return world.ghosts(player) == 0 or game.tick - began > 300
    end, function()
      player.walking_state = { walking = false }
      note(("a row two tiles abeam: set out for %s, built %d of %d")
        :format(tostring(sized), #WHERE - world.ghosts(player), #WHERE))
      assert.are.equal(#WHERE, sized,
        "the claw set off for less than the row, so the rest will be walked past")
      assert.are.equal(0, world.ghosts(player),
        ("%d of %d were walked past"):format(world.ghosts(player), #WHERE))
      assert.are.equal(#WHERE, world.count(player, BELT), "not every belt was put down")
      assert.are.equal(STOCK, player.get_item_count(BELT) + world.count(player, BELT),
        "a belt was made or lost")
    end, "the walk never ended", 400)
  end)
end)
