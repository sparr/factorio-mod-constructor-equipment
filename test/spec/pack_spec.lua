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

describe("which facing a vector points nearest to", function()
  it("is the inverse of pack.facing at every one of the sixteen", function()
    for d = 0, 15 do
      local x, y = pack.facing(d)
      assert.are.equal(d, pack.towards(x, y), "direction " .. d)
    end
  end)

  it("rounds to the nearest rather than truncating", function()
    -- A sixteenth short of west, which an inserter's own truncation would call south
    local x, y = pack.facing(11)
    assert.are.equal(12, pack.towards(x, y, 4))
  end)

  it("gives only the four cardinals when asked for four", function()
    for d = 0, 15 do
      local x, y = pack.facing(d)
      local way = pack.towards(x, y, 4)
      assert.are.equal(0, way % 4, "asked for a quarter and got " .. way)
    end
  end)

  it("puts each quarter round the facing it belongs to", function()
    assert.are.equal(0, pack.towards(0, -1, 4))
    assert.are.equal(4, pack.towards(1, 0, 4))
    assert.are.equal(8, pack.towards(0, 1, 4))
    assert.are.equal(12, pack.towards(-1, 0, 4))
  end)

  it("does not care how long the vector is", function()
    assert.are.equal(4, pack.towards(40, 1, 4))
    assert.are.equal(4, pack.towards(0.04, 0.001, 4))
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

--- A hull two tiles wide and three long, near enough a tank, and deliberately not square:
--- a square one would hide every mistake that swaps the two axes.
local ACROSS, ALONG = 1, 1.5

--- Where a station is, said in the words the arrangement is written in.
local function at(point, x, y)
  return close(point.x, x * ACROSS) and close(point.y, y * ALONG)
end

local function station(slot, count)
  return pack.hull(slot, count, ACROSS, ALONG)
end

describe("where the arms sit on a hull", function()
  ---Every arm on a hull, as places in the words the arrangement is written in.
  local function places(count)
    local found = {}
    for slot = 1, count do
      local place = station(slot, count)
      table.insert(found, ("%.3f,%.3f"):format(place.x / ACROSS, place.y / ALONG))
    end
    return found
  end

  ---Whether a set of arms is exactly these places, in any order.
  local function holds(count, wanted)
    local seen = {}
    for _, where in ipairs(places(count)) do seen[where] = (seen[where] or 0) + 1 end
    for _, where in ipairs(wanted) do
      if not seen[where] then return false, where .. " is not among " ..
        table.concat(places(count), " ") end
      seen[where] = seen[where] - 1
      if seen[where] == 0 then seen[where] = nil end
    end
    local left = next(seen)
    if left then return false, left .. " was not wanted, out of "
      .. table.concat(places(count), " ") end
    return true
  end

  local RIGHT, LEFT = "1.000,0.000", "-1.000,0.000"
  local BACK_RIGHT, FRONT_RIGHT = "1.000,-1.000", "1.000,1.000"
  local BACK_LEFT, FRONT_LEFT = "-1.000,-1.000", "-1.000,1.000"

  it("puts a lone arm out to the right", function()
    assert.is_true(holds(1, { RIGHT }))
  end)

  it("puts two one a side", function()
    assert.is_true(holds(2, { RIGHT, LEFT }))
  end)

  it("puts three at the middle of the left and both right hand corners", function()
    local ok, why = holds(3, { LEFT, BACK_RIGHT, FRONT_RIGHT })
    assert.is_true(ok, why)
  end)

  it("puts four at the corners", function()
    local ok, why = holds(4, { BACK_LEFT, FRONT_LEFT, BACK_RIGHT, FRONT_RIGHT })
    assert.is_true(ok, why)
  end)

  it("adds the middle of the right side for five", function()
    local ok, why = holds(5, { BACK_LEFT, FRONT_LEFT, BACK_RIGHT, FRONT_RIGHT, RIGHT })
    assert.is_true(ok, why)
  end)

  it("adds the middle of the left side for six", function()
    local ok, why = holds(6, { BACK_LEFT, FRONT_LEFT, BACK_RIGHT, FRONT_RIGHT, RIGHT, LEFT })
    assert.is_true(ok, why)
  end)

  ---Every arm on one side of the hull, from the back corner forward.
  local function side_of(count, which)
    local found = {}
    for slot = 1, count do
      local place = station(slot, count)
      if close(place.x, which * ACROSS) then table.insert(found, place.y / ALONG) end
    end
    table.sort(found)
    return found
  end

  ---Whether a row of arms runs the whole side and is evenly spaced down it.
  local function evenly(row)
    if #row == 1 then return close(row[1], 0), "a lone arm should sit in the middle" end
    if not (close(row[1], -1) and close(row[#row], 1)) then
      return false, "the row does not run from corner to corner"
    end
    local step = 2 / (#row - 1)
    for i = 2, #row do
      if not close(row[i] - row[i - 1], step) then
        return false, ("the gap from %d to %d is %.3f rather than %.3f")
          :format(i - 1, i, row[i] - row[i - 1], step)
      end
    end
    return true
  end

  it("spaces four along the right side, corner to corner, for seven", function()
    local right, left = side_of(7, 1), side_of(7, -1)
    assert.are.equal(4, #right, "the right side should carry four of seven")
    assert.are.equal(3, #left, "the left side should carry three of seven")
    local ok, why = evenly(right)
    assert.is_true(ok, why)
  end)

  it("spaces four along the left side as well for eight", function()
    local right, left = side_of(8, 1), side_of(8, -1)
    assert.are.equal(4, #right)
    assert.are.equal(4, #left)
    local ok, why = evenly(left)
    assert.is_true(ok, why)
  end)

  it("keeps filling the sides in, one side and then the other", function()
    for count = 1, 24 do
      local right, left = side_of(count, 1), side_of(count, -1)
      assert.are.equal(math.ceil(count / 2), #right,
        ("%d arms put %d on the right"):format(count, #right))
      assert.are.equal(math.floor(count / 2), #left,
        ("%d arms put %d on the left"):format(count, #left))
      for _, row in ipairs{ right, left } do
        if #row > 0 then
          local ok, why = evenly(row)
          assert.is_true(ok, ("%d arms: %s"):format(count, why or ""))
        end
      end
    end
  end)

  it("never puts an arm anywhere but on a side", function()
    for count = 1, 24 do
      for slot = 1, count do
        local place = station(slot, count)
        assert.is_true(close(math.abs(place.x), ACROSS),
          ("%d arms put slot %d at %.3f across, which is not on a side")
            :format(count, slot, place.x))
        assert.is_true(math.abs(place.y) <= ALONG + 1e-9,
          ("%d arms put slot %d past the end of the hull"):format(count, slot))
      end
    end
  end)

  it("never puts two arms in the same place", function()
    for count = 1, 24 do
      local seen = {}
      for slot = 1, count do
        local place = station(slot, count)
        local key = ("%.4f,%.4f"):format(place.x, place.y)
        assert.is_nil(seen[key], ("%d arms put two in %s"):format(count, key))
        seen[key] = true
      end
    end
  end)
end)

describe("how much of a lift an arm takes", function()
  it("gives none to an arm on the far side", function()
    assert.are.equal(0, pack.nearness{ x = 0, y = -1 }, "an arm due north took a lift")
    assert.are.equal(0, pack.nearness{ x = 1, y = -1 }, "a far corner took a lift")
  end)

  it("gives none to an arm square on either beam", function()
    assert.is_true(close(pack.nearness{ x = 1, y = 0 }, 0))
    assert.is_true(close(pack.nearness{ x = -1, y = 0 }, 0))
  end)

  it("gives all of it to an arm due south", function()
    assert.is_true(close(pack.nearness{ x = 0, y = 2 }, 1))
  end)

  it("gives a corner its share", function()
    assert.is_true(close(pack.nearness{ x = 1, y = 1 }, math.sqrt(0.5)),
      "a south east corner should take the sine of half a right angle")
  end)

  it("follows the turn as a vehicle comes round", function()
    -- an arm out on the right of a hull, through a whole turn: nothing facing the camera,
    -- all of it facing across, and no jumps in between
    local last = nil
    for step = 0, 32 do
      local mount = pack.mount(step / 2, 1, 1, 1, 1.5)
      local lift = pack.nearness(mount)
      assert.is_true(lift >= 0 and lift <= 1, "a lift outside nothing and all of it")
      if last then
        assert.is_true(math.abs(lift - last) < 0.25,
          ("the lift jumped from %.3f to %.3f"):format(last, lift))
      end
      last = lift
    end
  end)

  it("is nothing for an arm in the middle, where there is no side to be on", function()
    assert.are.equal(0, pack.nearness{ x = 0, y = 0 })
  end)
end)

describe("where a hull's arms end up on the map", function()
  it("puts a lone arm out to the right of a vehicle, whichever way it faces", function()
    for d = 0, 15 do
      local fx, fy = pack.facing(d)
      local mount = pack.mount(d, 1, 1, ACROSS, ALONG)
      -- its right is a quarter turn clockwise from the way it faces, by its own half width
      assert.is_true(close(mount.x, -fy * ACROSS) and close(mount.y, fx * ACROSS),
        ("facing %d put the arm at %.3f,%.3f"):format(d, mount.x, mount.y))
    end
  end)

  it("puts the pair out to the sides, turning with the vehicle", function()
    -- the odd slots go to the right, so the first of a pair is the right hand one; facing
    -- north, its right is east
    local right, left = pack.mount(0, 1, 2, ACROSS, ALONG), pack.mount(0, 2, 2, ACROSS, ALONG)
    assert.is_true(close(right.x, ACROSS) and close(right.y, 0),
      ("facing north, the right hand arm sat at %.3f,%.3f"):format(right.x, right.y))
    assert.is_true(close(left.x, -ACROSS) and close(left.y, 0),
      ("facing north, the left hand arm sat at %.3f,%.3f"):format(left.x, left.y))
    -- facing east, its right is south
    local south = pack.mount(4, 1, 2, ACROSS, ALONG)
    assert.is_true(close(south.x, 0) and close(south.y, ACROSS),
      ("facing east, the right hand arm sat at %.3f,%.3f"):format(south.x, south.y))
  end)

  it("takes a fractional facing, which is what a vehicle has", function()
    local straight = pack.mount(0, 1, 1, ACROSS, ALONG)
    local barely = pack.mount(0.5, 1, 1, ACROSS, ALONG)
    assert.is_true(math.abs(barely.y - straight.y) > 1e-3,
      "half a step round should move the arm")
    assert.is_true(close(math.sqrt(barely.x ^ 2 + barely.y ^ 2), ACROSS),
      "turning should not change how far out the arm sits")
  end)

  it("keeps every arm on the hull it belongs to", function()
    for count = 1, 20 do
      for slot = 1, count do
        for d = 0, 15 do
          local mount = pack.mount(d, slot, count, ACROSS, ALONG)
          local out = math.sqrt(mount.x ^ 2 + mount.y ^ 2)
          assert.is_true(out <= math.sqrt(ACROSS ^ 2 + ALONG ^ 2) + 1e-9,
            ("%d arms slot %d facing %d sat %.3f out"):format(count, slot, d, out))
        end
      end
    end
  end)
end)
