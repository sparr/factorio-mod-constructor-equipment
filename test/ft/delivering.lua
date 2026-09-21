--- The inserter cycle: reach out with the item, put it down, come back.
---
local world = require("test.ft.world")
local tiers = require("lib.tiers")
--- Skipped wholesale while the walking penalty is switched off, rather than deleted: the
--- switch is meant to be flipped back. See tiers.SLOWS.
local slowed_describe = tiers.SLOWS and describe or describe.skip
local slowed_it = tiers.SLOWS and it or it.skip

local BELT = "transport-belt"
local player

local function job()
  return world.job(player)
end

before_each(function()
  player = world.player()
  world.clear(player)
  world.equipped(player)
  player.insert{ name = BELT, count = 10 }
end)

after_each(function()
  storage.constructor_arms[player.index] = nil
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
    end)
  end)

  --- Paid for on the way out rather than on arrival. The claw is loaded out of the
  --- character's pockets, so the item leaves them when the arm sets off and is in the claw
  --- for the whole journey. Nothing is created and nothing is destroyed on the way: what
  --- the pockets lose, the claw holds.
  it("takes the item into the claw when it sets off", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(8, function()
      assert.are.equal(9, player.get_item_count(BELT),
        "the item should have been taken when the claw was loaded")
      local arm = world.arms(player)[1]
      assert.is_true(arm and arm.held_stack.valid_for_read,
        "the claw should be holding what the pockets lost")
      assert.are.equal(BELT, arm.held_stack.name)
    end)
  end)

  it("carries the item until it gets there", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.SWING_TICKS - 4, function()
      assert.is_not_nil(job(), "the swing ended early")
      assert.are.equal(1, world.ghosts(player), "the ghost went up before the claw arrived")
      local arm = world.arms(player)[1]
      assert.is_true(arm and arm.held_stack.valid_for_read,
        "the claw let go of the item before it arrived")
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
--- Standing on a ghost is not by itself a reason to leave it alone. What decides it is
--- whether the thing that would be built collides with whoever is standing there: a belt
--- does not, and goes up under you exactly as a construction robot would put it up, while a
--- chest does and has to wait until you move.
describe("a ghost the character is standing on", function()
  it("is built when it would not collide with them", function()
    -- put the character exactly in it, rather than trusting an offset of nothing to land
    -- inside a footprint that snaps to the tile grid
    local ghost = world.ghost(player, BELT, 0, 0)
    player.teleport(ghost.position, player.surface)
    assert.is_true(player.surface.can_place_entity{
      name = BELT, position = ghost.position, direction = ghost.direction,
      force = player.force,
      build_check_type = defines.build_check_type.ghost_revive },
      "a belt under a character is not placeable after all, so this proves nothing")
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the belt it was standing on was never built")
      assert.are.equal(0, world.ghosts(player), "it is still a ghost")
    end)
  end)

  it("builds both the one underfoot and the one beside it", function()
    local underfoot = world.ghost(player, BELT, 0, 0)
    player.teleport(underfoot.position, player.surface)
    world.ghost(player, BELT, 1, 0)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(2, world.count(player, BELT),
        "one of the two was left standing as a ghost")
      assert.are.equal(0, world.ghosts(player), "something is still a ghost")
    end)
  end)

  it("is left alone when it would collide with them", function()
    local ghost = player.surface.create_entity{ name = "entity-ghost",
      inner_name = "iron-chest", position = world.ORIGIN, force = player.force }
    assert.is_not_nil(ghost, "could not place a chest ghost")
    player.insert{ name = "iron-chest", count = 5 }
    player.teleport(ghost.position, player.surface)
    after_ticks(world.BUILD_INTERVAL, function()
      assert.is_nil(job(), "it started a swing for a chest it was standing in")
      assert.are.equal(1, world.ghosts(player), "it built one it could not")
    end)
  end)

  it("builds the colliding one once the character steps off it", function()
    local ghost = player.surface.create_entity{ name = "entity-ghost",
      inner_name = "iron-chest", position = world.ORIGIN, force = player.force }
    player.insert{ name = "iron-chest", count = 5 }
    player.teleport(ghost.position, player.surface)
    after_ticks(world.BUILD_INTERVAL, function()
      player.teleport({ ghost.position.x - 1.5, ghost.position.y }, player.surface)
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, player.surface.count_entities_filtered{ name = "iron-chest",
        position = world.ORIGIN, radius = 5 },
        "it never went back for the chest once it could build it")
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
    local AWAY = world.CYCLE + 120
    world.ghost(player, BELT, 2, 0)
    after_ticks(AWAY, function()
      assert.is_nil(world.arm(player), "it should have been put away by now")
      world.ghost(player, BELT, -2, 0)
    end)
    -- after_ticks counts from the start of the test, so this has to be past the offset
    -- above rather than merely a few cycles long
    after_ticks(AWAY + world.CYCLE * 2, function()
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

  it("is one arm for one of the equipment", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(20, function()
      assert.are.equal(1, #world.arms(player), "one of the equipment grew more than one arm")
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
    world.ghost(player, BELT, -1.75, 0)
    after_ticks(8, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      world.ghost(player, BELT, 1.75, 0)
      -- three quarters of a tile east leaves the first 2.5 tiles off and the second one
      player.teleport({ world.ORIGIN.x + 0.75, world.ORIGIN.y }, player.surface)
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
  -- Two tiles out and one across: 2.24 tiles away, so outside a radius of two and well
  -- inside a square of it. A ghost snaps to the middle of a tile, so the only way to land
  -- just outside a whole number of tiles is to go diagonally. The live case was 4.4 tiles
  -- against a range of four.
  local OUT = { 2, -1 }

  it("is never reached for", function()
    world.ghost(player, BELT, OUT[1], OUT[2])
    after_ticks(world.CYCLE, function()
      assert.is_nil(job(), "it started a swing for something it cannot reach")
      assert.are.equal(1, world.ghosts(player), "it built something out of range")
    end)
  end)

  it("does not stop it building what is in reach", function()
    world.ghost(player, BELT, OUT[1], OUT[2])
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "the one in reach was never built, so the far one jammed it")
      assert.are.equal(1, world.ghosts(player), "the far one should still be waiting")
    end)
  end)

  it("gets built once the character walks closer", function()
    world.ghost(player, BELT, OUT[1], OUT[2])
    after_ticks(world.BUILD_INTERVAL, function()
      player.teleport({ world.ORIGIN.x + 1, world.ORIGIN.y }, player.surface)
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
    world.ghost(player, BELT, 2, 0)
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
    world.ghost(player, BELT, 2, 0)
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
    world.ghost(player, BELT, 2, 0)
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
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.SWING_TICKS - 6, function()
      player.teleport({ world.ORIGIN.x + 25, world.ORIGIN.y }, player.surface)
    end)
    after_ticks(world.CYCLE * 2, function()
      local dropped = player.surface.count_entities_filtered{ name = "item-on-ground" }
      assert.are.equal(0, dropped, "it put the item it gave up on down on the ground")
    end)
  end)

  it("picks up where it left off once back in reach", function()
    world.ghost(player, BELT, 2, 0)
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

--- The equipment can come out of the armour mid reach, with the claw halfway to a ghost
--- and an item in it. Nothing is owed either way: the item in the claw was conjured there
--- rather than taken from the inventory, and it is only debited on arrival, so an arm that
--- never arrives has cost its owner nothing at all.
describe("taking the equipment off mid delivery", function()
  local function reaching_then_stripped()
    world.ghost(player, BELT, 2, 0)
    after_ticks(8, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      assert.are.equal(BELT, world.held(player), "the claw was not carrying anything yet")
      assert.is_true(world.unequip(player, "constructor-equipment"),
        "there was no equipment to take out")
    end)
  end

  it("takes the arm away at once", function()
    reaching_then_stripped()
    after_ticks(10, function()
      assert.is_nil(world.arm(player), "the arm stayed on after the equipment came out")
      assert.is_nil(job(), "it is still reaching for something it can no longer build")
    end)
  end)

  it("leaves the ghost standing", function()
    reaching_then_stripped()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.ghosts(player), "it finished the build anyway")
      assert.are.equal(0, world.count(player, BELT))
    end)
  end)

  it("costs the character nothing", function()
    reaching_then_stripped()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(10, player.get_item_count(BELT),
        "the item in the claw was charged for a delivery that never happened")
    end)
  end)

  it("does not leave the item it was carrying on the ground", function()
    reaching_then_stripped()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, player.surface.count_entities_filtered{ name = "item-on-ground" },
        "the claw dropped what it was holding when the equipment came out")
    end)
  end)

  slowed_it("gives the character their speed back", function()
    local full = player.character_running_speed
    reaching_then_stripped()
    after_ticks(10, function()
      assert.is_true(player.character_running_speed < full,
        "the character was never slowed, so this proves nothing")
    end)
    after_ticks(world.CYCLE * 4, function()
      assert.is_nil(world.slowed_by(player),
        "the character is still slowed by equipment they are not wearing")
      assert.are.equal(full, player.character_running_speed,
        "the character never got their walking speed back")
    end)
  end)

  it("comes back if the equipment goes back in", function()
    reaching_then_stripped()
    after_ticks(20, function()
      player.character.grid.put{ name = "constructor-equipment" }
      for _, equipment in pairs(player.character.grid.equipment) do
        equipment.energy = equipment.max_energy
      end
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never built the ghost once the equipment was back on")
    end)
  end)
end)

--- The character can spend the item while the claw is halfway to a ghost holding one of
--- their own. Nothing is owed either way: the item in the claw was conjured there, and the
--- inventory is only debited on arrival, so the worst that can happen is a wasted swing.
--- Spending everything while a claw is on its way out.
---
--- This used to cancel the delivery: the item was only charged on arrival, so emptying the
--- pockets left nothing to pay with and the claw brought its load home. It is charged when
--- the claw is loaded now, so what it is carrying has already been bought and the ghost it
--- was sent to still goes up. What emptying the pockets stops is the next journey, not the
--- one already under way.
describe("spending everything mid delivery", function()
  local function reaching_then_broke()
    world.ghost(player, BELT, 2, 0)
    after_ticks(8, function()
      assert.is_not_nil(job(), "nothing was reaching, so this proves nothing")
      assert.are.equal(BELT, world.held(player), "the claw was not carrying anything yet")
      player.remove_item{ name = BELT, count = 100 }
      assert.are.equal(0, player.get_item_count(BELT), "the inventory was not emptied")
    end)
  end

  it("still builds the one it is carrying, because it is paid for", function()
    reaching_then_broke()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, world.ghosts(player), "the ghost it had already paid for is still standing")
      assert.are.equal(1, world.count(player, BELT), "the belt was never built")
    end)
  end)

  it("does not put the item back in the pockets", function()
    reaching_then_broke()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, player.get_item_count(BELT),
        "an item that went into a ghost came back to the pockets as well")
    end)
  end)

  it("leaves nothing on the ground", function()
    reaching_then_broke()
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(0, player.surface.count_entities_filtered{ name = "item-on-ground" },
        "something ended up on the floor")
    end)
  end)

  it("starts nothing new once the pockets are empty", function()
    reaching_then_broke()
    after_ticks(4, function() world.ghost(player, BELT, -2, 0) end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.ghosts(player),
        "it set off for a second ghost with nothing to pay for it")
    end)
  end)
end)

describe("walking while the arm is reaching", function()
  local EAST, WEST = defines.direction.east, defines.direction.west

  --- Back and forth rather than off in one direction. A character walks about a seventh of
  --- a tile a tick, so a hundred ticks of walking east is fifteen tiles and the ghost is
  --- simply left behind: what is wanted here is a base that keeps moving, not one that
  --- leaves.
  ---
  --- Written every tick, because walking_state is what the character is doing this tick
  --- rather than a standing order: set once, it moves them for one tick and then they
  --- stop. Setting it every eighth tick looked like walking and was standing still.
  local TURN = 8
  local function pace(from, to)
    for n = from, to do
      after_ticks(n, function()
        local way = math.floor((n - from) / TURN) % 2 == 0 and EAST or WEST
        player.walking_state = { walking = true, direction = way }
      end)
    end
    after_ticks(to + 1, function()
      player.walking_state = { walking = false, direction = EAST }
    end)
  end

  before_each(function()
    -- The third tier, for room to move about without putting the ghost out of reach. The
    -- armour goes back on from scratch: the outer fixture has already put a first tier one
    -- on, and a 3x5 will not fit in a modular armour beside it.
    world.clear(player)
    world.equip(player, { "constructor-equipment-3", "battery-equipment" }, true)
    player.insert{ name = BELT, count = 10 }
  end)

  after_each(function()
    player.walking_state = { walking = false, direction = EAST }
  end)

  it("still delivers", function()
    world.ghost(player, BELT, 0, -2)
    pace(4, 60)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "nothing was built while the character was walking")
      assert.are.equal(9, player.get_item_count(BELT), "the item was not taken")
    end)
  end)

  it("brings the claw home again rather than leaving the arm out", function()
    world.ghost(player, BELT, 0, -2)
    pace(4, 60)
    after_ticks(world.CYCLE * 2 + 90, function()
      assert.is_nil(world.job(player), "the swing never finished")
      assert.is_nil(world.arm(player), "the arm never went away")
      assert.are.equal(0, player.surface.count_entities_filtered{ name = "item-on-ground" },
        "something was dropped on the ground")
    end)
  end)

  it("keeps going through a run of them", function()
    world.several(player, BELT, 6)
    pace(4, 130)
    after_ticks(150, function()
      assert.is_true(world.count(player, BELT) >= 3,
        "only " .. world.count(player, BELT) .. " went up while the character walked")
    end)
  end)
end)

--- Walking onto the thing being built.
---
--- An inserter will not reach for something underneath its own base, so a ghost the
--- character is standing in is passed over when work is handed out. It has to be asked
--- again every tick of the swing: walking onto the target mid reach is every bit as final
--- as walking away from it, and the claw would otherwise sit over it trying and failing
--- until the swing limit gave up on its own.
describe("walking onto the ghost being built", function()
  it("gives up when what it was reaching for can no longer go up", function()
    -- a chest, because a belt would simply be built: standing on one does not stop it
    local ghost = player.surface.create_entity{ name = "entity-ghost",
      inner_name = "iron-chest", position = { world.ORIGIN.x + 2, world.ORIGIN.y },
      force = player.force }
    player.insert{ name = "iron-chest", count = 10 }
    local target = ghost.position
    after_ticks(10, function()
      assert.is_not_nil(world.job(player), "nothing was reaching, so this proves nothing")
      player.teleport(target, player.surface)
    end)
    after_ticks(24, function()
      local job = world.job(player)
      assert.is_true(job == nil or job.going == "back",
        "it was still reaching for the chest it was standing in")
    end)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.ghosts(player), "it built the one under its own feet")
      assert.are.equal(10, player.get_item_count("iron-chest"), "it spent the item anyway")
    end)
  end)

  it("goes back for it once the character steps off", function()
    local ghost = world.ghost(player, BELT, 2, 0)
    local target = ghost.position
    after_ticks(10, function() player.teleport(target, player.surface) end)
    after_ticks(40, function()
      player.teleport({ target.x - 1.5, target.y }, player.surface)
    end)
    after_ticks(40 + world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, BELT),
        "it never went back for the ghost once it could reach it again")
    end)
  end)
end)

--- Standing on something with a small collision box.
---
--- A medium electric pole takes up a whole tile and collides across about a third of one,
--- so a character standing a fifth of a tile off its centre is outside its box while still
--- squarely in its way. Judged by the box, the arm reached for a ghost directly beneath
--- itself, failed, sprang back and tried again for as long as the player stood there.
---
--- Two things were wrong. The footprint is the tiles the thing will occupy, not its
--- collision box. And a ghost that cannot be built where it stands should not be reached
--- for at all, whatever the reason: standing merely near a pole is enough to stop it going
--- up, and that is a case a player walks into constantly.
describe("a ghost the character is in the way of", function()
  local POLE = "medium-electric-pole"

  local function pole_at(dx, dy)
    local ghost = player.surface.create_entity{
      name = "entity-ghost", inner_name = POLE,
      position = { world.ORIGIN.x + dx, world.ORIGIN.y + dy }, force = player.force }
    assert(ghost, "could not place a pole ghost")
    return ghost
  end

  before_each(function()
    player.insert{ name = POLE, count = 10 }
  end)

  -- A pole is the awkward case: it takes a whole tile and collides across about a third of
  -- one, so how far off centre a character stands decides whether they are really in its
  -- way. The mod follows the engine on that rather than keeping an opinion of its own, so
  -- what each offset should do is asked of the engine here rather than written down.
  for _, off in ipairs{ 0, 0.2, 0.35, 0.49 } do
    it(("does what the engine allows, stood %.2f off centre"):format(off), function()
      local ghost = pole_at(1, 0)
      player.teleport({ ghost.position.x - off, ghost.position.y }, player.surface)
      local allowed = player.surface.can_place_entity{
        name = POLE, position = ghost.position, direction = ghost.direction,
        force = player.force,
        build_check_type = defines.build_check_type.ghost_revive }
      local reached = 0
      for n = 4, 120, 2 do
        after_ticks(n, function()
          local job = world.job(player)
          if job and job.going == "out" then reached = reached + 1 end
        end)
      end
      after_ticks(130, function()
        if allowed then
          assert.are.equal(0, world.ghosts(player),
            ("the engine allows a pole %.2f off centre and it was not built"):format(off))
        else
          assert.are.equal(0, reached,
            ("it reached for a pole it was standing in, %.2f off centre, on %d samples")
              :format(off, reached))
          assert.are.equal(1, world.ghosts(player), "it built one it was standing in")
        end
      end)
    end)
  end

  -- The footprint test only knows about the character. Anything else can be in the way
  -- too, and reaching for a ghost that cannot go up is the same wasted journey repeating:
  -- out, fail to revive, home, pick the same one again.
  it("is left alone when something else is in the way", function()
    local ghost = pole_at(2, 0)
    local tree = player.surface.create_entity{
      name = "tree-01", position = ghost.position }
    assert.is_not_nil(tree, "no tree to block it with")
    assert.is_false(
      player.surface.can_place_entity{
        name = POLE, position = ghost.position, direction = ghost.direction,
        force = player.force,
        build_check_type = defines.build_check_type.ghost_revive },
      "the tree is not actually in the way, so this proves nothing")
    local reached = 0
    for n = 4, 120, 2 do
      after_ticks(n, function()
        local job = world.job(player)
        if job and job.going == "out" then reached = reached + 1 end
      end)
    end
    after_ticks(130, function()
      assert.are.equal(0, reached,
        "it reached for a pole it could not build, on " .. reached .. " samples")
      assert.are.equal(1, world.ghosts(player), "the pole should still be waiting")
    end)
  end)

  it("goes for it once the way is clear", function()
    local ghost = pole_at(2, 0)
    local tree = player.surface.create_entity{
      name = "tree-01", position = ghost.position }
    after_ticks(30, function()
      assert.are.equal(1, world.ghosts(player), "it built through the tree")
      tree.destroy()
    end)
    after_ticks(30 + world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, POLE),
        "it never went for the pole once the tree was gone")
    end)
  end)

  it("is built once the character is out of its way", function()
    local ghost = pole_at(2, 0)
    -- far enough that the character's own body is not in the pole's space
    player.teleport(world.ORIGIN, player.surface)
    after_ticks(world.CYCLE * 2, function()
      assert.are.equal(1, world.count(player, POLE),
        "a pole two tiles off, with nothing in the way, was never built")
    end)
  end)
end)

--- Stowing the arm.
---
--- It used to vanish the instant it ran out of work, which read as a glitch rather than as
--- something being put away. The entity still goes at once -- an entity's sprites are
--- scaled in its prototype and nothing changes that at runtime -- but a drawn copy of the
--- folded claw is left in its place for a fifth of a second, shrinking and fading, and a
--- drawn sprite takes its scale and tint from script.
describe("putting the arm away", function()
  ---Every claw currently shrinking away, by the mod's own reckoning.
  local function stowing()
    local n = 0
    for _ in pairs(storage.constructor_stowing or {}) do n = n + 1 end
    return n
  end

  it("leaves a claw shrinking behind it", function()
    world.ghost(player, BELT, 2, 0)
    local seen, smallest = 0, 99
    for n = world.CYCLE, world.CYCLE + 140, 2 do
      after_ticks(n, function()
        for id in pairs(storage.constructor_stowing or {}) do
          local drawn = rendering.get_object_by_id(id)
          if drawn and drawn.valid then
            seen = seen + 1
            smallest = math.min(smallest, drawn.x_scale)
          end
        end
      end)
    end
    after_ticks(world.CYCLE + 150, function()
      assert.is_true(seen > 0, "nothing was ever drawn in the arm's place")
      assert.is_true(smallest < 0.1,
        ("the claw only shrank to %.3f before it went"):format(smallest))
    end)
  end)

  it("clears the drawing away afterwards", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.CYCLE + 200, function()
      assert.are.equal(0, stowing(),
        stowing() .. " claws were left behind, still being stowed")
      assert.are.equal(0, #rendering.get_all_objects("constructor-equipment"),
        "the mod left drawings on the map")
    end)
  end)
end)

-- A bulk claw carrying several and handing them out one ghost at a time, at the distances
-- the showroom uses. The walk round reported it building one, turning to the next and
-- coming home without building that one, over and over. Part of that was a yard fault --
-- two of the five ghosts sat at 5.39 tiles from a five tile arm -- and part of it was real:
-- the claw did turn to the next ghost and did then go all the way home before reaching it,
-- because an inserter that has just let go swings back to its pickup before it will look at
-- a new drop. Measured on the showroom's own save, a round of three cost 55 ticks a ghost
-- where it now costs 5.
--
-- Counting what went up cannot see that: the claw built every one of them either way, only
-- slowly. So the round is timed as well as counted.
describe("a bulk claw with a yard of ghosts in reach", function()
  local ARC = { { 4, -2 }, { 4, 2 }, { 3, -3 }, { 3, 3 }, { 4, 1 } }

  after_each(function()
    for _, name in pairs{ "inserter-capacity-bonus-1", "inserter-capacity-bonus-2",
                          "bulk-inserter" } do
      local technology = player.force.technologies[name]
      if technology then technology.researched = false end
    end
    player.get_inventory(defines.inventory.character_armor).clear()
  end)

  it("builds every one of them", function()
    for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1",
                          "inserter-capacity-bonus-2" } do
      player.force.technologies[name].researched = true
    end
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment-4", "fission-reactor-equipment",
                          "battery-mk2-equipment" }, true)
    player.insert{ name = BELT, count = 50 }
    for _, at in pairs(ARC) do world.ghost(player, BELT, at[1], at[2]) end
    after_ticks(world.CYCLE * 12, function()
      assert.are.equal(0, world.ghosts(player),
        "some of the arc is still standing")
      assert.are.equal(#ARC, world.count(player, BELT), "not all of them went up")
    end)
  end)

  -- The round measured rather than merely observed to happen. A claw that comes home
  -- between each ghost still builds all five, so the only thing that tells the two apart is
  -- how long three of them take: a journey each is one whole out and back per ghost, and
  -- this allows less than a single out leg for all three.
  it("builds three inside one journey out", function()
    for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1",
                          "inserter-capacity-bonus-2" } do
      player.force.technologies[name].researched = true
    end
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment-4", "fission-reactor-equipment",
                          "battery-mk2-equipment" }, true)
    player.insert{ name = BELT, count = 50 }
    for _, at in pairs(ARC) do world.ghost(player, BELT, at[1], at[2]) end

    local first, third
    for n = 1, world.CYCLE * 6 do
      after_ticks(n, function()
        local up = world.count(player, BELT)
        if not first and up >= 1 then first = game.tick end
        if not third and up >= 3 then third = game.tick end
      end)
    end
    after_ticks(world.CYCLE * 6 + 5, function()
      assert.is_truthy(first, "nothing was built at all")
      assert.is_truthy(third, "the round never reached a third ghost")
      assert.is_true(third - first <= world.SWING_TICKS,
        ("three ghosts took %d ticks, which is a journey each rather than a round")
          :format(third - first))
    end)
  end)

  -- One trip, several ghosts: part way through, more than one has gone.
  it("hands out more than one between visits home", function()
    for _, name in pairs{ "bulk-inserter", "inserter-capacity-bonus-1",
                          "inserter-capacity-bonus-2" } do
      player.force.technologies[name].researched = true
    end
    player.get_inventory(defines.inventory.character_armor).clear()
    world.equip(player, { "constructor-equipment-4", "fission-reactor-equipment",
                          "battery-mk2-equipment" }, true)
    player.insert{ name = BELT, count = 50 }
    for _, at in pairs(ARC) do world.ghost(player, BELT, at[1], at[2]) end
    after_ticks(world.CYCLE * 3, function()
      assert.is_true(world.count(player, BELT) >= 2,
        ("only %d went up in three cycles, which is a journey each rather than a round")
          :format(world.count(player, BELT)))
    end)
  end)
end)
