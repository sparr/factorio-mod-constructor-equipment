local pack = require("lib.pack")

local function close(a, b)
  return math.abs(a - b) < 1e-6
end

describe("which way a facing points", function()
  -- north is nought and the y axis grows southwards, so north is negative y
  it("points north for nought", function()
    local x, y = pack.facing(0)
    assert.is_true(close(x, 0), tostring(x))
    assert.is_true(close(y, -1), tostring(y))
  end)

  it("points east a quarter of the way round", function()
    local x, y = pack.facing(4)
    assert.is_true(close(x, 1), tostring(x))
    assert.is_true(close(y, 0), tostring(y))
  end)

  it("points south halfway round", function()
    local x, y = pack.facing(8)
    assert.is_true(close(y, 1), tostring(y))
  end)

  it("points west three quarters round", function()
    local x, y = pack.facing(12)
    assert.is_true(close(x, -1), tostring(x))
  end)

  it("comes back to north after a full turn", function()
    local x, y = pack.facing(16)
    assert.is_true(close(x, 0) and close(y, -1))
  end)

  it("is always a unit vector", function()
    for d = 0, 15 do
      local x, y = pack.facing(d)
      assert.is_true(close(math.sqrt(x * x + y * y), 1), "direction " .. d)
    end
  end)
end)

describe("where the arm is mounted", function()
  -- the camera looks from the south, so a character facing north has their back to it and
  -- the arm should sit on the side of them the camera can see
  it("is toward the camera when they face north", function()
    local north = pack.offset(0)
    local south = pack.offset(8)
    assert.is_true(north.y > south.y,
      ("facing north should sit lower on screen than facing south: %.3f vs %.3f")
        :format(north.y, south.y))
  end)

  it("is on the far side from where they are looking", function()
    assert.is_true(pack.offset(4).x < 0, "facing east, the back is to the west")
    assert.is_true(pack.offset(12).x > 0, "facing west, the back is to the east")
  end)

  it("is up at shoulder height whichever way they face", function()
    for d = 0, 15 do
      local at = pack.offset(d)
      assert.is_true(at.y < 0, "direction " .. d .. " put it below the character's feet")
      assert.is_true(at.y > -1.2, "direction " .. d .. " put it over their head")
    end
  end)

  it("never strays far from the middle of them", function()
    for d = 0, 15 do
      local at = pack.offset(d)
      assert.is_true(math.abs(at.x) <= pack.BACK + 1e-9, "direction " .. d)
    end
  end)

  -- it is asked for every tick with whatever the character's direction happens to be
  it("copes with no direction at all", function()
    assert.is_not_nil(pack.offset(nil))
    assert.is_not_nil(pack.offset(0))
  end)
end)
