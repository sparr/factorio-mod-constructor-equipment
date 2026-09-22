--- Carrying the engine's arm rather than reading it off the claw.
---
--- The mod cannot ask an inserter where its hand is. held_stack_position is where the claw is
--- *drawn*, and past about two thirds of a turn that is not where the arm is -- see
--- `test/ft/swinging.lua`, which measures the gap. So control.lua carries the two numbers
--- itself, stepping each of them toward whatever end the hand is chasing at the tier's own
--- rate, which is what the engine does.
---
--- This drives a bare inserter through the same sequence of re-aims a walking owner puts one
--- through, runs reach.stepped and reach.turned alongside in exactly the order follow() runs
--- them, and holds the sum to the engine two ways: where the drawing can be trusted the two
--- must agree, and the arrival the sum predicts must be the arrival the engine makes.
---
--- The order is the part that is easy to get wrong and is measured rather than assumed. An
--- inserter updates after the scripts do, so a target written on a tick is the one the engine
--- moves on that same tick, and a hand charged on the tick it is made has taken its first
--- step by the next one. So the step made at the top of tick k is the one the engine made
--- with the target that stood at the end of tick k - 1.
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

--- The engine keeps a position to the nearest two hundred and fifty sixth of a tile an axis,
--- so a radius read back off one is worth about that and no more.
local QUANTUM = 2 / 256

describe("a hand the mod is carrying rather than reading", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  --- Where the claw is asked to be on a given tick: a bearing held for a while and then
  --- thrown to a new one, which is what a claw turning to the next ghost does. Written as a
  --- sum of the tick so that the run is the same every time.
  local HOLD = 24
  local LEGS = { { turn = 0, part = 1.0 }, { turn = 45, part = 0.6 },
                 { turn = 180, part = 1.0 }, { turn = 90, part = 0.5 },
                 { turn = -135, part = 0.9 }, { turn = 30, part = 1.0 } }

  for _, level in ipairs{ 1, 2, 4 } do
    it(("tier %d: the sum keeps up with the engine"):format(level), function()
      local surface = player.surface
      local tier = tiers.by_level[level]
      local base = { x = world.ORIGIN.x + 10.5, y = world.ORIGIN.y + 0.5 }
      local arm = surface.create_entity{ name = tier.inserter, position = base,
        force = player.force, direction = defines.direction.east }
      arm.pickup_position = { base.x + 0.2, base.y }
      arm.energy = arm.prototype.get_max_energy_usage() * 100
      -- Something in the hand for the whole run, so the engine drives it at the drop
      -- throughout and there is one end to follow rather than two.
      arm.held_stack.set_stack{ name = "transport-belt", count = 1 }

      local function spot(leg)
        local angle = math.rad(leg.turn)
        local want = tier.range * leg.part
        return { x = base.x + math.cos(angle) * want, y = base.y - math.sin(angle) * want }
      end

      -- A barred box at each drop, which the engine calls waiting for space in the
      -- destination: the hand goes out to the drop and waits there holding what it has. So
      -- nothing is ever delivered, the engine drives the hand at the drop from the first tick
      -- to the last, and there is one end to follow rather than two.
      local function box(at)
        local made = surface.create_entity{ name = "constructor-equipment-catcher",
          position = { at.x, at.y }, force = player.force }
        made.get_inventory(defines.inventory.chest).set_bar(1)
        return made
      end
      local at = spot(LEGS[1])
      arm.drop_position = { at.x, at.y }
      local catcher = box(at)

      -- The carried state, and what the engine was last told, which is what it moved on.
      local out, pointing = reach.BORN, { x = 1, y = 0 }
      local chased = { x = at.x - base.x, y = at.y - base.y }

      local began = game.tick
      local checked, worst_out, worst_at, arrivals, leg = 0, 0, 0, 0, 1
      world.once(function()
        arm.energy = arm.prototype.get_max_energy_usage() * 100
        local k = game.tick - began
        if k == 0 then return false end

        -- follow(): one step on the target that stood when the engine last moved.
        local turning = reach.turning(pointing, chased, tier.rotation)
        out = reach.stepped(out,
          math.sqrt(chased.x * chased.x + chased.y * chased.y), tier.extension)
        pointing = reach.turned(pointing, chased, tier.rotation)

        -- What the engine actually did, which the sum is held to wherever the drawing can be
        -- trusted: a hand that was not turning is drawn exactly where it is.
        local hand = arm.held_stack_position
        local dx, dy = hand.x - arm.position.x, hand.y - arm.position.y
        local drawn = math.sqrt(dx * dx + dy * dy)
        if not turning then
          checked = checked + 1
          worst_out = math.max(worst_out, math.abs(drawn - out))
          if drawn >= 0.2 then
            worst_at = math.max(worst_at, apart(math.deg(atan2(-dy, dx)) % 360,
              math.deg(atan2(-pointing.y, pointing.x)) % 360))
          end
        end

        -- aim(): a new leg every HOLD ticks, held steady in between so that each turn has
        -- room to finish. Counted off the tick rather than worked out from where the drop
        -- now reads: the engine keeps a position to the nearest two hundred and fifty sixth
        -- of a tile, so a drop read back never quite equals the one that was written.
        local wants = math.floor(k / HOLD) % #LEGS + 1
        if wants ~= leg then
          leg = wants
          local want = spot(LEGS[leg])
          arrivals = arrivals + 1
          catcher.destroy()
          arm.drop_position = { want.x, want.y }
          catcher = box(want)
        end

        -- remember(): what it will be chasing when the engine comes to move it.
        local now = arm.drop_position
        chased = { x = now.x - arm.position.x, y = now.y - arm.position.y }
        return k >= HOLD * #LEGS
      end, function()
        log(("FOLLOW | tier %d | %d legs | held to the engine on %d ticks | worst %.4f tiles"
          .. " and %.3f degrees out, against a quantum of %.4f"):format(level, arrivals,
          checked, worst_out, worst_at, QUANTUM))
        assert.is_true(checked > 20,
          ("only %d ticks were worth checking, which is too few to say anything")
            :format(checked))
        assert.is_true(worst_out <= QUANTUM,
          ("the carried radius was %.4f tiles off what the engine drew"):format(worst_out))
        assert.is_true(worst_at <= 1.0,
          ("the carried bearing was %.3f degrees off what the engine drew"):format(worst_at))
      end, "the run never ended", HOLD * #LEGS + 60)
    end)
  end
end)
