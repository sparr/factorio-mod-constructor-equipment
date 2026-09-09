--- The inserter cycle: reach out with the item, put it down, come back.
---
--- These read storage directly, which the fixtures can do because they are required from
--- control.lua and share its environment. The alternative is inferring the state of the
--- swing from what has been built, which says nothing about what the arm is doing partway
--- through.
local world = require("test.ft.world")

local BELT = "transport-belt"
local player

local function job()
  return storage.constructor_reach[player.index]
end

before_each(function()
  player = world.player()
  world.clear(player)
  world.equipped(player)
  player.insert{ name = BELT, count = 10 }
end)

after_each(function()
  storage.constructor_reach[player.index] = nil
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
end)

describe("reaching for a ghost", function()
  it("starts a swing rather than building at once", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(8, function()
      assert.is_not_nil(job(), "no swing was started")
      assert.are.equal("out", job().going)
      assert.are.equal(1, world.ghosts(player), "it built instantly instead of reaching")
      assert.are.equal(10, player.get_item_count(BELT), "it took the item before delivering")
    end)
  end)

  it("carries the item until it gets there", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(world.SWING_TICKS - 4, function()
      assert.is_not_nil(job(), "the swing ended early")
      assert.are.equal(10, player.get_item_count(BELT),
        "the item was taken before the claw arrived")
      assert.are.equal(1, world.ghosts(player), "the ghost went up before the claw arrived")
    end)
  end)

  it("builds it and takes the item on arrival", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.count(player, BELT), "it never arrived")
      assert.are.equal(9, player.get_item_count(BELT), "the item was not taken")
    end)
  end)

  -- the engine brings the empty hand back on its own, and quickly, so this watches for
  -- the return happening at all rather than trying to catch it mid flight
  it("brings the claw home afterwards", function()
    world.ghost(player, BELT, 2, 0)
    local returning = false
    for n = 1, 10 do
      after_ticks(6 + n * 3, function()
        if job() and job().going == "back" then returning = true end
      end)
    end
    after_ticks(world.BUILD_INTERVAL + 20, function()
      assert.are.equal(1, world.count(player, BELT), "it never built, so this proves nothing")
      assert.is_true(returning, "it was never seen coming home")
      assert.is_nil(job(), "the swing never finished")
    end)
  end)

  it("goes again for the next one", function()
    world.ghost(player, BELT, 2, 0)
    world.ghost(player, BELT, -2, 0)
    after_ticks(world.BUILD_INTERVAL * 2 + 20, function()
      assert.are.equal(2, world.count(player, BELT), "only one of the two went up")
    end)
  end)
end)

--- The character can walk off mid swing. An arm that stretched to follow would be no kind
--- of inserter, so it lets go and comes back empty handed.
describe("walking away mid swing", function()
  it("gives up on a ghost that has gone out of reach", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(6, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.ghosts(player), "it built from clear across the map")
      assert.are.equal(10, player.get_item_count(BELT), "it spent the item anyway")
    end)
  end)

  -- the return is quick when it gives up early, so this watches for it never reaching
  -- again rather than trying to catch it on its way home
  it("comes home empty rather than staying stretched out", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(6, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    local still_reaching = false
    for n = 1, 8 do
      after_ticks(6 + n * 3, function()
        if job() and job().going == "out" then still_reaching = true end
      end)
    end
    after_ticks(world.BUILD_INTERVAL + 20, function()
      assert.is_false(still_reaching,
        "it went on reaching after the character had walked away")
      assert.is_nil(job(), "it never finished coming back")
    end)
  end)

  it("picks up where it left off once back in reach", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(6, function()
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    after_ticks(world.BUILD_INTERVAL + 20, function()
      player.teleport(world.ORIGIN, player.surface)
    end)
    after_ticks(world.BUILD_INTERVAL * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never went back for the ghost it gave up on")
    end)
  end)
end)
