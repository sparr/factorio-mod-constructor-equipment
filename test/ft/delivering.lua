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
    for n = 1, 14 do
      after_ticks(world.SWING_TICKS + n * 3, function()
        if job() and job().going == "back" then returning = true end
      end)
    end
    after_ticks(world.CYCLE + 20, function()
      assert.are.equal(1, world.count(player, BELT), "it never built, so this proves nothing")
      assert.is_true(returning, "it was never seen coming home")
      assert.is_nil(job(), "the swing never finished")
    end)
  end)

  it("goes again for the next one", function()
    world.ghost(player, BELT, 2, 0)
    world.ghost(player, BELT, -2, 0)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(2, world.count(player, BELT), "only one of the two went up")
    end)
  end)
end)

--- An inserter will not reach for something underneath its own base. Asked to, it twitches
--- a tick's worth and springs back, and because a swing is under way nothing else gets a
--- look in: standing on a ghost jammed the mod until you moved off, and sometimes after.
describe("a ghost the character is standing on", function()
  it("is left alone rather than reached for", function()
    -- put the character exactly in it, rather than trusting an offset of nothing to land
    -- inside a footprint that snaps to the tile grid
    local ghost = world.ghost(player, BELT, 0, 0)
    player.teleport(ghost.position, player.surface)
    after_ticks(world.BUILD_INTERVAL, function()
      assert.is_nil(job(), "it started a swing for something under its own feet")
      assert.are.equal(1, world.ghosts(player), "it built one it could not reach")
    end)
  end)

  it("does not stop it building anything else", function()
    local underfoot = world.ghost(player, BELT, 0, 0)
    player.teleport(underfoot.position, player.surface)
    world.ghost(player, BELT, 3, 0)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the reachable ghost was never built, so the one underfoot jammed it")
      assert.are.equal(1, world.ghosts(player), "the one underfoot should still be waiting")
    end)
  end)

  it("gets built once the character steps off it", function()
    local ghost = world.ghost(player, BELT, 0, 0)
    player.teleport(ghost.position, player.surface)
    after_ticks(world.BUILD_INTERVAL, function()
      player.teleport({ ghost.position.x - 3, ghost.position.y }, player.surface)
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never went back for the ghost once it could reach it")
    end)
  end)
end)

--- The arm is not worn all the time. It comes out to work and is put away a second after
--- it stops, rather than being carried about while the character wanders.
describe("the arm itself", function()
  it("is out while there is something to build", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.is_not_nil(world.arm(player), "no arm appeared to do the work")
    end)
  end)

  it("is put away once it has had nothing to do for a second", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.CYCLE + 20, function()
      assert.are.equal(1, world.count(player, BELT), "it never built, so this proves nothing")
      assert.is_not_nil(world.arm(player), "it should still be out just after finishing")
    end)
    after_ticks(world.CYCLE + 120, function()
      assert.is_nil(world.arm(player), "the arm was still out with nothing to do")
    end)
  end)

  it("comes back out when something else turns up", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.CYCLE + 120, function()
      assert.is_nil(world.arm(player), "it should have been put away by now")
      world.ghost(player, BELT, -2, 0)
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(2, world.count(player, BELT),
        "it never came back out for the second one")
    end)
  end)

  -- lib.pack works out where the arm sits from the facing, and the unit tier checks that
  -- arithmetic; this checks that control.lua actually asks it, which a mutation showed no
  -- other test did. The arm is an entity, so its position is the mounting point.
  it("sits on whichever side of the character is their back", function()
    world.ghost(player, BELT, 2, 0)
    local facing_north, facing_south
    after_ticks(12, function()
      player.character.direction = defines.direction.north
    end)
    after_ticks(16, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "no arm to measure")
      facing_north = arm.position.y - player.position.y
      player.character.direction = defines.direction.south
    end)
    after_ticks(22, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "the arm went away mid measurement")
      facing_south = arm.position.y - player.position.y
      assert.is_true(facing_north > facing_south,
        ("facing north should put it nearer the camera than facing south: %.3f vs %.3f")
          :format(facing_north, facing_south))
    end)
  end)

  -- One arm, however many of the equipment are worn. Wearing two does nothing at present:
  -- the mod asks whether the equipment is there at all, not how much of it.
  it("is one arm even with two of the equipment worn", function()
    local grid = player.character.grid
    grid.put{ name = "constructor-equipment" }
    world.ghost(player, BELT, 2, 0)
    after_ticks(20, function()
      local arms = player.surface.find_entities_filtered{
        name = "constructor-equipment-inserter", position = player.position, radius = 4 }
      assert.are.equal(1, #arms, "two of the equipment grew a second arm")
    end)
  end)
end)

--- The claw is already out and already holding the right thing, so a ghost that takes the
--- same item is worth turning to rather than going home to fetch an identical one.
describe("giving up on one ghost with another like it in reach", function()
  -- The far ghost goes down first so the swing definitely starts on it, and the second
  -- appears only once the arm is on its way. Stepping east then puts the first out of reach
  -- and leaves the second in it.
  local function start_far_then_offer_near()
    world.ghost(player, BELT, -3.5, 0)
    after_ticks(8, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      world.ghost(player, BELT, 3.5, 0)
      player.teleport({ world.ORIGIN.x + 1.5, world.ORIGIN.y }, player.surface)
    end)
  end

  -- "going back" happens after a successful delivery too, so what matters is the order:
  -- if it turned, something is built before the arm is ever seen coming home.
  it("turns to the other one instead of going home", function()
    start_far_then_offer_near()
    local first = nil
    for n = 1, 20 do
      after_ticks(10 + n * 4, function()
        if first then return end
        if world.count(player, BELT) > 0 then
          first = "built"
        elseif job() and job().going == "back" then
          first = "went home"
        end
      end)
    end
    after_ticks(world.CYCLE * 2 + 40, function()
      assert.are.equal(1, world.count(player, BELT), "it never built the one in reach")
      assert.are.equal("built", first,
        "it went home before building, so it did not turn to the other ghost")
    end)
  end)

  it("keeps hold of the item while it turns", function()
    start_far_then_offer_near()
    local dropped_it = false
    for n = 1, 20 do
      after_ticks(10 + n * 4, function()
        if job() and job().going == "out" and not world.held(player) then
          dropped_it = true
        end
      end)
    end
    after_ticks(world.CYCLE * 2 + 40, function()
      assert.is_false(dropped_it, "it let go of the item while turning to the other ghost")
    end)
  end)

  it("leaves the one it gave up on standing", function()
    start_far_then_offer_near()
    after_ticks(world.CYCLE * 2 + 40, function()
      assert.are.equal(1, world.ghosts(player),
        "the ghost it turned away from should still be waiting")
    end)
  end)
end)

--- A square search reaches 1.41 times as far at its corners as a radius does, and
--- find_entities_filtered returns anything whose own box merely overlaps the area. Between
--- them, a ghost whose centre was well over four tiles away came back as a candidate, was
--- abandoned as out of range on the next tick, and found again on the tick after: the arm
--- swung out and back for ever and nothing in reach ever got a turn.
describe("a ghost just outside the range", function()
  -- 4.4 tiles away, which is what the live case turned out to be: outside a radius of
  -- four, inside a square of four, and with a box that overlaps the square's edge
  local OUT = 4.4

  it("is never reached for", function()
    world.ghost(player, BELT, 0, -OUT)
    after_ticks(world.CYCLE, function()
      assert.is_nil(job(), "it started a swing for something it cannot reach")
      assert.are.equal(1, world.ghosts(player), "it built something out of range")
    end)
  end)

  it("does not stop it building what is in reach", function()
    world.ghost(player, BELT, 0, -OUT)
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the one in reach was never built, so the far one jammed it")
      assert.are.equal(1, world.ghosts(player), "the far one should still be waiting")
    end)
  end)

  it("gets built once the character walks closer", function()
    world.ghost(player, BELT, 0, -OUT)
    after_ticks(world.BUILD_INTERVAL, function()
      player.teleport({ world.ORIGIN.x, world.ORIGIN.y - 2 }, player.surface)
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never built the ghost once it was in reach")
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

  -- The item was conjured into the hand rather than taken from the inventory, so letting
  -- go of it costs nothing -- but it should not wink out of a closed claw halfway across
  -- the ground. It comes back with the arm and is taken out when the arm gets there.
  it("brings the item back in the claw rather than dropping it out of existence", function()
    world.ghost(player, BELT, 3, 0)
    local carried_home = false
    after_ticks(world.SWING_TICKS - 6, function()
      assert.are.equal(BELT, world.held(player), "it was not carrying anything yet")
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    for n = 1, 8 do
      after_ticks(world.SWING_TICKS - 4 + n * 3, function()
        if job() and job().going == "back" and world.held(player) == BELT then
          carried_home = true
        end
      end)
    end
    after_ticks(world.CYCLE * 2, function()
      assert.is_true(carried_home,
        "the claw came home empty, so the item vanished when it gave up")
      assert.is_nil(job(), "the swing never finished")
      assert.is_nil(world.held(player), "the item should be out of the hand by now")
      assert.are.equal(10, player.get_item_count(BELT), "nothing should have been spent")
    end)
  end)

  it("does not leave the carried item on the ground", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(world.SWING_TICKS - 6, function()
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    after_ticks(world.CYCLE * 2, function()
      local dropped = player.surface.count_entities_filtered{ name = "item-on-ground" }
      assert.are.equal(0, dropped, "it put the item it gave up on down on the ground")
    end)
  end)

  it("picks up where it left off once back in reach", function()
    world.ghost(player, BELT, 3, 0)
    after_ticks(6, function()
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    after_ticks(world.CYCLE, function()
      player.teleport(world.ORIGIN, player.surface)
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never went back for the ghost it gave up on")
    end)
  end)
end)
