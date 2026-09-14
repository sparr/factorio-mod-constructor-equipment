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

--- Part way through a reach, which is when there is a slowdown to look at. One ghost is one
--- swing, and a swing that has been and gone takes its slowdown with it.
local MID_REACH = 30

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
    after_ticks(12, function()
      assert.are.equal(4, tank.get_item_count(BELT),
        "the arm should have taken a belt out of the hold to carry")
      -- getting out puts the arms away mid reach, which is the moment the load has to go
      -- back somewhere
      player.driving = false
      after_ticks(2, function()
        assert.are.equal(5, tank.get_item_count(BELT),
          "the belt in the claw did not go back into the vehicle")
        assert.are.equal(0, player.get_item_count(BELT),
          "the belt in the claw went into the driver's pockets instead")
      end)
    end)
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
      -- the roof
      tank.orientation = 0.75
      after_ticks(2, function()
        local north = world.arm(player).position.y - tank.position.y
        assert.is_true(math.abs(north + across) < 0.05,
          ("the northern arm sits %.2f out rather than the box's own %.2f")
            :format(north, -across))
      end)
    end)
  end)

  it("carries a spider vehicle's arms up to its body", function()
    local spider = player.surface.create_entity{
      name = "spidertron", position = world.ORIGIN, force = player.force }
    world.fitted(spider)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 5 }
    world.ghost(player, BELT, beside(spider))
    after_ticks(12, function()
      local arm = world.arm(player)
      assert.is_not_nil(arm, "the spidertron grew no arm")
      local height = spider.prototype.height
      assert.is_not_nil(height, "a spidertron should say how high it rides")
      -- its body rides a tile and a half up its legs, and every arm goes up with it
      local up = spider.position.y - arm.position.y
      assert.is_true(math.abs(up - height) < 0.05,
        ("the arm sits %.2f above the spidertron, which rides %.2f up"):format(up, height))
      spider.destroy()
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
      -- Facing east, its sides are north and south of it. The northern one sits square on
      -- the side; the southern one is lifted onto the near face of the hull, which is drawn
      -- above the ground it stands on.
      local out = {}
      for _, arm in pairs(arms) do table.insert(out, arm.position.y - tank.position.y) end
      table.sort(out)
      assert.is_true(math.abs(out[1] + across) < 0.05,
        ("the northern arm sits %.2f out rather than the side's own %.2f")
          :format(out[1], -across))
      assert.is_true(out[2] > 0 and out[2] < across,
        ("the southern arm sits %.2f out, where the side is %.2f"):format(out[2], across))
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
    world.fitted(spider)
    spider.set_driver(player)
    spider.insert{ name = BELT, count = 20 }
    world.ghost(player, BELT, beside(spider))
    after_ticks(MID_REACH, function()
      assert.is_not_nil(world.slowing_anything(spider), "the spidertron was never slowed")
      assert.is_not_nil(world.sticker_on(spider, tiers.list[1].stickers.legs.flat)
        or world.sticker_on(spider, tiers.list[1].stickers.legs.slowing),
        "the spidertron took the wheeled slowdown rather than the legged one")
      after_ticks(A_VEHICLE_BUILD, function()
        assert.is_true(world.count(player, BELT) > 0, "the spidertron's own arm built nothing")
        spider.destroy()
      end)
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
      world.fitted(spider)
      spider.set_driver(player)
      spider.insert{ name = BELT, count = 5 }
      -- the lone arm stands out on the spidertron's right, a tile east of it, so these two
      -- spots are the same distance from it and on opposite sides
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
        -- the arms are given work ten times a second, so two builds of the same length can
        -- still land a handful of ticks apart
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

describe("the slowdown a vehicle's arms ask for", function()
  local tank

  before_each(function()
    tank = world.vehicle(player)
    world.fitted(tank)
    tank.insert{ name = BELT, count = 20 }
  end)

  it("lands on the vehicle", function()
    world.ghost(player, BELT, beside(tank))
    after_ticks(MID_REACH, function()
      assert.is_not_nil(world.slowing_anything(tank), "the vehicle was never slowed")
    end)
  end)

  it("does not land on the driver", function()
    world.ghost(player, BELT, beside(tank))
    after_ticks(MID_REACH, function()
      assert.is_nil(world.slowing_anything(player.character),
        "the driver was slowed as well as the vehicle they are sat in")
    end)
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
    after_ticks(MID_REACH, function()
      assert.is_not_nil(world.slowing_anything(tank), "the vehicle was never slowed")
      player.driving = false
      after_ticks(2, function()
        assert.is_nil(world.slowing_anything(tank),
          "the vehicle is still slowed by arms nobody is driving")
      end)
    end)
  end)
end)
