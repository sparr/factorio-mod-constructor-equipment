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
