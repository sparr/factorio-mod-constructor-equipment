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
