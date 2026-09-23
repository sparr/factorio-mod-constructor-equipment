--- How the slowdown behaves, now that it is a sticker rather than a number.
---
--- The number was character_running_speed_modifier, which every mod shares. The point of
--- the sticker is that this mod no longer writes to anything anyone else can see, and
--- that the slowdown ends on its own rather than because the mod remembered to end it.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
--- Skipped wholesale while the walking penalty is switched off, rather than deleted: the
--- switch is meant to be flipped back. See tiers.SLOWS.
local slowed_describe = tiers.SLOWS and describe or describe.skip
local slowed_it = tiers.SLOWS and it or it.skip

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
  world.equipped(player)
  player.insert{ name = BELT, count = 20 }
end)

after_each(function()
  for _, sticker in pairs(player.character.stickers or {}) do sticker.destroy() end
  world.clear(player)
  player.character_running_speed_modifier = 0
end)

slowed_describe("the slowdown", function()
  it("is one sticker of the mod's own", function()
    world.ghost(player, BELT, 2, 0)
    after_ticks(world.DELIVERED, function()
      assert.are.equal(1, world.stickers(player), "expected exactly one sticker")
      assert.is_not_nil(world.slowed_by(player), "and it should be the mod's own")
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
      assert.is_nil(world.slowed_by(player), "the sticker should have run out")
    end)
  end)
end)

--- Once there is nothing left in reach, the flat slowdown is swapped for one that
--- interpolates back up to full speed over its lifetime, so the character accelerates
--- rather than snapping back. The ramp belongs at the end because that is the only place
--- there is one of it: while there is work, the slowdown's life keeps being restarted, and
--- an interpolating sticker would restart with it and read as a stutter.
slowed_describe("coming back up to speed", function()
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
    -- Sampled whenever the recovery sticker is actually on, rather than at offsets guessed
    -- from how long a build takes. The ramp is only 45 ticks long, and every change to how
    -- fast the arm swings moves when it starts: fixed offsets kept sliding off the end of
    -- it and catching nothing but full speed.
    for n = 30, 160, 4 do
      after_ticks(n, function()
        if world.slowdown(player, world.RECOVERY) then sample() end
      end)
    end
    after_ticks(170, function()
      assert.is_true(#samples >= 4,
        "the recovery was only seen " .. #samples .. " times")
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
  it("is slowed again when there is something to build again", function()
    world.ghost(player, BELT, 2, 0)
    -- The exact tick the recovery starts on depends on how long the swing took, so this
    -- watches for it across a window rather than naming a tick. The second ghost goes down
    -- afterwards, and what matters is that the character is slowed again without the two
    -- stickers ever being on at once.
    local recovered_at, both_seen, slowed_after = nil, false, false
    for n = 0, 24 do
      after_ticks(world.CYCLE + n * 8, function()
        if not recovered_at and world.slowdown(player, world.RECOVERY) then
          recovered_at = n
        end
        if world.stickers(player) > 1 then both_seen = true end
      end)
    end
    local PLACED = world.CYCLE + 25 * 8
    after_ticks(PLACED, function()
      world.ghost(player, BELT, -2, 0)
    end)
    for n = 1, 20 do
      after_ticks(PLACED + n * 8, function()
        if world.slowed_by(player) then slowed_after = true end
        if world.stickers(player) > 1 then both_seen = true end
      end)
    end
    after_ticks(PLACED + 200, function()
      assert.are.equal(2, world.count(player, BELT), "both belts should be up by now")
      assert.is_not_nil(recovered_at,
        "it never started recovering after running out of things to build")
      assert.is_true(slowed_after,
        "it was never slowed again after finding something else to build")
      assert.is_false(both_seen,
        "the slowdown and the recovery were on the character at the same time")
    end)
  end)
end)

--- Builds come every BUILD_INTERVAL ticks and the sticker lasts longer than that, so a
--- run of building never lets it lapse. What the second build must not do is add another
--- sticker: two of the same name do not stack, so a second one would sit there doing
--- nothing while the first expired on its original schedule, and the character would
--- speed up in the middle of a run.
slowed_describe("building several things in a row", function()
  it("keeps one sticker rather than piling them up", function()
    world.several(player, BELT, 5)
    -- partway through the run rather than after it: sampled once the run is over, the
    -- slowdown has rightly gone and there is nothing left to count
    after_ticks(world.CYCLE * 3, function()
      assert.is_true(world.count(player, BELT) >= 3,
        "not enough got built to be a run: " .. world.count(player, BELT))
      assert.are.equal(1, world.stickers(player),
        "the stickers piled up instead of being refreshed")
    end)
  end)

  it("keeps the slowdown unbroken across builds", function()
    world.several(player, BELT, 6)
    -- sampled right before each build is due, which is when a sticker that was not
    -- refreshed would have lapsed
    local lapses, seen = 0, 0
    local function sample()
      seen = seen + 1
      if not world.slowed_by(player) then lapses = lapses + 1 end
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

  -- Only the flat sticker is refreshed. The ramp is deliberately left to run: refreshing
  -- that would start the descent again and the character would surge mid-run. So this
  -- waits for the ramp to have finished handing over before it measures anything.
  it("refreshes the flat sticker rather than letting it run down", function()
    world.several(player, BELT, 6)
    local first
    after_ticks(world.RAMP_TICKS + world.CYCLE, function()
      local sticker = world.slowdown(player)
      assert.is_not_nil(sticker, "the flat sticker never took over from the ramp")
      first = sticker.time_to_live
    end)
    after_ticks(world.RAMP_TICKS + world.CYCLE * 2 + 10, function()
      local sticker = world.slowdown(player)
      assert.is_not_nil(sticker, "the slowdown went away mid-run")
      assert.is_true(sticker.time_to_live > first - world.CYCLE,
        ("it was not refreshed: %d ticks left, having started at %d")
          :format(sticker.time_to_live, first))
    end)
  end)
end)

--- A reach of two tiles takes longer than the interval between reaches, so the arm is
--- always still swinging when the next one falls due. A reach of one does not: the claw
--- gets home with ticks to spare and stands there waiting for the clock.
---
--- Those gaps used to end the slowdown. Recovery went by whether an arm was swinging,
--- which had been the same question as whether there was anything left to build only
--- because the gap never existed. Once it did, the character surged between every ghost
--- along a blueprint.
slowed_describe("building things close enough together to leave gaps", function()
  local NEAR = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 1, 1 }, { -1, 1 }, { 1, -1 } }

  local function near_ghosts()
    for _, spot in pairs(NEAR) do world.ghost(player, BELT, spot[1], spot[2]) end
  end

  it("does not start recovering in the gaps", function()
    near_ghosts()
    local recovering, sampled = 0, 0
    for n = 20, 150, 2 do
      after_ticks(n, function()
        -- only while there is still something to build: recovering after the last one is
        -- the whole point of the thing
        if world.ghosts(player) > 0 then
          sampled = sampled + 1
          if world.slowdown(player, world.RECOVERY) then recovering = recovering + 1 end
        end
      end)
    end
    after_ticks(160, function()
      assert.is_true(sampled > 20, "the run was over too soon to sample: " .. sampled)
      assert.are.equal(0, recovering,
        "it began giving the speed back " .. recovering .. " times out of " .. sampled
        .. " with ghosts still standing")
    end)
  end)

  it("stays slowed all the way through", function()
    near_ghosts()
    local lapses, sampled = 0, 0
    for n = 20, 150, 2 do
      after_ticks(n, function()
        if world.ghosts(player) > 0 then
          sampled = sampled + 1
          if not world.slowed_by(player) then lapses = lapses + 1 end
        end
      end)
    end
    after_ticks(160, function()
      assert.is_true(sampled > 20, "the run was over too soon to sample: " .. sampled)
      assert.are.equal(0, lapses,
        "the slowdown lapsed " .. lapses .. " times out of " .. sampled .. " samples")
    end)
  end)
end)
