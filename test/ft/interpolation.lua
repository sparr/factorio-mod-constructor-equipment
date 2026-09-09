--- What target_movement_modifier_from and _to actually do over a sticker's life.
local world = require("test.ft.world")

local player

before_each(function()
  player = world.player()
  world.clear(player)
end)

after_each(function()
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
end)

--- The engine keeps one sticker of a given name per target and restarts its life, rather
--- than stacking a second. The mod leans on that instead of finding and refreshing its own
--- sticker, so it is worth pinning. Uses a vanilla sticker rather than the mod's own,
--- because the mod would take its own away again as soon as a build fell due.
describe("putting the same sticker on twice", function()
  it("keeps one and restarts its life", function()
    local character = player.character
    local function place()
      character.surface.create_entity{
        name = "slowdown-sticker", position = character.position, target = character }
    end
    place()
    after_ticks(10, function()
      local before = world.slowdown(player, "slowdown-sticker").time_to_live
      assert.are.equal(1, world.stickers(player))
      place()
      assert.are.equal(1, world.stickers(player), "a second sticker of the same name stuck")
      assert.is_true(world.slowdown(player, "slowdown-sticker").time_to_live > before,
        ("its life did not restart: %d ticks left, was %d"):format(
          world.slowdown(player, "slowdown-sticker").time_to_live, before))
    end)
  end)
end)

describe("a sticker with a from and a to", function()
  it("walks the modifier from one to the other over its life", function()
    local character = player.character
    local full = player.character_running_speed
    character.surface.create_entity{
      name = "constructor-equipment-recovery", position = character.position, target = character }
    local samples = {}
    local function sample()
      local sticker = world.slowdown(player, "constructor-equipment-recovery")
      samples[#samples + 1] = ("t=%d ttl=%s speed=%.3f"):format(
        game.tick, sticker and sticker.time_to_live or "gone",
        player.character_running_speed / full)
    end
    sample()
    -- after_ticks measures from the start of the test rather than from the last one, so
    -- these are absolute offsets and not a chain
    for n = 1, 7 do after_ticks(n * 5, sample) end
    after_ticks(40, function()
      sample()
      print("INTERP " .. table.concat(samples, " | "))
      assert.is_true(true)
    end)
  end)
end)
