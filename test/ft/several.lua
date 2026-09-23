--- More than one of the equipment, and so more than one arm.
---
--- Each copy is a whole arm of its own: its own inserter on the character's back, its own
--- clock, and its own ghost to reach for. Two of them really are twice the building rather
--- than two arms taking turns at one arm's rate.
local world = require("test.ft.world")

local BELT = "transport-belt"
--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- check cycle it started on. Built on the swing rather than on world.BUILD_INTERVAL, which
--- is a leftover from when the mod capped its own build rate and has nothing to do with how
--- long a reach takes: two of those intervals is sixty ticks, and a first tier arm reaching
--- the edge of its two tiles wants up to sixty three.
local A_BUILD = world.DELIVERED

local player
local two_arms

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("two of the equipment", function()
  before_each(function()
    world.equipped_with(player, 2)
    player.insert{ name = BELT, count = 20 }
  end)

  it("grows two arms", function()
    world.several(player, BELT, 4)
    after_ticks(12, function()
      assert.are.equal(2, #world.arms(player), "two of the equipment did not grow two arms")
    end)
  end)

  it("puts them side by side rather than on top of each other", function()
    world.several(player, BELT, 4)
    after_ticks(12, function()
      local arms = world.arms(player)
      assert.are.equal(2, #arms, "there should be two arms to compare")
      local apart = math.sqrt((arms[1].position.x - arms[2].position.x) ^ 2
                            + (arms[1].position.y - arms[2].position.y) ^ 2)
      assert.is_true(apart > 0.2,
        ("the two arms are mounted %.3f tiles apart, which is the same spot"):format(apart))
    end)
  end)

  it("reaches for two different ghosts at once", function()
    world.several(player, BELT, 4)
    local both = false
    for n = 2, 40, 2 do
      after_ticks(n, function()
        -- Only while both are still on their way out. A job that has delivered is still a
        -- job -- the claw has to come home -- but it has let go of its ghost by then, so
        -- there would be nothing left to compare.
        local first, second = world.job(player, 1), world.job(player, 2)
        if first and second and first.going == "out" and second.going == "out" then
          assert.is_not_nil(first.ghost, "the first arm is reaching for nothing")
          assert.is_not_nil(second.ghost, "the second arm is reaching for nothing")
          assert.are_not.equal(first.ghost.unit_number, second.ghost.unit_number,
            "both arms went for the same ghost")
          both = true
        end
      end)
    end
    after_ticks(45, function()
      assert.is_true(both, "the two arms were never both reaching at once")
    end)
  end)

  it("builds more in the same time than one arm does", function()
    world.several(player, BELT, 10)
    after_ticks(A_BUILD + 10, function()
      two_arms = world.count(player, BELT)
      assert.is_true(two_arms > 0, "two arms built nothing at all")
    end)
  end)
end)

--- What one arm manages on its own, for the pair above to be measured against. The rate
--- is the claw's own now rather than a number the mod picks, so the two are compared
--- against each other rather than against an absolute.
describe("one of the equipment", function()
  it("builds less than two of them do", function()
    world.equipped_with(player, 1)
    player.insert{ name = BELT, count = 40 }
    world.several(player, BELT, 10)
    after_ticks(A_BUILD + 10, function()
      local one_arm = world.count(player, BELT)
      assert.is_true(one_arm > 0, "one arm built nothing at all")
      assert.is_not_nil(two_arms, "the two arm measurement never ran")
      assert.is_true(two_arms > one_arm,
        ("two arms built %d where one built %d"):format(two_arms, one_arm))
    end)
  end)
end)

describe("taking one of two copies out", function()
  before_each(function()
    world.equipped_with(player, 2)
    player.insert{ name = BELT, count = 20 }
  end)

  it("takes one arm away and leaves the other", function()
    world.several(player, BELT, 6)
    after_ticks(12, function()
      assert.are.equal(2, #world.arms(player), "there should be two arms to start with")
      assert.is_true(world.unequip(player, "constructor-equipment"), "nothing was taken out")
    end)
    after_ticks(20, function()
      assert.are.equal(1, #world.arms(player), "taking one copy out left both arms on")
    end)
  end)

  it("leaves the other one building", function()
    world.several(player, BELT, 6)
    local built
    after_ticks(12, function()
      world.unequip(player, "constructor-equipment")
      built = world.count(player, BELT)
    end)
    after_ticks(A_BUILD * 3, function()
      assert.is_true(world.count(player, BELT) > built,
        "nothing was built after one of the two copies came out")
    end)
  end)
end)

--- lib.pack works out the arrangement and the unit tier checks that arithmetic. This is
--- here to check control.lua actually tells it which arm is which and how many there are,
--- which nothing else does once there are more than two: with two, getting the slots the
--- wrong way round looks exactly the same.
describe("three of the equipment", function()
  local pack = require("lib.pack")

  it("mounts them as a triangle on the back", function()
    -- a modular armour's grid only takes two of them
    world.equipped_with(player, 3, "power-armor")
    player.insert{ name = BELT, count = 20 }
    world.several(player, BELT, 6)
    -- facing north, so the shoulders are level and the drop is straight down the screen
    player.character.direction = defines.direction.north
    after_ticks(14, function()
      local arms = world.arms(player)
      assert.are.equal(3, #arms, "three of the equipment did not grow three arms")

      -- The engine keeps entity positions to a 256th of a tile, so a measured position
      -- can be half of that out from the one that was asked for.
      local FINE = 1 / 64
      local function near(a, b)
        return math.abs(a.x - b.x) < FINE and math.abs(a.y - b.y) < FINE
      end

      -- every one of the three places lib.pack lays out is occupied, which is what says
      -- control.lua is telling it both which arm this is and how many there are: passing
      -- a count of one would stack all three in the middle of the back
      for slot = 1, 3 do
        local offset = pack.offset(player.character.direction, slot, 3)
        local wanted = {
          x = player.position.x + offset.x,
          y = player.position.y + offset.y,
        }
        local found = false
        for _, arm in pairs(arms) do
          if near(arm.position, wanted) then found = true end
        end
        assert.is_true(found,
          ("nothing is mounted at slot %d of three, %.3f,%.3f"):format(
            slot, wanted.x, wanted.y))
      end

      -- and said the readable way round: two level on the shoulders, one centred below
      local at = {}
      for _, arm in pairs(arms) do
        table.insert(at, {
          x = arm.position.x - player.position.x,
          y = arm.position.y - player.position.y,
        })
      end
      table.sort(at, function(a, b) return a.y < b.y end)
      local left, right, low = at[1], at[2], at[3]
      if left.x > right.x then left, right = right, left end
      assert.is_true(math.abs(left.y - right.y) < FINE,
        ("the two shoulder arms are not level: %.3f and %.3f"):format(left.y, right.y))
      assert.is_true(left.x < 0 and right.x > 0,
        "the shoulder arms are not either side of the middle of the back")
      assert.is_true(low.y > left.y + FINE, "the third arm is not below the other two")
      assert.is_true(math.abs(low.x) < FINE,
        ("the third arm is not centred: %.3f"):format(low.x))
    end)
  end)

  it("has all three of them building", function()
    world.equipped_with(player, 3, "power-armor")
    player.insert{ name = BELT, count = 20 }
    world.several(player, BELT, 6)
    local most = 0
    for n = 6, 40, 2 do
      after_ticks(n, function()
        if world.working(player) > most then most = world.working(player) end
      end)
    end
    after_ticks(45, function()
      assert.are.equal(3, most, "only " .. most .. " of the three arms ever had work")
    end)
  end)
end)

--- Somebody else's arms are arms too.
---
--- What each arm is reaching for used to be gathered from one wearer's own list, so nothing
--- stopped two players standing over the same ghost both sending a claw to it: one of them
--- builds it and the other carries its load all the way home for nothing.
---
--- There is no making a second player in the harness -- a player comes from a connection --
--- so the other wearer is stood up in storage instead. That is all the gathering reads of
--- one: a record with a job holding a ghost.
describe("a ghost somebody else's arm has claimed", function()
  local ELSEWHERE = 99
  local MINE = { world.SPOTS[1][1], world.SPOTS[1][2] }
  local THEIRS = { world.SPOTS[2][1], world.SPOTS[2][2] }

  before_each(function()
    world.equipped_with(player, 1)
    player.insert{ name = BELT, count = 20 }
  end)

  after_each(function()
    storage.constructor_arms[ELSEWHERE] = nil
  end)

  it("is left alone until the claim goes", function()
    local spoken_for = world.ghost(player, BELT, THEIRS[1], THEIRS[2])
    storage.constructor_arms[ELSEWHERE] = { { job = { ghost = spoken_for } } }
    after_ticks(world.CYCLE, function()
      assert.is_true(spoken_for.valid,
        "an arm built a ghost another player's arm was already reaching for")
      storage.constructor_arms[ELSEWHERE] = nil
    end)
    after_ticks(world.CYCLE * 2, function()
      assert.is_false(spoken_for.valid,
        "the ghost was still standing after the other player's claim went, so it was not"
        .. " the claim keeping the arm off it")
    end)
  end)

  it("sends the arm to another one rather than nothing", function()
    local spoken_for = world.ghost(player, BELT, THEIRS[1], THEIRS[2])
    local free = world.ghost(player, BELT, MINE[1], MINE[2])
    storage.constructor_arms[ELSEWHERE] = { { job = { ghost = spoken_for } } }
    after_ticks(world.DELIVERED, function()
      assert.is_false(free.valid, "the arm did not build the ghost nobody had claimed")
      assert.is_true(spoken_for.valid, "the arm built the claimed ghost as well")
    end)
  end)
end)
