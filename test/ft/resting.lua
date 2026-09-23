--- Where a hand starts and where it stops, asked of the engine rather than assumed.
---
--- Two numbers hold up most of the lead arithmetic and one of the mod's own windows, and
--- both of them were folklore until this file existed.
---
--- The first is reach.BORN, where a freshly built hand sits. It is two 256ths of a tile
--- because prototypes/inserter.lua asks for exactly that -- starting_distance -- and that
--- field is the only thing that moves it: test/ft/intercept.lua already shows six copies of
--- a fourth tier arm with their pickup_position and insert_position moved about all starting
--- in the same place, and what is left over is this one. It is also what control.lua rests
--- an idle claw at, so a rebuilt arm has nowhere to jump to.
---
--- The second is what a hand does at the other end of a swing. control.lua carried the
--- claim that a hand cannot come closer to its own base than where a fresh one is born, and
--- wrote its homecoming window as the gap that left -- reach.BORN - REST. That is not what
--- the engine does. A hand comes to exactly wherever its pickup is put, on every tier, empty
--- or carrying something, at the default birth radius as at nought. There is no floor to
--- hide a rest point behind, which is why RETRACTED is a measured lag now and not a sum.
---
--- The third is why REST is not simply nothing, which the radius alone does not show: a hand
--- reaches a pickup on the arm's own base perfectly well, and takes a long curve round to
--- get there. A pickup on the base is no bearing, so the engine turns the hand back towards
--- the way the arm was built facing while it retracts. One 256th of a tile off it is enough
--- to cure that, and the sweep below is what says so. It only shows on an arm whose hand is
--- somewhere other than its own facing, which is why the last describe builds every arm
--- facing east and drives its hand elsewhere first.
---
--- The mod is left out of it. No equipment is worn, so control.lua has no arms to run; the
--- arms here are built and driven by the fixture out of the tiers' own prototypes.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"
local REPORT = "resting.txt"

local player
local first = true
local function note(line)
  helpers.write_file(REPORT, line .. "\n", not first)
  first = false
end

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  for _, tier in ipairs(tiers.list) do
    for _, arm in ipairs(player.surface.find_entities_filtered{ name = tier.inserter,
          position = world.ORIGIN, radius = 200 }) do
      if arm.valid then arm.destroy() end
    end
  end
  for _, thing in ipairs(player.surface.find_entities_filtered{
        name = "item-on-ground", position = world.ORIGIN, radius = 200 }) do
    if thing.valid then thing.destroy() end
  end
  world.clear(player)
end)

---How far out from its own base the claw is drawn.
local function out_of(arm)
  return reach.distance(arm.position, arm.held_stack_position)
end

--- Read on the tick the arm is built, before the engine has moved it.
describe("a freshly built hand", function()
  --- A whole 256th of grace, which is the grid the engine keeps positions on: a radius off
  --- the cardinals is snapped per axis rather than as a radius, so a diagonal reads a hair
  --- short of what was asked for.
  local GRID = 1 / 256

  for _, tier in ipairs(tiers.list) do
    it("starts on the base of the " .. tier.name .. " arm", function()
      -- Every way round, including a diagonal, because this radius is small enough that the
      -- snapping matters: two 256ths along a diagonal is two components of 0.0055, and what
      -- is being asserted is that neither of them lands back on the base.
      for _, facing in ipairs{ defines.direction.north, defines.direction.east,
                               defines.direction.south, defines.direction.west,
                               defines.direction.northeast } do
        local arm = player.surface.create_entity{ name = tier.inserter,
          position = world.ORIGIN, force = player.force, direction = facing }
        assert.is_not_nil(arm, "the arm was not built")
        local out = out_of(arm)
        assert.is_true(math.abs(out - reach.BORN) <= GRID,
          ("%s facing %d was born %.4f out rather than %.4f")
            :format(tier.name, facing, out, reach.BORN))
        -- On the base to look at, which is the whole point of the number.
        assert.is_true(out < 0.02,
          ("%s facing %d was born %.4f out, which is not on its base")
            :format(tier.name, facing, out))
        arm.destroy()
      end
    end)
  end
end)

--- What the rest point really buys, which is not what control.lua used to say it did.
---
--- Driven by hand: the claw is sent to full stretch, then its pickup and drop are both put
--- at the radius under test and it is left to come in. The closest it gets is what matters
--- as much as where it ends up -- a hand that dips past its rest point and comes back would
--- be a hand that can let go of a load somewhere the mod is not watching.
describe("a hand coming home", function()
  local RADII = { 0, 0.05, 0.1, 0.2, 0.4, 0.6 }

  for _, level in ipairs{ 1, 4 } do
    local tier = tiers.by_level[level]
    for _, loaded in ipairs{ false, true } do
      it(("comes to exactly its pickup on the %s arm, %s")
        :format(tier.name, loaded and "with a belt in the claw" or "empty"), function()
        for _, radius in ipairs(RADII) do
          local arm = player.surface.create_entity{ name = tier.inserter,
            position = world.ORIGIN, force = player.force,
            direction = defines.direction.north }
          assert.is_not_nil(arm, "the arm was not built")
          local born = out_of(arm)
          local far = { arm.position.x, arm.position.y - tier.range }
          local near = { arm.position.x, arm.position.y - radius }
          -- The arm is on no network out here, so it is paid by hand every tick. A loaded
          -- claw lets go when it arrives; it is handed another so the question stays "where
          -- does a carrying hand stop" rather than "where does an empty one".
          local function keep()
            arm.energy = arm.electric_buffer_size
            if loaded and not arm.held_stack.valid_for_read then
              arm.held_stack.set_stack{ name = BELT, count = 1 }
            end
          end
          keep()
          arm.pickup_position, arm.drop_position = far, far
          local began = game.tick
          world.once(function()
            keep()
            return out_of(arm) >= tier.range - 0.05 or game.tick - began > 400
          end, function()
            assert.is_true(out_of(arm) >= tier.range - 0.05,
              ("the %s arm never reached full stretch"):format(tier.name))
            arm.pickup_position, arm.drop_position = near, near
            local settling, closest = game.tick, math.huge
            world.once(function()
              keep()
              local now = out_of(arm)
              if now < closest then closest = now end
              return game.tick - settling > 200
            end, function()
              local final = out_of(arm)
              note(("%-12s %-6s born %.4f pickup %.2f closest %.4f final %.4f")
                :format(tier.name, loaded and "loaded" or "empty", born, radius,
                  closest, final))
              -- To the 256th of a tile the engine keeps positions on, and no nearer: the
              -- claw stops on its pickup rather than folding past it.
              local grid = 1 / 256
              assert.is_true(math.abs(final - radius) <= grid,
                ("%s asked for %.2f rested at %.4f"):format(tier.name, radius, final))
              assert.is_true(closest >= radius - grid,
                ("%s asked for %.2f dipped to %.4f"):format(tier.name, radius, closest))
              arm.destroy()
            end, "the hand never settled", 260)
          end, "the hand never stretched", 460)
        end
      end)
    end
  end
end)

--- Why the rest point is held off the base, which is the thing the radius alone will not
--- show. A hand folding to a pickup on the arm's own base arrives at the base, and gets
--- there the long way round.
---
--- Every arm here is built facing east and its hand then driven somewhere else, because an
--- arm whose hand is already on its own bearing has no turn to make and so shows nothing.
--- That is what hid this the first time it was looked at.
describe("a hand folding to its rest point", function()
  --- Where the hand is driven before it is folded. Not east, which is the way the arms are
  --- built here, and not west either: a half turn takes longer than the stretch does, so a
  --- hand sent due west is still turning when it reaches full stretch and the fold would be
  --- measured from a bearing it was only passing through.
  local WAYS = {
    { name = "north", x = 0, y = -1 },
    { name = "south", x = 0, y = 1 },
    { name = "northwest", x = -0.7071, y = -0.7071 },
  }

  --- The rest points to try, and the whole of the finding is the gap between the first two.
  --- One 256th of a tile is the smallest offset the engine will hold, and it is enough.
  local RESTS = { 0, 1 / 256, reach.BORN, 0.2 }

  for _, level in ipairs{ 1, 4 } do
    local tier = tiers.by_level[level]
    for _, way in ipairs(WAYS) do
      it(("comes in straight on the %s arm from the %s, and curves round only to the base")
        :format(tier.name, way.name), function()
        local worst = {}

        --- One fold, driven end to end, and then whatever is next. Chained rather than
        --- looped: each of these is a run of ticks, and a loop would start the second
        --- before the first had happened.
        local function fold(rest, next_one)
          local arm = player.surface.create_entity{ name = tier.inserter,
            position = world.ORIGIN, force = player.force,
            direction = defines.direction.east }
          assert.is_not_nil(arm, "the arm was not built")
          local base = { x = arm.position.x, y = arm.position.y }
          local out = { base.x + way.x * tier.range, base.y + way.y * tier.range }
          ---How far the hand is off the line it went out along.
          local function aside()
            local at = arm.held_stack_position
            return math.abs((at.x - base.x) * -way.y + (at.y - base.y) * way.x)
          end
          local function keep() arm.energy = arm.electric_buffer_size end
          keep()
          arm.pickup_position, arm.drop_position = out, out
          local began = game.tick
          -- Waited out on the bearing as well as on the radius. The turn outlasts the
          -- stretch on the later tiers -- a fourth tier hand crosses its five tiles in fifty
          -- ticks and turns the 135 degrees to the north west in fifty five -- so a hand at
          -- full stretch is not necessarily a hand that has arrived, and a fold measured
          -- from one is measured from a bearing it was only passing through.
          world.once(function()
            keep()
            return (out_of(arm) >= tier.range - 0.05 and aside() < 0.02)
              or game.tick - began > 400
          end, function()
            assert.is_true(aside() < 0.05,
              ("the hand was still %.3f off its bearing when the fold began"):format(aside()))
            local home = { base.x + way.x * rest, base.y + way.y * rest }
            arm.pickup_position, arm.drop_position = home, home
            local folding, widest = game.tick, 0
            world.once(function()
              keep()
              local off = aside()
              if off > widest then widest = off end
              return game.tick - folding > 240
            end, function()
              worst[rest] = widest
              note(("%-12s from the %-9s folding to %.5f: worst %.4f aside, settled %.4f")
                :format(tier.name, way.name, rest, widest, out_of(arm)))
              arm.destroy()
              next_one()
            end, "the hand never finished folding", 300)
          end, "the hand never stretched", 460)
        end

        --- Each rest point in turn, then what they say together.
        local function next_rest(index)
          if index > #RESTS then
            for _, rest in ipairs(RESTS) do
              if rest == 0 then
                -- A long way round to a pickup on the base, by more than a tile on every arm
                -- and bearing measured. This is the whole of why REST is not nought.
                assert.is_true(worst[rest] > 1,
                  ("folding to the base went only %.3f tiles sideways, so the curve this is"
                    .. " here to pin has gone"):format(worst[rest]))
              else
                -- And straight in to anything at all off it, down to the last 256th.
                assert.is_true(worst[rest] < 0.05,
                  ("folding to %.5f went %.3f tiles sideways"):format(rest, worst[rest]))
              end
            end
            return
          end
          fold(RESTS[index], function() next_rest(index + 1) end)
        end
        next_rest(1)
      end)
    end
  end
end)
