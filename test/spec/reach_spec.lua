-- The swing itself belongs to the inserter entity: it knows how to move its own arm,
-- including the elbow, and the engine animates it. What is left here is measuring, which
-- is what decides whether a thing is still worth reaching for.
local reach = require("lib.reach")

describe("how far apart two points are", function()
  it("is nothing for a point and itself", function()
    assert.are.equal(0, reach.distance({x = 3, y = 4}, {x = 3, y = 4}))
  end)

  it("is the straight line between them", function()
    assert.are.equal(5, reach.distance({x = 0, y = 0}, {x = 3, y = 4}))
    assert.are.equal(2, reach.distance({x = -1, y = 0}, {x = 1, y = 0}))
  end)
end)

describe("giving up on something out of reach", function()
  local FROM = {x = 0, y = 0}

  it("holds on to what is inside the range", function()
    assert.is_false(reach.out_of_range(FROM, {x = 3, y = 0}, 4))
    assert.is_false(reach.out_of_range(FROM, {x = 4, y = 0}, 4))
  end)

  it("lets go of what is outside it", function()
    assert.is_true(reach.out_of_range(FROM, {x = 4.1, y = 0}, 4))
    assert.is_true(reach.out_of_range(FROM, {x = 10, y = 0}, 4))
  end)

  -- the range is a circle, so the corners of a square are further than they look
  it("measures a diagonal as a diagonal", function()
    assert.is_true(reach.out_of_range(FROM, {x = 3, y = 3}, 4),
      "three by three is 4.24 away, which is out of a range of four")
  end)
end)

describe("how far round an arm has to turn", function()
  local FROM = {x = 0, y = 0}

  it("asks nothing of a hand already pointing that way", function()
    assert.are.equal(0, reach.turn(FROM, {x = 2, y = 0}, {x = 5, y = 0}))
  end)

  it("calls straight behind it half a turn", function()
    assert.are.equal(0.5, reach.turn(FROM, {x = 2, y = 0}, {x = -5, y = 0}))
  end)

  it("calls a right angle a quarter", function()
    assert.are.equal(0.25, reach.turn(FROM, {x = 2, y = 0}, {x = 0, y = 5}))
  end)

  -- an arm turns whichever way is shorter, so the answer never exceeds half a turn
  it("goes the short way round", function()
    assert.is_true(math.abs(reach.turn(FROM, {x = 1, y = -0.1}, {x = 1, y = 0.1})) < 0.05)
  end)

  -- a hand sitting on its own base is pointing nowhere, so there is nothing to turn from
  it("asks nothing of a hand with no bearing", function()
    assert.are.equal(0, reach.turn(FROM, FROM, {x = 5, y = 0}))
  end)
end)

describe("how long a swing would take", function()
  local FROM = {x = 0, y = 0}
  -- the fourth tier's numbers: five tiles at a tenth of a tile a tick, and a whole turn in
  -- a hundred and twenty five
  local TIER = { extension = 0.1, rotation = 0.008, range = 5 }

  it("charges a straight reach for its extension", function()
    assert.are.equal(30, reach.swing_ticks(TIER, FROM, {x = 2, y = 0}, {x = 5, y = 0}))
  end)

  it("charges nothing extra for coming back in along the same line", function()
    assert.are.equal(30, reach.swing_ticks(TIER, FROM, {x = 5, y = 0}, {x = 2, y = 0}))
  end)

  -- the point of the whole thing: an inserter turns and extends at once, so a near thing
  -- behind the claw is a longer journey than a far one in front of it
  it("makes a near thing behind the hand cost more than a far one in front", function()
    local behind = reach.swing_ticks(TIER, FROM, {x = 4, y = 0}, {x = -1, y = 0})
    local ahead = reach.swing_ticks(TIER, FROM, {x = 4, y = 0}, {x = 5, y = 0})
    assert.is_true(behind > ahead,
      ("a tile behind cost %d ticks and four tiles ahead cost %d"):format(behind, ahead))
  end)

  it("charges a turn that outlasts the reach for the turn", function()
    -- a quarter turn is 31 ticks where the one tile of extension is 10
    assert.are.equal(31.25, reach.swing_ticks(TIER, FROM, {x = 4, y = 0}, {x = 0, y = 5}))
  end)
end)

describe("how long a hand is out", function()
  it("charges the reach less where the hand was born, at the tier's own speed", function()
    assert.are.equal((5 - reach.BORN) / 0.1,
      reach.full_swing{ range = 5, extension = 0.1 })
  end)

  -- Measured on 2.1.19: the four tiers let go on ticks 37, 46, 33 and 43. The estimate is
  -- allowed to be a shade over, because the engine's last step covers whatever gap is left
  -- rather than creeping up on it, and is not allowed to be under.
  local MEASURED = {
    { range = 2, extension = 0.035, ticks = 37 },
    { range = 3, extension = 0.05,  ticks = 46 },
    { range = 4, extension = 0.1,   ticks = 33 },
    { range = 5, extension = 0.1,   ticks = 43 },
  }

  for _, tier in ipairs(MEASURED) do
    it(("matches what a %g tile arm was measured doing"):format(tier.range), function()
      local said = reach.full_swing(tier)
      assert.is_true(said >= tier.ticks and said < tier.ticks + 1,
        ("said %.2f ticks where the engine took %d"):format(said, tier.ticks))
    end)
  end
end)

describe("where to look for work", function()
  --- The worked example: a five tile arm whose hand is out for thirty ticks, on somebody
  --- walking at fifteen hundredths of a tile a tick. They cover four and a half tiles while
  --- it is out, so everything the hand could possibly meet lies within five tiles of some
  --- point on that four and a half tile line, and the smallest circle round that is centred
  --- half way along it and reaches the reach plus that half.
  local ARM = { { range = 5, ticks = 30 } }
  local WALKING = { x = 0.15, y = 0 }

  it("centres half the travel ahead and adds the other half to the reach", function()
    local centre, radius = reach.search(ARM, WALKING)
    assert.are.equal(2.25, centre.x)
    assert.are.equal(0, centre.y)
    assert.are.equal(7.25, radius)
  end)

  it("puts the centre along the way its owner is actually going", function()
    local centre, radius = reach.search(ARM, { x = 0, y = -0.15 })
    assert.are.equal(0, centre.x)
    assert.are.equal(-2.25, centre.y)
    assert.are.equal(7.25, radius)
  end)

  it("is the reach itself, on its owner, for somebody standing still", function()
    local centre, radius = reach.search(ARM, { x = 0, y = 0 })
    assert.are.same({ x = 0, y = 0 }, centre)
    assert.are.equal(5, radius)
  end)

  --- The whole promise: nothing an arm could meet is left out. Walked tick by tick along
  --- the owner's course, every point the hand could be at when it arrives has to fall
  --- inside the circle.
  it("covers everywhere the hand could arrive at any point in the flight", function()
    local centre, radius = reach.search(ARM, WALKING)
    for tick = 0, 30 do
      local owner = { x = WALKING.x * tick, y = WALKING.y * tick }
      -- the furthest corner of that tick's reach, in every direction round the circle
      for step = 0, 63 do
        local angle = step * 2 * math.pi / 64
        local edge = {
          x = owner.x + math.cos(angle) * ARM[1].range,
          y = owner.y + math.sin(angle) * ARM[1].range,
        }
        assert.is_true(reach.distance(centre, edge) <= radius + 1e-9,
          ("tick %d, bearing %d: %.4f from the middle of a %.4f circle")
            :format(tick, step, reach.distance(centre, edge), radius))
      end
    end
  end)

  it("is no bigger than it has to be", function()
    local _, radius = reach.search(ARM, WALKING)
    -- the far edge of the last tick's reach and the near edge of the first are a diameter
    -- apart, so nothing smaller holds them both
    assert.are.equal(radius * 2, (WALKING.x * 30 + ARM[1].range) + ARM[1].range)
  end)

  --- One search is shared out between every arm its owner is wearing, so one circle has to
  --- hold all of theirs. They all point the same way, being the same owner walking, so the
  --- span is from the furthest any of them reaches behind to the furthest any could meet
  --- ahead -- which need not be the same arm at both ends.
  describe("with several arms to cover", function()
    local SHORT_AND_SLOW = { range = 2, ticks = 60 }
    local LONG_AND_QUICK = { range = 5, ticks = 10 }

    it("takes its back edge from the longest reach and its front from the furthest ahead",
      function()
        local centre, radius = reach.search({ SHORT_AND_SLOW, LONG_AND_QUICK }, WALKING)
        -- behind: five, the long arm's reach. ahead: 2 + 0.15 * 60 = eleven, the slow one's
        assert.are.equal(8, radius)
        assert.are.equal(3, centre.x)
      end)

    it("holds every one of them", function()
      local arms = { SHORT_AND_SLOW, LONG_AND_QUICK }
      local centre, radius = reach.search(arms, WALKING)
      for _, arm in ipairs(arms) do
        local alone, its_radius = reach.search({ arm }, WALKING)
        assert.is_true(reach.distance(centre, alone) + its_radius <= radius + 1e-9,
          "one arm's own circle sticks out of the shared one")
      end
    end)
  end)
end)

describe("whether an arm could ever meet a spot", function()
  --- The fourth tier: five tiles at a tenth of a tile a tick, so a hand born 0.69 out takes
  --- 43 ticks to reach full stretch.
  local ARM = { range = 5, extension = 0.1 }
  local HORIZON = reach.full_swing(ARM)
  --- A character's own walk, measured: 38/256 of a tile a tick.
  local WALKING = { x = 0.1484375, y = 0 }
  local STILL = { x = 0, y = 0 }

  describe("for somebody standing still", function()
    it("is the reach and nothing else", function()
      assert.is_true(reach.meets(ARM, STILL, { x = 5, y = 0 }, HORIZON))
      assert.is_true(reach.meets(ARM, STILL, { x = -5, y = 0 }, HORIZON))
      assert.is_true(reach.meets(ARM, STILL, { x = 0, y = 5 }, HORIZON))
      assert.is_false(reach.meets(ARM, STILL, { x = 5.1, y = 0 }, HORIZON))
    end)
  end)

  describe("for somebody walking", function()
    it("meets what it will catch up with, past the reach", function()
      -- eight tiles ahead: three past the arm, and met on the way
      assert.is_true(reach.meets(ARM, WALKING, { x = 8, y = 0 }, HORIZON))
    end)

    it("does not meet what it will never catch up with", function()
      -- twelve ahead: the owner covers 6.4 tiles in the 43 ticks and the arm five, so no
      assert.is_false(reach.meets(ARM, WALKING, { x = 12, y = 0 }, HORIZON))
    end)

    --- The whole point of the cone, and where it differs from the circle the search draws.
    --- A ghost square abeam at the very edge of the reach is inside that circle and is not
    --- reachable: the hand needs 43 ticks to stretch five tiles, by which time its owner has
    --- carried the shoulder 6.4 tiles past it and the gap has only ever opened.
    it("does not meet something square abeam at the edge of the reach", function()
      assert.is_false(reach.meets(ARM, WALKING, { x = 0, y = 5 }, HORIZON))
    end)

    --- And barely anything abeam at all. A character walks 0.148 of a tile a tick and a
    --- fourth tier hand extends a tenth, so its owner outruns its own stretch by half
    --- again: by the time the hand is two tiles out its owner has carried the shoulder
    --- nearly two tiles on. Square abeam, the cone is 0.94 of a tile wide.
    ---
    --- Which is what was measured from the other end before any of this was worked out. A
    --- ghost laid one to three tiles to the side of a character already under way was set
    --- off for and written off without a delivery on nine passes of two dozen. See
    --- out_of_reach() in control.lua.
    it("meets almost nothing square abeam, however near", function()
      assert.is_true(reach.meets(ARM, WALKING, { x = 0, y = 0.9 }, HORIZON))
      assert.is_false(reach.meets(ARM, WALKING, { x = 0, y = 1 }, HORIZON))
      assert.is_false(reach.meets(ARM, WALKING, { x = 0, y = 2 }, HORIZON))
    end)

    it("meets it once it is far enough in front to be caught", function()
      assert.is_true(reach.meets(ARM, WALKING, { x = 4, y = 2 }, HORIZON))
    end)

    it("does not meet what it is walking away from", function()
      assert.is_false(reach.meets(ARM, WALKING, { x = -4, y = 0 }, HORIZON))
    end)

    --- A hand already out is a different arm from one at rest: it has its stretch behind it
    --- and can put something down where a fresh one could not get to in time.
    it("meets abeam once the hand is already at full stretch", function()
      local out = { range = 5, extension = 0.1, out = 5 }
      assert.is_true(reach.meets(out, WALKING, { x = 0, y = 5 }, HORIZON))
    end)

    it("carries a hand at full stretch forward with its owner", function()
      local out = { range = 5, extension = 0.1, out = 5 }
      -- the far tip of the capsule: the whole walk, plus the reach
      assert.is_true(reach.meets(out, WALKING, { x = 0.1484375 * HORIZON + 4.9, y = 0 },
        HORIZON))
    end)
  end)

  --- The closed form against a brute sweep of the same question, tick by tick, over every
  --- tier, four hand positions, and five ways of going. Points within a hundredth of the
  --- boundary are left out, since the sweep cannot place those to better than its own step.
  it("agrees with sweeping the flight tick by tick", function()
    local TIERS = {
      { range = 2, extension = 0.035 }, { range = 3, extension = 0.05 },
      { range = 4, extension = 0.1 },   { range = 5, extension = 0.1 },
    }
    local DRIFTS = {
      { x = 0.1484375, y = 0 }, { x = 0, y = -0.1484375 },
      { x = 0.105, y = 0.105 }, { x = 0, y = 0 }, { x = 0.3, y = 0 },
    }
    ---How near the hand ever comes to a spot, swept rather than solved.
    local function closest(arm, drift, at, ticks)
      local out = arm.out or reach.BORN
      local least = math.huge
      for step = 0, 240 do
        local k = ticks * step / 240
        local radius = math.min(arm.range, out + arm.extension * k)
        local dx, dy = at.x - drift.x * k, at.y - drift.y * k
        least = math.min(least, math.sqrt(dx * dx + dy * dy) - radius)
      end
      return least
    end

    local checked = 0
    for _, tier in ipairs(TIERS) do
      local horizon = reach.full_swing(tier)
      for _, out in ipairs{ reach.BORN, tier.range * 0.5, tier.range } do
        local arm = { range = tier.range, extension = tier.extension, out = out }
        for _, drift in ipairs(DRIFTS) do
          for x = -8, 14, 1.1 do
            for y = -8, 8, 1.1 do
              local at = { x = x, y = y }
              local slack = closest(arm, drift, at, horizon)
              if math.abs(slack) >= 0.01 then
                checked = checked + 1
                assert.are.equal(slack <= 0, reach.meets(arm, drift, at, horizon),
                  ("%g tile arm, hand %g out, drift %g,%g, spot %g,%g: %g from the hand")
                    :format(tier.range, out, drift.x, drift.y, x, y, slack))
              end
            end
          end
        end
      end
    end
    assert.is_true(checked > 5000, "the sweep checked only " .. checked .. " spots")
  end)
end)

describe("the circles a cone is searched with", function()
  local ARM = { range = 5, extension = 0.1 }
  local HORIZON = reach.full_swing(ARM)
  local WALKING = { x = 0.1484375, y = 0 }
  --- A car flat out, measured. Its cone is a ten degree needle 28 tiles long, which is the
  --- case a chain exists for.
  local DRIVING = { x = 0.5351563, y = 0 }

  it("is one circle round the whole cone when asked for one", function()
    local ring = reach.chain(ARM, WALKING, HORIZON, 1)
    assert.are.equal(1, #ring)
    local travel = WALKING.x * HORIZON
    assert.is_true(math.abs(ring[1].radius - (travel + reach.BORN + ARM.range) / 2) < 1e-9,
      "one piece should be the smallest circle round the two end discs")
  end)

  it("lays them along the way its owner is going", function()
    local ring = reach.chain(ARM, DRIVING, HORIZON, 4)
    assert.are.equal(4, #ring)
    for piece = 2, #ring do
      assert.is_true(ring[piece].at.x > ring[piece - 1].at.x,
        "the circles are not in order along the drift")
      assert.are.equal(0, ring[piece].at.y)
    end
  end)

  --- Standing still, every piece is a circle on the owner and only the last of them is
  --- worth anything: the cone has collapsed to the reach and the rest are nested inside it.
  --- Which is a cover, and a waste, and is why the piece count is chosen by how much ground
  --- the chain sweeps rather than set once -- see below, where a walk already asks for one.
  it("nests them on their owner when nobody is moving", function()
    local ring = reach.chain(ARM, { x = 0, y = 0 }, HORIZON, 3)
    for piece, circle in ipairs(ring) do
      assert.are.same({ x = 0, y = 0 }, circle.at)
      if piece > 1 then
        assert.is_true(circle.radius > ring[piece - 1].radius, "the circles do not grow")
      end
    end
    assert.is_true(math.abs(ring[#ring].radius - ARM.range) < 1e-9,
      "the last of them should be the reach itself")
  end)

  --- The promise the chain has to keep: between them the circles hold the whole cone. Swept
  --- over a grid fine enough to catch a gap between two of them, at every piece count worth
  --- asking for and on both a walk and a drive.
  it("leaves no part of the cone outside every circle", function()
    for _, drift in ipairs{ WALKING, DRIVING } do
      for _, pieces in ipairs{ 1, 2, 3, 4, 6 } do
        local ring = reach.chain(ARM, drift, HORIZON, pieces)
        for x = -3, drift.x * HORIZON + 6, 0.25 do
          for y = -6, 6, 0.25 do
            if reach.meets(ARM, drift, { x = x, y = y }, HORIZON) then
              local held = false
              for _, circle in ipairs(ring) do
                local dx, dy = x - circle.at.x, y - circle.at.y
                if dx * dx + dy * dy <= circle.radius * circle.radius then
                  held = true
                  break
                end
              end
              assert.is_true(held,
                ("%g,%g is in the cone and in none of %d circles at drift %g")
                  :format(x, y, pieces, drift.x))
            end
          end
        end
      end
    end
  end)

  --- More is not better, and how much is best is the wearer's speed rather than a constant.
  --- Every circle has the local width of the cone as a floor, so past a handful the chain
  --- pays that floor over and over.
  it("is best at one circle for a walk and at several for a drive", function()
    local function swept(drift, pieces)
      local total = 0
      for _, circle in ipairs(reach.chain(ARM, drift, HORIZON, pieces)) do
        total = total + math.pi * circle.radius * circle.radius
      end
      return total
    end
    local function fewest(drift)
      local best, at = math.huge, 0
      for pieces = 1, 8 do
        local swept_area = swept(drift, pieces)
        if swept_area < best then best, at = swept_area, pieces end
      end
      return at
    end
    assert.are.equal(1, fewest(WALKING))
    assert.is_true(fewest(DRIVING) >= 3, "a car's cone wants more than two circles")
    assert.is_true(swept(DRIVING, fewest(DRIVING)) < swept(DRIVING, 1) * 0.7,
      "chaining a car's cone should sweep well under two thirds of one circle round it")
  end)
end)
