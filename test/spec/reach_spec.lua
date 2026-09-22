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
      -- 1.07 of a tile, counting the tick of grace the engine's last step is worth.
      assert.is_true(reach.meets(ARM, WALKING, { x = 0, y = 1 }, HORIZON))
      assert.is_false(reach.meets(ARM, WALKING, { x = 0, y = 1.1 }, HORIZON))
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
    ---Whether any whole tick works, by looking at all of them. reach.meets answers in whole
    ---ticks because a hand only ever is anywhere on one, so this has to ask the same way.
    local function by_hand(arm, drift, at, ticks)
      for k = 0, math.floor(ticks) do
        if reach.on_it(arm, drift, at, k) then return true end
      end
      return false
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
              checked = checked + 1
              assert.are.equal(by_hand(arm, drift, at, horizon),
                reach.meets(arm, drift, at, horizon),
                ("%g tile arm, hand %g out, drift %g,%g, spot %g,%g")
                  :format(tier.range, out, drift.x, drift.y, x, y))
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
    -- The near disc is where a hand can be after one tick, grace and all, not where it sits.
    assert.is_true(math.abs(ring[1].radius
        - (travel + reach.BORN + ARM.extension + ARM.range) / 2) < 1e-9,
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

describe("when and where to aim to meet something", function()
  local ARM = { range = 5, extension = 0.1 }
  local HORIZON = reach.full_swing(ARM)
  local WALKING = { x = 0.1484375, y = 0 }
  local STILL = { x = 0, y = 0 }

  local function length(of) return math.sqrt(of.x * of.x + of.y * of.y) end

  describe("for somebody standing still", function()
    it("aims at the thing itself, since it is not going anywhere", function()
      local arrival, lead = reach.intercept(ARM, STILL, { x = 3, y = 0 }, HORIZON)
      assert.is_not_nil(arrival)
      assert.are.same({ x = 3, y = 0 }, lead)
    end)

    --- The plainest case there is, and the one that caught a boundary: a hand takes the
    --- whole horizon to stretch the whole reach, so without a tick's grace for the engine's
    --- last step this was refused.
    it("reaches something at exactly the edge of the reach", function()
      local arrival, lead = reach.intercept(ARM, STILL, { x = 5, y = 0 }, HORIZON)
      assert.is_not_nil(arrival, "a target at exactly the reach was called unreachable")
      assert.are.equal(5, length(lead))
    end)

    it("refuses something a hair past it", function()
      assert.is_nil(reach.intercept(ARM, STILL, { x = 5.01, y = 0 }, HORIZON))
    end)
  end)

  describe("for somebody walking", function()
    --- Ten ahead and four and a half to the side is eleven tiles off, twice the reach, and
    --- the claw is sent to where it will be rather than where it is.
    it("aims ahead of something it will catch up with", function()
      local arrival, lead = reach.intercept(ARM, WALKING, { x = 8.4, y = 4.5 }, HORIZON)
      assert.is_not_nil(arrival, "a ghost the walk brings into reach was called unreachable")
      assert.is_true(length(lead) <= ARM.range + 1e-9,
        ("the lead is %.4f long, past a reach of %g"):format(length(lead), ARM.range))
      -- and it is the target seen from where its owner will be standing by then
      assert.is_true(math.abs(lead.x - (8.4 - WALKING.x * arrival)) < 1e-9)
      assert.are.equal(4.5, lead.y)
    end)

    it("refuses what it will never catch, square abeam at the edge", function()
      assert.is_nil(reach.intercept(ARM, WALKING, { x = 0, y = 5 }, HORIZON))
    end)

    it("refuses what its owner is walking away from", function()
      assert.is_nil(reach.intercept(ARM, WALKING, { x = -4, y = 0 }, HORIZON))
    end)

    --- Something too far ahead has no intercept yet rather than none ever: an arm cannot set
    --- off for what is more than a swing away, and the same ghost is answerable a few ticks
    --- later once its owner has closed some of the gap.
    it("says not yet to something further ahead than a swing", function()
      assert.is_nil(reach.intercept(ARM, WALKING, { x = 10, y = 4.5 }, HORIZON))
      assert.is_not_nil(reach.intercept(ARM, WALKING, { x = 8.4, y = 4.5 }, HORIZON))
    end)
  end)

  --- A hand part way through a reach is the same question with a different starting radius,
  --- and it may come in as readily as go out.
  it("lets a hand already out retract to something nearer", function()
    local out = { range = 5, extension = 0.1, out = 4 }
    local arrival, lead = reach.intercept(out, WALKING, { x = -3, y = 1 }, HORIZON)
    assert.is_not_nil(arrival, "a hand at four tiles could not come in to meet something")
    assert.is_true(length(lead) < 4, "it should have had to retract, not stretch")
  end)

  --- The promise the lead rests on: whatever it hands back is inside the reach, so an arm is
  --- never asked to stretch past what its tier sells.
  it("never hands back a lead longer than the reach", function()
    for x = -8, 14, 0.37 do
      for y = -8, 8, 0.37 do
        local _, lead = reach.intercept(ARM, WALKING, { x = x, y = y }, HORIZON)
        if lead then
          assert.is_true(length(lead) <= ARM.range + 1e-9,
            ("%g,%g gave a lead %.4f long"):format(x, y, length(lead)))
        end
      end
    end
  end)
end)

describe("the first moment a hand could be on something", function()
  local ARM = { range = 5, extension = 0.1 }
  local WALKING = { x = 0.1484375, y = 0 }
  local STILL = { x = 0, y = 0 }
  local HORIZON = 300

  ---Every whole tick, which is what reach.earliest is meant to agree with.
  local function by_hand(arm, drift, offset)
    for k = 0, HORIZON do
      if reach.on_it(arm, drift, offset, k) then return k end
    end
    return nil
  end

  it("is now, for something a resting hand is already touching", function()
    -- a hand is born 0.6939 out, so that is exactly what it is touching
    assert.are.equal(0, reach.earliest(ARM, STILL, { x = reach.BORN, y = 0 }, HORIZON))
  end)

  it("waits for the hand to stretch, for something further off", function()
    -- One tick fewer than the nominal speed alone would say, since the engine's last step
    -- covers whatever gap is left rather than creeping up on it.
    local at = reach.earliest(ARM, STILL, { x = 4, y = 0 }, HORIZON)
    assert.are.equal(math.ceil((4 - reach.BORN) / 0.1) - 1, at)
  end)

  it("waits for the hand to pull in, for something nearer than it is", function()
    local out = { range = 5, extension = 0.1, out = 5 }
    -- two tiles away with the hand at five: it has to come in three tiles, which is thirty
    -- ticks at the nominal speed and twenty nine once the last step is counted
    local at = reach.earliest(out, STILL, { x = 2, y = 0 }, HORIZON)
    assert.are.equal(29, at)
    assert.is_false(reach.on_it(out, STILL, { x = 2, y = 0 }, 28))
  end)

  it("says nothing for what a walk carries away faster than the hand goes", function()
    assert.is_nil(reach.earliest(ARM, WALKING, { x = -4, y = 0 }, HORIZON))
  end)

  --- The reason this is not simply a matter of looking at where a target enters and leaves
  --- the reach. Those two points are where it is furthest away -- a whole reach away, by
  --- definition of the boundary -- which is the hardest place for a hand to get to rather
  --- than a representative one. Here is one arrangement of many: the thing is met in the
  --- middle of its crossing and at neither end of it.
  it("finds a meeting that both ends of the crossing miss", function()
    local arm = { range = 5, extension = 0.1, out = 1 }
    local drift = { x = 0.4051, y = 0.3497 }
    local offset = { x = 6.52, y = 8.55 }
    -- it is inside the reach from tick 11.3 to tick 28.0
    assert.is_false(reach.on_it(arm, drift, offset, 12))
    assert.is_false(reach.on_it(arm, drift, offset, 28))
    local at = reach.earliest(arm, drift, offset, HORIZON)
    assert.is_not_nil(at, "a meeting in the middle of the crossing was missed")
    assert.is_true(at > 12 and at < 28,
      ("met at %s, which is not inside the crossing"):format(tostring(at)))
  end)

  --- The whole of it, against the slow way round: every whole tick, over a spread of
  --- speeds, headings, hand positions and places to reach for.
  it("agrees with looking at every tick, over a wide spread", function()
    local drifts = {}
    for _, speed in ipairs{ 0.05, 0.1484375, 0.2227, 0.5351563 } do
      for eighth = 0, 7 do
        local angle = eighth * math.pi / 4
        drifts[#drifts + 1] = { x = speed * math.cos(angle), y = speed * math.sin(angle) }
      end
    end
    local checked, met = 0, 0
    for _, out in ipairs{ reach.BORN, 1, 2.5, 4, 5 } do
      local arm = { range = 5, extension = 0.1, out = out }
      for _, drift in ipairs(drifts) do
        for x = -11, 11, 2.5 do
          for y = -11, 11, 2.5 do
            local offset = { x = x, y = y }
            checked = checked + 1
            local said = reach.earliest(arm, drift, offset, HORIZON)
            if said then met = met + 1 end
            assert.are.equal(by_hand(arm, drift, offset), said,
              ("hand %g out, drift %.3f,%.3f, spot %g,%g"):format(out, drift.x, drift.y, x, y))
          end
        end
      end
    end
    assert.is_true(met > 1000, "the spread found only " .. met .. " meetings to check")
    assert.is_true(checked > 10000, "the spread was too small at " .. checked)
  end)
end)

describe("a hand that has to turn as well as stretch", function()
  --- The fourth tier's own figures: five tiles at a tenth a tick, and 0.008 of a turn a
  --- tick, which is 2.88 degrees.
  local FACING_EAST = { x = 1, y = 0 }
  local TURNING = { range = 5, extension = 0.1, rotation = 0.008, out = 3,
                    facing = FACING_EAST }
  local STILL = { x = 0, y = 0 }
  local HORIZON = 300

  ---Something three tiles out at a given angle, which is the same distance the hand is
  ---already at, so nothing needs stretching and the turn is the whole journey.
  local function round_by(degrees)
    local angle = math.rad(degrees)
    return { x = math.cos(angle) * 3, y = math.sin(angle) * 3 }
  end

  --- Floor of the nominal, which is what the engine does: its last turn step covers whatever
  --- is left of the turn rather than creeping up on it, the same as its last extension step.
  --- Nominals here are 15.625, 31.25, 46.875 and 62.5 steps.
  ---
  --- These read 16, 32, 47 and 63 for a long while, on a measurement that is most likely of
  --- the mod's own arrival window rather than of the hand. Measured again with the hand held
  --- at a fixed three tiles by a barred box and arrival asked as a hundredth of a tile from
  --- the spot, the engine is there on floor every time -- see test/ft/swinging.lua, and the
  --- eight cases written up at reach.on_it.
  it("charges a turn at the tier's own rate", function()
    assert.are.equal(0, reach.earliest(TURNING, STILL, round_by(0), HORIZON))
    assert.are.equal(15, reach.earliest(TURNING, STILL, round_by(45), HORIZON))
    assert.are.equal(31, reach.earliest(TURNING, STILL, round_by(90), HORIZON))
    assert.are.equal(46, reach.earliest(TURNING, STILL, round_by(135), HORIZON))
    assert.are.equal(62, reach.earliest(TURNING, STILL, round_by(180), HORIZON))
  end)

  it("takes the shorter way round", function()
    assert.are.equal(reach.earliest(TURNING, STILL, round_by(90), HORIZON),
      reach.earliest(TURNING, STILL, round_by(-90), HORIZON))
  end)

  --- A hand with no bearing is a fresh one, and a fresh one is built facing whatever it is
  --- about to reach for, so it has nothing to turn through.
  it("charges nothing to a hand that has no bearing yet", function()
    local fresh = { range = 5, extension = 0.1, out = 3 }
    assert.are.equal(reach.earliest(fresh, STILL, round_by(0), HORIZON),
      reach.earliest(fresh, STILL, round_by(180), HORIZON))
  end)

  it("stops mattering once the hand has had time to face anywhere", function()
    assert.are.equal(62.5, reach.any_way{ rotation = 0.008 })
    -- past half a turn the bearing can be anything, so the only thing left is the stretch
    local far = { x = -4.9, y = 0 }
    local turning = reach.earliest(TURNING, STILL, far, HORIZON)
    local fresh = reach.earliest({ range = 5, extension = 0.1, out = 3 }, STILL, far, HORIZON)
    assert.is_true(turning >= fresh, "turning should never be the quicker of the two")
    assert.is_true(turning <= 63, "a half turn is all it can ever cost")
  end)

  --- The whole of it against the slow way round, with a bearing in play.
  it("agrees with looking at every tick, over a wide spread", function()
    local checked, met = 0, 0
    for _, out in ipairs{ reach.BORN, 1, 2.5, 4, 5 } do
      for eighth = 0, 7 do
        local face = eighth * math.pi / 4
        local arm = { range = 5, extension = 0.1, rotation = 0.008, out = out,
                      facing = { x = math.cos(face), y = math.sin(face) } }
        for _, speed in ipairs{ 0, 0.1484375, 0.3 } do
          local drift = { x = speed, y = 0 }
          for x = -9, 9, 3 do
            for y = -9, 9, 3 do
              local offset = { x = x, y = y }
              local said = reach.earliest(arm, drift, offset, 300)
              local truth
              for k = 0, 300 do
                if reach.on_it(arm, drift, offset, k) then truth = k break end
              end
              checked = checked + 1
              if said then met = met + 1 end
              assert.are.equal(truth, said,
                ("hand %g out facing %d/8, drift %g, spot %g,%g")
                  :format(out, eighth, speed, x, y))
            end
          end
        end
      end
    end
    assert.is_true(met > 300, "only " .. met .. " meetings were found to check")
    assert.is_true(checked > 5000, "the spread was too small at " .. checked)
  end)
end)

--- The cheap cone test, which exists to throw candidates away before anything expensive is
--- spent on them. The only thing that matters about it is that it never throws away
--- anything real: it may keep more than reach.meets would, and it may not keep less.
describe("the cheap cone test", function()
  local reach = require("lib.reach")

  local ARMS = {
    { range = 2, extension = 0.035 },
    { range = 3, extension = 0.05 },
    { range = 5, extension = 0.1 },
  }
  local DRIFTS = {
    { x = 0, y = 0 }, { x = 0.15, y = 0 }, { x = 0, y = -0.3 },
    { x = 0.3, y = 0.3 }, { x = -0.45, y = 0.2 }, { x = 0.05, y = -0.02 },
  }

  it("keeps everything reach.meets says is really in reach", function()
    local tested, kept = 0, 0
    for _, arm in ipairs(ARMS) do
      for _, drift in ipairs(DRIFTS) do
        local ticks = (arm.range - reach.BORN) / arm.extension
        local cone = reach.cone(arm, drift, ticks)
        for x = -30, 30 do
          for y = -30, 30 do
            local offset = { x = x * 0.5, y = y * 0.5 }
            if reach.meets(arm, drift, offset, ticks) then
              tested = tested + 1
              if reach.in_cone(cone, offset) then kept = kept + 1 end
            end
          end
        end
      end
    end
    assert.is_true(tested > 500, "the sweep found almost nothing to test: " .. tested)
    assert.are.equal(tested, kept,
      ("the cone test threw away %d of the %d spots that are really in reach"):format(
        tested - kept, tested))
  end)

  it("is tighter than the circle the search draws round the same cone", function()
    local arm = { range = 5, extension = 0.1 }
    local drift = { x = 0.45, y = 0 }
    local ticks = (arm.range - reach.BORN) / arm.extension
    local cone = reach.cone(arm, drift, ticks)
    local _, radius = reach.search({ { range = arm.range, ticks = ticks } }, drift)
    local inside, circled = 0, 0
    for x = -60, 60 do
      for y = -60, 60 do
        local offset = { x = x * 0.5, y = y * 0.5 }
        if reach.in_cone(cone, offset) then inside = inside + 1 end
        if offset.x * offset.x + offset.y * offset.y <= radius * radius * 4 then
          circled = circled + 1
        end
      end
    end
    assert.is_true(inside < circled,
      ("the cone kept %d where a circle keeps %d"):format(inside, circled))
  end)
end)

--- The box the search is drawn as when its owner is moving. It exists to be cheaper than
--- the circle, and the only thing that would make it wrong is leaving something out.
describe("the oriented search box", function()
  local reach = require("lib.reach")

  local DRIFTS = {
    { x = 0.15, y = 0 }, { x = 0, y = -0.3 }, { x = 0.3, y = 0.3 },
    { x = -0.45, y = 0.2 }, { x = 0.05, y = -0.02 }, { x = -0.2, y = -0.35 },
  }

  ---Whether a spot seen from the wearer is inside the box.
  local function holds(middle, long, wide, turned, offset)
    local angle = turned * 2 * math.pi
    local dx, dy = offset.x - middle.x, offset.y - middle.y
    local along = dx * math.cos(angle) + dy * math.sin(angle)
    local across = -dx * math.sin(angle) + dy * math.cos(angle)
    return math.abs(along) <= long + 1e-9 and math.abs(across) <= wide + 1e-9
  end

  it("holds everything the arms on a wearer can really meet", function()
    local SETS = {
      { { range = 2, extension = 0.035 } },
      { { range = 5, extension = 0.1 } },
      { { range = 2, extension = 0.035 }, { range = 5, extension = 0.1 } },
    }
    local tested, held = 0, 0
    for _, set in ipairs(SETS) do
      for _, drift in ipairs(DRIFTS) do
        local arms = {}
        for index, arm in ipairs(set) do
          arms[index] = { range = arm.range,
                          ticks = (arm.range - reach.BORN) / arm.extension }
        end
        local middle, long, wide, turned = reach.search_box(arms, drift)
        assert.is_not_nil(middle, "a moving wearer was given no box at all")
        for x = -60, 60 do
          for y = -60, 60 do
            local offset = { x = x * 0.5, y = y * 0.5 }
            local reachable = false
            for index, arm in ipairs(set) do
              if reach.meets(arm, drift, offset, arms[index].ticks) then reachable = true end
            end
            if reachable then
              tested = tested + 1
              if holds(middle, long, wide, turned, offset) then held = held + 1 end
            end
          end
        end
      end
    end
    assert.is_true(tested > 1000, "the sweep found almost nothing to test: " .. tested)
    assert.are.equal(tested, held,
      ("the box left out %d of the %d spots the arms can really meet"):format(
        tested - held, tested))
  end)

  it("covers less ground than the circle it replaces", function()
    local arms = { { range = 5, ticks = (5 - reach.BORN) / 0.1 } }
    local drift = { x = 0.45, y = 0 }
    local _, radius = reach.search(arms, drift)
    local _, long, wide = reach.search_box(arms, drift)
    assert.is_true(long * wide * 4 < radius * radius * math.pi,
      ("the box covers %.0f square tiles where the circle covers %.0f"):format(
        long * wide * 4, radius * radius * math.pi))
  end)

  it("hands back nothing at all for a wearer standing still", function()
    assert.is_nil(reach.search_box({ { range = 5, ticks = 43 } }, { x = 0, y = 0 }))
  end)
end)

-- The two numbers an inserter's arm really is, stepped the way the engine steps them. The
-- mod carries these rather than reading the claw, because the claw is drawn somewhere else
-- while a hand is turning -- see follow() in control.lua, and test/ft/following.lua, which
-- runs these against a real inserter.
describe("a hand stepping out or in", function()
  it("moves one step toward where it is going", function()
    assert.are.equal(1.05, reach.stepped(1, 3, 0.05))
    assert.are.equal(0.95, reach.stepped(1, 0, 0.05))
  end)

  it("covers whatever is left inside a step rather than creeping up on it", function()
    assert.are.equal(3, reach.stepped(2.97, 3, 0.05))
    assert.are.equal(3, reach.stepped(3.04, 3, 0.05))
  end)

  it("stays where it is once it is there", function()
    assert.are.equal(3, reach.stepped(3, 3, 0.05))
  end)
end)

describe("a hand turning toward a bearing", function()
  local EAST = { x = 1, y = 0 }
  --- A sixteenth of a turn a tick, so a quarter turn is four ticks.
  local QUICK = 1 / 16

  ---How far round a vector is, in degrees, with the y axis growing southwards. Compared to a
  ---millionth of a degree rather than exactly: these are cosines and sines of each other.
  local function bearing(want, of)
    local got = math.deg((math.atan2 or math.atan)(of.y, of.x)) % 360
    assert.is_true(math.abs(got - want) < 1e-6,
      ("bearing %.6f where %.6f was wanted"):format(got, want))
  end

  it("turns one step, the short way round", function()
    bearing(22.5, reach.turned(EAST, { x = 0, y = 1 }, QUICK))
    bearing(337.5, reach.turned(EAST, { x = 0, y = -1 }, QUICK))
  end)

  it("covers whatever is left inside a step", function()
    local nearly = { x = math.cos(math.rad(20)), y = math.sin(math.rad(20)) }
    bearing(20, reach.turned(EAST, nearly, QUICK))
  end)

  it("keeps its bearing when there is nowhere to point", function()
    assert.are.same(EAST, reach.turned(EAST, { x = 0, y = 0 }, QUICK))
  end)

  it("is turning only while more than a step is left", function()
    assert.is_true(reach.turning(EAST, { x = 0, y = 1 }, QUICK))
    assert.is_false(reach.turning(EAST, { x = math.cos(math.rad(20)),
      y = math.sin(math.rad(20)) }, QUICK))
    assert.is_false(reach.turning(EAST, EAST, QUICK))
    assert.is_false(reach.turning(EAST, { x = 0, y = 0 }, QUICK))
  end)

  --- A dead half turn is the one bearing with no short way round, so the sum picks a side and
  --- keeps it. Which side does not matter -- a hand turns at the same rate either way and
  --- arrives on the same tick -- but it has to be a side rather than nothing.
  it("picks a side for a turn that has no short way round", function()
    bearing(337.5, reach.turned(EAST, { x = -1, y = 0 }, QUICK))
  end)
end)

-- How long a reach already under way is allowed to take. The greater of stretching and
-- turning rather than their sum, because the engine runs both at once -- the same law
-- reach.on_it is built on.
describe("the longest a hand could need", function()
  --- The fourth tier: five tiles at a tenth a tick, 0.0068 of a turn a tick. Fifty ticks of
  --- stretch, seventy three and a half of turn.
  local FOURTH = { range = 5, extension = 0.1, rotation = 0.0068 }

  it("is the greater of stretching and turning, not their sum", function()
    assert.is_true(math.abs(reach.longest(FOURTH) - 0.5 / 0.0068) < 1e-9,
      ("%.1f where the turn alone is %.1f"):format(reach.longest(FOURTH), 0.5 / 0.0068))
  end)

  it("is the stretch where the stretch is the slower half", function()
    -- A tier that turns quickly and creeps out: the stretch is what it waits on.
    local creeper = { range = 5, extension = 0.02, rotation = 0.05 }
    assert.are.equal(250, reach.longest(creeper))
  end)

  it("is the stretch alone for a hand that need not turn", function()
    assert.are.equal(50, reach.longest{ range = 5, extension = 0.1 })
  end)

  it("is never less than one flight out", function()
    -- Whatever else it is, a reach under way may have further to go than a fresh one: a
    -- hand at its own base has the whole range to cover where a fresh one starts part way.
    local tier = { range = 5, extension = 0.1, rotation = 0.0068 }
    assert.is_true(reach.longest(tier) >= (tier.range - reach.BORN) / tier.extension)
  end)
end)
