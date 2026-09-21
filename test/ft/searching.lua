--- What a search costs, drawn four ways.
---
--- An arm can only meet what is inside a cone: a circle the size of a newborn hand, growing
--- at the tier's extension speed, sliding along the way its owner is going. reach.meets says
--- exactly whether a spot is in it, but the search that finds candidates has to be a shape
--- the engine will take, and there are three of those.
---
---   capsule   what the mod draws now: one circle round a capsule that assumes full stretch
---             from the first tick, which is the cone plus everything the cone grew into
---   cone      one circle round the cone itself, which is reach.chain with a single piece
---   chain     several circles laid end to end along the cone
---   box       one oriented bounding box round the cone. find_entities_filtered honours a
---             BoundingBox orientation -- measured: a flat box over a diagonal line of
---             fifteen ghosts found three of them, and the same box turned found all fifteen
---
--- What is asserted is that every shape holds everything reach.meets says is really there:
--- a shape that misses real work is no use however fast it is. What is logged beside that is
--- how many candidates each hands back and what a call costs.
---
--- The counts are exact and repeat to the entity. The timings do not: they want a quiet
--- machine, and what is in TODO 12 was taken at three hundred calls and three runs a shape,
--- best of the three, on a machine carrying a load average of two. This runs a twentieth of
--- that, because its job here is to catch a shape that stops covering the cone.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

--- How many calls to time, per shape per scenario.
local CALLS = 300
--- How many times to time each shape, since the smallest of several is the honest one.
local RUNS = 3
--- Half the side of the field the ghosts are laid in.
local FIELD = 22

---The oriented box round a cone, in world coordinates.
---
---Laid along positive x and then turned, because that is the mapping the engine uses: a box
---along x with orientation a is a box along the bearing a turns clockwise from x.
---@param arm {range: number, extension: number, out: number?}
---@param from {x: number, y: number} the arm's own base
---@param drift {x: number, y: number}
---@param ticks number
local function cone_box(arm, from, drift, ticks)
  local out = arm.out or reach.BORN
  local near = math.min(arm.range, out + arm.extension)
  local far = math.min(arm.range, out + arm.extension * (ticks + 1))
  local along = { x = drift.x * ticks, y = drift.y * ticks }
  local length = math.sqrt(along.x * along.x + along.y * along.y)
  if length < 1e-9 then
    -- Nowhere to slide, so the cone is just the circle the hand grows into -- the far
    -- radius, not the near one. Getting that wrong is a box a tenth the size of the reach,
    -- which found nine of eighty one and reported no trouble at all.
    return { left_top = { from.x - far, from.y - far },
             right_bottom = { from.x + far, from.y + far } }
  end
  local half = (length + near + far) / 2
  local middle = (length + far - near) / 2
  local centre = { x = from.x + along.x / length * middle,
                   y = from.y + along.y / length * middle }
  local across = math.max(near, far)
  return {
    left_top = { centre.x - half, centre.y - across },
    right_bottom = { centre.x + half, centre.y + across },
    orientation = (math.atan2 or math.atan)(along.y, along.x) / (2 * math.pi) % 1,
  }
end

describe("the shapes a search can be drawn as", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = FIELD * 2, type = "entity-ghost" }) do
      if e.valid then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  local SPEEDS = {
    { name = "standing still", speed = 0 },
    { name = "walking",        speed = 0.15 },
    { name = "a car",          speed = 0.30 },
    { name = "a train",        speed = 0.45 },
  }
  local SPACINGS = { { name = "sparse", step = 2 }, { name = "packed", step = 1 } }
  local LEVELS = { 2, 4 }

  for _, level in ipairs(LEVELS) do
  for _, spacing in ipairs(SPACINGS) do
  for _, going in ipairs(SPEEDS) do
    it(("PROBE: tier %d, %s, %s"):format(level, spacing.name, going.name), function()
      local surface = player.surface
      local tier = tiers.by_level[level]
      local from = { x = world.ORIGIN.x, y = world.ORIGIN.y }
      -- due east, so nothing about the numbers depends on which way it happens to point
      local drift = { x = going.speed, y = 0 }
      local ticks = reach.full_swing(tier)
      local arm = { range = tier.range, extension = tier.extension }

      local laid = 0
      for x = -FIELD, FIELD, spacing.step do
        for y = -FIELD, FIELD, spacing.step do
          if surface.create_entity{ name = "entity-ghost", inner_name = "transport-belt",
              position = { from.x + x + 0.5, from.y + y + 0.5 }, force = player.force } then
            laid = laid + 1
          end
        end
      end

      -- What is really in reach, which is what every shape has to hold all of.
      local truly = {}
      for _, ghost in ipairs(surface.find_entities_filtered{ position = from,
            radius = FIELD * 2, type = "entity-ghost" }) do
        if reach.meets(arm, drift, { x = ghost.position.x - from.x,
              y = ghost.position.y - from.y }, ticks) then
          truly[ghost.unit_number] = true
        end
      end
      local true_count = 0
      for _ in pairs(truly) do true_count = true_count + 1 end

      -- What choose() does with a candidate list before it picks anything from it: a price
      -- for every one of them, and then a sort of the lot. The sort is the part that does
      -- not scale -- it is n log n over a comparator that can measure two distances -- so a
      -- shape that hands back more candidates pays for them twice over.
      local hand = { x = from.x + 0.7, y = from.y }
      local function process(found)
        local cost = {}
        for _, work in ipairs(found) do
          if work.valid then
            cost[work.unit_number] = reach.swing_ticks(tier, from, hand, work.position)
          end
        end
        table.sort(found, function(one, other)
          if not (one.valid and other.valid) then return false end
          local mine = cost[one.unit_number] or math.huge
          local theirs = cost[other.unit_number] or math.huge
          if mine == theirs then
            return reach.distance(from, one.position) < reach.distance(from, other.position)
          end
          return mine < theirs
        end)
        return #found
      end

      -- The same again with a sieve in front of it: reach.meets on every candidate, which
      -- is a good deal cheaper than pricing a swing, and then the pricing and the sort only
      -- over what survives. This is the arrangement neither shape-versus-shape comparison
      -- can see, because it makes the shape's over-reach cost almost nothing.
      -- The cone as plain arithmetic, which is what a rejection test should be. Everything
      -- it needs is worked out once per search: the way its owner is going, how long the
      -- cone is, and how wide it is at each end.
      --
      -- Two circles, radius r0 at the near end and r1 at the far one, L apart. The line
      -- that wraps them is the external tangent, at an angle a to the axis where
      -- sin a = (r1 - r0) / L, and its distance from the axis at x is (r0 + x sin a)/cos a.
      -- Clamping x to the cone's own length turns the flare into the caps, which is wider
      -- than the true circles and therefore never rejects anything real.
      --
      -- Per candidate that is a dot product, a cross product and two compares.
      local speed = math.sqrt(drift.x * drift.x + drift.y * drift.y)
      local out = reach.BORN
      local r0 = math.min(arm.range, out + arm.extension)
      local r1 = math.min(arm.range, out + arm.extension * (ticks + 1))
      local length = speed * ticks
      local dirx, diry = 1, 0
      local cosa, grow = 1, 0
      if length > 1e-9 then
        dirx, diry = drift.x / speed, drift.y / speed
        -- How fast the hand widens against how fast its owner moves. The radius stops
        -- growing the moment the hand is at full stretch, so a straight line from one end
        -- to the other runs under the real thing in the middle and throws real spots away:
        -- measured, two of a hundred and fourteen. The radius is taken at the spot instead.
        grow = arm.extension / speed
        local sina = math.min(grow, 0.999)
        cosa = math.sqrt(math.max(1e-6, 1 - sina * sina))
      end
      local function in_cone(at)
        local ox, oy = at.x - from.x, at.y - from.y
        if length <= 1e-9 then return ox * ox + oy * oy <= r1 * r1 end
        local along = ox * dirx + oy * diry
        if along < -r0 or along > length + r1 then return false end
        local across = ox * diry - oy * dirx
        if across < 0 then across = -across end
        local held = along
        if held < 0 then held = 0 elseif held > length then held = length end
        -- The tangent that wraps the growing hand, capped where the hand stops growing.
        -- Never wider than the reach: every disc the cone is made of is inside that.
        local wide = (out + arm.extension + held * grow) / cosa
        if wide > arm.range then wide = arm.range end
        return across <= wide
      end

      local function cheaply(found)
        local real = {}
        for _, work in ipairs(found) do
          if work.valid and in_cone(work.position) then real[#real + 1] = work end
        end
        return process(real)
      end

      -- What choose() actually wants: the cheapest candidate that will do, not a sorted
      -- list. One pass keeping the best so far, with two short circuits.
      --
      -- The first is the cone test. The second is that a swing's price is the greater of
      -- how far the hand must stretch and how far it must turn, so the stretch alone is a
      -- floor under it -- and the stretch costs one distance where the turn costs two
      -- arctangents. Anything whose floor is already above the best so far can be dropped
      -- without the turn ever being worked out.
      --
      -- What is not modelled here is the acceptance test, which in choose() is a handful of
      -- prototype and inventory lookups per candidate. Sorted, it runs down the list until
      -- something passes; scanned, it runs only when a candidate would take the lead. That
      -- makes the real gain larger than this measures rather than smaller.
      local hand_out_now = reach.distance(from, hand)
      local function scan(found)
        local best_price, best_far, taken = math.huge, math.huge, 0
        for _, work in ipairs(found) do
          if work.valid and in_cone(work.position) then
            local at = work.position
            local far = reach.distance(from, at)
            local floor_price = math.abs(far - hand_out_now) / tier.extension
            if floor_price <= best_price then
              local price = reach.swing_ticks(tier, from, hand, at)
              if price < best_price or (price == best_price and far < best_far) then
                best_price, best_far, taken = price, far, taken + 1
              end
            end
          end
        end
        return taken
      end

      local function sift(found)
        local real = {}
        for _, work in ipairs(found) do
          if work.valid and reach.meets(arm, drift,
              { x = work.position.x - from.x, y = work.position.y - from.y }, ticks) then
            real[#real + 1] = work
          end
        end
        return process(real)
      end

      ---Run a shape CALLS times, and say what it found and whether it missed anything.
      ---@param name string
      ---@param query fun(): LuaEntity[]
      local function measure(name, query)
        local held, missed = query(), 0
        local seen = {}
        for _, ghost in ipairs(held) do seen[ghost.unit_number] = true end
        for id in pairs(truly) do if not seen[id] then missed = missed + 1 end end
        -- Three runs and all three reported. A machine with anything else on it makes a
        -- single timing worth very little, and the smallest of several is the one least
        -- polluted by whatever else was running.
        for run = 1, RUNS do
          local total = 0
          local bare = helpers.create_profiler()
          for _ = 1, CALLS do total = total + #query() end
          bare.stop()
          local whole = helpers.create_profiler()
          for _ = 1, CALLS do total = total + process(query()) end
          whole.stop()
          local sieved = helpers.create_profiler()
          for _ = 1, CALLS do total = total + sift(query()) end
          sieved.stop()
          local quick = helpers.create_profiler()
          for _ = 1, CALLS do total = total + cheaply(query()) end
          quick.stop()
          local scanned = helpers.create_profiler()
          for _ = 1, CALLS do total = total + scan(query()) end
          scanned.stop()
          -- and the cheap test has to be a superset too, or it is no use however fast
          local kept = {}
          for _, work in ipairs(query()) do
            if in_cone(work.position) then kept[work.unit_number] = true end
          end
          local lost = 0
          for id in pairs(truly) do if not kept[id] then lost = lost + 1 end end
          assert.are.equal(0, lost,
            ("the cheap cone test threw away %d of %d real spots, after %s"):format(
              lost, true_count, name))
          log{ "", ("SHAPE | tier %d | %-6s | %-14s | %-12s | %4d found of %4d laid,"
            .. " %3d really in reach, %d missed | run %d of %d | search "):format(level,
            spacing.name, going.name, name, #held, laid, true_count, missed, run, CALLS),
            bare, " | search and sift ", whole, " | search sieve and sift ", sieved,
            " | search cone and sift ", quick,
            " | search cone and scan ", scanned }
        end
        assert.are.equal(0, missed,
          ("%s missed %d of the %d spots the arm can really meet"):format(name, missed,
            true_count))
        if false then
        end
      end

      local offset, radius = reach.search({ { range = tier.range, ticks = ticks } }, drift)
      measure("capsule", function()
        return surface.find_entities_filtered{
          position = { from.x + offset.x, from.y + offset.y }, radius = radius,
          type = "entity-ghost" }
      end)

      for _, pieces in ipairs{ 1, 2, 4, 8 } do
        local circles = reach.chain(arm, drift, ticks, pieces)
        measure(pieces == 1 and "cone" or ("chain of " .. pieces), function()
          local found = {}
          for _, circle in ipairs(circles) do
            for _, ghost in ipairs(surface.find_entities_filtered{
                position = { from.x + circle.at.x, from.y + circle.at.y },
                radius = circle.radius, type = "entity-ghost" }) do
              found[ghost.unit_number] = ghost
            end
          end
          local flat = {}
          for _, ghost in pairs(found) do flat[#flat + 1] = ghost end
          return flat
        end)
      end

      local box = cone_box(arm, from, drift, ticks)
      measure("oriented box", function()
        return surface.find_entities_filtered{ area = box, type = "entity-ghost" }
      end)
    end)
  end
  end
  end
end)
