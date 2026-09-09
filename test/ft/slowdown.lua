--- How the slowdown behaves, now that it is a sticker rather than a number.
---
--- The number was character_running_speed_modifier, which every mod shares. The point of
--- the sticker is that this mod no longer writes to anything anyone else can see, and
--- that the slowdown ends on its own rather than because the mod remembered to end it.
local world = require("test.ft.world")

local A_BUILD = world.BUILD_INTERVAL * 2
local BELT = "transport-belt"

local player

before_each(function()
  player = world.player()
  world.clear(player)
  world.equipped(player)
  player.insert{ name = BELT, count = 20 }
end)

after_each(function()
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

describe("the slowdown", function()
  it("is one sticker of the mod's own", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.stickers(player), "expected exactly one sticker")
      assert.is_not_nil(world.slowdown(player), "and it should be the mod's own")
    end)
  end)

  -- the whole reason for the change: another mod's modifier is nobody else's to touch
  it("leaves another mod's speed modifier alone", function()
    player.character_running_speed_modifier = -0.5
    world.ghost(player, BELT, 2, 0)
    after_ticks(A_BUILD, function()
      assert.are.equal(1, world.count(player, BELT), "it did not build, so this proves nothing")
      assert.are.equal(-0.5, player.character_running_speed_modifier,
        "the mod overwrote a modifier that was not its own")
    end)
  end)

  it("composes with another mod's modifier rather than replacing it", function()
    local full = player.character_running_speed
    player.character_running_speed_modifier = -0.5
    local halved = player.character_running_speed
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.is_true(player.character_running_speed < halved,
        ("both effects should apply: full %.4f, halved %.4f, now %.4f")
          :format(full, halved, player.character_running_speed))
    end)
  end)

  it("ends by itself, with nothing having to remember to end it", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.SLOWDOWN_TICKS + A_BUILD, function()
      assert.is_nil(world.slowdown(player), "the sticker should have run out")
    end)
  end)
end)

--- Once there is nothing left in reach, the flat slowdown is swapped for one that
--- interpolates back up to full speed over its lifetime, so the character accelerates
--- rather than snapping back. The ramp belongs at the end because that is the only place
--- there is one of it: while there is work, the slowdown's life keeps being restarted, and
--- an interpolating sticker would restart with it and read as a stutter.
describe("coming back up to speed", function()
  local BELT_FULL

  before_each(function()
    BELT_FULL = player.character_running_speed
  end)

  -- The recovery only exists between the build falling due with nothing to do and its own
  -- expiry, which is a window rather than a moment, so this looks across it rather than
  -- picking a tick and hoping.
  it("takes over from the flat slowdown once there is nothing left", function()
    world.ghost(player, BELT, 2, 0)
    local recovery_seen, both_seen = false, false
    local function sample()
      if world.slowdown(player, "constructor-equipment-recovery") then recovery_seen = true end
      if world.stickers(player) > 1 then both_seen = true end
    end
    for n = 0, 11 do after_ticks(world.DELIVERED + n * 6, sample) end
    after_ticks(world.DELIVERED + 80, function()
      assert.are.equal(1, world.count(player, BELT), "it never built, so this proves nothing")
      assert.is_true(recovery_seen, "nothing took over to bring the speed back")
      assert.is_false(both_seen, "the flat slowdown and the recovery overlapped")
    end)
  end)

  it("rises rather than jumping", function()
    world.ghost(player, BELT, 2, 0)
    local samples = {}
    local function sample()
      samples[#samples + 1] = player.character_running_speed / BELT_FULL
    end
    for n = 0, 3 do after_ticks(world.BUILD_INTERVAL + 6 + n * 8, sample) end
    after_ticks(world.BUILD_INTERVAL + 50, function()
      assert.are.equal(4, #samples, "the samples did not all run")
      local text = {}
      for i, v in pairs(samples) do text[i] = ("%.3f"):format(v) end
      assert.is_true(samples[1] < 0.9,
        "it was already at full speed on the first sample: " .. table.concat(text, " "))
      for i = 2, #samples do
        assert.is_true(samples[i] >= samples[i - 1],
          "the speed went backwards: " .. table.concat(text, " "))
      end
      assert.is_true(samples[#samples] > samples[1],
        "the speed never came up: " .. table.concat(text, " "))
      -- the point of the ramp: a slowdown that simply ended would only ever be seen at a
      -- quarter speed or at full, never partway
      local partway = false
      for _, fraction in pairs(samples) do
        if fraction > 0.3 and fraction < 0.95 then partway = true end
      end
      assert.is_true(partway,
        "it jumped from slow to full without passing through: " .. table.concat(text, " "))
    end)
  end)

  it("finishes at full speed with nothing left on the character", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.BUILD_INTERVAL + world.SLOWDOWN_TICKS + 40, function()
      assert.are.equal(0, world.stickers(player), "something is still stuck to the character")
      assert.are.equal(BELT_FULL, player.character_running_speed)
    end)
  end)

  -- both stickers at once would multiply, so someone who paused and started again would
  -- end up slower than someone who never stopped
  -- both stickers at once would multiply, so someone who paused and started again would
  -- end up slower than someone who never stopped. The flat slowdown only lasts until the
  -- next build falls due with nothing to build, so this samples across the window rather
  -- than guessing which tick to look on.
  it("goes back to the flat slowdown when there is something to build again", function()
    world.ghost(player, BELT, 2, 0)
    local recovering = false
    after_ticks(world.BUILD_INTERVAL * 2, function()
      recovering = world.slowdown(player, "constructor-equipment-recovery") ~= nil
      world.ghost(player, BELT, -2, 0)
    end)
    local flat_seen, both_seen = false, false
    local function sample()
      if world.slowdown(player) then flat_seen = true end
      if world.stickers(player) > 1 then both_seen = true end
    end
    for n = 0, 13 do after_ticks(world.BUILD_INTERVAL * 2 + 6 + n * 6, sample) end
    after_ticks(world.BUILD_INTERVAL * 2 + 100, function()
      assert.is_true(recovering, "it should have been recovering when the second ghost went down")
      assert.are.equal(2, world.count(player, BELT), "the second belt was never built")
      assert.is_false(both_seen,
        "the flat slowdown and the recovery were on the character at the same time")
      assert.is_true(flat_seen,
        "the flat slowdown never came back after it found something else to build")
    end)
  end)
end)

--- Builds come every BUILD_INTERVAL ticks and the sticker lasts longer than that, so a
--- run of building never lets it lapse. What the second build must not do is add another
--- sticker: two of the same name do not stack, so a second one would sit there doing
--- nothing while the first expired on its original schedule, and the character would
--- speed up in the middle of a run.
describe("building several things in a row", function()
  it("keeps one sticker rather than piling them up", function()
    for i = 1, 5 do world.ghost(player, BELT, i - 3, 2) end
    -- one build per interval, and the first does not start until the first check tick
    after_ticks(world.BUILD_INTERVAL * 5, function()
      assert.is_true(world.count(player, BELT) >= 3,
        "not enough got built to be a run: " .. world.count(player, BELT))
      assert.are.equal(1, world.stickers(player),
        "the stickers piled up instead of being refreshed")
    end)
  end)

  it("keeps the slowdown unbroken across builds", function()
    for i = 1, 6 do world.ghost(player, BELT, i - 4, 2) end
    -- sampled right before each build is due, which is when a sticker that was not
    -- refreshed would have lapsed
    local lapses, seen = 0, 0
    local function sample()
      seen = seen + 1
      if not world.slowdown(player) then lapses = lapses + 1 end
    end
    -- after_ticks counts from the start of the test rather than from the last one, so
    -- these are absolute offsets. Sampled just before each build falls due, which is when
    -- a slowdown that had not been kept alive would have lapsed.
    -- sampled just before each build falls due, from after the first delivery onwards
    for n = 1, 4 do after_ticks(world.DELIVERED + n * world.BUILD_INTERVAL - 2, sample) end
    after_ticks(world.DELIVERED + world.BUILD_INTERVAL * 4 + 5, function()
      assert.are.equal(4, seen, "the samples did not all run")
      assert.are.equal(0, lapses,
        "the slowdown lapsed " .. lapses .. " times during a continuous run")
    end)
  end)

  it("refreshes the sticker's remaining life rather than letting it run down", function()
    world.ghost(player, BELT, 2, 0)
    world.ghost(player, BELT, 3, 0)
    local first
    after_ticks(world.DELIVERED, function()
      first = world.slowdown(player).time_to_live
    end)
    -- past the next build, which should have set it back to its full life
    after_ticks(world.BUILD_INTERVAL + 5, function()
      local sticker = world.slowdown(player)
      assert.is_not_nil(sticker, "the slowdown went away mid-run")
      assert.is_true(sticker.time_to_live > first - world.BUILD_INTERVAL,
        ("it was not refreshed: %d ticks left, having started at %d")
          :format(sticker.time_to_live, first))
    end)
  end)
end)
