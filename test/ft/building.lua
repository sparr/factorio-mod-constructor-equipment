--- What the equipment does, and what it declines to do.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- check cycle it started on. Built on the swing rather than on world.BUILD_INTERVAL, which
--- is a leftover from when the mod capped its own build rate and has nothing to do with how
--- long a reach takes: two of those intervals is sixty ticks, and a first tier arm reaching
--- the edge of its two tiles wants up to sixty three.
local A_BUILD = world.DELIVERED

local BELT = "transport-belt"

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("a character wearing the equipment", function()
  before_each(function()
    world.equipped(player)
    player.insert{ name = BELT, count = 5 }
  end)

  it("builds a ghost that is within reach", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the belt was never built")
      assert.are.equal(0, world.ghosts(player), "the ghost is still standing there")
    end)
  end)

  it("pays for it with one item out of the inventory", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(4, player.get_item_count(BELT),
        "one belt should have gone, out of five")
    end)
  end)

  --- Holding the stack is what a player about to place one by hand does, and it takes the
  --- items out of the inventory for as long as it is held. Their only stack held that way
  --- left every arm looking at a player carrying nothing, and the whole set went quiet at
  --- the moment they were most obviously working.
  it("pays out of the stack on the cursor when that is the only one", function()
    local main = player.get_inventory(defines.inventory.character_main)
    local all = main.get_item_count(BELT)
    main.remove{ name = BELT, count = all }
    player.cursor_stack.set_stack{ name = BELT, count = all }
    assert.are.equal(0, main.get_item_count(BELT), "the stack is still in the inventory")
    assert.are.equal(all, player.cursor_stack.count, "the cursor is not holding it")
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "nothing was built off the cursor")
      local held = player.cursor_stack.valid_for_read and player.cursor_stack.count or 0
      assert.are.equal(4, held + main.get_item_count(BELT),
        "one belt should have gone, out of five")
    end)
  end)

  it("pays for it out of the batteries", function()
    local grid = player.character.grid
    local before = grid.available_in_batteries
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.is_true(grid.available_in_batteries < before,
        "building cost nothing: batteries went from " .. before .. " to "
        .. grid.available_in_batteries)
    end)
  end)

  it("leaves a ghost that is out of reach alone", function()
    world.ghost(player, BELT, world.BUILD_RANGE + 6, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "a ghost well out of range was built")
      assert.are.equal(1, world.ghosts(player))
    end)
  end)

  it("builds one at a time rather than all at once", function()
    world.several(player, BELT, 4)
    -- One swing should be one belt, not the whole row: the arm has to go out and come back
    -- before the next one starts. Asked once a swing has had time to land rather than after
    -- a build interval, because a reach takes as long as it takes: every spot in the row is
    -- the same two tiles from the arm, whichever side of its owner it is on.
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.count(player, BELT),
        "the whole row went up at once, so the arm is not being waited for")
    end)
    after_ticks(world.CYCLE * 2, function()
      assert.is_true(world.count(player, BELT) >= 2,
        "it never got to the second one")
      assert.is_true(world.count(player, BELT) < 4,
        "the row went up faster than one a swing")
    end)
  end)

  --- An arm is strapped two thirds of the way up its owner, and the map draws that as most
  --- of a tile to the north of their feet. Aimed at the ground it would have been reaching a
  --- tile and a half for a ghost two tiles behind them and half a tile for one two tiles in
  --- front, and built at twice the rate facing the camera; aimed in its own frame it reaches
  --- the same distance whichever way it is pointed.
  it("builds as quickly behind its owner as in front of them", function()
    local took = { north = nil, south = nil }

    ---@param dy number
    ---@param into string
    ---@param whenever fun()
    local function timed(dy, into, whenever)
      world.equipped(player)
      player.insert{ name = BELT, count = 5 }
      world.ghost(player, BELT, 0, dy)
      local started = game.tick
      script.on_nth_tick(1, function()
        if not took[into] and world.count(player, BELT) > 0 then
          took[into] = game.tick - started
        end
      end)
      after_ticks(world.CYCLE, function()
        script.on_nth_tick(nil)
        world.clear(player)
        whenever()
      end)
    end

    timed(-2, "north", function()
      timed(2, "south", function()
        assert.is_not_nil(took.north, "nothing was built in front")
        assert.is_not_nil(took.south, "nothing was built behind")
        -- Back to asking for the same time both ways, which is what an arm pointed at what
        -- it is reaching for gives: a reach opens with no turn whichever way the ghost
        -- lies. It had to allow a factor of two while every arm was built facing north and
        -- reaching behind its owner meant swinging through a half turn first.
        --
        -- The arms are given work ten times a second, so two reaches of the same length can
        -- still land a handful of ticks apart.
        assert.is_true(math.abs(took.north - took.south) <= 12,
          ("in front took %d ticks and behind %d, which is not the same reach both ways")
            :format(took.north, took.south))
      end)
    end)
  end)
end)

describe("a character who cannot build", function()
  it("does nothing without the equipment", function()
    world.equip(player, { "battery-equipment" }, true)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built without the equipment")
      assert.are.equal(5, player.get_item_count(BELT))
    end)
  end)

  it("does nothing with flat batteries", function()
    world.equip(player, { "constructor-equipment", "battery-equipment" }, false)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built with no power")
    end)
  end)

  it("does nothing without the item to build with", function()
    world.equipped(player)
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT),
        "it built a belt the character was not carrying")
      assert.are.equal(1, world.ghosts(player))
    end)
  end)
end)

--- The build loop used to revive nearby_ghosts[1] rather than the ghost it had matched an
--- item for. With one kind of ghost about that is invisible. With two it took the item for
--- the one it could build and put up the one it could not, so you ended up a belt lighter
--- and looking at a chest.
describe("with more than one kind of ghost in reach", function()
  before_each(function()
    world.equipped(player)
  end)

  it("builds the one it has the item for", function()
    -- a chest ghost and a belt ghost, and only belts in the pocket
    world.ghost(player, "wooden-chest", -2, 0)
    world.ghost(player, BELT, 2, 0)
    player.insert{ name = BELT, count = 5 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the belt it could build is missing")
      assert.are.equal(0, world.count(player, "wooden-chest"),
        "it built a chest the character was not carrying")
    end)
  end)

  it("leaves the one it cannot pay for standing", function()
    world.ghost(player, "wooden-chest", -2, 0)
    world.ghost(player, BELT, 2, 0)
    player.insert{ name = BELT, count = 5 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.ghosts(player), "the chest ghost should still be waiting")
      assert.are.equal(4, player.get_item_count(BELT), "exactly one belt should have gone")
    end)
  end)
end)

--- What happens when a ghost wants more of something than a claw can hold.
---
--- A claw holds what its inserter holds, which for a plain one is a single item, and a
--- curved rail wants three. A construction robot carries all three at once whatever its
--- cargo size, so the arm makes the same bargain differently: the whole round comes out of
--- the pockets when it sets off, the claw carries what fits, and the rest travels with the
--- job and is spent on arrival or handed back if the arm comes home with nothing built.
describe("a ghost that wants more than the claw can hold", function()
  local CURVE = "curved-rail-a"

  local function curve_in_reach()
    local ghost = player.surface.create_entity{ name = "entity-ghost",
      inner_name = CURVE, position = { world.ORIGIN.x + 4, world.ORIGIN.y },
      force = player.force, direction = defines.direction.north }
    return ghost
  end

  -- the fourth tier for its reach, with no capacity research, so its claw still holds a
  -- single item and a curved rail is still more than it can carry in one trip
  before_each(function()
    world.equip(player, { tiers.list[4].name, "battery-mk2-equipment" }, true)
  end)

  it("takes the whole round out of the pockets when it sets off", function()
    player.insert{ name = "rail", count = 10 }
    curve_in_reach()
    after_ticks(10, function()
      assert.are.equal(7, player.get_item_count("rail"),
        "all three should have been taken when the arm set off, not one")
      local arm = world.arms(player)[1]
      assert.is_true(arm and arm.held_stack.valid_for_read,
        "the claw should be carrying what it can of them")
    end)
  end)

  it("builds it, and charges exactly three", function()
    player.insert{ name = "rail", count = 10 }
    curve_in_reach()
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, CURVE), "the curved rail was never built")
      assert.are.equal(7, player.get_item_count("rail"),
        "a curved rail takes three, so seven of ten should be left")
    end)
  end)

  it("hands all three back if the ghost goes while the arm is out", function()
    player.insert{ name = "rail", count = 10 }
    local ghost = curve_in_reach()
    after_ticks(10, function()
      assert.are.equal(7, player.get_item_count("rail"))
      ghost.destroy()
    end)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(10, player.get_item_count("rail"),
        "the ghost went, so nothing was built and all three should have come back")
      assert.are.equal(0, player.surface.count_entities_filtered{
        name = "item-on-ground", position = world.ORIGIN, radius = 8 },
        "something was dropped on the floor instead of being handed back")
    end)
  end)

  it("leaves nothing behind when it cannot be built at all", function()
    player.insert{ name = "rail", count = 2 }
    curve_in_reach()
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(2, player.get_item_count("rail"),
        "two rails cannot build a curved rail, and should still be in the pockets")
      assert.are.equal(0, world.count(player, CURVE))
    end)
  end)
end)

--- A half diagonal rail takes two rails and a curved one takes three. The mod used to
--- build either for anyone holding a single rail, and take only that rail off them.
describe("a ghost that takes more than one item", function()
  local RAIL_GHOST = "half-diagonal-rail"

  -- A half diagonal rail snaps to a two tile grid and has a long box, so placed in the
  -- middle of the arena the character is standing inside it and it is rightly ignored.
  -- Two tiles east, with the character stepped round to its western side, it is a tile
  -- and a half off and clear of their feet.
  local function rail_in_reach()
    local ghost = world.ghost(player, RAIL_GHOST, 2, 0)
    player.teleport({ world.ORIGIN.x + 1, world.ORIGIN.y + 0.5 }, player.surface)
    return ghost
  end

  before_each(function()
    world.equipped(player)
  end)

  it("is left alone when the character has too few", function()
    rail_in_reach()
    player.insert{ name = "rail", count = 1 }
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, RAIL_GHOST),
        "a rail that takes two was built with one")
      assert.are.equal(1, player.get_item_count("rail"), "the rail should not have gone")
    end)
  end)

  it("is built when the character has enough", function()
    rail_in_reach()
    player.insert{ name = "rail", count = 10 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, RAIL_GHOST), "the rail was never built")
    end)
  end)

  it("costs as many items as it takes", function()
    rail_in_reach()
    player.insert{ name = "rail", count = 10 }
    after_ticks(A_BUILD, function()
      assert.are.equal(8, player.get_item_count("rail"),
        "a half diagonal rail takes two rails, so eight of ten should be left")
    end)
  end)
end)

--- The engine, not the mod, decides when an inserter hand has arrived, and it lands the
--- hand exactly on its target in a single step that is not bounded by the tier's extension
--- or rotation speed -- measured at 0.44 tiles for the third tier against a nominal 0.25.
--- So the mod can miss an arrival however wide its window is, and when it does, the engine
--- finishes the swing by putting the load on the floor.
---
--- That load is not the player's item arriving early. The claw is filled from nothing, so
--- what lands is a second one, free. Left alone this is both a ghost that never got built
--- and an item the player was never charged for.
describe("a load the engine put on the ground", function()
  -- Capacity research is a force wide setting, so a test that turns it on and walks away
  -- leaves every test after it with claws that carry more than they expect. Seven of them
  -- failed that way before this was put back.
  after_each(function()
    for n = 1, 7 do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = false end
    end
    -- force bonuses and where the character is standing are both shared, and a test that
    -- walks off with either leaves every test after it in a world it did not ask for
    player.force.inserter_stack_size_bonus = 0
    player.force.bulk_inserter_capacity_bonus = 0
    player.teleport(world.ORIGIN, player.surface)
    -- and the ground away from the arena that one of these tests works on, which world
    -- .clear knows nothing about
    for _, thing in pairs(player.surface.find_entities_filtered{
        position = { x = 29.238, y = 2.918 }, radius = 25 }) do
      if thing.valid and thing.type ~= "character" then thing.destroy() end
    end
  end)

  local BELT = "transport-belt"

  --- Nothing of the mod's should ever reach the floor.
  ---
  --- It used to be possible. The claw was aimed at the ghost the whole way out and the
  --- engine decided for itself what arriving meant: a ghost of something that could take
  --- the item made the inserter wait, and a ghost of something that could not -- a wall, a
  --- pole, a solar panel -- had the load put down beside it. The mod then swept the floor
  --- afterwards to clear up.
  ---
  --- There is a box on the ghost now, and an inserter puts things into boxes, so none of
  --- those cases can arise and the sweeping is gone with them. This is what is left: the
  --- promise itself.
  it("never leaves anything of the mod's on the floor", function()
    local WALL = "stone-wall"
    world.equipped(player)
    player.insert{ name = WALL, count = 10 }
    for _, spot in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do
      world.ghost(player, WALL, spot[1], spot[2])
    end
    after_ticks(world.CYCLE * 4, function()
      local loose = {}
      for _, thing in pairs(player.surface.find_entities_filtered{ type = "item-entity",
          position = world.ORIGIN, radius = 8 }) do
        if thing.valid and thing.stack.valid_for_read then
          table.insert(loose, ("%s x%d at %.2f,%.2f"):format(thing.stack.name,
            thing.stack.count, thing.position.x, thing.position.y))
        end
      end
      assert.are.equal(0, #loose, "on the floor: " .. table.concat(loose, " ; "))
      assert.is_true(world.count(player, WALL) > 0, "nothing was built at all")
    end)
  end)

  --- The sweep is bounded by what the hand was carrying, not by the radius alone, so that
  --- a stack the player left on the same tile survives.
  --- The mod does not touch what the player has dropped. It used to sweep the floor near a
  --- ghost to clear up after its own losses, which meant deciding whose items those were;
  --- with a box on the ghost there is nothing to clear up and nothing to decide.
  it("leaves the player's own items where they lie", function()
    -- a wall rather than a belt: a belt built over items on the ground takes them onto
    -- itself, which looks exactly like the mod having pocketed them
    local WALL = "stone-wall"
    world.equipped(player)
    player.insert{ name = WALL, count = 5 }
    local ghost = world.ghost(player, WALL, 2, 0)
    local mine = { x = ghost.position.x, y = ghost.position.y }
    player.surface.create_entity{ name = "item-on-ground", position = mine,
      stack = { name = "iron-plate", count = 1 } }
    after_ticks(world.CYCLE * 2, function()
      local left = player.surface.find_entities_filtered{
        type = "item-entity", position = mine, radius = 0.5 }
      assert.are.equal(1, #left, "the player's own iron plate was taken")
    end)
  end)

  it("is what stops the ghost being revived at all", function()
    local INSERTER = "inserter"
    world.equipped(player)
    local ghost = world.ghost(player, INSERTER, 2, 0)
    local at = { x = ghost.position.x, y = ghost.position.y }
    local function revivable(name)
      return player.surface.can_place_entity{ name = name, position = at,
        direction = ghost.direction, force = player.force,
        build_check_type = defines.build_check_type.ghost_revive }
    end
    assert.is_true(revivable(INSERTER), "a bare ghost should be revivable to begin with")
    local litter = player.surface.create_entity{ name = "item-on-ground", position = at,
      stack = { name = INSERTER, count = 1 } }
    assert.is_false(revivable(INSERTER), "an item on the ghost should block the revive")
    assert.is_true(revivable(BELT),
      "a belt should still be buildable there, since it would take the item onto itself")
    litter.destroy()
    assert.is_true(revivable(INSERTER), "taking the item away should allow it again")
  end)

  --- With the item blocking the revive, the arm arrives, fails to build, and gives up
  --- still holding its load. If giving up leaves the claw aimed at the ghost, the engine
  --- finishes the swing and drops a second item, and so on for ever.
  --- Whether a ghost blocks an inserter's drop turns on what the ghost would become. It
  --- blocks only if the finished entity could have taken the item: a chest ghost blocks, a
  --- belt ghost blocks. A wall, a pole, a solar panel could take nothing, so the engine
  --- drops the load on the floor instead, on the ghost's own tile.
  ---
  --- That is the whole of it, and it is why every earlier attempt at this test could not
  --- fail: they were written with belt ghosts, which cannot produce the fault at all. The
  --- first player sighting was a wall, and the rest were solar panels.
  ---
  --- The arm is aimed at the ghost the whole way out, so an arrival the mod does not notice
  --- is one the engine finishes itself. A claw pivoting at full stretch crosses the whole
  --- arrival window in a single tick, and the mod, looking once a tick, never sees it.
  it("does not drop a load onto a ghost that cannot take it", function()
    local WALL = "stone-wall"
    for n = 1, 7 do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = n == 1 end
    end
    world.equip(player, { tiers.list[4].name, "battery-mk2-equipment",
      "fission-reactor-equipment" }, true, "power-armor-mk2")
    player.insert{ name = WALL, count = 60 }

    -- spread right round, so every turn between them is a wide one taken at full stretch
    local r = tiers.list[4].range
    local SPOTS = { { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r },
                    { r - 1, r - 3 }, { -(r - 1), -(r - 3) } }
    for _, d in ipairs(SPOTS) do world.ghost(player, WALL, d[1], d[2]) end
    for n = 60, 540, 60 do
      after_ticks(n, function()
        for _, d in ipairs(SPOTS) do
          local at = { x = world.ORIGIN.x + d[1], y = world.ORIGIN.y + d[2] }
          for _, built in pairs(player.surface.find_entities_filtered{ name = WALL,
              position = at, radius = 0.6 }) do built.destroy() end
          if #player.surface.find_entities_filtered{ ghost_name = WALL, position = at,
              radius = 0.6 } == 0 then
            player.surface.create_entity{ name = "entity-ghost", inner_name = WALL,
              position = at, force = player.force }
          end
        end
        if player.get_item_count(WALL) < 20 then player.insert{ name = WALL, count = 40 } end
      end)
    end

    after_ticks(560, function()
      local dropped = {}
      for _, thing in pairs(player.surface.find_entities_filtered{
          type = "item-entity", position = world.ORIGIN, radius = 12 }) do
        if thing.valid and thing.stack.valid_for_read then
          table.insert(dropped, ("%s x%d at %.2f,%.2f"):format(thing.stack.name,
            thing.stack.count, thing.position.x, thing.position.y))
        end
      end
      assert.are.equal(0, #dropped,
        "the engine put the load on the ground: " .. table.concat(dropped, " ; "))
    end)
  end)

  --- Walking into the thing being built, which is what both sightings had in common: the
  --- player was moving towards the ghosts. advance() gives the swing up when the character
  --- ends up standing in the target, and the claw is full at that moment.
  ---
  --- This passes with or without abandon() re-aiming, so it is a property worth holding
  --- rather than a reproduction of anything. Stepping in front of the claw by teleport
  --- moves the arm too, since it is mounted on the character, so the hand does not stay
  --- where it would have to be for the engine to act on the stale aim.
  it("is not left behind when you walk into the ghost", function()
    local INSERTER = "inserter"
    for n = 1, 7 do
      local tech = player.force.technologies["inserter-capacity-bonus-" .. n]
      if tech then tech.researched = true end
    end
    world.equip(player, { tiers.list[4].name, "battery-equipment" }, true, "power-armor")
    player.insert{ name = INSERTER, count = 40 }
    local r = tiers.list[4].range
    local ghost = world.ghost(player, INSERTER, r, 0)
    local at = { x = ghost.position.x, y = ghost.position.y }

    -- step onto it the moment the claw is out and loaded, which is the moment the mod
    -- gives up and the engine is still holding the aim
    local stepped = false
    for n = 5, 200 do
      after_ticks(n, function()
        if stepped then return end
        local arm = world.arms(player)[1]
        if arm and arm.valid and arm.held_stack.valid_for_read then
          local hand, mount = arm.held_stack_position, arm.position
          local out = math.sqrt((hand.x - mount.x) ^ 2 + (hand.y - mount.y) ^ 2)
          if out > r - 1 then
            player.teleport(at)
            stepped = true
          end
        end
      end)
    end

    after_ticks(world.CYCLE * 4, function()
      assert.is_true(stepped, "the claw never got out far enough to step in front of")
      local left = 0
      for _, thing in pairs(player.surface.find_entities_filtered{ type = "item-entity",
          position = at, radius = 2 }) do
        left = left + (thing.stack.valid_for_read and thing.stack.count or 0)
      end
      assert.are.equal(0, left,
        ("%d items were left on the ground where the ghost was"):format(left))
    end)
  end)

  it("does not build for free when there was no load at all", function()
    world.equipped(player)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 2, 0)
    after_ticks(20, function()
      local arm = world.arms(player)[1]
      assert.is_not_nil(arm)
      arm.held_stack.clear()
    end)
    after_ticks(40, function()
      assert.are.equal(0, world.count(player, BELT),
        "a ghost was built from an empty claw and nothing on the floor")
    end)
  end)
end)

--- What an arm does about a ghost its owner is walking away from.
---
--- A ghost abeam of somebody under way is left behind faster than a claw can follow: the
--- bearing to a thing one tile to the side of a character strolling at a ninth of a tile a
--- tick sweeps at nearly twice the speed the last tier's arm can turn, so the hand trails it
--- and never lands. Nothing aims its way out of that. What the arm can do is not go.
describe("a ghost its owner is walking away from", function()
  --- Every case here walks its character a long way from the middle of the arena, so what
  --- the last one left behind lies well outside the radius world.clear sweeps. Left there,
  --- it is an arm's next job: a claw that turned round for a belt fifty tiles back is not
  --- the swing the case meant to measure, and it read as a chase spending four times the
  --- rotation it really does.
  local function scrub()
    player = world.player()
    for _, thing in pairs(player.surface.find_entities_filtered{
        position = world.ORIGIN, radius = 200 }) do
      if thing.valid and (thing.name == BELT or thing.type == "entity-ghost"
          or thing.type == "item-entity") then
        thing.destroy()
      end
    end
    player.teleport(world.ORIGIN)
    world.clear(player)
  end

  ---Walk east at `pace` from the arena's middle, for as long as the caller wants.
  local function stroll(pace, ticks, watch)
    for n = 1, ticks do
      after_ticks(n, function()
        player.teleport({ world.ORIGIN.x + n * pace, world.ORIGIN.y })
        if watch then watch(n) end
      end)
    end
  end

  before_each(function()
    scrub()
    world.equip(player, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
    player.get_inventory(defines.inventory.character_main).clear()
    player.insert{ name = BELT, count = 50 }
  end)

  after_each(scrub)

  -- Laid down astern of a character already under way, so there is no approach to deliver
  -- on and the whole swing would be spent chasing a bearing going aft.
  it("does not set off for one it cannot reach in time", function()
    local swings, had = 0, false
    after_ticks(1, function() world.ghost(player, BELT, -1, 3) end)
    stroll(0.09, 160, function()
      local working = world.job(player) ~= nil
      if working and not had then swings = swings + 1 end
      had = working
    end)
    after_ticks(180, function()
      assert.are.equal(0, world.count(player, BELT),
        "it built one it was walking away from, which would be a better test than this")
      assert.are.equal(0, swings,
        ("the arm set off %d times for a ghost it could never reach"):format(swings))
    end)
  end)

  -- The other direction, which is the one this must not touch: walking towards a thing
  -- shortens the reach as the hand goes, so a swing that looks too long from where the arm
  -- stands is finished well before the estimate says. Judged both ways, an arm turned down
  -- a row of twelve it had been building every one of.
  it("still sets off for one it is walking towards", function()
    for step = 0, 5 do world.ghost(player, BELT, 3 + step * 2, 1.2) end
    local wanted = world.ghosts(player)
    stroll(0.09, 300)
    after_ticks(320, function()
      assert.are.equal(wanted, world.count(player, BELT),
        ("only %d of the %d ahead went up"):format(world.count(player, BELT), wanted))
    end)
  end)

  -- Standing still, nothing is predicted at all and the edge of the range is the edge of
  -- the range.
  it("sets off for one at the edge of its reach when nobody is moving", function()
    local range = tiers.list[4].range
    world.ghost(player, BELT, range, 0)
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(1, world.count(player, BELT),
        "a ghost at the edge of the range was left standing by a character stood still")
    end)
  end)
end)
