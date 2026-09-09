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

--- One arm per copy of the equipment. A lone one sits in the middle of the back and the
--- rest go round a circle centred there: two on the shoulders, three a triangle of
--- shoulders and lower back, four a square of shoulders and elbows, and on round.
describe("where the arm bases sit on the back", function()
  local function radius(slot, count)
    local a, d = pack.station(slot, count)
    return math.sqrt(a * a + d * d)
  end

  local function apart(one, other, count)
    local a1, d1 = pack.station(one, count)
    local a2, d2 = pack.station(other, count)
    return math.sqrt((a1 - a2) ^ 2 + (d1 - d2) ^ 2)
  end

  it("puts a lone arm in the middle of the back", function()
    local a, d = pack.station(1, 1)
    assert.is_true(close(a, 0) and close(d, 0), ("%.3f,%.3f"):format(a, d))
  end)

  it("puts every other arrangement out on the circle", function()
    for n = 2, 16 do
      for slot = 1, n do
        assert.is_true(close(radius(slot, n), pack.RADIUS),
          ("%d arms put slot %d at %.3f from the middle"):format(n, slot, radius(slot, n)))
      end
    end
  end)

  it("puts two of them on the shoulders", function()
    local left_a, left_d = pack.station(1, 2)
    local right_a, right_d = pack.station(2, 2)
    assert.is_true(left_a < 0 and right_a > 0, "they are not either side of the middle")
    assert.is_true(close(left_d, right_d), "they are not level with each other")
    assert.is_true(left_d < 0, "they are below the middle of the back, not on the shoulders")
  end)

  -- the special case: evenly spaced, two would sit at the widest part of the circle
  it("puts two of them where the top two of four go", function()
    local pair = { { pack.station(1, 2) }, { pack.station(2, 2) } }
    local top = {}
    for slot = 1, 4 do
      local a, d = pack.station(slot, 4)
      if d < 0 then table.insert(top, { a, d }) end
    end
    assert.are.equal(2, #top, "four arms should have two of them above the middle")
    table.sort(pair, function(x, y) return x[1] < y[1] end)
    table.sort(top, function(x, y) return x[1] < y[1] end)
    for i = 1, 2 do
      assert.is_true(close(pair[i][1], top[i][1]) and close(pair[i][2], top[i][2]),
        ("two-arm slot %d is at %.3f,%.3f but four-arm has %.3f,%.3f")
          :format(i, pair[i][1], pair[i][2], top[i][1], top[i][2]))
    end
  end)

  it("puts three of them in a triangle of two shoulders and a lower back", function()
    local at = {}
    for slot = 1, 3 do
      local a, d = pack.station(slot, 3)
      table.insert(at, { a = a, d = d })
    end
    table.sort(at, function(x, y) return x.d < y.d end)
    assert.is_true(close(at[1].d, at[2].d), "the two shoulder arms are not level")
    assert.is_true(at[3].d > at[2].d, "the third arm is not below the other two")
    assert.is_true(close(at[3].a, 0), "the third arm is not centred on the back")
    assert.is_true(close(at[1].a, -at[2].a), "the shoulders are not either side of centre")
  end)

  it("puts four of them in a square", function()
    local corners = {}
    for slot = 1, 4 do
      local a, d = pack.station(slot, 4)
      table.insert(corners, ("%.3f,%.3f"):format(math.abs(a), math.abs(d)))
    end
    for _, corner in pairs(corners) do
      assert.are.equal(corners[1], corner,
        "the four are not the same distance across and down: " .. corner)
    end
  end)

  -- Evenly spaced round a circle means every arm's nearest neighbour is one chord away,
  -- and the length of that chord follows from the count. Measured as distances rather than
  -- as angles because two argument math.atan is not there in every Lua this runs under.
  it("spaces them evenly round the circle", function()
    for n = 3, 16 do
      local chord = 2 * pack.RADIUS * math.sin(math.pi / n)
      for slot = 1, n do
        local nearest = math.huge
        for other = 1, n do
          if other ~= slot then nearest = math.min(nearest, apart(slot, other, n)) end
        end
        assert.is_true(close(nearest, chord),
          ("%d arms put slot %d %.4f from its neighbour, not %.4f")
            :format(n, slot, nearest, chord))
      end
    end
  end)

  -- no arm at the very top, so the arrangement reads as a pair of shoulders rather than
  -- as one arm with others hanging off it
  it("leaves the top of the circle between two arms", function()
    for n = 2, 16 do
      for slot = 1, n do
        local a, d = pack.station(slot, n)
        assert.is_false(close(a, 0) and d < 0,
          ("%d arms put slot %d at the very top"):format(n, slot))
      end
    end
  end)

  it("is a mirror image of itself left to right", function()
    for n = 1, 16 do
      for slot = 1, n do
        local a, d = pack.station(slot, n)
        local mirrored = false
        for other = 1, n do
          local oa, od = pack.station(other, n)
          if close(oa, -a) and close(od, d) then mirrored = true end
        end
        assert.is_true(mirrored,
          ("%d arms have nothing opposite the one at %.3f,%.3f"):format(n, a, d))
      end
    end
  end)

  it("gives every arm its own spot", function()
    for n = 1, 16 do
      local seen = {}
      for slot = 1, n do
        local a, d = pack.station(slot, n)
        local key = ("%.4f,%.4f"):format(a, d)
        assert.is_nil(seen[key], ("%d arms put two of them on %s"):format(n, key))
        seen[key] = true
      end
    end
  end)

  it("copes with being asked for an arm that is not there", function()
    assert.is_not_nil(pack.offset(0, 5, 3))
    assert.is_not_nil(pack.offset(0, 1, 0))
    assert.is_not_nil(pack.offset(0, nil, nil))
  end)
end)

describe("mounting more than one arm", function()
  it("puts a lone arm exactly where a lone arm always went", function()
    for d = 0, 15 do
      local alone = pack.offset(d)
      local only = pack.offset(d, 1, 1)
      assert.is_true(close(alone.x, only.x) and close(alone.y, only.y), "direction " .. d)
    end
  end)

  -- Two is left out: they are the top half of the four rather than a whole circle, so
  -- they sit above the middle of the back by design. That is checked just below.
  it("centres the circle on the spot a lone arm would have taken", function()
    for _, n in ipairs{ 1, 3, 4, 5, 6, 7, 8, 9, 12 } do
      for d = 0, 15, 4 do
        local alone = pack.offset(d)
        local sx, sy = 0, 0
        for slot = 1, n do
          local at = pack.offset(d, slot, n)
          sx, sy = sx + at.x, sy + at.y
        end
        assert.is_true(close(sx / n, alone.x) and close(sy / n, alone.y),
          ("%d arms facing %d average to %.3f,%.3f rather than %.3f,%.3f")
            :format(n, d, sx / n, sy / n, alone.x, alone.y))
      end
    end
  end)

  it("sits two of them above the middle of the back rather than around it", function()
    for d = 0, 15, 4 do
      local alone = pack.offset(d)
      local left, right = pack.offset(d, 1, 2), pack.offset(d, 2, 2)
      assert.is_true((left.y + right.y) / 2 < alone.y,
        ("facing %d, the pair averages %.3f rather than sitting above %.3f")
          :format(d, (left.y + right.y) / 2, alone.y))
    end
  end)

  -- across the shoulders turns with the character; down the back does not, because it is
  -- how far down the body the thing is strapped rather than a direction in the world
  it("turns the circle with the facing but not the drop", function()
    for n = 2, 8 do
      for slot = 1, n do
        local across, down = pack.station(slot, n)
        for d = 0, 15 do
          local fx, fy = pack.facing(d)
          local at = pack.offset(d, slot, n)
          local expected_x = -fx * pack.BACK - fy * across
          local expected_y = pack.HEIGHT - fy * pack.BACK + fx * across + down
          assert.is_true(close(at.x, expected_x) and close(at.y, expected_y),
            ("%d arms slot %d facing %d"):format(n, slot, d))
        end
      end
    end
  end)

  it("keeps them all on the character", function()
    for n = 1, 16 do
      for d = 0, 15 do
        for slot = 1, n do
          local at = pack.offset(d, slot, n)
          assert.is_true(at.y < 0 and at.y > -1.3,
            ("%d arms facing %d put one at y %.3f"):format(n, d, at.y))
          assert.is_true(math.abs(at.x) <= pack.BACK + pack.RADIUS + 1e-9,
            ("%d arms facing %d put one at x %.3f"):format(n, d, at.x))
        end
      end
    end
  end)
end)
