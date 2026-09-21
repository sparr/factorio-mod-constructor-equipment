--- A whole chunk of ghosts, of the kinds a blueprint is actually made of.
---
--- The uniform field of belts the shape benchmark uses is a fair test of geometry and a poor
--- one of anything else: real work comes in runs of belt with inserters alongside, machines
--- on a three by three footprint, and chests dotted about. Sizes differ, so what a search
--- hands back differs, and an assembler's ghost answers a position query from any of nine
--- tiles.
---
--- What is measured here is the whole of what a tick costs one arm: the search, and then
--- what choose() does with everything it hands back.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local CALLS = 60
local RUNS = 1
--- A chunk is thirty two tiles square.
local CHUNK = 32

---Lay out something a player might actually have stamped down.
---@return table<string, integer>
local function blueprint(surface, at, force)
  local made = {}
  local function ghost(name, x, y, direction)
    local thing = surface.create_entity{ name = "entity-ghost", inner_name = name,
      position = { at.x + x, at.y + y }, direction = direction, force = force }
    if thing then made[name] = (made[name] or 0) + 1 end
    return thing
  end

  for row = 0, CHUNK - 1 do
    local y = row - CHUNK / 2 + 0.5
    if row % 8 == 0 then
      -- a belt run the width of the chunk, which is what most of a blueprint is
      for step = 0, CHUNK - 1 do
        ghost("transport-belt", step - CHUNK / 2 + 0.5, y, defines.direction.east)
      end
    elseif row % 8 == 1 or row % 8 == 7 then
      -- inserters feeding off it, every other tile
      for step = 0, CHUNK - 1, 2 do
        ghost("inserter", step - CHUNK / 2 + 0.5, y,
          row % 8 == 1 and defines.direction.north or defines.direction.south)
      end
    elseif row % 8 == 3 then
      -- machines on their three by three, with a chest between every pair
      for step = 0, CHUNK - 4, 5 do
        ghost("assembling-machine-1", step - CHUNK / 2 + 1.5, y + 0.5)
        ghost("iron-chest", step - CHUNK / 2 + 4.5, y)
      end
    end
  end
  return made
end

describe("a chunkful of ghosts", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = CHUNK * 2, type = "entity-ghost" }) do
      if e.valid then e.destroy() end
    end
  end

  before_each(function()
    player = world.player()
    player.walking_state = { walking = false }
    world.clear(player)
    scrub()
  end)

  after_each(function()
    player.walking_state = { walking = false }
    scrub()
    world.clear(player)
  end)

  it("PROBE: what a tick costs one arm in the middle of one", function()
    local surface = player.surface
    local made = blueprint(surface, world.ORIGIN, player.force)
    local kinds, total = {}, 0
    for name, count in pairs(made) do
      kinds[#kinds + 1] = ("%s x%d"):format(name, count)
      total = total + count
    end
    table.sort(kinds)

    local tier = tiers.by_level[4]
    local from = { x = world.ORIGIN.x, y = world.ORIGIN.y }
    local hand = { x = from.x + 0.7, y = from.y }
    local ticks = reach.full_swing(tier)
    local arm = { range = tier.range, extension = tier.extension }

    for _, going in ipairs{ { name = "standing still", speed = 0 },
                            { name = "walking", speed = 0.15 },
                            { name = "a car", speed = 0.30 } } do
      local drift = { x = going.speed, y = 0 }
      local cone = reach.cone(arm, drift, ticks)
      local offset, radius = reach.search({ { range = tier.range, ticks = ticks } }, drift)

      local function found()
        return surface.find_entities_filtered{
          position = { from.x + offset.x, from.y + offset.y }, radius = radius,
          type = "entity-ghost" }
      end

      -- and the same ground drawn as a box lying along the walk, which is what work_near
      -- draws now whenever its owner is moving
      local middle, long, wide, turned = reach.search_box(
        { { range = tier.range, ticks = ticks } }, drift)
      local function boxed()
        if not middle then return found() end
        return surface.find_entities_filtered{
          area = { left_top = { from.x + middle.x - long, from.y + middle.y - wide },
                   right_bottom = { from.x + middle.x + long, from.y + middle.y + wide },
                   orientation = turned },
          type = "entity-ghost" }
      end

      -- what the mod used to do: price everything, then sort it
      local function priced(list)
        local cost = {}
        for _, work in ipairs(list) do
          if work.valid then
            cost[work.unit_number] = reach.swing_ticks(tier, from, hand, work.position)
          end
        end
        table.sort(list, function(one, other)
          if not (one.valid and other.valid) then return false end
          local mine = cost[one.unit_number] or math.huge
          local theirs = cost[other.unit_number] or math.huge
          if mine == theirs then
            return reach.distance(from, one.position) < reach.distance(from, other.position)
          end
          return mine < theirs
        end)
        return #list
      end

      -- and what it does now: the cone, then one pass keeping the best
      local reaching = reach.distance(from, hand)
      local function scanned(list)
        local best_price, best_far, taken = math.huge, math.huge, 0
        for _, work in ipairs(list) do
          if work.valid then
            local spot = work.position
            if reach.in_cone(cone, { x = spot.x - from.x, y = spot.y - from.y }) then
              local far = reach.distance(from, spot)
              if math.abs(far - reaching) / tier.extension <= best_price then
                local price = reach.swing_ticks(tier, from, hand, spot)
                if price < best_price or (price == best_price and far < best_far) then
                  best_price, best_far, taken = price, far, taken + 1
                end
              end
            end
          end
        end
        return taken
      end

      local candidates = #found()
      -- Timed one at a time and in a different order every run, because whichever goes
      -- last goes fastest: measured, two pipelines doing identical work differed by two to
      -- one on position alone. A warm up before each does the rest.
      local WAYS = {
        { name = "circle sorted",  run = function() return priced(found()) end },
        { name = "circle scanned", run = function() return scanned(found()) end },
        { name = "box scanned",    run = function() return scanned(boxed()) end },
      }
      for run = 1, RUNS do
        for turn = 1, #WAYS do
          local way = WAYS[(turn + run - 2) % #WAYS + 1]
          local sum = 0
          for _ = 1, 20 do sum = sum + way.run() end
          local clock = helpers.create_profiler()
          for _ = 1, CALLS do sum = sum + way.run() end
          clock.stop()
          log{ "", ("CHUNK | %-14s | %4d in the circle, %4d in the box, of %d ghosts |"
            .. " %-14s over %d calls took "):format(going.name, candidates, #boxed(),
            total, way.name, CALLS), clock }
        end
      end
    end
    log("CHUNK | what was laid: " .. table.concat(kinds, ", "))
  end)

  --- And the whole thing running for real: four arms on a character's back, walking the
  --- length of a chunk of ghosts with the stock to build them. What is asserted is that the
  --- work gets done and that nothing goes missing doing it -- the cost is what the probe
  --- above is for.
  it("is built by four arms walking through it", function()
    local surface = player.surface
    world.equip(player, { "constructor-equipment-4", "constructor-equipment-4",
      "constructor-equipment-3", "constructor-equipment-3", "battery-mk2-equipment" },
      true, "power-armor")
    local made = blueprint(surface, world.ORIGIN, player.force)
    local wanted = 0
    for _, count in pairs(made) do wanted = wanted + count end
    for name in pairs(made) do player.insert{ name = name, count = 200 } end
    local stocked = {}
    for name in pairs(made) do stocked[name] = player.get_item_count(name) end

    -- across the chunk and back, which is how somebody actually lays a blueprint down
    player.teleport{ x = world.ORIGIN.x - CHUNK / 2 - 2, y = world.ORIGIN.y }
    for step = 1, 90 do
      after_ticks(step * 8, function()
        player.walking_state = { walking = true, direction = defines.direction.east }
      end)
    end

    after_ticks(90 * 8 + world.CYCLE * 2, function()
      player.walking_state = { walking = false }
      local left = surface.count_entities_filtered{ position = world.ORIGIN,
        radius = CHUNK * 2, type = "entity-ghost" }
      local built = wanted - left
      -- Nothing made and nothing lost: everything is either standing, still a ghost, in the
      -- pockets, or in a claw.
      for name, had in pairs(stocked) do
        local standing = surface.count_entities_filtered{ name = name,
          position = world.ORIGIN, radius = CHUNK * 2 }
        local ghosts = surface.count_entities_filtered{ position = world.ORIGIN,
          radius = CHUNK * 2, type = "entity-ghost", ghost_name = name }
        local held = player.get_item_count(name)
        local flying = 0
        for _, record in pairs(storage.constructor_arms[player.index] or {}) do
          local arm, box = record.entity, record.catcher
          if arm and arm.valid and arm.held_stack.valid_for_read
              and arm.held_stack.name == name then
            flying = flying + arm.held_stack.count
          end
          if box and box.valid then
            flying = flying + box.get_inventory(defines.inventory.chest).get_item_count(name)
          end
          if record.job and record.job.item == name then
            flying = flying + (record.job.escrow or 0)
          end
        end
        -- Nothing made and nothing lost: what was stocked is what is standing, plus what
        -- is still in the pockets, plus whatever is in a claw or a box.
        assert.are.equal(had, standing + held + flying,
          ("%s does not add up: %d stocked against %d standing, %d in the pockets and %d"
            .. " in the air"):format(name, had, standing, held, flying))
        -- and every ghost is either built or still a ghost
        assert.are.equal(made[name] or 0, standing + ghosts,
          ("%s: %d laid as ghosts, %d standing and %d still ghosts"):format(name,
            made[name] or 0, standing, ghosts))
      end
      helpers.write_file("chunkful.txt",
        ("four arms walking a chunk: %d of %d built\n"):format(built, wanted), false)
      -- A single walk past is not a full clearance -- an arm reaches what its cone can
      -- meet, and a chunk is wider than that -- so this asks that the walk did real work
      -- rather than naming a number the layout would have to keep hitting.
      assert.is_true(built > 20,
        ("only %d of %d were built walking through"):format(built, wanted))
    end)
  end)
end)
