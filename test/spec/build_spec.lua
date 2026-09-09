local build = require("lib.build")

describe("whether a build is due", function()
  it("is due at once for a player who has never built", function()
    assert.is_true(build.due(0, nil, 30))
    assert.is_true(build.due(12345, nil, 30))
  end)

  it("is not due until the interval has passed", function()
    assert.is_false(build.due(100, 100, 30))
    assert.is_false(build.due(129, 100, 30))
  end)

  it("is due once it has", function()
    assert.is_true(build.due(130, 100, 30))
    assert.is_true(build.due(131, 100, 30))
  end)

  -- the mod is checked ten times a second and builds twice, so it will usually be asked
  -- some way past the exact tick
  it("stays due after the moment it became due", function()
    assert.is_true(build.due(1000, 100, 30))
  end)
end)

describe("choosing what to spend on a ghost", function()
  --- What a prototype hands over: a list rather than a table keyed by name, since 2.0.
  local BELT = { { name = "transport-belt", count = 1 } }
  local RAIL = { { name = "rail", count = 4 } }
  local EITHER = {
    { name = "fast-transport-belt", count = 1 },
    { name = "transport-belt", count = 1 },
  }

  local function holding(stock)
    return function(name) return stock[name] or 0 end
  end

  it("picks the item when the character has it", function()
    local item, count = build.placing_item(BELT, holding{ ["transport-belt"] = 3 })
    assert.are.equal("transport-belt", item)
    assert.are.equal(1, count)
  end)

  it("picks nothing when the character has none of it", function()
    assert.is_nil(build.placing_item(BELT, holding{ ["wooden-chest"] = 3 }))
    assert.is_nil(build.placing_item(BELT, holding{}))
  end)

  it("picks the first one it is actually carrying", function()
    assert.are.equal("transport-belt",
      (build.placing_item(EITHER, holding{ ["transport-belt"] = 1 })))
    assert.are.equal("fast-transport-belt",
      (build.placing_item(EITHER, holding{ ["fast-transport-belt"] = 1 })))
  end)

  it("prefers the earlier of two it is carrying, as the prototype lists them", function()
    assert.are.equal("fast-transport-belt",
      (build.placing_item(EITHER, holding{
        ["fast-transport-belt"] = 1, ["transport-belt"] = 1 })))
  end)

  it("copes with a ghost that nothing places", function()
    assert.is_nil(build.placing_item({}, holding{ ["transport-belt"] = 1 }))
    assert.is_nil(build.placing_item(nil, holding{ ["transport-belt"] = 1 }))
  end)

  --- A curved rail takes three rails and a half diagonal takes two. The mod used to build
  --- either for anyone holding a single rail, and take only that one.
  it("wants as many as the ghost actually takes", function()
    assert.is_nil(build.placing_item(RAIL, holding{ ["rail"] = 1 }),
      "one rail is not enough to place a ghost that takes four")
    assert.is_nil(build.placing_item(RAIL, holding{ ["rail"] = 3 }))
    local item, count = build.placing_item(RAIL, holding{ ["rail"] = 4 })
    assert.are.equal("rail", item)
    assert.are.equal(4, count, "it should ask for all four")
  end)

  it("says how many to take, not just what", function()
    local _, count = build.placing_item(BELT, holding{ ["transport-belt"] = 9 })
    assert.are.equal(1, count)
  end)

  it("skips one it cannot afford in favour of one it can", function()
    local mixed = {
      { name = "rail", count = 4 },
      { name = "transport-belt", count = 1 },
    }
    local item = build.placing_item(mixed, holding{ ["rail"] = 2, ["transport-belt"] = 1 })
    assert.are.equal("transport-belt", item,
      "it settled for a rail ghost it could not pay for")
  end)
end)
