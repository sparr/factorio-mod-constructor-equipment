--- A ghost aimed at rather than cut off.
---
--- Leading is for things out of reach, and something already in reach when an arm sets off is
--- not one: with nobody moving, the point to hold the claw on is the ghost itself, so
--- course_to() says so and works no lead out at all. What that answer does not cover is its
--- owner walking off a moment later. The ghost is then a moving target like any other, and
--- one still aimed at directly is chased round rather than cut off.
---
--- A first tier arm because it is the plainest case: its hand extends 0.035 of a tile a tick
--- against a walk of 0.148, so a target it does not cut off it cannot catch at all. Measured
--- before it was fixed, on a belt two tiles ahead: the claw closed to 0.086 of the drop and
--- never arrived. The belt was swept in past the arm's own base and out behind it while the
--- hand was two tenths of a tile into its stretch, and the reach was written off twenty seven
--- ticks later with nothing built.
---
--- Which of the two comes first -- the arm setting off or the walk beginning -- is what
--- decides whether it happens, and nothing a player does decides that: control.lua hands work
--- out ten times a second, so a walk lands on one of six phases against it. Only the phases
--- where the arm sets off first show this, so the walk is started from each of them in turn
--- and a single unphased run would find it one time in six.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
local FIRST = tiers.by_level[1]

--- How often control.lua hands work out, from CHECK_PER_SECOND there.
local CHECK_INTERVAL = 6

--- Long enough for the walk to carry its owner well past the belt, and for the arm to have
--- given up on it if it is going to.
local A_WALK = 30

local player

before_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
  world.equip(player, { FIRST.name, "battery-equipment" }, true)
  player.insert{ name = BELT, count = 5 }
end)

after_each(function()
  player.walking_state = { walking = false }
  world.clear(player)
end)

describe("a ghost in reach when its owner starts walking", function()
  ---@param phase integer which phase of the check tick the walk begins on
  ---@param done fun()
  local function walk_off_from_phase(phase, done)
    world.ghost(player, BELT, 2, 0)
    local began = nil
    world.once(function()
      if not began then
        if game.tick % CHECK_INTERVAL ~= phase then return false end
        began = game.tick
      end
      local since = game.tick - began
      player.walking_state = { walking = since < A_WALK, direction = defines.direction.east }
      return since > A_WALK * 2
    end, function()
      player.walking_state = { walking = false }
      done()
    end, "the walk never ended", A_WALK * 4 + CHECK_INTERVAL)
  end

  for phase = 0, CHECK_INTERVAL - 1 do
    it(("is built though its owner walks over it, from phase %d"):format(phase), function()
      walk_off_from_phase(phase, function()
        assert.are.equal(1, world.count(player, BELT),
          "a belt two tiles ahead of a walk was never built")
        assert.are.equal(4, player.get_item_count(BELT), "it was not paid for out of pocket")
      end)
    end)
  end
end)
