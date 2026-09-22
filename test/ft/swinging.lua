--- What a hand really does while it goes out and round at once, and what the entity says it
--- is doing. They are not the same thing, and the difference is worth a fixture.
---
--- Two answers, and they pull in opposite directions.
---
--- The law of arrival is exactly what reach.on_it assumes. Extension and rotation are two
--- speeds the engine runs at once and neither waits on the other, so a hand told to go
--- somewhere gets there in the greater of the two times. Measured here over three tiers, five
--- bearings and two radii, the engine landed on the tick max() names every time, never later
--- than it and at worst a tick before -- which is its last step covering whatever gap is left
--- rather than creeping up on it.
---
--- The state that law has to be asked of is the part that is wrong. held_stack_position is
--- where the claw is drawn, and past about two thirds of a turn that is not where the engine's
--- arm is: the drawn hand runs ahead of its own state in the radius and in the bearing at
--- once, and comes back to it by the end of the turn. Measured in the model's own terms, which
--- is how far past one step of grace apiece the drawn hand gets:
---
---     turn      radius              bearing
---     up to 120 nothing at all      nothing at all
---     135       0.011 to 0.072      0 to 2.4 degrees
---     150       0.140 to 0.201      2.6 to 5.5 degrees
---     180       0.504 to 0.559      5.8 to 11.3 degrees
---
--- The same on all three tiers, which is what says it is the drawing rather than a speed.
---
--- Which matters because the mod reads the hand's radius and bearing off exactly that
--- position -- see hand_out() and hand_facing() in control.lua. Fed the drawn hand rather
--- than the state, the same arithmetic comes out optimistic: the second describe below
--- re-aims a claw part way through a swing, and where the swing was a half turn the delivery
--- lands as much as twelve ticks after the tick the drawn hand's arithmetic named. Asked of
--- the state itself it is right to the tick.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local atan2 = math.atan2 or math.atan

--- How far apart two bearings are, in degrees, going the short way round.
local function apart(one, other)
  local gap = math.abs(one - other) % 360
  if gap > 180 then gap = 360 - gap end
  return gap
end

--- Where the engine's own two numbers put the hand after k ticks: the radius carried out at
--- the tier's extension speed and the bearing carried round at its rotation speed, each
--- stopping when it arrives and neither waiting on the other.
---@return {x: number, y: number} the hand from the arm's base
---@return number how far out
---@return number how far round, in degrees
local function state_at(tier, turn, want, k)
  local way = want < reach.BORN and -1 or 1
  local out = reach.BORN + way * math.min(math.abs(want - reach.BORN), tier.extension * k)
  local round = math.min(turn, tier.rotation * 360 * k)
  local angle = math.rad(round)
  return { x = out * math.cos(angle), y = -out * math.sin(angle) }, out, round
end

--- How far the drawn hand gets past its own state, in the two numbers the model is written
--- in: tiles of radius and degrees of bearing, each already allowed the one step of grace
--- on_it gives it. Neither the radius nor the bearing creeps up on its target -- the step
--- that arrives covers whatever is left -- so without that step the tick of arrival alone
--- would read as a gap on every swing there is.
---@return number tiles
---@return number degrees
local function past_its_state(tier, turn, want, path)
  local widest, furthest = 0, 0
  for index, hand in ipairs(path) do
    local _, out, round = state_at(tier, turn, want, index - 1)
    local drawn = math.sqrt(hand.x * hand.x + hand.y * hand.y)
    widest = math.max(widest, math.abs(drawn - out) - tier.extension)
    furthest = math.max(furthest,
      apart(math.deg(atan2(-hand.y, hand.x)) % 360, round) - tier.rotation * 360)
  end
  return math.max(0, widest), math.max(0, furthest)
end

describe("a hand going out and round at once", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  --- Drive one bare inserter of a tier's own prototype from its birth radius to a spot, and
  --- hand the flight to `finished` as one entry a tick, from the arm's own base.
  local function flown(tier, turn, want, finished)
    local surface = player.surface
    local base = { x = world.ORIGIN.x + 10.5, y = world.ORIGIN.y + 0.5 }
    -- Born facing east, so the hand starts due east at its birth radius and the whole of the
    -- turn is the bearing asked for.
    local arm = surface.create_entity{ name = tier.inserter, position = base,
      force = player.force, direction = defines.direction.east }
    local angle = math.rad(turn)
    local drop = { x = base.x + math.cos(angle) * want,
                   y = base.y - math.sin(angle) * want }
    arm.pickup_position = { base.x + 0.2, base.y }
    arm.drop_position = { drop.x, drop.y }
    -- Something in the hand, so the engine drives it at the drop rather than the pickup.
    arm.held_stack.set_stack{ name = "transport-belt", count = 1 }
    surface.create_entity{ name = "constructor-equipment-catcher",
      position = { drop.x, drop.y }, force = player.force }

    local began, path = game.tick, {}
    world.once(function()
      arm.energy = arm.prototype.get_max_energy_usage() * 100
      local hand = arm.held_stack_position
      path[#path + 1] = { x = hand.x - arm.position.x, y = hand.y - arm.position.y }
      return game.tick - began > 90 or not arm.held_stack.valid_for_read
    end, function() finished(path) end, "the swing never ended", 200)
  end

  for _, level in ipairs{ 1, 2, 4 } do
    for _, turn in ipairs{ 0, 45, 90, 120, 135, 150, 180 } do
      it(("tier %d, %d degrees round: the drawn hand against the state it is in")
          :format(level, turn), function()
        local tier = tiers.by_level[level]
        local want = tier.range
        flown(tier, turn, want, function(path)
          local widest, furthest = past_its_state(tier, turn, want, path)
          log(("SWING | tier %d | %3d degrees | %d ticks | the drawn hand gets %.4f tiles and"
            .. " %.2f degrees past its own state, over the step of grace each"):format(level,
            turn, #path, widest, furthest))
          if turn <= 120 then
            -- Up to two thirds of a turn the drawn hand is the state, to within the step
            -- that arrives.
            assert.is_true(widest <= 1e-9 and furthest <= 1e-9,
              ("a %d degree turn drew the hand %.4f tiles and %.2f degrees past its own"
                .. " state"):format(turn, widest, furthest))
          elseif turn >= 150 then
            -- Past that it is not, and by far more than the engine's quantum of a two
            -- hundred and fifty sixth of a tile an axis.
            assert.is_true(widest > 0.1 and furthest > 2,
              ("a %d degree turn was expected to draw the hand wide of its own state and did"
                .. " not: %.4f tiles, %.2f degrees"):format(turn, widest, furthest))
          end
          -- 135 degrees is the boundary and is logged rather than asserted: the radius is out
          -- by 0.011 on the fourth tier and 0.072 on the first, which is real but is only a
          -- couple of the engine's own quanta on the tier where it is smallest.
        end)
      end)
    end
  end

  for _, level in ipairs{ 1, 2, 4 } do
    for _, turn in ipairs{ 0, 45, 90, 135, 180 } do
      for _, part in ipairs{ 0.45, 1.0 } do
        it(("tier %d, %d degrees round, %.2f of the reach: arrives on the greater of the"
            .. " stretch and the turn"):format(level, turn, part), function()
          local tier = tiers.by_level[level]
          local want = tier.range * part
          flown(tier, turn, want, function(path)
            local by_out = math.abs(want - reach.BORN) / tier.extension
            local by_turn = (turn / 360) / tier.rotation
            local law = math.max(by_out, by_turn)
            local arrived
            for index, hand in ipairs(path) do
              local out = math.sqrt(hand.x * hand.x + hand.y * hand.y)
              if math.abs(out - want) < 0.01
                  and apart(math.deg(atan2(-hand.y, hand.x)) % 360, turn % 360) < 0.5 then
                arrived = index - 1
                break
              end
            end
            log(("SWING | tier %d | %3d degrees | %.2f of the reach | the law says %.1f (out"
              .. " %.1f, turn %.1f) | arrived %s"):format(level, turn, part, law, by_out,
              by_turn, tostring(arrived)))
            assert.is_not_nil(arrived, "the hand never got there")
            -- Never late, and at worst a tick early, which is the last step again.
            assert.is_true(arrived <= law + 1e-6,
              ("arrived on %d against a law of %.1f"):format(arrived, law))
            assert.is_true(arrived > law - 1.5,
              ("arrived on %d, more than a tick before a law of %.1f"):format(arrived, law))
          end)
        end)
      end
    end
  end
end)

describe("a hand re-aimed part way through a swing", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  -- The two readings the same law can be asked of. One is the hand as the mod reads it --
  -- radius and bearing off held_stack_position, which is what hand_out() and hand_facing()
  -- do. The other is the state the engine is in, which is the birth radius carried out at
  -- the extension speed and the birth bearing carried round at the rotation speed. They
  -- agree while the swing is a right angle or less and part company on anything bigger.
  for _, first in ipairs{ 90, 180 } do
    for _, at in ipairs{ 8, 16 } do
      for _, second in ipairs{ -45, 0, 60 } do
        it(("out for %d, re-aimed on tick %d to %d"):format(first, at, second), function()
          local surface = player.surface
          local tier = tiers.by_level[2]
          local base = { x = world.ORIGIN.x + 10.5, y = world.ORIGIN.y + 0.5 }
          local arm = surface.create_entity{ name = tier.inserter, position = base,
            force = player.force, direction = defines.direction.east }
          local function spot(deg, out)
            local a = math.rad(deg)
            return { x = base.x + math.cos(a) * out, y = base.y - math.sin(a) * out }
          end
          local want = tier.range * 0.8
          local one, two = spot(first, tier.range), spot(second, want)
          arm.pickup_position = { base.x + 0.2, base.y }
          arm.drop_position = { one.x, one.y }
          arm.held_stack.set_stack{ name = "transport-belt", count = 1 }
          local catcher = surface.create_entity{ name = "constructor-equipment-catcher",
            position = { one.x, one.y }, force = player.force }

          local began, drawn, turned, took = game.tick, nil, nil, nil
          world.once(function()
            arm.energy = arm.prototype.get_max_energy_usage() * 100
            local k = game.tick - began
            if k == at then
              local hand = arm.held_stack_position
              local dx, dy = hand.x - arm.position.x, hand.y - arm.position.y
              drawn = { out = math.sqrt(dx * dx + dy * dy),
                        at = math.deg(atan2(-dy, dx)) % 360 }
              catcher.destroy()
              arm.drop_position = { two.x, two.y }
              catcher = surface.create_entity{ name = "constructor-equipment-catcher",
                position = { two.x, two.y }, force = player.force }
              turned = k
            end
            if turned and not took and not arm.held_stack.valid_for_read then
              took = k - turned
            end
            return took ~= nil or k > 160
          end, function()
            local function law(out, bearing)
              return math.max(math.abs(want - out) / tier.extension,
                apart(second % 360, bearing) / (tier.rotation * 360))
            end
            -- The arm has been flying since the tick after it was made, so at tick `at` it
            -- has had `at - 1` steps.
            local _, out, round = state_at(tier, first, tier.range, at - 1)
            local by_drawn, by_state = law(drawn.out, drawn.at), law(out, round)
            log(("REAIM | out for %3d | re-aimed on %2d to %4d | drawn hand %.3f at %6.2f,"
              .. " state %.3f at %6.2f | the drawn hand says %.1f, the state says %.1f |"
              .. " took %s"):format(first, at, second, drawn.out, drawn.at, out, round,
              by_drawn, by_state, tostring(took)))
            assert.is_not_nil(took, "the claw never delivered")
            -- The state's arithmetic is right either way: the delivery lands on the tick it
            -- names, give or take the engine's last step one side and its drop lag the
            -- other.
            assert.is_true(math.abs(took - by_state) <= 1.5,
              ("the state said %.1f and it took %d"):format(by_state, took))
            if first <= 90 then
              -- Up to a right angle the drawn hand is the state, so it says the same thing.
              assert.is_true(math.abs(took - by_drawn) <= 1.5,
                ("the drawn hand said %.1f and it took %d"):format(by_drawn, took))
            end
          end, "the claw never delivered", 220)
        end)
      end
    end
  end
end)
