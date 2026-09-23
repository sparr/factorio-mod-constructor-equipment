--- What the equipment does about a cliff marked for deconstruction.
---
--- A cliff is not something an arm can take apart. It is a delivery: the claw carries an
--- explosive out and comes home empty, which is what a construction robot does with one.
--- Measured on 2.1.17, a marked cliff stood untouched while a network with no explosives
--- finished everything else around it, and went the moment one reached a chest.
local world = require("test.ft.world")

--- Comfortably more than one swing, so a test is not at the mercy of which tick of the
--- check cycle it started on. Built on the swing rather than on world.BUILD_INTERVAL, which
--- is a leftover from when the mod capped its own build rate and has nothing to do with how
--- long a reach takes: two of those intervals is sixty ticks, and a first tier arm reaching
--- the edge of its two tiles wants up to sixty three.
local A_BUILD = world.DELIVERED
local EXPLOSIVE = "cliff-explosives"

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  player = world.player()
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

--- The fourth tier, which reaches five tiles. A cliff lies on a four tile grid and comes to
--- rest two and a half tiles from the middle of the arena at the nearest, which the first
--- tier's two tiles cannot get to.
local FAR_ENOUGH = { "constructor-equipment-4", "battery-equipment" }

describe("a cliff marked for deconstruction", function()
  before_each(function()
    world.equip(player, FAR_ENOUGH, true, "power-armor")
  end)

  it("is blown up when the character is carrying an explosive", function()
    local cliff = world.cliff(player, 2, 0)
    if not cliff then return end
    player.insert{ name = EXPLOSIVE, count = 3 }
    after_ticks(A_BUILD, function()
      assert.are.equal(0, player.surface.count_entities_filtered{ type = "cliff" },
        "the cliff is still standing")
    end)
  end)

  it("costs one explosive", function()
    local cliff = world.cliff(player, 2, 0)
    if not cliff then return end
    player.insert{ name = EXPLOSIVE, count = 3 }
    after_ticks(A_BUILD, function()
      assert.are.equal(2, player.get_item_count(EXPLOSIVE),
        "one of the three should have gone")
    end)
  end)

  it("is left alone with nothing to blow it up with", function()
    local cliff = world.cliff(player, 2, 0)
    if not cliff then return end
    after_ticks(A_BUILD, function()
      assert.are.equal(1, player.surface.count_entities_filtered{ type = "cliff" },
        "a cliff went up without an explosive being spent on it")
    end)
  end)

  it("leaves an unmarked cliff standing", function()
    local cliff = world.cliff(player, 2, 0)
    if not cliff then return end
    cliff.cancel_deconstruction(player.force)
    player.insert{ name = EXPLOSIVE, count = 3 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, player.surface.count_entities_filtered{ type = "cliff" },
        "a cliff nobody marked was blown up")
      assert.are.equal(3, player.get_item_count(EXPLOSIVE), "an explosive was spent anyway")
    end)
  end)

  it("leaves one out of reach alone", function()
    local cliff = world.cliff(player, 20, 0)
    if not cliff then return end
    player.insert{ name = EXPLOSIVE, count = 3 }
    after_ticks(A_BUILD, function()
      assert.are.equal(1, player.surface.count_entities_filtered{ type = "cliff" },
        "it reached further than its range")
    end)
  end)
end)
