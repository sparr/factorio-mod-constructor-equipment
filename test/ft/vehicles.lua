--- Riding rather than walking: whose grid the arms come out of, and who pays for them.
---
--- The trade the mod offers on foot is building for walking speed. A driver is not walking,
--- so armour worn in a seat would be building for nothing. What they get instead is a
--- vehicle that wears the equipment itself, mounts the arms on its own hull, and takes the
--- same fraction off its own speed.
local world = require("test.ft.world")
local tiers = require("lib.tiers")

local BELT = "transport-belt"
--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- check cycle it started on. Built on the swing rather than on world.BUILD_INTERVAL, which
--- is a leftover from when the mod capped its own build rate and has nothing to do with how
--- long a reach takes: two of those intervals is sixty ticks, and a first tier arm reaching
--- the edge of its two tiles wants up to sixty three.
local A_BUILD = world.DELIVERED

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

  --- A tank is the one vanilla vehicle with a turret, and its arms go on that rather than
  --- out on its flanks: see TURRETED in control.lua. Turned north, the two arrangements are
  --- far apart -- a flank arm sits two thirds of a tile east or west of the hull's middle
  --- and square on the ground, where a turret arm sits on the middle and is drawn north of
  --- it, up on the turret -- so north is the facing these are asked in.
  it("mounts a lone arm on the tank's turret", function()
    local tank = world.vehicle(player)
    tank.orientation = 0
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 0, -2)
    after_ticks(12, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "the vehicle grew no arm")
      assert.is_true(math.abs(arm.position.x - tank.position.x) < 0.05,
        ("the arm sits %.2f off the middle of the hull, which is out on a flank")
          :format(arm.position.x - tank.position.x))
      -- The turret's round part runs from 0.60 to 1.62 north of the tank's own position,
      -- and an arm bolted to it stands at the bottom edge.
      local up = tank.position.y - arm.position.y
      assert.is_true(up > 0.35 and up < 0.9,
        ("the arm is drawn %.2f north of the tank, where the turret's foot is 0.60")
          :format(up))
    end)
  end)

  --- A turret sits over the middle of its hull whichever way the hull is pointed, so an arm
  --- bolted to one stays put as the vehicle turns. This is what the tank has instead of the
  --- near side lift, which it used to take out on its flanks: the lift itself is
  --- pack.nearness, and lives in test/spec/pack_spec.lua, since no vanilla vehicle with an
  --- equipment grid mounts on its flanks any more.
  it("keeps a tank's arm on its turret as the hull turns", function()
    local tank = world.vehicle(player)
    tank.orientation = 0
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, 0, -2)
    after_ticks(12, function()
      local first = world.arm(player).position
      local up = tank.position.y - first.y
      tank.orientation = 0.25
      after_ticks(2, function()
        local turned = world.arm(player).position
        assert.is_true(math.abs(turned.x - tank.position.x) < 0.05,
          ("the arm swung %.2f off the middle when the hull turned")
            :format(turned.x - tank.position.x))
        assert.is_true(math.abs((tank.position.y - turned.y) - up) < 0.05,
          ("the arm was drawn %.2f north facing north and %.2f facing east")
            :format(up, tank.position.y - turned.y))
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

  -- Two of them ring the turret the way two on a character ring the middle of their back:
  -- side by side and level, rather than one a side of the hull.
  it("rings a pair of arms round the tank's turret", function()
    local tank = world.vehicle(player)
    tank.orientation = 0
    world.fit(tank, { "constructor-equipment", "constructor-equipment", "battery-equipment" },
      true)
    tank.insert{ name = BELT, count = 5 }
    world.several(player, BELT, 4)
    after_ticks(12, function()
      local arms = world.arms(player)
      assert.are.equal(2, #arms, "two of the equipment did not grow two arms")
      local across, up = {}, {}
      for _, arm in pairs(arms) do
        table.insert(across, arm.position.x - tank.position.x)
        table.insert(up, tank.position.y - arm.position.y)
      end
      table.sort(across)
      assert.is_true(across[1] < -0.05 and across[2] > 0.05,
        ("the pair sits at %.2f and %.2f across, which is not a pair at all")
          :format(across[1], across[2]))
      assert.is_true(math.abs(across[1] + across[2]) < 0.05,
        "the pair is not centred on the turret")
      -- Both on the same side of the ring, so they read as two arms rather than as a pair
      -- of hips: the top two of the arrangement of four.
      assert.is_true(math.abs(up[1] - up[2]) < 0.05,
        ("one is drawn %.2f north and the other %.2f"):format(up[1], up[2]))
      assert.is_true(up[1] > 0.35, ("the pair is drawn %.2f north, off the turret")
        :format(up[1]))
      -- On the turret and nowhere near the flanks, which on a tank facing north are two
      -- thirds of a tile east and west.
      assert.is_true(math.abs(across[1]) < 0.4,
        ("the pair sits %.2f out, which is on the flanks"):format(across[1]))
    end)
  end)

  -- A reach is measured from where the arm is bolted, which for a spidertron is a leg and
  -- not the middle of it: a leg mount is most of a tile out, so a spot the torso could not
  -- reach is well inside what the arm on the leg nearest it can.
  it("reaches from the arm's own base rather than from the middle of the vehicle", function()
    local spider = player.surface.create_entity{
      name = "spidertron", position = world.ORIGIN, force = player.force }
    world.fit(spider, SPIDER_ARMS, true)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 50 }
    local range = tiers.list[1].range
    local mounts = leg_mounts(spider)
    local furthest = 0
    for _, mount in pairs(mounts) do
      furthest = math.max(furthest, math.sqrt(mount.x * mount.x + mount.y * mount.y))
    end
    assert.is_true(furthest > 0.4,
      ("the legs are only %.2f off the middle, which is no test at all"):format(furthest))
    -- Out past what the middle could reach and inside what the nearest leg can, which on a
    -- spidertron wants a corner rather than a beam: the legs are most of a tile out
    -- diagonally and barely half a tile out square. Whole tiles, because a one by one ghost
    -- snaps to the middle of a tile and a spot worked out to two decimal places is not the
    -- spot the ghost ends up on.
    local dx, dy = 1, -2
    local away = math.sqrt(dx * dx + dy * dy)
    assert.is_true(away > range,
      ("%.2f tiles out is inside the %.2f the middle itself reaches"):format(away, range))
    local nearest = math.huge
    for _, mount in pairs(mounts) do
      nearest = math.min(nearest,
        math.sqrt((dx - mount.x) ^ 2 + (dy - mount.y) ^ 2))
    end
    assert.is_true(nearest < range,
      ("the nearest leg is %.2f off it, which is past the %.2f an arm reaches")
        :format(nearest, range))
    world.ghost(player, BELT, dx, dy)
    after_ticks(A_VEHICLE_BUILD, function()
      assert.are.equal(1, world.count(player, BELT),
        ("nothing was built %.2f tiles out, where the middle cannot reach and a leg can")
          :format(away))
      spider.destroy()
    end)
  end)

  -- The other side of mounting on the turret: it sits over the middle of the hull, so a
  -- tank's reach is the same off its nose as off its flank. Out on the flanks it was not --
  -- an arm on the side could not stretch to the front of its own tank -- and that is the
  -- price of putting them where a player looks.
  it("reaches as far off a tank's nose as off its flank", function()
    local tank = world.vehicle(player)
    tank.orientation = 0
    world.fitted(tank)
    tank.insert{ name = BELT, count = 5 }
    local range = tiers.list[1].range
    -- The nose, which is past the hull's own end, and the flank, which is past its side.
    world.ghost(player, BELT, 0, -range)
    world.ghost(player, BELT, range, 0)
    after_ticks(A_VEHICLE_BUILD * 2, function()
      assert.are.equal(2, world.count(player, BELT),
        ("only %d of the two went up, so the reach is not the same all round")
          :format(world.count(player, BELT)))
      assert.are.equal(0, world.ghosts(player), "a ghost is still standing there")
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
    after_ticks(A_VEHICLE_BUILD, function()
      assert.is_true(world.count(player, BELT) > 0, "the spidertron's own arms built nothing")
      spider.destroy()
    end)
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

