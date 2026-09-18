--- Riding rather than walking: whose grid the arms come out of, and who pays for them.
---
--- The trade the mod offers on foot is building for walking speed. A driver is not walking,
--- so armour worn in a seat would be building for nothing. What they get instead is a
--- vehicle that wears the equipment itself, mounts the arms on its own hull, and takes the
--- same fraction off its own speed.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
local A_BUILD = world.BUILD_INTERVAL * 2

--- Longer than a character's build, because a vehicle's arms have further to go: the ghosts
--- they reach for are out past the hull rather than round their owner's feet.
local A_VEHICLE_BUILD = A_BUILD * 3

---A spot out to the right of a vehicle, which is where a lone arm is mounted and so the one
---place it can reach without the hull being in the way.
---
---Out past the hull's own edge, because a ghost underneath a vehicle cannot be built at all,
---and inside the arm's two tiles, because an arm measures its reach from its own base rather
---than from the middle of the thing it is bolted to.
---@param vehicle LuaEntity
---@param out number? how far past the side, in tiles
---@return number dx from the arena's middle, where the vehicle stands
---@return number dy
local function beside(vehicle, out)
  local box = vehicle.prototype.selection_box
  local across = (box.right_bottom.x - box.left_top.x) / 2
  local away = across + (out or 1.5)
  local turns = vehicle.orientation * 2 * math.pi
  -- north is nought and the y axis grows southwards, so the right of one facing north is to
  -- the east of it
  return math.cos(turns) * away, math.sin(turns) * away
end

---Where a spider vehicle's legs meet its body, which is where the first arms are bolted.
---Read off the prototype the same way the mod reads it.
---@param spider LuaEntity
---@return {x: number, y: number}[]
local function leg_mounts(spider)
  local engine = spider.prototype.spider_engine
  local spots = {}
  for _, leg in ipairs(engine and engine.legs or {}) do
    local at = leg.mount_position
    if at then spots[#spots + 1] = { x = at.x or at[1] or 0, y = at.y or at[2] or 0 } end
  end
  return spots
end

--- Two tiles east of a spidertron's middle, which is in reach of the arms bolted to its
--- legs. A leg meets the body less than a tile out -- measured, the furthest is 0.78 -- so
--- an arm there reaches a good deal less far from the middle than one bolted to the edge of
--- a hull does, and beside() measures from the edge.
local SPIDER_REACH = { 2, 0 }

---A ring of ghosts two tiles out all the way round, so that every leg has something in
---reach and every arm has a reason to come out. An arm with nothing to do is not made at
---all, so one ghost makes one arm however many are in the grid.
---@param who LuaPlayer
local function ring_round(who)
  for dx = -2, 2 do
    for dy = -2, 2 do
      if math.max(math.abs(dx), math.abs(dy)) == 2 then
        world.ghost(who, BELT, dx, dy)
      end
    end
  end
end

--- One arm for every leg, which is what the showroom puts on a spidertron and what makes
--- the mounting worth looking at.
local SPIDER_ARMS = { "constructor-equipment", "constructor-equipment",
                      "constructor-equipment", "constructor-equipment",
                      "constructor-equipment", "constructor-equipment",
                      "constructor-equipment", "constructor-equipment",
                      "battery-mk2-equipment" }

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  world.unseat(player)
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("a driver's own armour", function()
  before_each(function()
    world.equipped(player)
    player.insert{ name = BELT, count = 5 }
  end)

  it("builds nothing while they are in a vehicle", function()
    world.vehicle(player, "car")
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "the armour built from the driving seat")
      assert.are.equal(1, world.ghosts(player), "the ghost was taken")
    end)
  end)

  it("grows no arms while they are in a vehicle", function()
    world.vehicle(player, "car")
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, #world.arms(player), "an arm is out with nobody to wear it")
    end)
  end)

  it("takes its arms away when they get in", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(12, function()
      assert.are.equal(1, #world.arms(player), "the armour never grew an arm to lose")
      world.vehicle(player, "car")
      after_ticks(2, function()
        assert.are.equal(0, #world.arms(player), "the arm stayed out once they were driving")
      end)
    end)
  end)

  it("works again the moment they get out", function()
    local car = world.vehicle(player, "car")
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "it built while they were driving")
      player.driving = false
      car.destroy()
      -- getting out sets the character down beside the vehicle, which is further from the
      -- ghost than a first tier arm reaches
      player.teleport(world.ORIGIN)
      after_ticks(A_BUILD, function()
        assert.are.equal(1, world.count(player, BELT), "it did not start again on foot")
      end)
    end)
  end)
end)

describe("equipment in a vehicle's own grid", function()
  it("builds what is in reach of the vehicle", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "the vehicle's own arm built nothing")
      assert.are.equal(0, world.ghosts(player), "the ghost is still standing there")
    end)
  end)

  it("pays for it out of the vehicle's own hold", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(4, tank.get_item_count(BELT),
        "one belt should have gone out of the five in the vehicle")
    end)
  end)

  it("leaves the driver's own pockets alone", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "nothing was built at all")
      assert.are.equal(5, player.get_item_count(BELT),
        "the vehicle spent the driver's belt rather than its own")
    end)
  end)

  it("builds nothing out of an empty hold, whatever the driver is carrying", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    player.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(0, world.count(player, BELT),
        "the vehicle reached into its driver's pockets")
      assert.are.equal(5, player.get_item_count(BELT), "the driver's belts were taken")
    end)
  end)

  it("hands back into the vehicle what a claw was carrying", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    -- The tick the belt leaves the hold, rather than a tick chosen as roughly then: an arm
    -- pointed at what it is reaching for can be there and back inside the window this used
    -- to wait out.
    world.once(function() return tank.get_item_count(BELT) == 4 end, function()
      -- getting out puts the arms away mid reach, which is the moment the load has to go
      -- back somewhere
      player.driving = false
      after_ticks(2, function()
        assert.are.equal(5, tank.get_item_count(BELT),
          "the belt in the claw did not go back into the vehicle")
        assert.are.equal(0, player.get_item_count(BELT),
          "the belt in the claw went into the driver's pockets instead")
      end)
    end, "the arm never took a belt out of the hold to carry")
  end)

  it("pays for it out of the vehicle's own batteries", function()
    local tank = world.vehicle(player)
    local grid = world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    local before = grid.available_in_batteries
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.is_true(grid.available_in_batteries < before,
        "building cost the vehicle nothing: batteries went from " .. before
        .. " to " .. grid.available_in_batteries)
    end)
  end)

  it("mounts a lone arm on the right side of the hull", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(12, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "the vehicle grew no arm")
      -- world.vehicle puts it down facing east, so its right is south of it
      local box = tank.prototype.selection_box
      local across = (box.right_bottom.x - box.left_top.x) / 2
      local out = arm.position.y - tank.position.y
      assert.is_true(out > 0 and out < across,
        ("the arm sits %.2f south, where the side is %.2f out"):format(out, across))
      assert.is_true(math.abs(arm.position.x - tank.position.x) < 0.05,
        "the arm is fore or aft rather than in the middle of the side")
    end)
  end)

  --- The camera looks from the south, so the near side of a hull is drawn above the ground
  --- it stands on and an arm bolted out there has to be lifted to meet it. The far side is
  --- hidden behind the body and stays where it is.
  it("lifts an arm on the side facing the camera, and not one facing away", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    local box = tank.prototype.selection_box
    local across = (box.right_bottom.x - box.left_top.x) / 2
    world.ghost(player, BELT, beside(tank))
    after_ticks(12, function()
      -- facing east, its right hand arm is the southern one and is lifted
      local south = world.arm(player).position.y - tank.position.y
      assert.is_true(south < across - 0.2,
        ("the southern arm sits %.2f out, as low as the box's own %.2f"):format(south, across))

      -- facing west, the same arm is the northern one, where a lift would poke it out over
      -- the roof. It is not on the box's own edge either: arms are bolted inboard of the
      -- running gear, which on a tank is its tracks, so what is asked is that it is out on
      -- that side and not lifted off it.
      tank.orientation = 0.75
      after_ticks(2, function()
        local north = world.arm(player).position.y - tank.position.y
        assert.is_true(north < 0 and north > -across,
          ("the northern arm sits %.2f out, where the side is %.2f"):format(north, -across))
        assert.is_true(north < -0.5 * across,
          ("the northern arm sits %.2f out, which is lifted rather than square on the side")
            :format(north))
      end)
    end)
  end)

  it("bolts a spider vehicle's arms to its legs, and carries them up to its body", function()
    local spider = player.surface.create_entity{
      name = "spidertron", position = world.ORIGIN, force = player.force }
    world.fit(spider, SPIDER_ARMS, true)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 50 }
    local mounts = leg_mounts(spider)
    assert.is_true(#mounts >= 8, "a spidertron should have eight legs to bolt arms to")
    ring_round(player)
    after_ticks(12, function()
      local height = spider.prototype.height
      assert.is_not_nil(height, "a spidertron should say how high it rides")
      local arms = world.arms(player)
      assert.is_true(#arms >= 8, ("only %d arms came out of eight"):format(#arms))
      -- Every arm over a leg, and every leg with an arm over it. Matched by position
      -- rather than by order, because find_entities_filtered hands them back in the map's
      -- own order and not the grid's. Its body rides a tile and a half up those legs, so
      -- each one is drawn that far north of the leg it belongs to.
      local taken = {}
      for _, arm in ipairs(arms) do
        local onto
        for slot, want in ipairs(mounts) do
          local dx = arm.position.x - (spider.position.x + want.x)
          local dy = arm.position.y - (spider.position.y + want.y - height)
          if math.abs(dx) < 0.05 and math.abs(dy) < 0.05 then onto = slot end
        end
        assert.is_not_nil(onto,
          ("an arm at %.2f,%.2f is over no leg at all"):format(
            arm.position.x - spider.position.x, arm.position.y - spider.position.y))
        assert.is_nil(taken[onto], ("two arms are on leg %s"):format(tostring(onto)))
        taken[onto] = true
      end
      for slot = 1, 8 do
        assert.is_true(taken[slot] or false, ("leg %d has no arm on it"):format(slot))
      end
      spider.destroy()
    end)
  end)

  -- A spidertron's torso swings round to face what it is aiming at while its legs stay put.
  -- Arms on the legs stay put with them; arms on a tank go round with the hull, because the
  -- whole of a tank turns.
  it("leaves a spider vehicle's arms alone when its body turns", function()
    local spider = player.surface.create_entity{
      name = "spidertron", position = world.ORIGIN, force = player.force }
    world.fit(spider, SPIDER_ARMS, true)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 50 }
    ring_round(player)
    after_ticks(12, function()
      local before = {}
      for slot, arm in ipairs(world.arms(player)) do
        before[slot] = { x = arm.position.x, y = arm.position.y }
      end
      assert.is_true(#before >= 8, "no arms to watch")
      spider.orientation = (spider.orientation + 0.25) % 1
      after_ticks(4, function()
        for slot, arm in ipairs(world.arms(player)) do
          local was = before[slot]
          if was then
            assert.is_true(math.abs(arm.position.x - was.x) < 0.05
              and math.abs(arm.position.y - was.y) < 0.05,
              ("arm %d moved when the torso turned"):format(slot))
          end
        end
        spider.destroy()
      end)
    end)
  end)

  it("puts two arms out on the sides", function()
    local tank = world.vehicle(player)
    world.fit(tank, { "constructor-equipment", "constructor-equipment", "battery-equipment" },
      true)
    tank.insert{ name = BELT, count = 5 }
    -- world.SPOTS includes the two straight out to the sides, which is where a pair of arms
    -- is mounted and so what they can reach
    world.several(player, BELT, 4)
    after_ticks(12, function()
      local arms = world.arms(player)
      assert.are.equal(2, #arms, "two of the equipment did not grow two arms")
      local box = tank.prototype.selection_box
      local across = (box.right_bottom.x - box.left_top.x) / 2
      -- Facing east, its sides are north and south of it, and both are bolted inboard of
      -- the tracks. The northern one sits square on its side; the southern one is lifted
      -- onto the near face of the hull, which is drawn above the ground it stands on, so it
      -- ends up nearer the middle than the northern one is.
      local out = {}
      for _, arm in pairs(arms) do table.insert(out, arm.position.y - tank.position.y) end
      table.sort(out)
      assert.is_true(out[1] < -0.5 * across and out[1] > -across,
        ("the northern arm sits %.2f out, where the side is %.2f"):format(out[1], -across))
      assert.is_true(out[2] > 0 and out[2] < across,
        ("the southern arm sits %.2f out, where the side is %.2f"):format(out[2], across))
      assert.is_true(math.abs(out[2]) < math.abs(out[1]),
        "the southern arm was not lifted onto the hull")
    end)
  end)

  it("reaches from the arm's own base rather than from the middle of the vehicle", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    local dx, dy = beside(tank)
    local away = math.sqrt(dx * dx + dy * dy)
    -- further from the middle of the tank than the tier reaches, and well within reach of
    -- the arm bolted to its side
    assert.is_true(away > tiers.list[1].range,
      ("the spot beside it is only %.2f from the middle, which the middle could reach")
        :format(away))
    world.ghost(player, BELT, dx, dy)
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(1, world.count(player, BELT),
        ("nothing was built %.2f tiles out to the side, where the arm is"):format(away))
    end)
  end)

  it("will not reach across its own hull to the far side", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    -- two tiles from the middle, which is inside what the tier promises, and further than
    -- that from the arm out on the side, which is not
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(0, world.count(player, BELT),
        "the arm stretched from the back of the tank to the front of it")
      assert.are.equal(1, world.ghosts(player), "the ghost went somewhere")
    end)
  end)

  it("carries the arm along when the vehicle moves", function()
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(12, function()
      tank.teleport{ world.ORIGIN.x + 10, world.ORIGIN.y }
      after_ticks(2, function()
        local arm = world.arms(player)[1]
          or player.surface.find_entities_filtered{
               name = tiers.list[1].inserter, position = tank.position, radius = 3 }[1]
        assert.is_not_nil(arm, "the arm was left behind when the vehicle moved")
        assert.is_true(math.abs(arm.position.x - tank.position.x) < 2,
          "the arm did not follow the vehicle")
      end)
    end)
  end)

  it("does nothing for a passenger who is not driving", function()
    local tank = player.surface.create_entity{
      name = "tank", position = world.ORIGIN, force = player.force }
    world.fitted(tank)
    tank.set_passenger(player)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(tank))
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(0, world.count(player, BELT), "a passenger drove the vehicle's arms")
      assert.are.equal(0, #world.arms(player), "a passenger grew an arm")
    end)
  end)

  it("works the same in a spidertron's grid", function()
    local spider = player.surface.create_entity{
      name = "spidertron", position = world.ORIGIN, force = player.force }
    -- One arm on a spidertron is bolted to its first leg rather than out on its right, so
    -- a lone arm and a ghost beside the hull are no longer a pair. Eight of them, one to a
    -- leg, which is what a spidertron is for.
    world.fit(spider, SPIDER_ARMS, true)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 20 }
    world.ghost(player, BELT, SPIDER_REACH[1], SPIDER_REACH[2])
    world.once(function() return world.slowing_anything(spider) ~= nil end, function()
      assert.is_not_nil(world.sticker_on(spider, tiers.list[1].stickers.legs.flat)
        or world.sticker_on(spider, tiers.list[1].stickers.legs.slowing),
        "the spidertron took the wheeled slowdown rather than the legged one")
      after_ticks(A_VEHICLE_BUILD, function()
        assert.is_true(world.count(player, BELT) > 0, "the spidertron's own arms built nothing")
        spider.destroy()
      end)
    end, "the spidertron was never slowed")
  end)

  --- The point of aiming in the frame the arm is drawn in. A spidertron's torso rides a tile
  --- and a half up its legs, so an arm drawn on it and aimed at the ground would have half
  --- again as far to stretch southward as northward: it was measurably slower to build
  --- behind itself than in front, which is the sort of thing a player feels without being
  --- able to say why.
  it("builds as quickly behind a spider vehicle as in front of it", function()
    local took = { north = nil, south = nil }

    ---Time one build, with the ghost the same distance from the arm either way.
    ---@param dy number
    ---@param into string
    ---@param whenever fun()
    local function timed(dy, into, whenever)
      local spider = player.surface.create_entity{
        name = "spidertron", position = world.ORIGIN, force = player.force }
      world.fit(spider, SPIDER_ARMS, true)
      spider.set_driver(player)
      spider.insert{ name = BELT, count = 20 }
      -- Eight arms, one to a leg, arranged evenly round the body, so these two spots are
      -- the same distance from the nearest arm and on opposite sides of the spidertron.
      world.ghost(player, BELT, 2, dy)
      local started = game.tick
      script.on_nth_tick(1, function()
        if not took[into] and world.count(player, BELT) > 0 then
          took[into] = game.tick - started
        end
      end)
      after_ticks(A_VEHICLE_BUILD, function()
        script.on_nth_tick(nil)
        world.unseat(player)
        spider.destroy()
        world.clear(player)
        whenever()
      end)
    end

    timed(-1, "north", function()
      timed(1, "south", function()
        assert.is_not_nil(took.north, "nothing was built to the north")
        assert.is_not_nil(took.south, "nothing was built to the south")
        -- The same time both ways, for the reason in building.lua: an arm is built facing
        -- what it is about to reach for, so neither side opens with a turn. The arms are
        -- given work ten times a second, so two builds of the same length can still land a
        -- handful of ticks apart.
        assert.is_true(math.abs(took.north - took.south) <= 12,
          ("north took %d ticks and south %d, which is not the same reach both ways")
            :format(took.north, took.south))
      end)
    end)
  end)

  it("is the only equipment that counts, armour and all", function()
    world.equipped_with(player, 2)
    local tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 20 }
    world.several(player, BELT, 4)
    after_ticks(12, function()
      assert.are.equal(1, #world.arms(player),
        "two in the armour and one in the vehicle should be one arm, not three")
    end)
  end)
end)

--- A vehicle's own arms, reaching for what is lying under it.
---
--- A claw stuttering for ever over a plate beneath the hull was the same arrival test as a
--- character walking past one: a fetch waited for the engine to say the hand was settled
--- over its source, and an arm bolted to something that moves never settles.
describe("a vehicle over something marked", function()
  it("picks up what is lying under it", function()
    local tank = world.vehicle(player)
    world.fit(tank, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
    for _, at in ipairs{ { 0, 0 }, { 0, 2.5 } } do
      local loose = player.surface.create_entity{ name = "item-on-ground",
        position = { tank.position.x + at[1], tank.position.y + at[2] },
        stack = { name = BELT, count = 1 } }
      assert.is_not_nil(loose, "the plate would not go on the floor")
      loose.order_deconstruction(player.force)
    end
    after_ticks(world.CYCLE * 3, function()
      assert.are.equal(0, player.surface.count_entities_filtered{
        name = "item-on-ground", position = tank.position, radius = 6 },
        "something marked was left lying under the tank")
      local hold = tank.get_inventory(defines.inventory.car_trunk)
      assert.are.equal(2, hold.get_item_count(BELT), "they did not come home to the hold")
    end)
  end)
end)

describe("the slowdown a vehicle's arms ask for", function()
  local tank

  before_each(function()
    tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 20 }
  end)

  it("lands on the vehicle", function()
    world.ghost(player, BELT, beside(tank))
    world.once(function() return world.slowing_anything(tank) ~= nil end, function() end,
      "the vehicle was never slowed")
  end)

  it("does not land on the driver", function()
    world.ghost(player, BELT, beside(tank))
    -- Asked on the tick the vehicle is slowed rather than at a tick it ought to be by:
    -- with nothing slowed yet, nothing is on the driver either, and the test passes
    -- without having looked at anything.
    world.once(function() return world.slowing_anything(tank) ~= nil end, function()
      assert.is_nil(world.slowing_anything(player.character),
        "the driver was slowed as well as the vehicle they are sat in")
    end, "the vehicle was never slowed")
  end)

  --- Measured rather than read off the prototype: LuaEntityPrototype does not hand back a
  --- sticker's vehicle figures, and they are not the tier's own number anyway. What is
  --- being claimed is about speed, so speed is what is compared.
  ---
  --- Top speed, so each vehicle is started above its own and left to settle down onto it.
  --- Climbing to it from rest takes thousands of ticks and never quite arrives, and a
  --- vehicle still accelerating is down by more than its share.
  --- The tier to measure the wheeled slowdown with. Not the first: a first tier arm reaches
  --- two tiles, and a tank fills very nearly two tiles of that with its own hull, so there
  --- is no band left where a ghost is both in reach and clear of the vehicle. The second
  --- reaches three.
  local DRIVING_TIER = tiers.by_level[2]

  ---How far a tank gets in ten seconds at its settled speed, with arms working on it or
  ---with nothing in its grid at all.
  ---
  ---Measured end to end, with the mod doing the slowing, because there is no way to hold
  ---one of its stickers on a vehicle behind its back: an empty vehicle ignores a riding
  ---state, with or without a character sat in it, so a wheeled vehicle only moves with a
  ---player at the wheel -- and the moment the mod finds a wearer of its own with nothing to
  ---build, it hands the speed back. So the tank is given something to build all the way
  ---along: a row of ghosts beside its path, close enough together that one is always within
  ---the arm's three tiles and far enough to the side to be clear of the hull.
  ---
  ---At its settled speed, so it is started above its own top speed and given twenty five
  ---seconds to come down to it. A vehicle still picking up speed is down by more than its
  ---share, which would make this read as too harsh rather than as wrong.
  ---@param fitted boolean whether to fit arms that will work the whole way
  ---@param whenever fun(tiles: number, slowed: number)
  local function settled_run(fitted, whenever)
    local flats = world.flats()
    local tank = flats.create_entity{
      name = "tank", position = { 0, 0 }, force = player.force,
      direction = defines.direction.east }
    tank.insert{ name = "coal", count = 50 }
    if fitted then
      world.fit(tank, { DRIVING_TIER.name, "battery-equipment", "battery-equipment" }, true)
      tank.insert{ name = BELT, count = 400 }
      for x = 4, 700, 1 do
        flats.create_entity{
          name = "entity-ghost", inner_name = BELT, position = { x, 2.5 }, force = player.force }
      end
    end
    -- the character has to be on the surface before it can be put in the seat
    player.teleport({ 0, 0 }, flats)
    tank.set_driver(player)
    tank.speed = 1.0
    player.riding_state = { acceleration = defines.riding.acceleration.accelerating,
                            direction = defines.riding.direction.straight }
    local slowed = 0
    script.on_nth_tick(1, function()
      if tank.valid and world.slowing_anything(tank) then slowed = slowed + 1 end
    end)
    after_ticks(1500, function()
      local from = tank.position.x
      after_ticks(600, function()
        local tiles = tank.position.x - from
        script.on_nth_tick(nil)
        player.driving = false
        tank.destroy()
        for _, entity in pairs(flats.find_entities_filtered{
              type = { "entity-ghost", "transport-belt" } }) do entity.destroy() end
        player.teleport(world.ORIGIN, game.surfaces[1])
        whenever(tiles, slowed / 2100)
      end)
    end)
  end

  it("is the same share of top speed a character loses", function()
    local wanted = DRIVING_TIER.stickers.modifier
    settled_run(true, function(slow, share_slowed)
      assert.is_true(share_slowed > 0.9,
        ("the tank was only slowed for %.0f%% of the run, so this measures nothing")
          :format(share_slowed * 100))
      settled_run(false, function(free)
        local share = slow / free
        assert.is_true(math.abs(share - wanted) < 0.02,
          ("a tank with its arms working covered %.1f tiles against a bare one's %.1f, which"
            .. " is %.3f of it rather than the %.3f the tier asks of a character")
            :format(slow, free, share, wanted))
      end)
    end)
  end)

  it("is the same share again for a spider vehicle, whose legs take the figure straight",
    function()
      local set = tiers.list[1].stickers
      world.unseat(player)
      -- driverless for the same reason the tank above is
      local function strides(sticker, whenever)
        local flats = world.flats()
        local spider = flats.create_entity{
          name = "spidertron", position = { 0, 0 }, force = player.force }
        if sticker then
          script.on_nth_tick(30, function()
            if spider.valid then
              flats.create_entity{ name = sticker, position = spider.position, target = spider }
            end
          end)
        end
        spider.autopilot_destination = { 400, 0 }
        -- measured from a running start, so that setting off is not in the figure
        after_ticks(300, function()
          local from = spider.position.x
          after_ticks(600, function()
            local travelled = spider.position.x - from
            script.on_nth_tick(nil)
            spider.destroy()
            whenever(travelled)
          end)
        end)
      end
      strides(set.legs.flat, function(slowed)
        strides(nil, function(free)
          local share = slowed / free
          assert.is_true(math.abs(share - set.modifier) < 0.02,
            ("a slowed spidertron covered %.2f tiles against a free one's %.2f, which is"
              .. " %.3f of it rather than the %.3f the tier asks for")
              :format(slowed, free, share, set.modifier))
        end)
      end)
    end)

  it("is given back when the driver gets out", function()
    world.ghost(player, BELT, beside(tank))
    world.once(function() return world.slowing_anything(tank) ~= nil end, function()
      player.driving = false
      after_ticks(2, function()
        assert.is_nil(world.slowing_anything(tank),
          "the vehicle is still slowed by arms nobody is driving")
      end)
    end, "the vehicle was never slowed")
  end)
end)

-- Climbing into a locomotive wearing arms ended a session: slow() puts a sticker on
-- whoever is wearing the arms, rolling stock does not accept stickers, and create_entity
-- raises over it rather than returning nothing.
describe("a wearer that will not take a sticker", function()
  it("is slowed down by nothing rather than taking the game down", function()
    -- Rolling stock goes where the track lets it rather than where it is asked for, so
    -- the rail goes down first and the locomotive onto whichever rail took.
    local locomotive
    for step = -4, 4 do
      player.surface.create_entity{ name = "straight-rail",
        position = { world.ORIGIN.x + step * 2, world.ORIGIN.y + 8 },
        direction = defines.direction.east, force = player.force }
    end
    for _, rail in pairs(player.surface.find_entities_filtered{
        position = { world.ORIGIN.x, world.ORIGIN.y + 8 }, radius = 10,
        type = "straight-rail" }) do
      locomotive = locomotive or player.surface.create_entity{ name = "locomotive",
        position = rail.position, direction = rail.direction, force = player.force }
    end
    assert.is_truthy(locomotive, "no locomotive to try it on")
    -- Straight at the function the crash came out of, because a locomotive has no
    -- equipment grid in the base game and so cannot be made to wear an arm here.
    assert.has_no.errors(function()
      slow(player, locomotive, tiers.list[1].stickers)
    end)
    assert.is_nil(world.sticker_on(locomotive),
      "a locomotive took a slowdown sticker after all")
    locomotive.destroy()
  end)
end)
