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
