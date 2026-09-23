--- What an arm will and will not do to the ground its owner is standing on.
---
--- There are several kinds of job and they are not alike. Building wants the space the
--- player is occupying and cannot have it. Taking something up wants nothing of the sort --
--- a heap of plates is most often exactly where you are standing, and bending down for it
--- is what a person does. Upgrading swaps a thing for another of the same footprint. A
--- cliff is solid and nobody stands on one at all.
---
--- The mod already draws some of those distinctions: standing_in() lets a taking job and a
--- cliff through and stops a build, and choose() sorts what its owner stands on to the back
--- of the queue rather than out of it. What this measures is what actually happens, job by
--- job, with the work directly underfoot and the same work a tile away as the control.
local world = require("test.ft.world")
local reach = require("lib.reach")

--- Long enough for several journeys, since anything underfoot is done last by design.
local WATCH = world.CYCLE * 6

describe("work under its owner's own feet", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 20 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
    local flat = {}
    for x = -4, 4 do
      for y = -4, 4 do
        flat[#flat + 1] = { name = "grass-1",
          position = { world.ORIGIN.x + x, world.ORIGIN.y + y } }
      end
    end
    player.surface.set_tiles(flat)
  end

  before_each(function()
    player = world.player()
    player.walking_state = { walking = false }
    world.clear(player)
    scrub()
    world.equip(player, { "constructor-equipment-4", "battery-mk2-equipment" }, true,
      "power-armor")
  end)

  after_each(function()
    scrub()
    world.clear(player)
  end)

  --- Each job, laid at an offset from the character. Nought is underfoot.
  local KINDS = {
    {
      name = "an item lying on the ground, marked",
      lay = function(surface, at, force)
        local item = surface.create_entity{ name = "item-on-ground", position = at,
          stack = { name = "iron-plate", count = 5 }, force = force }
        if item then item.order_deconstruction(force) end
        return item
      end,
      done = function(thing) return not thing.valid end,
    },
    {
      name = "a belt standing there, marked",
      lay = function(surface, at, force)
        local thing = surface.create_entity{ name = "transport-belt", position = at,
          direction = defines.direction.east, force = force }
        if thing then thing.order_deconstruction(force) end
        return thing
      end,
      done = function(thing) return not thing.valid end,
    },
    {
      name = "a floor tile, marked",
      lay = function(surface, at, force)
        surface.set_tiles{ { name = "concrete", position = { at.x, at.y } } }
        local tile = surface.get_tile(at.x, at.y)
        tile.order_deconstruction(force)
        return tile
      end,
      done = function(tile) return tile.name ~= "concrete" end,
    },
    {
      name = "a ghost waiting to be built",
      lay = function(surface, at, force)
        return surface.create_entity{ name = "entity-ghost", inner_name = "transport-belt",
          position = at, direction = defines.direction.east, force = force }
      end,
      done = function(thing) return not thing.valid end,
      stock = { name = "transport-belt", count = 5 },
    },
    {
      name = "a chest ghost, which collides with a character",
      lay = function(surface, at, force)
        return surface.create_entity{ name = "entity-ghost", inner_name = "iron-chest",
          position = at, force = force }
      end,
      done = function(thing) return not thing.valid end,
      stock = { name = "iron-chest", count = 5 },
    },
    {
      name = "an assembler ghost, three tiles across",
      lay = function(surface, at, force)
        return surface.create_entity{ name = "entity-ghost",
          inner_name = "assembling-machine-1", position = at, force = force }
      end,
      done = function(thing) return not thing.valid end,
      stock = { name = "assembling-machine-1", count = 5 },
    },
    {
      name = "a belt marked to be upgraded",
      lay = function(surface, at, force)
        local thing = surface.create_entity{ name = "transport-belt", position = at,
          direction = defines.direction.east, force = force }
        if thing then
          thing.order_upgrade{ force = force, target = "fast-transport-belt" }
        end
        return thing
      end,
      done = function(thing) return not thing.valid or thing.name == "fast-transport-belt" end,
      stock = { name = "fast-transport-belt", count = 5 },
    },
  }

  for _, kind in ipairs(KINDS) do
    for _, where in ipairs{ { name = "underfoot", dx = 0 },
                            { name = "a tile away", dx = 1 },
                            { name = "three tiles away", dx = 3 } } do
      it(("PROBE: %s, %s"):format(kind.name, where.name), function()
        local surface = player.surface
        player.get_inventory(defines.inventory.character_main).clear()
        if kind.stock then player.insert(kind.stock) end
        local at = { x = world.ORIGIN.x + where.dx, y = world.ORIGIN.y }
        local thing = kind.lay(surface, at, player.force)
        assert.is_not_nil(thing, "the work would not go down")

        after_ticks(WATCH, function()
          local record = (storage.constructor_arms[player.index] or {})[1]
          local job = record and record.job
          -- and what the engine itself would allow there, so that a refusal by the mod can
          -- be told apart from one by the game
          local allowed = surface.can_place_entity{
            name = "transport-belt", position = at, direction = defines.direction.east,
            force = player.force, build_check_type = defines.build_check_type.ghost_revive }
          local swappable = surface.can_place_entity{
            name = "fast-transport-belt", position = at,
            direction = defines.direction.east, force = player.force,
            build_check_type = defines.build_check_type.manual }
          log(("FOOT | engine at %s: a belt may be revived = %s, a belt may be swapped = %s")
            :format(where.name, tostring(allowed), tostring(swappable)))
          log(("FOOT | %-36s %-17s %-10s | arm %s, job %s"):format(
            kind.name, where.name, kind.done(thing) and "DONE" or "not done",
            record and record.entity and record.entity.valid and "out" or "away",
            job and ("%s going=%s take=%s"):format(tostring(job.item), tostring(job.going),
              tostring(job.take)) or "none"))
        end)
      end)
    end
  end

  --- The case the report came from: a heap of things underfoot with plenty else to do
  --- round it. Anything underfoot is sorted to the back of the queue on purpose, so the
  --- question is not whether an arm will stoop for it but whether it ever gets round to it
  --- while its owner stands there and the queue keeps refilling.
  it("PROBE: a heap underfoot with other work all round it", function()
    local surface = player.surface
    player.get_inventory(defines.inventory.character_main).clear()
    local under = {}
    for _ = 1, 4 do
      local item = surface.create_entity{ name = "item-on-ground",
        position = { world.ORIGIN.x, world.ORIGIN.y },
        stack = { name = "iron-plate", count = 10 }, force = player.force }
      if item then
        item.order_deconstruction(player.force)
        under[#under + 1] = item
      end
    end
    local around = 0
    for _, at in ipairs{ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 },
                         { 3, 2 }, { -3, 2 }, { 3, -2 }, { -3, -2 } } do
      local thing = surface.create_entity{ name = "transport-belt",
        position = { world.ORIGIN.x + at[1], world.ORIGIN.y + at[2] },
        direction = defines.direction.east, force = player.force }
      if thing then thing.order_deconstruction(player.force) around = around + 1 end
    end

    -- How long the lot takes, so that the reason the penalty was there -- that stooping is
    -- the slowest swing and costs the round its pace -- can be checked rather than argued.
    local began, cleared, heap_at = game.tick, nil, nil
    world.once(function()
      local left = 0
      for _, item in ipairs(under) do if item.valid then left = left + 1 end end
      if left == 0 and not heap_at then heap_at = game.tick - began end
      local standing = surface.count_entities_filtered{ name = "transport-belt",
        position = world.ORIGIN, radius = 10 }
      if left == 0 and standing == 0 then cleared = game.tick - began end
      return cleared ~= nil or game.tick - began > world.CYCLE * 14
    end, function()
      local left = 0
      for _, item in ipairs(under) do if item.valid then left = left + 1 end end
      local standing = surface.count_entities_filtered{ name = "transport-belt",
        position = world.ORIGIN, radius = 10 }
      -- Banished behind a hundred thousand ticks the heap went at 317 and the lot was
      -- clear at 317; with nothing added at all it went at 3 and the lot took until 592,
      -- because every journey after it began from a folded hand. One extension keeps both.
      log(("FOOT | a heap of %d underfoot and %d belts round it: heap taken at %s, all of"
        .. " it clear at %s | %d of the heap and %d belts left, %d plates home"):format(
        #under, around, tostring(heap_at), tostring(cleared), left, standing,
        player.get_item_count("iron-plate")))
    end, "never settled", world.CYCLE * 15)
  end)

  --- The same question asked at every ratio, because the charge above was settled on one.
  ---
  --- choose() prices work underfoot an extra full extension of the arm, on the grounds that
  --- stooping is the slowest swing there is: the hand comes all the way in, and whatever is
  --- next has to go all the way out again. That is measured and right for a claw choosing
  --- between one thing underfoot and one thing at arm's length.
  ---
  --- What it cannot be right for is a heap that is mostly underfoot, where the next job is
  --- another plate off the same heap and the hand never goes out again -- the charge is then
  --- paying for a journey nobody makes. This lays the same work in four ratios and logs what
  --- order it came in and how long the lot took, which is what says where the crossover is.
  for _, mix in ipairs{ { under = 1, around = 8 }, { under = 2, around = 8 },
                        { under = 4, around = 8 }, { under = 8, around = 4 },
                        { under = 8, around = 1 }, { under = 8, around = 0 } } do
    it(("PROBE: %d underfoot and %d round it"):format(mix.under, mix.around), function()
      local surface = player.surface
      player.get_inventory(defines.inventory.character_main).clear()
      local under = {}
      for _ = 1, mix.under do
        local item = surface.create_entity{ name = "item-on-ground",
          position = { world.ORIGIN.x, world.ORIGIN.y },
          stack = { name = "iron-plate", count = 10 }, force = player.force }
        if item then
          item.order_deconstruction(player.force)
          under[#under + 1] = item
        end
      end
      local SPOTS = { { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 },
                      { 3, 2 }, { -3, 2 }, { 3, -2 }, { -3, -2 } }
      local round = {}
      for i = 1, mix.around do
        local thing = surface.create_entity{ name = "transport-belt",
          position = { world.ORIGIN.x + SPOTS[i][1], world.ORIGIN.y + SPOTS[i][2] },
          direction = defines.direction.east, force = player.force }
        if thing then round[#round + 1] = thing end
      end
      for _, thing in ipairs(round) do thing.order_deconstruction(player.force) end

      -- The tick each one went, so the order is a fact rather than an inference from two
      -- totals. A heap that goes first and a heap that goes last can take the same time.
      --
      -- And the tick the work is really finished, which is not the tick the last entity
      -- vanishes: a heap is mined into the box in one scoop and then ferried home a claw at
      -- a time, so an order that takes the heap first looks instant and is still paying for
      -- it hundreds of ticks later. Done is everything gone, every plate in the pockets and
      -- the arm put away.
      local PLATES = mix.under * 10
      local began = game.tick
      local went_under, went_round, done = {}, {}, nil
      local seen_under, seen_round = 0, 0
      world.once(function()
        local left = 0
        for _, item in ipairs(under) do if item.valid then left = left + 1 end end
        if #under - left > seen_under then
          seen_under = #under - left
          went_under[#went_under + 1] = game.tick - began
        end
        local standing = 0
        for _, thing in ipairs(round) do if thing.valid then standing = standing + 1 end end
        if #round - standing > seen_round then
          seen_round = #round - standing
          went_round[#went_round + 1] = game.tick - began
        end
        if left == 0 and standing == 0 and not done
            and player.get_item_count("iron-plate") >= PLATES
            and not world.arm(player) then
          done = game.tick - began
        end
        return done ~= nil or game.tick - began > world.CYCLE * 14
      end, function()
        local left = 0
        for _, item in ipairs(under) do if item.valid then left = left + 1 end end
        local standing = 0
        for _, thing in ipairs(round) do if thing.valid then standing = standing + 1 end end
        local function ticks(list)
          local out = {}
          for i, t in ipairs(list) do out[i] = tostring(t) end
          return "[" .. table.concat(out, " ") .. "]"
        end
        log(("HEAP | %d underfoot, %d round it | underfoot went %s | round it went %s |"
          .. " all done at %s | %d and %d left | %d of %d plates home"):format(
          mix.under, mix.around, ticks(went_under), ticks(went_round), tostring(done),
          left, standing, player.get_item_count("iron-plate"), PLATES))
      end, "never settled", world.CYCLE * 15)
    end)
  end

  --- Whether stooping really costs the job after it anything, which is what the charge in
  --- choose() says it does.
  ---
  --- The claim is that taking something up from under the base leaves the hand folded, so
  --- whatever is next has to go all the way out again. A fetch drops at the rest point, so
  --- the hand comes home at the end of every take-up job and not only an underfoot one --
  --- see aim(). If that is so there is nothing to charge for, and the one thing left that
  --- could make an underfoot pickup different is that it breaks a round: a claw crossing
  --- from one target to the next keeps its hand out, and a target underfoot is one it has to
  --- come in for.
  ---
  --- So: the same second job in both cases, marked on the tick the first one goes, with
  --- nothing else anywhere to queue behind. What differs is only where the claw was when it
  --- was asked.
  for _, first in ipairs{ { name = "underfoot", dx = 0, dy = 0 },
                          { name = "two tiles off", dx = -2, dy = 0 } } do
    it(("PROBE: what the job after one %s costs"):format(first.name), function()
      local surface = player.surface
      player.get_inventory(defines.inventory.character_main).clear()
      local one = surface.create_entity{ name = "item-on-ground",
        position = { world.ORIGIN.x + first.dx, world.ORIGIN.y + first.dy },
        stack = { name = "iron-plate", count = 1 }, force = player.force }
      assert.is_not_nil(one, "the first thing was not laid")
      one.order_deconstruction(player.force)

      local began, took_one, took_two, out_at = game.tick, nil, nil, nil
      local two
      world.once(function()
        if not took_one and not one.valid then
          took_one = game.tick - began
          -- Where the claw is at the moment the next job appears, which is the whole of
          -- what the charge is an argument about.
          local arm = world.arm(player)
          out_at = arm and arm.valid
            and reach.distance(arm.position, arm.held_stack_position) or -1
          two = surface.create_entity{ name = "item-on-ground",
            position = { world.ORIGIN.x + 2, world.ORIGIN.y },
            stack = { name = "iron-plate", count = 1 }, force = player.force }
          if two then two.order_deconstruction(player.force) end
        end
        if took_one and two and not two.valid and not took_two then
          took_two = game.tick - began
        end
        return took_two ~= nil or game.tick - began > world.CYCLE * 6
      end, function()
        log(("AFTER | a first thing %-13s taken at %s, claw %.2f out when the next was"
          .. " marked | the next one, always two tiles off, taken at %s -- %s ticks later")
          :format(first.name, tostring(took_one), out_at or -1, tostring(took_two),
            took_one and took_two and tostring(took_two - took_one) or "?"))
        assert.is_not_nil(took_two, "the second thing was never taken")
      end, "never settled", world.CYCLE * 7)
    end)
  end

  --- A field of one kind, which is the showroom's case and the one the charge looks worst
  --- in. A downgraded chest sheds plates around and under whoever ordered it, so every
  --- candidate is the same item and the same trip; the only thing between them is where they
  --- lie. An arm that reaches past the plate it is standing on for an identical plate two
  --- tiles away is doing the one thing nobody would.
  for _, spread in ipairs{ 1, 2 } do
    it(("PROBE: plates underfoot among plates %d tiles out"):format(spread), function()
      local surface = player.surface
      player.get_inventory(defines.inventory.character_main).clear()
      local under, out = {}, {}
      for _ = 1, 4 do
        local item = surface.create_entity{ name = "item-on-ground",
          position = { world.ORIGIN.x, world.ORIGIN.y },
          stack = { name = "iron-plate", count = 1 }, force = player.force }
        if item then item.order_deconstruction(player.force) under[#under + 1] = item end
      end
      for _, at in ipairs{ { spread, 0 }, { -spread, 0 }, { 0, spread }, { 0, -spread } } do
        for _ = 1, 3 do
          local item = surface.create_entity{ name = "item-on-ground",
            position = { world.ORIGIN.x + at[1], world.ORIGIN.y + at[2] },
            stack = { name = "iron-plate", count = 1 }, force = player.force }
          if item then item.order_deconstruction(player.force) out[#out + 1] = item end
        end
      end

      -- Which of the two groups the arm works through first, counted as each one goes. A
      -- charge that is right here is one that leaves these interleaved or takes the near
      -- ones first; one that is wrong empties the ring before it stoops.
      local began, order = game.tick, {}
      local was_under, was_out = #under, #out
      world.once(function()
        local left, still = 0, 0
        for _, item in ipairs(under) do if item.valid then left = left + 1 end end
        for _, item in ipairs(out) do if item.valid then still = still + 1 end end
        for _ = 1, was_under - left do order[#order + 1] = "under" end
        for _ = 1, was_out - still do order[#order + 1] = "out" end
        was_under, was_out = left, still
        return (left == 0 and still == 0) or game.tick - began > world.CYCLE * 14
      end, function()
        local left, still = 0, 0
        for _, item in ipairs(under) do if item.valid then left = left + 1 end end
        for _, item in ipairs(out) do if item.valid then still = still + 1 end end
        local first_out
        for i, which in ipairs(order) do
          if which == "under" then first_out = i break end
        end
        log(("FIELD | 4 plates underfoot among 12 at %d tiles | order %s | the first"
          .. " underfoot one was number %s of %d | %d and %d left"):format(spread,
          table.concat(order, " "), tostring(first_out), #order, left, still))
      end, "never settled", world.CYCLE * 15)
    end)
  end

  --- The same rule for somebody driving. It is the vehicle standing on the ground rather
  --- than them, and a vehicle collides with things a character walks over, so what the
  --- engine allows under a tank is not what it allows under a pair of boots.
  for _, kind in ipairs{ "transport-belt", "iron-chest" } do
    it("PROBE: a " .. kind .. " ghost under a tank", function()
      local surface = player.surface
      local tank = world.vehicle(player, "tank")
      world.fit(tank, { "constructor-equipment-4", "battery-mk2-equipment" }, true)
      tank.insert{ name = kind, count = 10 }
      local at = tank.position
      local ghost = surface.create_entity{ name = "entity-ghost", inner_name = kind,
        position = at, direction = defines.direction.east, force = player.force }
      if not ghost then
        log(("FOOT | a %s ghost would not go down under a tank at all"):format(kind))
        return
      end
      local allowed = surface.can_place_entity{ name = kind, position = ghost.position,
        direction = ghost.direction, force = player.force,
        build_check_type = defines.build_check_type.ghost_revive }
      after_ticks(WATCH, function()
        log(("FOOT | a %-15s under a tank: the engine allows it = %-5s, the arm %s"):format(
          kind, tostring(allowed), ghost.valid and "left it alone" or "built it"))
      end)
    end)
  end
end)
