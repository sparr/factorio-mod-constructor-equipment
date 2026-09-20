--- A dry run of leading a target: send the arm out before the ghost is reachable, along a
--- bearing that travels with its owner, and see whether the claw and the ghost arrive in
--- the same place at the same time.
---
--- This is an experiment rather than a check on the mod. Nothing in control.lua leads a
--- target yet -- work_near only offers what is already inside the reach -- so the arm here
--- is built and driven by the fixture, out of the same tier prototype and by the same
--- arithmetic aim() uses, and control.lua is left out of it entirely: no equipment is worn,
--- so the mod has no arms to run and nothing to disagree with.
---
--- What it measures is the two numbers the feature stands on. How long a hand takes to go
--- from newly built to full stretch, which decides how far in advance an arm has to set
--- off, and how near the claw is to the ghost on the tick the ghost first comes inside the
--- reach, which is whether the lead worked.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local pack = require("lib.pack")
local reach = require("lib.reach")

local TIER = tiers.by_level[4]
local BELT = "transport-belt"

--- Where the arm rests between reaches, from control.lua. The pickup end goes here so that
--- coming home is a retraction rather than a swing.
local REST = 0.2

--- How far up a character an arm is drawn, for one arm. aimed_at() lifts the target by the
--- same amount, so the vector the hand travels is the one measured on the ground.
local LIFT = pack.lift(1, 1)

--- Where the ghost stands, relative to where its owner sets off from.
local GHOST = { x = 10, y = 4.5 }

--- How far along that the ghost first comes inside a five tile reach, worked out rather
--- than looked for: the owner walks the x axis, so the reach is met where the half chord of
--- the circle through the ghost meets it.
local HALF_CHORD = math.sqrt(TIER.range * TIER.range - GHOST.y * GHOST.y)
local ENTERS = GHOST.x - HALF_CHORD

--- The offset the claw is sent to, which is the ghost seen from where its owner will be
--- standing when it comes into reach. Exactly the tier's range long, and constant, so the
--- swing is all extension and no turn.
local LEAD = { x = HALF_CHORD, y = GHOST.y }

--- What the hand has to travel, going by the one figure the repo has measured: a freshly
--- built hand starts seven tenths of a tile out along its own bearing. See
--- prototypes/inserter.lua.
local BORN_AT = 0.7
local PREDICTED = (TIER.range - BORN_AT) / TIER.extension

--- Long enough for any of this to finish and be seen to have finished.
local PATIENCE = 400

local player

--- Everything one run wrote down, so that a trace survives the test that made it.
local lines = {}

local function say(fmt, ...)
  lines[#lines + 1] = string.format(fmt, ...)
end

local function flush(name)
  helpers.write_file(name, table.concat(lines, "\n") .. "\n")
  lines = {}
end

local BORN_TABLE = "intercept-born.txt"
local born_first = true

---One line per tier, so the four can be compared at a glance.
local function record_born(line)
  if born_first then
    helpers.write_file(BORN_TABLE, string.format("%-28s %6s %10s %10s %6s %10s\n",
      "tier", "range", "extension", "born out", "drop", "tiles/tick"), false)
    born_first = false
  end
  helpers.write_file(BORN_TABLE, line .. "\n", true)
end

---Where the arm is drawn and where its hand rests, for a character carrying one arm.
---@param at {x: number, y: number} the character's own position
---@return {x: number, y: number} mount
---@return {x: number, y: number} rest
local function frame(at, bearing)
  local mount = { x = at.x, y = at.y - LIFT }
  return mount, { x = mount.x + bearing.x * REST, y = mount.y + bearing.y * REST }
end

---A unit vector.
local function unit(v)
  local length = math.sqrt(v.x * v.x + v.y * v.y)
  return { x = v.x / length, y = v.y / length }
end

---Build the arm the way point() builds one: facing what it is about to reach for, so that
---there is next to nothing left to turn through.
---@param at {x: number, y: number} the character's position this tick
---@param offset {x: number, y: number} where it is reaching, from the character
---@param tier table? which tier's arm, defaulting to the one the sweep is run on
---@return LuaEntity
local function deploy(at, offset, tier)
  local bearing = unit(offset)
  local mount = frame(at, bearing)
  local arm = player.surface.create_entity{
    name = (tier or TIER).inserter,
    position = mount,
    force = player.force,
    direction = pack.towards(offset.x, offset.y),
  }
  assert.is_not_nil(arm, "the arm was not built")
  return arm
end

---Hold the arm on its owner and pointed at a spot that travels with them, which is all of
---aim() that this experiment needs.
---@param arm LuaEntity
---@param at {x: number, y: number} the character's position this tick
---@param offset {x: number, y: number} where it is reaching, from the character
local function hold(arm, at, offset)
  arm.energy = arm.electric_buffer_size
  local bearing = unit(offset)
  local mount, rest = frame(at, bearing)
  arm.teleport(mount)
  arm.pickup_position = { rest.x, rest.y }
  -- The lift again, on the target end, exactly as aimed_at() applies it.
  arm.drop_position = { at.x + offset.x, at.y + offset.y - LIFT }
  return mount
end

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

after_each(function()
  for _, tier in ipairs(tiers.list) do
    for _, arm in pairs(player.surface.find_entities_filtered{ name = tier.inserter }) do
      arm.destroy()
    end
  end
  player.walking_state = { walking = false }
  world.clear(player)
end)

--- Where a freshly built hand starts, and how long it then takes to go all the way out.
---
--- Both are wanted for every tier rather than the fourth alone, because the search a moving
--- arm has to make is drawn from them: how far its owner will have walked by the time the
--- hand could arrive is the swing, and the swing is the reach less wherever the hand began,
--- over the tier's own extension speed. A birth position guessed from one tier and applied
--- to four would put that search out by a tile.
---
--- Read on the tick the arm is built, before the engine has moved it. Every other reading
--- in this file is a tick later than that and so has a step of extension in it already.
describe("where a freshly built hand starts", function()
  for level, tier in ipairs(tiers.list) do
    it("is the same distance out on the " .. tier.name .. " arm", function()
      -- Out to the side rather than along an axis, so that a hand sitting at its own base
      -- could not be mistaken for one sitting on its bearing.
      local away = { x = tier.range * 0.6, y = tier.range * 0.8 }
      local began = game.tick
      local arm = deploy(player.position, away, tier)
      local mount = frame(player.position, unit(away))
      local born = reach.distance(mount, arm.held_stack_position)
      hold(arm, player.position, away)
      arm.held_stack.set_stack{ name = BELT, count = 1 }

      say("--- tier %d (%s): range %g, extension %g", level, tier.name,
        tier.range, tier.extension)
      say("built facing %d, hand born %.4f out, predicted swing %.2f ticks",
        pack.towards(away.x, away.y), born, (tier.range - born) / tier.extension)

      local dropped
      world.once(function()
        local since = game.tick - began
        local at = player.position
        hold(arm, at, away)
        local out = reach.distance(frame(at, unit(away)), arm.held_stack_position)
        local holding = arm.held_stack.valid_for_read
        say("  t+%3d  out %.4f  holding %s", since, out, tostring(holding))
        if not holding then dropped = since end
        return dropped ~= nil or since > PATIENCE
      end, function()
        say("born %.4f out, let go at t+%s, which is %.4f a tick over %g tiles",
          born, tostring(dropped), dropped and (tier.range - born) / dropped or -1,
          tier.range)
        flush(("intercept-born-%d.txt"):format(level))
        record_born(string.format("%-28s %6.3f %10.4f %10.4f %6s %10.4f",
          tier.name, tier.range, tier.extension, born, tostring(dropped),
          dropped and (tier.range - born) / dropped or -1))
        assert.is_not_nil(dropped, "the claw never finished its reach")
      end, "the claw never finished its reach", PATIENCE)
    end)
  end
end)

describe("how long a fourth tier hand takes to reach full stretch", function()
  --- Three bearings rather than one. The lift is meant to make a swing the same length
  --- whichever way it faces, and the historical failure was that it did not: a claw drawn
  --- up on a back had further to stretch southward than northward. If that is cured, these
  --- three agree, and if it is not, the lead has to know which way it is going.
  local WAYS = {
    { name = "the lead's own bearing", at = { x = HALF_CHORD, y = GHOST.y } },
    { name = "due north", at = { x = 0, y = -TIER.range } },
    { name = "due south", at = { x = 0, y = TIER.range } },
  }

  for _, way in ipairs(WAYS) do
    it("extends " .. way.name .. " in about " .. math.floor(PREDICTED) .. " ticks", function()
      local began = game.tick
      local arm = deploy(player.position, way.at)
      local mount = hold(arm, player.position, way.at)
      arm.held_stack.set_stack{ name = BELT, count = 1 }

      say("--- standing still, %s, offset (%.4f, %.4f), length %.4f",
        way.name, way.at.x, way.at.y, reach.distance({ x = 0, y = 0 }, way.at))
      say("built facing %d of %d, predicted %.2f ticks",
        pack.towards(way.at.x, way.at.y), pack.DIRECTIONS, PREDICTED)

      local previous, full, dropped
      world.once(function()
        local since = game.tick - began
        mount = hold(arm, player.position, way.at)
        local hand = arm.held_stack_position
        local out = reach.distance(mount, hand)
        local step = previous and (out - previous) or 0
        previous = out
        local holding = arm.held_stack.valid_for_read
        say("  t+%3d  out %.4f  step %.4f  holding %s", since, out, step, tostring(holding))
        if not full and out >= TIER.range - 0.001 then full = since end
        if not dropped and not holding then dropped = since end
        return (dropped ~= nil) or since > PATIENCE
      end, function()
        say("full stretch at t+%s, let go at t+%s, predicted %.2f",
          tostring(full), tostring(dropped), PREDICTED)
        local landed = player.surface.find_entities_filtered{ name = "item-on-ground" }
        for _, item in ipairs(landed) do
          say("  landed at (%.4f, %.4f), wanted (%.4f, %.4f)",
            item.position.x, item.position.y,
            player.position.x + way.at.x, player.position.y + way.at.y - LIFT)
        end
        flush("intercept-still-" .. pack.towards(way.at.x, way.at.y) .. ".txt")
        assert.is_not_nil(dropped, "the claw never let go of what it was carrying")
      end, "the claw never finished its reach", PATIENCE)
    end)
  end
end)



--- Where the ghost stands, relative to where its owner sets off from, across a spread of
--- placements. What varies is how far to the side it is, which is the whole of what decides
--- the shape of the problem: a ghost on the line of march is passed slowly through a ten
--- tile window, and one out at almost the full five tiles is clipped by a corner of the
--- reach for a tick or two.
---
--- Far enough ahead that every one of them has more warning than a swing costs. Where there
--- is not enough warning the earliest intersection cannot be met at all and the lead has to
--- be worked out some other way, which is a separate question and not this one.
local PLACEMENTS = {
  { name = "dead ahead",            at = { x = 20, y = 0 } },
  { name = "two tiles off",         at = { x = 20, y = 2 } },
  { name = "three and a half off",  at = { x = 20, y = 3.5 } },
  { name = "four and a half off",   at = { x = 20, y = 4.5 } },
  { name = "four point nine off",   at = { x = 20, y = 4.9 } },
  { name = "clipped at the corner", at = { x = 20, y = 4.999 } },
  { name = "the same to the north", at = { x = 20, y = -4.5 } },
  { name = "nearer, half a minute", at = { x = 10, y = 4.5 } },
}

--- The engine lets go against the drop position it was given on the tick before, not this
--- tick's, so a claw aimed at where the ghost will be when the hand arrives puts its load
--- down one tick of walking short of it. Everything a lead is worked out from is therefore
--- a tick earlier than the arrival.
local DROP_LAG = 1

--- How many ticks of its owner's walking a lead has to allow for: the swing, less the tick
--- the drop lags by.
local ALLOWED = PREDICTED - DROP_LAG

---Where the ghost will be, seen from the arm, after so many ticks of the owner's present
---course. Drift is measured rather than assumed, which is the whole of why it is passed in:
---a character's speed goes with the tile they are on and with whatever is stuck to them,
---and none of that is a number this can look up.
---@param at {x: number, y: number} where the arm reaches from now
---@param ghost {x: number, y: number}
---@param drift {x: number, y: number} how far its owner went last tick
---@param ticks number
---@return {x: number, y: number}
local function offset_after(at, ghost, drift, ticks)
  return { x = ghost.x - (at.x + drift.x * ticks), y = ghost.y - (at.y + drift.y * ticks) }
end

--- How long after the ghost comes into reach the claw is aimed to arrive. One, because the
--- engine lets go against the aim it was given a tick earlier, so the handover needs a tick
--- to have happened in.
local MARGIN = 1

---How long a hand takes to travel a given distance out, going by the tier's own numbers and
---by where a freshly built hand starts.
---@param length number
---@return number ticks
local function swing_for(length)
  return (length - BORN_AT) / TIER.extension
end

---How many ticks until the ghost is inside the reach, on the owner's present course.
---
---Nought if it is already. Nothing at all if the course never brings it inside, which is a
---ghost being walked away from and no business of any arm's.
---@param at {x: number, y: number}
---@param ghost {x: number, y: number}
---@param drift {x: number, y: number}
---@return number? the first tick it is inside the reach
---@return number? the last tick it is still inside the reach
local function ticks_until_reachable(at, ghost, drift)
  local first
  for n = 0, 600 do
    local away = reach.distance({ x = at.x + drift.x * n, y = at.y + drift.y * n }, ghost)
    if away <= TIER.range then
      if not first then first = n end
    elseif first then
      return first, n - 1
    end
  end
  return first, first and 600 or nil
end

---When to aim for, given how long the ghost will be inside the reach.
---
---A tick after it comes in, or the last tick it is still there, whichever is sooner. The
---margin is what the handover needs to have happened in, and a ghost that is only clipped
---by the corner of the reach has not got a tick to spare: it is that tick or nothing.
---@param wait number? from ticks_until_reachable
---@param last number?
---@return number? which tick to arrive on
local function arrive_on(wait, last)
  if not wait then return nil end
  return math.min(wait + MARGIN, last or wait)
end

--- Three ways of deciding where to send the claw, run over the same placements so the
--- difference between them is the only thing that varies.
---
--- Each one answers two questions. Whether the arm may set off yet, and where to hold the
--- drop end once it has.
local STRATEGIES = {
  {
    key = "entry",
    name = "aimed at the earliest intersection",
    --- The first thing tried: aim where the ghost will be at the moment it first comes
    --- inside the reach, and set off a swing's length before that moment. Its fault is
    --- the drop lag, which puts the load down a tick short of where the claw is.
    ready = function(at, ghost, drift, entry)
      local to_go = drift.x > 0 and (entry.x - at.x) / drift.x or math.huge
      return to_go <= PREDICTED
    end,
    lead = function(at, ghost, drift, entry)
      return { x = ghost.x - entry.x, y = ghost.y - entry.y }
    end,
    hold = function(fixed) return fixed end,
  },
  {
    key = "ahead",
    name = "aimed a tick ahead of the arrival",
    --- The same, one tick earlier in the owner's course: the claw is sent where the ghost
    --- will be seen from a tick before the hand arrives, which is the aim the engine will
    --- actually let go against. It needs no entry point of its own -- the moment such an
    --- aim is inside the reach is the moment to set off, and that moment is the earliest
    --- intersection.
    ready = function(at, ghost, drift)
      return reach.distance({ x = 0, y = 0 }, offset_after(at, ghost, drift, ALLOWED))
        <= TIER.range
    end,
    lead = function(at, ghost, drift)
      return offset_after(at, ghost, drift, ALLOWED)
    end,
    hold = function(fixed) return fixed end,
  },
  {
    key = "late",
    name = "aimed to arrive a tick late, then handed over",
    --- A lead is only ever needed while the ghost is out of reach. The moment it is inside,
    --- where it is beats any guess about where it will be, so the claw is aimed at the thing
    --- itself and the lead is forgotten.
    ---
    --- Which only helps if the handover happens before the hand arrives, because the engine
    --- lets go against the aim it was given a tick earlier. Landing exactly on the moment
    --- the ghost comes into reach is therefore a tick too early: the aim it lets go against
    --- is still the lead. So the arm is aimed to arrive a tick after that moment instead,
    --- and the tick it spends waiting is what the load is delivered against.
    ---
    --- Late is the safe side of this and early is not. A claw that arrives late is aimed at
    --- the ghost itself by then and simply finishes its stretch; one that arrives early lets
    --- go at the lead, which is wherever the ghost was going to be and not where it is.
    ready = function(at, ghost, drift)
      local arrival = arrive_on(ticks_until_reachable(at, ghost, drift))
      if not arrival then return false end
      local lead = offset_after(at, ghost, drift, arrival)
      local length = reach.distance({ x = 0, y = 0 }, lead)
      if length > TIER.range then return false end
      -- How long the hand would take to travel that far, against how long there is.
      return swing_for(length) >= arrival
    end,
    lead = function(at, ghost, drift)
      return offset_after(at, ghost, drift,
        arrive_on(ticks_until_reachable(at, ghost, drift)))
    end,
    hold = function(fixed, at, ghost, in_range)
      if not in_range then return fixed end
      return { x = ghost.x - at.x, y = ghost.y - at.y }
    end,
  },
}

local SUMMARY = "intercept-summary.txt"
local first_row = true

---One line per run, so the shape of the whole sweep is on one page.
local function record(line)
  helpers.write_file(SUMMARY, line .. "\n", not first_row)
  first_row = false
end

for _, strategy in ipairs(STRATEGIES) do
  describe("an arm " .. strategy.name, function()
    for index, placement in ipairs(PLACEMENTS) do
      local ghost_at = placement.at
      local half = math.sqrt(TIER.range * TIER.range - ghost_at.y * ghost_at.y)

      it("meets a ghost " .. placement.name, function()
        if first_row then
          record(string.format("%-34s %-22s %5s %5s %5s %5s %5s %8s %8s",
            "strategy", "placement", "set", "drop", "entry", "swing", "early",
            "miss", "landed"))
        end

        local start = { x = player.position.x, y = player.position.y }
        local ghost = { x = start.x + ghost_at.x, y = start.y + ghost_at.y }
        --- Where its owner stands at the earliest moment the ghost is inside the reach,
        --- which only the entry strategy is told.
        local entry = { x = start.x + ghost_at.x - half, y = start.y }

        lines = {}
        say("--- %s: %s, ghost at (%.4f, %.4f)", strategy.name, placement.name,
          ghost_at.x, ghost_at.y)
        say("enters the reach at x %+.4f, window %.4f tiles wide, predicted swing %.2f ticks",
          ghost_at.x - half, 2 * half, PREDICTED)

        local began = game.tick
        local arm, fixed, deployed, dropped, entered, left
        local previous, drift = nil, { x = 0, y = 0 }
        local drop_miss, landed, facing

        world.once(function()
          local since = game.tick - began
          player.walking_state = { walking = true, direction = defines.direction.east }
          local at = { x = player.position.x, y = player.position.y }
          drift = previous and { x = at.x - previous.x, y = at.y - previous.y }
            or { x = 0, y = 0 }
          previous = at

          local range = reach.distance(at, ghost)
          local in_range = range <= TIER.range
          if in_range and not entered then
            entered = since
            say("in reach from t+%d, x %+.4f", since, at.x - start.x)
          end
          if entered and not left and not in_range then
            left = since
            say("out of reach again at t+%d", since)
          end

          if not arm and drift.x > 0 and strategy.ready(at, ghost, drift, entry) then
            fixed = strategy.lead(at, ghost, drift, entry)
            facing = pack.towards(fixed.x, fixed.y)
            arm = deploy(at, fixed)
            hold(arm, at, fixed)
            arm.held_stack.set_stack{ name = BELT, count = 1 }
            deployed = since
            say("set off at t+%d, x %+.4f, drift %.7f/tick, lead (%.6f, %.6f) length %.6f",
              since, at.x - start.x, drift.x, fixed.x, fixed.y,
              reach.distance({ x = 0, y = 0 }, fixed))
          end

          if arm then
            local aim = strategy.hold(fixed, at, ghost, in_range)
            local mount = hold(arm, at, aim)
            local hand = arm.held_stack_position
            local out = reach.distance(mount, hand)
            local miss = reach.distance(hand, { x = ghost.x, y = ghost.y - LIFT })
            local holding = arm.held_stack.valid_for_read
            say("  t+%3d  x %+.4f  out %.4f  range %.4f  miss %.4f  holding %s",
              since, at.x - start.x, out, range, miss, tostring(holding))
            if not dropped and not holding then
              dropped = since
              drop_miss = miss
              say("let go at t+%d, the claw %.4f from the ghost", since, miss)
            end
          else
            say("  t+%3d  x %+.4f  range %.4f  waiting", since, at.x - start.x, range)
          end

          return (dropped ~= nil and entered ~= nil) or since > PATIENCE
        end, function()
          player.walking_state = { walking = false }
          for _, item in ipairs(player.surface.find_entities_filtered{
                name = "item-on-ground", position = ghost, radius = 25 }) do
            -- The lift taken back off, since a claw holding something over a tile is drawn
            -- a lift to the north of it and the load lands where it is drawn.
            landed = reach.distance(
              { x = item.position.x, y = item.position.y + LIFT }, ghost)
          end
          say("set off t+%s, let go t+%s, in reach from t+%s", tostring(deployed),
            tostring(dropped), tostring(entered))
          say("the load landed %.4f from the ghost", landed or -1)
          flush(("intercept-%s-%d.txt"):format(strategy.key, index))
          record(string.format("%-34s %-22s %5s %5s %5s %5d %5d %8.4f %8.4f",
            strategy.name, placement.name, tostring(deployed), tostring(dropped),
            tostring(entered), (deployed and dropped) and (dropped - deployed) or 0,
            (dropped and entered) and (entered - dropped) or 0,
            drop_miss or -1, landed or -1))
          assert.is_not_nil(deployed, "the arm was never sent")
          assert.is_not_nil(entered, "the ghost never came into reach")
          assert.is_not_nil(landed, "nothing was ever put down")
        end, "the run never finished", PATIENCE)
      end)
    end
  end)
end

--- What the search actually brings back, now that it is drawn round where its owner is
--- going rather than round where they stand.
---
--- The circle is arithmetic and is pinned in test/spec/reach_spec.lua, exhaustively: every
--- bearing of every tick of a flight is checked to fall inside it. What cannot be checked
--- there is that control.lua hands that circle to the engine -- the right middle, the right
--- radius, and the same pair to all four of the searches it makes. So this asks the real
--- find_entities_filtered, on real ground, for real ghosts.
---
--- A synthetic list of arms rather than a mustered one, because work_near() reads nothing
--- off a record but its tier, and a bare level says which tier without an armour, a grid, a
--- battery or a claw having to exist to say it.
describe("the ground a walking owner searches", function()
  local FOURTH = { { level = 4 } }
  --- A character's own walk, measured: the engine advances them 38/256 of a tile a tick and
  --- throws the remainder away, rather than the 0.15 the prototype says.
  local WALKING = { x = 0.1484375, y = 0 }
  local STILL = { x = 0, y = 0 }
  local BELT = "transport-belt"

  ---Whether a search brought a particular ghost back.
  local function found(list, drift, ghost)
    for _, work in ipairs(work_near(player.character, list, drift)) do
      if work == ghost then return true end
    end
    return false
  end

  it("reaches past the arm, to what the hand could meet on the way", function()
    -- Seven tiles: past a fourth tier arm's five, and inside the eight and a fifth the
    -- circle covers once its owner is walking towards it.
    local ahead = world.ghost(player, BELT, 7, 0)
    assert.is_true(found(FOURTH, WALKING, ahead),
      "a ghost the hand would meet halfway was not searched for")
  end)

  it("leaves it alone while its owner stands still", function()
    local ahead = world.ghost(player, BELT, 7, 0)
    assert.is_false(found(FOURTH, STILL, ahead),
      "a ghost out of reach of somebody going nowhere was searched for anyway")
  end)

  it("still holds everything already in reach behind them", function()
    -- The back edge sits at exactly the reach, which is the whole of what the old search
    -- was: walking forward must not drop anything that was in reach standing still.
    local behind = world.ghost(player, BELT, -5, 0)
    assert.is_true(found(FOURTH, WALKING, behind),
      "walking east lost a ghost five tiles west, which is in reach either way")
  end)

  it("stops somewhere, rather than searching the whole surface", function()
    local far = world.ghost(player, BELT, 13, 0)
    assert.is_false(found(FOURTH, WALKING, far),
      "a ghost well past anything the hand could meet was searched for")
  end)

  --- The three searches beyond the ghost one -- deconstruction orders, cliffs and upgrade
  --- orders -- take the same middle and radius, and have been left behind by a change to
  --- this one before.
  it("carries things marked for taking up along with it", function()
    local marked = player.surface.create_entity{
      name = "iron-chest", position = { world.ORIGIN.x + 7, world.ORIGIN.y },
      force = player.force }
    marked.order_deconstruction(player.force)
    assert.is_true(found(FOURTH, WALKING, marked),
      "a chest marked for taking up, seven tiles ahead, was not searched for")
    marked.destroy()
  end)

  --- What the circle is drawn from is the tier, not a constant. Not simply the reach
  --- either: how long the hand is out counts for as much as how far it goes, and the two
  --- do not go together. A first tier arm reaches two tiles and is out for 37 ticks, which
  --- carries its owner 5.54 tiles, so it searches 7.54 tiles ahead -- nearly four times its
  --- own reach, and further ahead than a third tier arm would if that arm were slower.
  it("draws each tier its own circle, out of the reach and the swing together", function()
    local ahead = world.ghost(player, BELT, 9, 0)
    assert.is_true(found({ { level = 4 } }, WALKING, ahead),
      "the fourth tier searches 11.4 tiles ahead and should have found it")
    assert.is_false(found({ { level = 1 } }, WALKING, ahead),
      "the first tier searches 7.5 tiles ahead and should not have")
  end)
end)

--- What the engine charges for each shape of search, on real ground.
---
--- Two questions worth answering with a clock rather than an argument. A circle and a box
--- that both hold the cone are not the same size, and which is smaller depends on which way
--- its owner is going. And asking for both and keeping what is in both would be tighter
--- still, but costs a second search to save work that the arithmetic in lib/reach.lua can
--- do exactly, on one search, for nothing.
---
--- Sized so the whole thing is a second or so. It asserts nothing about the clock -- a
--- timing that fails the suite on a busy machine is worse than no timing -- and writes what
--- it saw to script-output for reading.
--- Whether to run the benchmarks in this file.
---
--- Off by default. The two describes they gate lay a field of several thousand ghosts and
--- then make the same search fifteen hundred times over, which is several seconds on every
--- run of the whole suite, and they assert nothing about the clock -- deliberately, since a
--- timing that fails on a busy machine is worse than no timing at all. What they are for is
--- a number to read, and a number is only worth reading when somebody is looking.
---
--- Flip this to true and run them by name. Wait for the machine to be quiet first: the
--- shapes are timed one after another in a single run, so load moves all of them together,
--- but the ratios are only worth quoting off an idle machine.
local BENCHMARKS = false
local benchmark = BENCHMARKS and describe or describe.skip

benchmark("what each shape of search costs", function()
  local TIER = tiers.by_level[4]
  local WALKING = { x = 0.1484375, y = 0 }
  local HORIZON = reach.full_swing(TIER)
  local ROUNDS = 600

  --- Dense enough to stand in for a blueprint being walked along, and wide enough to hold
  --- the largest of the shapes with room to spare.
  local FIELD = 22
  local REPORT = "search-shapes.txt"

  local function lay_a_field()
    local made = 0
    for dx = -FIELD, FIELD do
      for dy = -FIELD, FIELD do
        local ghost = player.surface.create_entity{
          name = "entity-ghost", inner_name = "transport-belt",
          position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
          force = player.force,
        }
        if ghost then made = made + 1 end
      end
    end
    return made
  end

  it("is cheaper one way for a circle and the other way for a box", function()
    local laid = lay_a_field()
    local at = player.position
    helpers.write_file(REPORT,
      ("a field of %d ghosts, %d rounds of each shape\n"):format(laid, ROUNDS), false)

    -- Everything below holds the cone of a fourth tier arm on a character walking east.
    local travel = { x = WALKING.x * HORIZON, y = WALKING.y * HORIZON }
    local span = reach.distance({ x = 0, y = 0 }, travel)
    -- what work_near searches today: the circle that also holds an arm at full stretch
    local wide = TIER.range + span / 2
    local wide_at = { x = at.x + travel.x / 2, y = at.y + travel.y / 2 }
    -- the smallest circle round the cone alone
    local tight = (span + reach.BORN + TIER.range) / 2
    local tight_at = { x = at.x + travel.x * (tight - reach.BORN) / span,
                       y = at.y + travel.y * (tight - reach.BORN) / span }
    -- and the smallest box round the cone alone
    local box = {
      { math.min(at.x - reach.BORN, at.x + travel.x - TIER.range),
        math.min(at.y - reach.BORN, at.y + travel.y - TIER.range) },
      { math.max(at.x + reach.BORN, at.x + travel.x + TIER.range),
        math.max(at.y + reach.BORN, at.y + travel.y + TIER.range) },
    }
    local arm = { range = TIER.range, extension = TIER.extension }

    local slant = { x = WALKING.x / math.sqrt(2), y = WALKING.x / math.sqrt(2) }
    local slant_travel = { x = slant.x * HORIZON, y = slant.y * HORIZON }
    local diagonal_at = {
      x = at.x + slant_travel.x * (tight - reach.BORN) / span,
      y = at.y + slant_travel.y * (tight - reach.BORN) / span }
    local diagonal_box = {
      { math.min(at.x - reach.BORN, at.x + slant_travel.x - TIER.range),
        math.min(at.y - reach.BORN, at.y + slant_travel.y - TIER.range) },
      { math.max(at.x + reach.BORN, at.x + slant_travel.x + TIER.range),
        math.max(at.y + reach.BORN, at.y + slant_travel.y + TIER.range) },
    }

    local surface = player.surface
    local function circle(middle, radius)
      return surface.find_entities_filtered{
        position = middle, radius = radius, type = "entity-ghost" }
    end

    local shapes = {
      { name = "circle, as searched now", radius = wide, run = function()
          return circle(wide_at, wide)
        end },
      { name = "circle round the cone", radius = tight, run = function()
          return circle(tight_at, tight)
        end },
      { name = "box round the cone", run = function()
          return surface.find_entities_filtered{ area = box, type = "entity-ghost" }
        end },
      -- The same pair again with its owner going north east, where the cone lies across
      -- the box's corner rather than along its side and the two swap places on paper.
      { name = "circle round the cone, diagonal", run = function()
          return circle(diagonal_at, tight)
        end },
      { name = "box round the cone, diagonal", run = function()
          return surface.find_entities_filtered{ area = diagonal_box, type = "entity-ghost" }
        end },
      { name = "both, and what is in both", run = function()
          local by_box = {}
          for _, work in ipairs(surface.find_entities_filtered{
                area = box, type = "entity-ghost" }) do
            by_box[work.unit_number or 0] = true
          end
          local kept = {}
          for _, work in ipairs(circle(tight_at, tight)) do
            if by_box[work.unit_number or 0] then kept[#kept + 1] = work end
          end
          return kept
        end },
      { name = "circle, each position read", run = function()
          -- Reading nothing but where each one is, so that what the engine charges for the
          -- search can be told apart from what Lua charges for touching what came back.
          local kept = {}
          for _, work in ipairs(circle(tight_at, tight)) do
            local spot = work.position
            if spot.x ~= math.huge then kept[#kept + 1] = work end
          end
          return kept
        end },
      { name = "all four filters, tight circle", run = function()
          -- What work_near would cost drawn round the cone instead: the same four searches
          -- it makes now, at the smaller radius.
          local found = surface.find_entities_filtered{
            position = tight_at, radius = tight, type = "entity-ghost" }
          for _, other in ipairs{
                { position = tight_at, radius = tight, to_be_deconstructed = true },
                { position = tight_at, radius = tight, type = "cliff",
                  to_be_deconstructed = true },
                { position = tight_at, radius = tight, to_be_upgraded = true } } do
            for _, work in ipairs(surface.find_entities_filtered(other)) do
              found[#found + 1] = work
            end
          end
          return found
        end },
      { name = "work_near as it stands", run = function()
          return work_near(player.character, { { level = 4 } }, WALKING)
        end },
      { name = "circle round the cone, sifted", run = function()
          local kept = {}
          for _, work in ipairs(circle(tight_at, tight)) do
            local spot = work.position
            if reach.meets(arm, WALKING,
                  { x = spot.x - at.x, y = spot.y - at.y }, HORIZON) then
              kept[#kept + 1] = work
            end
          end
          return kept
        end },
    }

    for _, shape in ipairs(shapes) do
      -- Once outside the clock, so that whatever the first call warms is warm for all of
      -- them and the count is read without the reading being timed.
      local kept = #shape.run()
      local clock = helpers.create_profiler()
      for _ = 1, ROUNDS do shape.run() end
      clock.stop()
      clock.divide(ROUNDS)
      -- Written as it goes rather than gathered up and written at the end. A localised
      -- string takes twenty parameters and no more, and a report built as one long list
      -- quietly stopped being written the moment a tenth shape pushed it over -- leaving
      -- the previous run's file sitting there looking like a fresh result.
      helpers.write_file(REPORT,
        { "", ("  %-32s %5d kept   "):format(shape.name, kept), clock, "\n" }, true)
    end

    for _, ghost in ipairs(player.surface.find_entities_filtered{
          type = "entity-ghost", position = world.ORIGIN, radius = FIELD * 2 }) do
      ghost.destroy()
    end
    assert.is_true(laid > 1000, "the field was not laid")
  end)
end)

--- The same clock, on a cone long enough for the shape of the search to matter.
---
--- A car covers 23 tiles while a fourth tier hand stretches five, so its cone is a ten
--- degree needle 28 tiles long, and one circle round that is mostly the ground either side
--- of it. Three questions: whether a chain of circles laid along the needle beats the one
--- circle round it, whether the array spelling of a position is cheaper to hand the engine
--- than the keyed one, and whether the cone test is worth what it costs once it stops
--- allocating a table for every candidate it is asked about.
benchmark("searching a long thin cone", function()
  local TIER = tiers.by_level[4]
  local HORIZON = reach.full_swing(TIER)
  local ARM = { range = TIER.range, extension = TIER.extension }
  --- Measured by driving one flat out. A character manages 0.1484375.
  local CAR = { x = 0.5351563, y = 0 }
  local ROUNDS = 1500
  --- Wide enough to hold the far tip of a car's cone, which is 28 tiles ahead.
  local FIELD = 34
  local REPORT = "search-chain.txt"

  local function lay_a_field()
    local made = 0
    for dx = -FIELD, FIELD do
      for dy = -FIELD, FIELD do
        if player.surface.create_entity{
              name = "entity-ghost", inner_name = "transport-belt",
              position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy },
              force = player.force } then
          made = made + 1
        end
      end
    end
    return made
  end

  local function clear_the_field()
    for _, ghost in ipairs(player.surface.find_entities_filtered{
          type = "entity-ghost", position = world.ORIGIN, radius = FIELD * 2 }) do
      ghost.destroy()
    end
  end

  ---Time a shape, and say how much it brought back and how much of that was doubled up.
  local function time(name, run)
    local got = run()
    local seen, unique = {}, 0
    for _, work in ipairs(got) do
      local id = work.unit_number or 0
      if not seen[id] then seen[id] = true; unique = unique + 1 end
    end
    local clock = helpers.create_profiler()
    for _ = 1, ROUNDS do run() end
    clock.stop()
    clock.divide(ROUNDS)
    helpers.write_file(REPORT,
      { "", ("  %-34s %5d kept %5d twice  "):format(name, unique, #got - unique), clock,
        "\n" }, true)
  end

  it("is cheaper as a chain of circles than as one circle round the lot", function()
    local laid = lay_a_field()
    local at = player.position
    local surface = player.surface
    helpers.write_file(REPORT,
      ("a field of %d ghosts, a car's cone, %d rounds of each shape\n"):format(laid, ROUNDS),
      false)

    local span = reach.distance({ x = 0, y = 0 }, { x = CAR.x * HORIZON, y = CAR.y * HORIZON })
    local wide = TIER.range + span / 2
    time("capsule circle, as searched now", function()
      return surface.find_entities_filtered{
        position = { at.x + CAR.x * HORIZON / 2, at.y }, radius = wide, type = "entity-ghost" }
    end)

    for _, pieces in ipairs{ 1, 2, 3, 4, 6, 8 } do
      local ring = reach.chain(ARM, CAR, HORIZON, pieces)
      time(("%d circle%s along the cone"):format(pieces, pieces > 1 and "s" or ""),
        function()
          local found = surface.find_entities_filtered{
            position = { at.x + ring[1].at.x, at.y + ring[1].at.y },
            radius = ring[1].radius, type = "entity-ghost" }
          for index = 2, #ring do
            for _, work in ipairs(surface.find_entities_filtered{
                  position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
                  radius = ring[index].radius, type = "entity-ghost" }) do
              found[#found + 1] = work
            end
          end
          return found
        end)
    end

    -- The same chain, but stopping early. Its pieces are laid in the order the hand could
    -- get to them, so the first of them is both the nearest ground and the soonest -- which
    -- is the ground an arm takes work from when there is any. Searching that alone and only
    -- going further when an arm came away empty is worth whatever the later pieces cost,
    -- however often the first one is enough.
    for _, upto in ipairs{ 1, 2, 3 } do
      local ring = reach.chain(ARM, CAR, HORIZON, 3)
      time(("the first %d of 3 circles"):format(upto), function()
        local found = surface.find_entities_filtered{
          position = { at.x + ring[1].at.x, at.y + ring[1].at.y },
          radius = ring[1].radius, type = "entity-ghost" }
        for index = 2, upto do
          for _, work in ipairs(surface.find_entities_filtered{
                position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
                radius = ring[index].radius, type = "entity-ghost" }) do
            found[#found + 1] = work
          end
        end
        return found
      end)
    end

    -- What a miss costs, which is the whole of whether staging is worth anything.
    --
    -- Searching is only half of it. Something downstream looks at every candidate that comes
    -- back, and that costs more per candidate than the engine charges to find it, so what
    -- decides a miss is how many candidates get looked at rather than how much ground gets
    -- searched. The arithmetic below stands in for whatever does the looking; choose() does
    -- a great deal more per candidate than this, so the gap between the two is understated.
    --
    -- An arm that came away empty from a stage has already turned down everything in it, so
    -- the next stage only has to offer it the ground it has not seen. Handing over the whole
    -- prefix again instead is the easy mistake, and it is not a small one.
    do
      local ring = reach.chain(ARM, CAR, HORIZON, 3)
      local out, e, range = reach.BORN, ARM.extension, ARM.range
      local growing = math.min(HORIZON, (range - out) / e)
      local speed2 = CAR.x * CAR.x + CAR.y * CAR.y
      local function sift(found, into)
        for _, work in ipairs(found) do
          local spot = work.position
          local wx, wy = spot.x - at.x, spot.y - at.y
          local a = speed2 - e * e
          local b = -2 * (wx * CAR.x + wy * CAR.y + out * e)
          local c = wx * wx + wy * wy - out * out
          local least = math.min(c, a * growing * growing + b * growing + c)
          if a > 0 then
            local turn = -b / (2 * a)
            if turn > 0 and turn < growing then
              least = math.min(least, a * turn * turn + b * turn + c)
            end
          end
          if least <= 0 then into[#into + 1] = work end
        end
        return into
      end
      local function circle_of(index)
        return surface.find_entities_filtered{
          position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
          radius = ring[index].radius, type = "entity-ghost" }
      end

      time("a miss, only the new ground looked at", function()
        local kept = sift(circle_of(1), {})
        -- the arm came away empty, so on to the next piece, and only the next piece
        return sift(circle_of(2), kept)
      end)
      time("a miss, the whole prefix looked at again", function()
        sift(circle_of(1), {})
        -- the easy mistake: ask again for everything up to here and look at all of it
        local kept = sift(circle_of(1), {})
        return sift(circle_of(2), kept)
      end)
      time("a hit on the first piece", function()
        return sift(circle_of(1), {})
      end)
    end

    -- And the same again for a walking character, whose cone is stubby rather than long,
    -- to see whether the piece count is a constant or something a wearer's speed decides.
    local WALKING = { x = 0.1484375, y = 0 }
    for _, upto in ipairs{ 1, 2 } do
      local ring = reach.chain(ARM, WALKING, HORIZON, 2)
      time(("walking, the first %d of 2 circles"):format(upto), function()
        local found = surface.find_entities_filtered{
          position = { at.x + ring[1].at.x, at.y + ring[1].at.y },
          radius = ring[1].radius, type = "entity-ghost" }
        for index = 2, upto do
          for _, work in ipairs(surface.find_entities_filtered{
                position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
                radius = ring[index].radius, type = "entity-ghost" }) do
            found[#found + 1] = work
          end
        end
        return found
      end)
    end
    for _, pieces in ipairs{ 1, 2, 3 } do
      local ring = reach.chain(ARM, WALKING, HORIZON, pieces)
      time(("%d circle%s, walking"):format(pieces, pieces > 1 and "s" or " "), function()
        local found = surface.find_entities_filtered{
          position = { at.x + ring[1].at.x, at.y + ring[1].at.y },
          radius = ring[1].radius, type = "entity-ghost" }
        for index = 2, #ring do
          for _, work in ipairs(surface.find_entities_filtered{
                position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
                radius = ring[index].radius, type = "entity-ghost" }) do
            found[#found + 1] = work
          end
        end
        return found
      end)
    end

    clear_the_field()
    assert.is_true(laid > 4000, "the field was not laid")
  end)

  --- A box the engine turns to lie along the cone, against the chain of circles.
  ---
  --- find_entities_filtered takes an orientation on its area, which turns the box about its
  --- own middle, so one query can follow a cone that a circle has to box in. Verified to miss
  --- nothing: swept over a field at four speeds and two headings, every ghost the cone could
  --- reach came back inside the box.
  ---
  --- What it trades is shape against calls. A box holds more of the ground either side of a
  --- cone than a chain of circles does, and an area query matches anything whose own box
  --- merely overlaps, which widens it by about half a tile all round. Against that it is one
  --- call where the chain is three or four, and a call is not free.
  it("compares a box turned along the cone with a chain of circles", function()
    local laid = lay_a_field()
    local at = player.position
    local surface = player.surface
    helpers.write_file(REPORT,
      ("a field of %d ghosts, a car's cone, %d rounds of each\n"):format(laid, ROUNDS), false)

    local speed = reach.distance({ x = 0, y = 0 }, CAR)
    local along = speed * HORIZON
    local half_long = (along + TIER.range + reach.BORN) / 2
    local middle = (along + TIER.range - reach.BORN) / 2
    local ux, uy = CAR.x / speed, CAR.y / speed
    -- Built long in x and turned from east round to the way its owner is going. Orientation
    -- counts clockwise from north, so east is a quarter turn and has to come back off.
    local turn = ((math.atan2 or math.atan)(ux, -uy) / (2 * math.pi) - 0.25) % 1
    local box = {
      left_top = { x = at.x + ux * middle - half_long, y = at.y + uy * middle - TIER.range },
      right_bottom = { x = at.x + ux * middle + half_long, y = at.y + uy * middle + TIER.range },
      orientation = turn,
    }

    -- Measured first and last, because the first shape timed in a test comes out about a
    -- third quick whatever it is, and a box measured only first would read as a winner on
    -- that alone.
    local function time_the_box(when)
      time("a turned box, " .. when, function()
        return surface.find_entities_filtered{ area = box, type = "entity-ghost" }
      end)
    end
    time_the_box("asked first")
    for _, pieces in ipairs{ 1, 3, 4 } do
      local ring = reach.chain(ARM, CAR, HORIZON, pieces)
      time(("%d circle%s along the cone"):format(pieces, pieces > 1 and "s" or ""), function()
        local found = surface.find_entities_filtered{
          position = { at.x + ring[1].at.x, at.y + ring[1].at.y },
          radius = ring[1].radius, type = "entity-ghost" }
        for index = 2, #ring do
          for _, work in ipairs(surface.find_entities_filtered{
                position = { at.x + ring[index].at.x, at.y + ring[index].at.y },
                radius = ring[index].radius, type = "entity-ghost" }) do
            found[#found + 1] = work
          end
        end
        return found
      end)
    end

    time_the_box("asked last")

    clear_the_field()
    assert.is_true(laid > 4000, "the field was not laid")
  end)

  it("charges differently for the two spellings of a position", function()
    local laid = lay_a_field()
    local at = player.position
    local surface = player.surface
    local ring = reach.chain(ARM, CAR, HORIZON, 3)
    local middle = { x = at.x + ring[2].at.x, y = at.y + ring[2].at.y }
    local radius = ring[2].radius

    helpers.write_file(REPORT,
      ("a field of %d ghosts, one circle, %d rounds of each\n"):format(laid, ROUNDS), false)
    -- Each spelling twice, and in both orders, because the first pair measured came out
    -- the same way round twice and that is exactly what an ordering effect looks like.
    time("position {n, n}, asked first", function()
      return surface.find_entities_filtered{
        position = { middle.x, middle.y }, radius = radius, type = "entity-ghost" }
    end)
    time("position {x =, y =}, asked second", function()
      return surface.find_entities_filtered{
        position = { x = middle.x, y = middle.y }, radius = radius, type = "entity-ghost" }
    end)
    time("position {x =, y =}, asked third", function()
      return surface.find_entities_filtered{
        position = { x = middle.x, y = middle.y }, radius = radius, type = "entity-ghost" }
    end)
    time("position {n, n}, asked fourth", function()
      return surface.find_entities_filtered{
        position = { middle.x, middle.y }, radius = radius, type = "entity-ghost" }
    end)

    -- And the cone test itself, once with a table built for every candidate it is asked
    -- about and once with the same arithmetic done on two numbers.
    local out, e, range = reach.BORN, ARM.extension, ARM.range
    local growing = math.min(HORIZON, (range - out) / e)
    local speed2 = CAR.x * CAR.x + CAR.y * CAR.y
    time("sifted, a table per candidate", function()
      local kept = {}
      for _, work in ipairs(surface.find_entities_filtered{
            position = { middle.x, middle.y }, radius = radius, type = "entity-ghost" }) do
        local spot = work.position
        if reach.meets(ARM, CAR, { x = spot.x - at.x, y = spot.y - at.y }, HORIZON) then
          kept[#kept + 1] = work
        end
      end
      return kept
    end)
    time("sifted, on two numbers", function()
      local kept = {}
      for _, work in ipairs(surface.find_entities_filtered{
            position = { middle.x, middle.y }, radius = radius, type = "entity-ghost" }) do
        local spot = work.position
        local wx, wy = spot.x - at.x, spot.y - at.y
        local a = speed2 - e * e
        local b = -2 * (wx * CAR.x + wy * CAR.y + out * e)
        local c = wx * wx + wy * wy - out * out
        local least = math.min(c, a * growing * growing + b * growing + c)
        if a > 0 then
          local turn = -b / (2 * a)
          if turn > 0 and turn < growing then
            least = math.min(least, a * turn * turn + b * turn + c)
          end
        end
        local met = least <= 0
        if not met then
          local along = (wx * CAR.x + wy * CAR.y) / speed2
          if along < growing then along = growing
          elseif along > HORIZON then along = HORIZON end
          local cap = math.min(range, out + e * along)
          local dx, dy = wx - CAR.x * along, wy - CAR.y * along
          met = dx * dx + dy * dy <= cap * cap
        end
        if met then kept[#kept + 1] = work end
      end
      return kept
    end)

    clear_the_field()
    assert.is_true(laid > 4000, "the field was not laid")
  end)
end)
