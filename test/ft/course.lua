--- How steady a wearer's course is, tick by tick.
---
--- A lead is held for as long as its owner holds their direction and recalculated when they
--- change it, so "the same direction" is a test the mod has to make every tick rather than a
--- statistic about how long people walk straight. What that test can be made of is a
--- question about what the engine hands back. A course that is the same vector tick after
--- tick can be compared for equality; one that wobbles needs a tolerance, and the tolerance
--- has to come from how far a lead may be wrong before the claw misses.
---
--- Self contained on purpose: it needs a character, a vehicle and the difference between two
--- positions, and nothing else.
local world = require("test.ft.world")

local REPORT = "course.txt"
local first = true

local function note(line)
  helpers.write_file(REPORT, line .. "\n", not first)
  first = false
end

--- Long enough for a character to be at their walking speed and a vehicle at its top one.
local SETTLE = 120
local WATCH = 90

local player

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

after_each(function()
  player.walking_state = { walking = false }
  for _, name in ipairs{ "car", "tank", "spidertron" } do
    for _, vehicle in ipairs(player.surface.find_entities_filtered{
          name = name, position = world.ORIGIN, radius = 500 }) do
      if vehicle.get_driver() then world.unseat(player) end
      vehicle.destroy()
    end
  end
  world.clear(player)
end)

---Where a step points, in degrees clockwise from north, which is how the game counts.
local function bearing(dx, dy)
  return math.deg((math.atan2 or math.atan)(dx, -dy))
end

---Drive for a while, handing every step to a collector.
---@param what LuaEntity whose position to watch
---@param drive fun(since: integer)
---@param ticks integer
---@param each fun(since: integer, dx: number, dy: number)
---@param done fun()
local function drive_for(what, drive, ticks, each, done)
  local previous, began = nil, game.tick
  world.once(function()
    local since = game.tick - began
    drive(since)
    local at = what.position
    if previous then each(since, at.x - previous.x, at.y - previous.y) end
    previous = { x = at.x, y = at.y }
    return since > ticks
  end, done, "the run never ended", ticks + 120)
end

describe("a character's step", function()
  --- All sixteen the engine counts, not the eight anybody would guess: a direction a
  --- character will not walk in is worth knowing about too.
  local WAYS = {
    "north", "northnortheast", "northeast", "eastnortheast",
    "east", "eastsoutheast", "southeast", "southsoutheast",
    "south", "southsouthwest", "southwest", "westsouthwest",
    "west", "westnorthwest", "northwest", "northnorthwest",
  }

  for _, way in ipairs(WAYS) do
    it("is the same every tick going " .. way, function()
      local going = defines.direction[way]
      assert.is_not_nil(going, "no such direction as " .. way)
      local steps, order = {}, {}
      drive_for(player.character, function()
        player.walking_state = { walking = true, direction = going }
      end, WATCH, function(since, dx, dy)
        -- the first few ticks are the character getting under way
        if since <= 10 then return end
        local key = ("%+.7f %+.7f"):format(dx, dy)
        if not steps[key] then steps[key] = 0; order[#order + 1] = key end
        steps[key] = steps[key] + 1
      end, function()
        local parts = {}
        for _, key in ipairs(order) do
          parts[#parts + 1] = ("%s x%d"):format(key, steps[key])
        end
        -- Pulled out rather than written inline: `a and b:match(...)` keeps only the first
        -- of the two the match returns, which read as the character standing still.
        local length, went = 0, 0
        if order[1] then
          local dx, dy = order[1]:match("(%S+) (%S+)")
          dx, dy = tonumber(dx), tonumber(dy)
          length = math.sqrt(dx * dx + dy * dy)
          went = bearing(dx, dy)
        end
        note(("%-16s %d distinct  len %.7f  bearing %+7.2f  %s"):format(
          way, #order, length, went, table.concat(parts, "   ")))
        assert.is_true(#order > 0, "the character never moved going " .. way)
      end)
    end)
  end
end)

describe("a character changing direction", function()
  it("does it between one tick and the next", function()
    local seen = {}
    drive_for(player.character, function(since)
      local going = defines.direction.east
      if since > 75 then going = nil
      elseif since > 50 then going = defines.direction.north
      elseif since > 25 then going = defines.direction.northeast end
      player.walking_state = going and { walking = true, direction = going }
        or { walking = false }
    end, 85, function(since, dx, dy)
      seen[since] = ("  t+%3d  step %+.7f %+.7f  bearing %+7.2f"):format(
        since, dx, dy, (dx == 0 and dy == 0) and 0 or bearing(dx, dy))
    end, function()
      note("")
      note("a character turning east, north east, north, then stopping:")
      for _, edge in ipairs{ 25, 26, 27, 50, 51, 52, 75, 76, 77 } do
        if seen[edge] then note(seen[edge]) end
      end
      assert.is_not_nil(seen[26], "the turn was never seen")
    end)
  end)
end)

describe("a steered vehicle", function()
  for _, name in ipairs{ "car", "tank", "spidertron" } do
    it("wanders its heading while a " .. name .. " is turning", function()
      local vehicle = world.vehicle(player, name)
      vehicle.insert{ name = "nuclear-fuel", count = 5 }
      local straight, turning = {}, {}
      local previous_bearing, previous_facing
      local walked = name == "spidertron"
      drive_for(vehicle, function(since)
        if walked then
          -- A spider is not steered, it is sent somewhere. Moving where it is going is the
          -- only way to make it turn.
          vehicle.autopilot_destination = since > SETTLE
            and { world.ORIGIN.x + 60, world.ORIGIN.y - 400 }
            or { world.ORIGIN.x + 400, world.ORIGIN.y }
        else
          vehicle.riding_state = {
            acceleration = defines.riding.acceleration.accelerating,
            direction = since > SETTLE and defines.riding.direction.left
              or defines.riding.direction.straight,
          }
        end
      end, SETTLE + WATCH, function(since, dx, dy)
        if dx == 0 and dy == 0 then return end
        local now = bearing(dx, dy)
        local turned = previous_bearing and (now - previous_bearing) or 0
        if turned > 180 then turned = turned - 360 elseif turned < -180 then turned = turned + 360 end
        previous_bearing = now
        -- What the engine says the body is doing, against what two positions say. The mod
        -- reads the second, because it is the only answer every kind of wearer gives, so the
        -- gap between them is noise a tolerance has to live above.
        local facing = vehicle.orientation * 360
        local swung = previous_facing and (facing - previous_facing) or 0
        if swung > 180 then swung = swung - 360 elseif swung < -180 then swung = swung + 360 end
        previous_facing = facing
        -- Only once it is up to speed, so that acceleration is not read as a wobble.
        local into = since > SETTLE + 5 and turning
          or (since > SETTLE - 30 and since < SETTLE - 2 and straight or nil)
        if into then
          into[#into + 1] = {
            speed = math.sqrt(dx * dx + dy * dy), turned = turned, swung = swung }
        end
      end, function()
        local function spread(list, what)
          local least, most, sum = math.huge, -math.huge, 0
          for _, one in ipairs(list) do
            local value = one[what]
            least = math.min(least, value); most = math.max(most, value)
            sum = sum + value
          end
          return least, most, sum / math.max(#list, 1)
        end
        local function widest(list, what)
          local least, most, mean = spread(list, what)
          return math.max(math.abs(least), math.abs(most)), mean
        end
        note("")
        for _, run in ipairs{ { "straight", straight }, { "turning", turning } } do
          local list = run[2]
          local s1, s2, s3 = spread(list, "speed")
          local worst, mean = widest(list, "turned")
          local body_worst, body_mean = widest(list, "swung")
          note(("%s %s, %d ticks:"):format(name, run[1], #list))
          note(("   speed %.7f to %.7f, mean %.7f"):format(s1, s2, s3))
          note(("   two positions say: worst %.4f deg a tick, mean %+.4f"):format(worst, mean))
          note(("   the body says:     worst %.4f deg a tick, mean %+.4f"):format(
            body_worst, body_mean))
          note(("   over a 43 tick reach, %.1f degrees by the body"):format(
            math.abs(body_mean) * 43))
        end
        assert.is_true(#turning > 10, name .. " was never seen turning")
      end)
    end)
  end
end)
