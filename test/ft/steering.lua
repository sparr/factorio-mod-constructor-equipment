--- Leading from a wearer that is turning.
---
--- An intercept is worked out from the course its owner is on, and a vehicle that steers is
--- on a different course every tick. The lead is re-solved every tick for exactly that
--- reason, but re-solving only says where to aim: the claw still has to swing there, and it
--- swings at its tier's own rotation speed with no way to be turned faster. So the question
--- is whether a wearer can out-turn its own arm.
---
--- A tank's body comes round at 1.26 degrees a tick against a fourth tier claw's 2.88, and a
--- spidertron does not turn at all -- it walks. A car is the awkward one: it swings round at
--- 3.32 degrees a tick, which the slowest claw cannot follow.
---
--- A car has no equipment grid in the base game, but plenty of mods give it one and the
--- showroom does too, so the arms have to work on it. test/ft/ce-tests hands cars and
--- locomotives a grid for the same reason the showroom does. Supported rather than tuned
--- for: what is asked here is that nothing breaks and nothing is lost, not that a car is
--- a good place to build from.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"
local FOURTH = tiers.by_level[4]
--- Long enough for half a dozen trips out and back, which is as many as an arm can make.
local A_DRIVE = 600

local player

--- These drive a hundred and fifty tiles, and world.clear sweeps thirty while world.ghosts
--- counts the whole surface, so their litter has to be swept over the ground they cover.
local function sweep()
  local half = 260
  local area = { { world.ORIGIN.x - half, world.ORIGIN.y - half },
                 { world.ORIGIN.x + half, world.ORIGIN.y + half } }
  for _, thing in ipairs(player.surface.find_entities_filtered{ area = area,
        name = { BELT, "fast-transport-belt", "express-transport-belt",
                 "turbo-transport-belt", "tank", "spidertron", "car", "item-on-ground",
                 "constructor-equipment-catcher" } }) do
    if thing.valid then thing.destroy() end
  end
  for _, ghost in ipairs(player.surface.find_entities_filtered{ area = area,
        type = "entity-ghost" }) do
    if ghost.valid then ghost.destroy() end
  end
  local arms = {}
  for _, tier in ipairs(tiers.list) do arms[#arms + 1] = tier.inserter end
  for _, arm in ipairs(player.surface.find_entities_filtered{ area = area, name = arms }) do
    if arm.valid then arm.destroy() end
  end
end

before_each(function()
  player = world.player()
  world.clear(player)
  sweep()
end)

after_each(function()
  if player.vehicle then world.unseat(player) end
  sweep()
  world.clear(player)
end)

--- How many belts went in, so that what comes out can be counted against it.
local STOCK = 120

---Drive a field of ghosts and say what became of them.
---@param name string which vehicle
---@param turning boolean
---@param done fun(built: integer, lag: number, all_told: integer)
local function drive_through(name, turning, done)
  local vehicle = world.vehicle(player, name)
  vehicle.insert{ name = "nuclear-fuel", count = 5 }
  world.fit(vehicle, { FOURTH.name, "battery-equipment" }, true)
  vehicle.insert{ name = BELT, count = STOCK }
  for dx = -15, 35, 5 do
    for dy = -25, 25, 5 do world.ghost(player, BELT, dx, dy) end
  end

  local began, worst = game.tick, 0
  world.once(function()
    local since = game.tick - began
    if name == "spidertron" then
      -- A spider is sent somewhere rather than steered, so a turn is a destination that
      -- keeps swinging round.
      local angle = turning and (since / A_DRIVE) * math.pi or 0
      vehicle.autopilot_destination = {
        world.ORIGIN.x + math.cos(angle) * 300, world.ORIGIN.y + math.sin(angle) * 300 }
    else
      vehicle.riding_state = {
        acceleration = defines.riding.acceleration.accelerating,
        direction = turning and defines.riding.direction.left
          or defines.riding.direction.straight }
    end
    -- How far behind its aim the claw is, while a reach is under way and the hand is out
    -- far enough for a bearing to mean anything.
    local record = (storage.constructor_arms[player.index] or {})[1]
    local arm = record and record.entity
    if arm and arm.valid and record.job
        and reach.distance(arm.position, arm.held_stack_position) > 1 then
      local base, hand, drop = arm.position, arm.held_stack_position, arm.drop_position
      local atan = math.atan2 or math.atan
      local lag = math.deg(atan(hand.x - base.x, -(hand.y - base.y))
        - atan(drop.x - base.x, -(drop.y - base.y)))
      if lag > 180 then lag = lag - 360 elseif lag < -180 then lag = lag + 360 end
      worst = math.max(worst, math.abs(lag))
    end
    return since > A_DRIVE
  end, function()
    if name ~= "spidertron" then
      vehicle.riding_state = { acceleration = defines.riding.acceleration.nothing,
        direction = defines.riding.direction.straight }
    end
    -- Every belt there is: standing where it was built, in the hold, in the claw, or lying
    -- about. A spider's arms are on its legs and build from out there, so counting only
    -- near the body misses what a leg put down and reads as a belt having gone missing.
    local standing = player.surface.count_entities_filtered{ name = BELT,
      position = world.ORIGIN, radius = 260 }
    local claw = 0
    local record = (storage.constructor_arms[player.index] or {})[1]
    local held = record and record.entity and record.entity.valid
      and record.entity.held_stack.valid_for_read and record.entity.held_stack.count or 0
    local loose = 0
    for _, item in ipairs(player.surface.find_entities_filtered{ name = "item-on-ground",
          position = world.ORIGIN, radius = 260 }) do
      if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
        loose = loose + item.stack.count
      end
    end
    local all_told = vehicle.get_item_count(BELT) + standing + held + loose + claw
    world.unseat(player)
    vehicle.destroy()
    -- Written down as well as asserted on. The assertions only say nothing broke; what is
    -- worth reading is how much a steering wearer gets done against one going straight.
    helpers.write_file("steering.txt",
      ("%-11s %-8s built %2d  worst claw lag %5.1f deg  belts all told %d\n")
        :format(name, turning and "turning" or "straight", standing, worst, all_told), true)
    done(standing, worst, all_told)
  end, "the drive never ended", A_DRIVE + 200)
end

describe("a wearer that steers", function()
  for _, name in ipairs{ "tank", "spidertron", "car" } do
    it("builds while a " .. name .. " holds a straight line", function()
      drive_through(name, false, function(built, lag, all_told)
        assert.is_true(built >= 1,
          ("a %s driving straight through a field built nothing at all"):format(name))
        assert.are.equal(STOCK, all_told, "a belt was made or lost")
      end)
    end)

    --- The case this file exists for. What it asks is that steering costs nothing: work
    --- still gets done and nothing goes missing doing it.
    ---
    --- How much work is deliberately not asserted tightly. The count is not stable enough
    --- to pin: a curving car built sixteen on one run and nine on another, and a curving
    --- spidertron four and then two, because where a vehicle's own path carries it through
    --- a field of ghosts is sensitive to everything around it. What is stable, on every run
    --- and every wearer, is that every belt is still accounted for. The counts go to
    --- script-output for reading rather than into an assertion that would fail for reasons
    --- that have nothing to do with the mod.
    it("builds just as well while a " .. name .. " turns all the way round", function()
      drive_through(name, true, function(built, lag, all_told)
        assert.is_true(built >= 1,
          ("a %s that steers built nothing at all"):format(name))
        assert.are.equal(STOCK, all_told, "a belt was made or lost while steering")
      end)
    end)
  end
end)

--- A train steers only where the rails do, so nothing here turns. What makes it worth its
--- own case is everything else about it: it is the fastest wearer there is at 0.4 tiles a
--- tick, which makes its cone a fourteen degree needle seventeen tiles long, and a
--- locomotive has no hold of its own, so its arms build out of the wagons behind it.
---
--- Supported rather than tuned for. A locomotive has no equipment grid in the base game
--- either; test/ft/ce-tests gives it one, as the showroom does.
describe("a train", function()
  local RAILS_FROM, RAILS_TO = -60, 220
  local STOCK = 60

  ---Lay a straight line of rail through the arena and put a fuelled train on it.
  ---@return LuaEntity locomotive
  ---@return LuaEntity wagon
  local function a_train()
    local surface, y = player.surface, world.ORIGIN.y
    for x = world.ORIGIN.x + RAILS_FROM, world.ORIGIN.x + RAILS_TO, 2 do
      surface.create_entity{ name = "straight-rail", position = { x, y },
        direction = defines.direction.east, force = player.force }
    end
    local loco = surface.create_entity{ name = "locomotive",
      position = { world.ORIGIN.x - 20, y }, direction = defines.direction.east,
      force = player.force }
    assert(loco, "the locomotive would not go on the rails")
    local wagon = surface.create_entity{ name = "cargo-wagon",
      position = { world.ORIGIN.x - 27, y }, direction = defines.direction.east,
      force = player.force }
    assert(wagon, "the wagon would not go on the rails")
    loco.insert{ name = "nuclear-fuel", count = 5 }
    -- The belts go in the wagon, because a locomotive has nowhere to put them.
    wagon.insert{ name = BELT, count = STOCK }
    world.fit(loco, { FOURTH.name, "battery-equipment" }, true)
    loco.train.manual_mode = true
    loco.set_driver(player)
    return loco, wagon
  end

  local function clear_the_line()
    local half = 300
    for _, thing in ipairs(player.surface.find_entities_filtered{
          area = { { world.ORIGIN.x - half, world.ORIGIN.y - half },
                   { world.ORIGIN.x + half, world.ORIGIN.y + half } },
          name = { "locomotive", "cargo-wagon", "straight-rail" } }) do
      if thing.valid then thing.destroy() end
    end
  end

  after_each(clear_the_line)

  it("builds out of its wagons as it runs past", function()
    local loco, wagon = a_train()
    -- Either side of the line, clear of the rails themselves.
    local laid = 0
    for x = 10, 100, 10 do
      for _, dy in ipairs{ -4, 4 } do world.ghost(player, BELT, x, dy); laid = laid + 1 end
    end
    local began = game.tick
    world.once(function()
      loco.train.speed = 0.4
      return game.tick - began > 320
    end, function()
      local standing = player.surface.count_entities_filtered{ name = BELT,
        position = world.ORIGIN, radius = 300 }
      local loose = 0
      for _, item in ipairs(player.surface.find_entities_filtered{ name = "item-on-ground",
            position = world.ORIGIN, radius = 300 }) do
        if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
          loose = loose + item.stack.count
        end
      end
      local record = (storage.constructor_arms[player.index] or {})[1]
      local held = record and record.entity and record.entity.valid
        and record.entity.held_stack.valid_for_read and record.entity.held_stack.count or 0
      helpers.write_file("steering.txt",
        ("%-11s %-8s built %2d of %d  belts all told %d\n")
          :format("train", "on rails", standing, laid,
            wagon.get_item_count(BELT) + standing + loose + held), true)
      assert.is_true(standing >= 1,
        ("a train ran past %d ghosts and built nothing"):format(laid))
      assert.are.equal(STOCK, wagon.get_item_count(BELT) + standing + loose + held,
        "a belt was made or lost")
      if loco.get_driver() then world.unseat(player) end
    end, "the train never finished its run", 420)
  end)
end)

--- A wearer whose speed is changing under the lead.
---
--- An intercept is worked out from how far its owner went last tick, held constant for the
--- whole flight. A wearer that is speeding up covers more ground than that, so the lead
--- ought to land short; one that is slowing covers less, so it ought to overshoot. Neither
--- happens, and it is worth writing down why, because the reason is not that the arithmetic
--- is clever.
---
--- The intercept is worked out again every tick, so the error never has more than a tick to
--- accumulate in. Watched on a tank: accelerating from a standing start the lead shortens
--- from 4.76 to 4.58 and the arrival creeps two ticks earlier; braking hard it lengthens
--- from 4.65 to 4.89 and the arrival slips five ticks later. The claw simply follows.
---
--- And behind that, the handover. Once the ghost is genuinely in reach the lead is dropped
--- and the claw is aimed at the thing itself, so however wrong the lead was on the way, the
--- last part of the journey is not a prediction at all.
---
--- What a hard enough brake can do is push the lead past the tier's reach, at which point
--- the intercept comes back with nothing and the reach is given up -- which is the stopping
--- case, and is already covered on a character.
describe("a wearer whose speed is changing", function()
  ---@param brake_after integer? ticks after the ghost is laid to start braking
  ---@param settle integer
  ---@param done fun(built: boolean, stock: integer)
  local function drive_and(settle, brake_after, done)
    local tank = world.vehicle(player, "tank")
    tank.insert{ name = "nuclear-fuel", count = 5 }
    world.fit(tank, { FOURTH.name, "battery-equipment" }, true)
    tank.insert{ name = BELT, count = 5 }
    local began, at = game.tick, nil
    world.once(function()
      local since = game.tick - began
      local pedal = defines.riding.acceleration.accelerating
      if brake_after and since > settle + brake_after then
        pedal = defines.riding.acceleration.braking
      end
      tank.riding_state = { acceleration = pedal,
        direction = defines.riding.direction.straight }
      if since == settle then
        local here = tank.position
        local ghost = player.surface.create_entity{ name = "entity-ghost",
          inner_name = BELT, position = { here.x + 12, here.y + 4 }, force = player.force }
        at = ghost and { x = ghost.position.x, y = ghost.position.y } or nil
      end
      local gone = at and player.surface.count_entities_filtered{ type = "entity-ghost",
        position = at, radius = 0.4 } == 0
      return gone or since > settle + 200
    end, function()
      tank.riding_state = { acceleration = defines.riding.acceleration.nothing,
        direction = defines.riding.direction.straight }
      local built = at ~= nil and player.surface.count_entities_filtered{
        type = "entity-ghost", position = at, radius = 0.4 } == 0
      local standing = player.surface.count_entities_filtered{ name = BELT,
        position = world.ORIGIN, radius = 260 }
      local stock = tank.get_item_count(BELT) + standing
      world.unseat(player)
      tank.destroy()
      done(built, stock)
    end, "the drive never ended", settle + 300)
  end

  it("builds from a standing start, while it is still speeding up hard", function()
    drive_and(10, nil, function(built, stock)
      assert.is_true(built, "a tank accelerating from rest never built the ghost")
      assert.are.equal(5, stock, "a belt was made or lost")
    end)
  end)

  it("builds while braking after the arm has set off", function()
    drive_and(200, 20, function(built, stock)
      assert.is_true(built, "a tank braking mid reach never built the ghost")
      assert.are.equal(5, stock, "a belt was made or lost")
    end)
  end)

  it("builds while braking from the moment the arm sets off", function()
    drive_and(200, 12, function(built, stock)
      assert.is_true(built, "a tank braking from the off never built the ghost")
      assert.are.equal(5, stock, "a belt was made or lost")
    end)
  end)
end)

--- Nothing on the floor. The existing tests count what went in against what came out, and
--- a belt lying on the ground passes that: it is still there to be counted. What it is not
--- is delivered, and a vehicle that sheds one belt a field is a vehicle leaving a trail.
---
--- A hand can finish a job still holding something -- a round that took more than its last
--- ghost wanted, work that went away with the claw loaded -- and with the job gone there was
--- nothing left to point the drop home, so it stayed on the last thing aimed at, out in the
--- world with its box taken away, and the engine let go over bare ground.
describe("what a vehicle leaves behind", function()
  for _, case in ipairs({
      { name = "car straight", vehicle = "car", turning = false },
      { name = "car turning", vehicle = "car", turning = true },
      { name = "tank straight", vehicle = "tank", turning = false },
      { name = "spidertron turning", vehicle = "spidertron", turning = true },
  }) do
    it(case.name, function()
      drive_through(case.vehicle, case.turning, function(built, lag, all_told)
        local loose = 0
        for _, item in pairs(player.surface.find_entities_filtered{
              position = world.ORIGIN, radius = 200, type = "item-entity" }) do
          if item.stack.valid_for_read and item.stack.name == BELT then
            loose = loose + item.stack.count
          end
        end
        assert.are.equal(0, loose,
          ("%s: %d belts were left lying on the ground"):format(case.name, loose))
        assert.is_true(built > 0, case.name .. ": nothing was built at all")
      end)
    end)
  end
end)

--- A claw glued to a ghost. The shape of it is a hand out at the thing it crossed to,
--- turning and stretching to stay exactly on it as its owner drives away, holding nothing
--- and doing nothing, until the swing limit gives up five seconds later.
---
--- What is behind it is a round whose counter and whose claw have come apart: the counter
--- says there is another delivery to make and the hand is empty, so deliver() waits for a
--- load into a box that nothing is going to fill. redirect() checks the two against each
--- other before it turns a claw to the next ghost, and nothing checked afterwards.
---
--- Driven rather than set going, because that is what turned it up: run, ease off, stop,
--- back up, run again.
describe("a train driven up and down a line of ghosts", function()
  local RAILS_FROM, RAILS_TO = -60, 260
  local BELTS = 200

  it("never leaves a claw sitting on a ghost with nothing to give it", function()
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
    -- the showroom's own locomotive kit, and its own layout: eight of the second tier, and
    -- ghosts two tiles either side of the rail, one tile apart
    local grid = {}
    for _ = 1, 8 do grid[#grid + 1] = tiers.by_level[2].name end
    grid[#grid + 1] = "battery-equipment"
    world.fit(loco, grid, true)
    loco.train.manual_mode = true
    loco.set_driver(player)
    for x = 6, 120 do
      for _, dy in ipairs{ -2, 2 } do world.ghost(player, BELT, x, dy) end
    end

    local began, stuck, worst = game.tick, {}, 0
    world.once(function()
      local phase = ((game.tick - began) % 300)
      if phase < 120 then loco.train.speed = 0.25
      elseif phase < 150 then loco.train.speed = 0.05
      elseif phase < 180 then loco.train.speed = 0
      elseif phase < 240 then loco.train.speed = -0.15
      else loco.train.speed = 0.3 end
      for slot, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm, job = record.entity, record.job
        local glued = false
        if arm and arm.valid and job and job.target then
          local hand = arm.held_stack_position
          glued = not arm.held_stack.valid_for_read
            and reach.distance(arm.position, hand) > 1
            and reach.distance(hand, { x = job.target.x,
                  y = job.target.y - (record.lift or 0) }) < 0.5
        end
        stuck[slot] = glued and (stuck[slot] or 0) + 1 or 0
        worst = math.max(worst, stuck[slot])
      end
      return game.tick - began > 1200
    end, function()
      loco.train.speed = 0
      -- A claw does pass through this for a tick or two on any ordinary arrival. Five
      -- seconds of it is the swing limit, and what was measured before was seventy three.
      assert.is_true(worst < 40,
        ("a claw sat on a ghost holding nothing for %d ticks"):format(worst))
      local built = surface.count_entities_filtered{ name = BELT,
        position = world.ORIGIN, radius = 300 }
      local loose = 0
      for _, item in ipairs(surface.find_entities_filtered{ name = "item-on-ground",
            position = world.ORIGIN, radius = 300 }) do
        if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
          loose = loose + item.stack.count
        end
      end
      local held = wagon.valid
        and wagon.get_inventory(defines.inventory.cargo_wagon).get_item_count(BELT) or 0
      -- and what is still in the air at the end of the run: a claw part way through a
      -- delivery, or a box standing on a ghost waiting for one
      local flying = 0
      for _, record in pairs(storage.constructor_arms[player.index] or {}) do
        local arm, box = record.entity, record.catcher
        if arm and arm.valid and arm.held_stack.valid_for_read
            and arm.held_stack.name == BELT then
          flying = flying + arm.held_stack.count
        end
        if box and box.valid then
          flying = flying + box.get_inventory(defines.inventory.chest).get_item_count(BELT)
        end
      end
      assert.are.equal(0, loose, ("%d belts were left on the ground"):format(loose))
      -- and the driver's own pockets, which is where a belt goes if an arm is ever handed
      -- back to a character rather than to the train
      local pocketed = player.get_main_inventory().get_item_count(BELT)
      assert.are.equal(BELTS, built + held + flying + pocketed,
        ("a belt was made or lost: %d built, %d in the wagon, %d in the air, %d in pockets")
          :format(built, held, flying, pocketed))
      assert.is_true(built > 100, ("only %d belts went down"):format(built))
    end, "the run never ended", 1300)
  end)
end)
