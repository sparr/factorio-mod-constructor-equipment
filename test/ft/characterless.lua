--- A player with no character.
---
--- This is not an exotic state: it is every player during freeplay's opening cutscene,
--- and anyone in the map editor or spectating. The mod read
--- character_running_speed_modifier without checking, which raises "No character", so a
--- new game crashed on its first tick. These are here to keep that shut.
local world = require("test.ft.world")

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  -- world.player puts the controller back to a character before asking for one, which
  -- create_character insists on: it refuses outright from a spectator.
  player = world.player()
  world.clear(player)
end)

describe("a player with no character", function()
  it("is left alone rather than crashed on", function()
    world.ghost(player, "transport-belt", 2, 0)
    player.character.destroy()
    assert.is_nil(player.character, "the character did not actually go away")
    -- the mod runs every sixth tick; several of those with no character is the case that
    -- used to raise "No character" on the first tick of a new game
    after_ticks(30, function()
      assert.is_nil(player.character)
      assert.are.equal(1, world.ghosts(player), "something built without a character")
    end)
  end)

  it("is left alone while spectating", function()
    world.equipped(player)
    player.insert{ name = "transport-belt", count = 5 }
    world.ghost(player, "transport-belt", 2, 0)
    player.set_controller{ type = defines.controllers.spectator }
    after_ticks(30, function()
      assert.is_nil(player.character)
      assert.are.equal(1, world.ghosts(player), "a spectator built something")
    end)
  end)
end)
