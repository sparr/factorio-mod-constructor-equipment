--- Leading from a wearer that is turning.
---
--- An intercept is worked out from the course its owner is on, and a vehicle that steers is
--- on a different course every tick. The lead is re-solved every tick for exactly that
--- reason, but re-solving only says where to aim: the claw still has to swing there, and it
--- swings at its tier's own rotation speed with no way to be turned faster. So the question
--- is whether a wearer can out-turn its own arm.
---
--- Measured, it cannot, and the reason is that the vehicle which turns fastest cannot carry
--- an arm at all. A car has no equipment grid in the base game. What is left is a tank,
--- whose body comes round at 1.26 degrees a tick against a fourth tier claw's 2.88, and a
--- spidertron, whose body does not turn at all -- it walks.
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
        name = { BELT, "tank", "spidertron", "item-on-ground",
                 "constructor-equipment-catcher" } }) do
    if thing.valid then thing.destroy() end
  end
  for _, ghost in ipairs(player.surface.find_entities_filtered{ area = area,
        type = "entity-ghost" }) do
    if ghost.valid then ghost.destroy() end
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
    done(standing, worst, all_told)
  end, "the drive never ended", A_DRIVE + 200)
end

describe("a wearer that steers", function()
  for _, name in ipairs{ "tank", "spidertron" } do
    it("builds while a " .. name .. " holds a straight line", function()
      drive_through(name, false, function(built, lag, all_told)
        assert.is_true(built >= 3,
          ("a %s driving straight through a field built only %d"):format(name, built))
        assert.are.equal(STOCK, all_told, "a belt was made or lost")
      end)
    end)

    --- The case this file exists for. What it asks is only that steering costs nothing:
    --- the same work gets done and nothing goes missing doing it.
    it("builds just as well while a " .. name .. " turns all the way round", function()
      drive_through(name, true, function(built, lag, all_told)
        assert.is_true(built >= 3,
          ("a %s that steers built only %d"):format(name, built))
        assert.are.equal(STOCK, all_told, "a belt was made or lost while steering")
      end)
    end)
  end
end)
