--- SCRATCH: the stall with the mod taken out of the loop.
---
--- No equipment, no character, no ghosts, no control.lua. One inserter of the arms' own
--- prototype standing where an arm stands, driven by hand through the same fetch cycle the
--- mod drives it through: aim at a thing, wait for the hand, put the load in the box, wait
--- for the hand to come home, take it out, move on to the next.
---
--- Everything is a number here rather than a thing in the world, which is the point: if this
--- wedges, the fault is the engine's and the mod is only the thing that meets it.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local pack = require("lib.pack")

local BELT = "transport-belt"

local STATUS = {}
for name, value in pairs(defines.entity_status) do STATUS[value] = name end
local CATCHER = "constructor-equipment-catcher"

--- The mod's own numbers, copied rather than read, so this harness has no opinion of its own.
local LIFT = 0.70        -- how far above its owner an arm is drawn
local MOUNT = 0.52       -- how far above its owner's middle the arm stands
local REST = 0.2         -- how far out the claw rests
local HOME = 0.4         -- how near counts as arrived
local STUCK = 90         -- how long a still hand counts as stalled

--- The ring that stalls: eight things one tile round the middle.
local RING = { { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 0 },
               { 1, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 } }

local function away(a, b)
  return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

describe("an inserter driven the way the mod drives one", function()
  local player

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  ---@param ring table[] the offsets to work through, in order
  ---@param label string
  local function run(ring, label, options)
    options = options or {}
    local surface = player.surface
    -- Well away from the character, who takes no part in this.
    local middle = { x = world.ORIGIN.x + 20, y = world.ORIGIN.y }
    local mount = { x = middle.x, y = middle.y - MOUNT }

    -- The ring as real things in the world, which is what the arena actually has in it: the
    -- box then stands on a tile that already holds a belt, and every neighbour is another
    -- thing an inserter could resolve a pickup to.
    local standing = {}
    if options.entities then
      for index, at in ipairs(ring) do
        standing[index] = surface.create_entity{ name = BELT,
          position = { middle.x + at[1], middle.y + at[2] },
          direction = defines.direction.east, force = player.force }
        if standing[index] and options.mark and options.mark(index, at) then
          standing[index].order_deconstruction(player.force)
        end
      end
    end

    -- The whole of the minimal case: one thing standing on the inserter's own tile, marked.
    local underfoot
    if options.under then
      underfoot = surface.create_entity{ name = BELT,
        position = { mount.x, mount.y - 0.48 }, direction = defines.direction.east,
        force = player.force }
      if underfoot and options.under_marked then
        underfoot.order_deconstruction(player.force)
      end
    end

    local arm
    local facing = defines.direction.north
    local function build()
      if arm and arm.valid then arm.destroy() end
      arm = surface.create_entity{ name = tiers.by_level[4].inserter,
        position = mount, force = player.force, direction = facing }
    end
    build()
    local box, keeper = nil, nil
    local which, phase, carried, idle = 1, "out", 0, 0
    local still, last, stalled = 0, nil, nil
    local began = game.tick

    world.once(function()
      if not arm.valid then return true end
      arm.energy = arm.prototype.get_max_energy_usage() * 100
      if not options.still_arm then arm.teleport(mount) end

      local target = ring[which]
      if not target then return true end
      local aim = { x = middle.x + target[1], y = middle.y + target[2] - LIFT }
      local towards = { x = aim.x - mount.x, y = aim.y - mount.y }
      local length = math.sqrt(towards.x ^ 2 + towards.y ^ 2)
      local rest = { x = mount.x + towards.x / length * REST,
                     y = mount.y + towards.y / length * REST }
      local hand = arm.held_stack_position

      if phase == "idle" then
        -- The gap between one job and the next, which the mod spends aimed at the rest
        -- point with nothing to do. Its claw is parked against a box of its own there.
        arm.pickup_position = { rest.x, rest.y }
        arm.drop_position = { rest.x, rest.y }
        if options.keeper then
          if not (keeper and keeper.valid) then
            keeper = surface.create_entity{ name = CATCHER, position = rest,
              force = player.force }
            local inside = keeper and keeper.get_inventory(defines.inventory.chest)
            if inside and inside.supports_bar() then inside.set_bar(1) end
          elseif keeper.position.x ~= rest.x or keeper.position.y ~= rest.y then
            keeper.teleport(rest)
          end
          if keeper and keeper.valid then arm.pickup_target = keeper end
        end
        idle = idle - 1
        if idle <= 0 then
          if keeper and keeper.valid then keeper.destroy() end
          keeper = nil
          if options.rebuild then
            local want = pack.towards(aim.x - mount.x, aim.y - mount.y)
            if arm.direction ~= want and not arm.held_stack.valid_for_read then
              facing = want
              build()
            end
          end
          phase = "out"
          still, last = 0, nil
        end
      elseif phase == "out" then
        arm.pickup_position = { aim.x, aim.y }
        arm.drop_position = { rest.x, rest.y }
        if not (box and box.valid) then
          box = surface.create_entity{ name = CATCHER, position = aim, force = player.force }
        elseif box.position.x ~= aim.x or box.position.y ~= aim.y then
          box.teleport(aim)
        end
        if box and box.valid then arm.pickup_target = box end

        -- The claw has arrived, so what it came for goes into the box, which is what
        -- take_up() does with loot_into().
        local inside = box and box.valid and box.get_inventory(defines.inventory.chest)
        if inside and inside.is_empty() and away(hand, aim) <= HOME then
          -- Mined, the way loot_into() does it: the thing goes and its item appears in the
          -- box for the claw to take.
          if standing[which] and standing[which].valid then standing[which].destroy() end
          inside.insert{ name = BELT, count = 1 }
        end
        if arm.held_stack.valid_for_read then
          phase = "back"
          if box and box.valid then box.destroy() end
          box = nil
        end
      else
        arm.pickup_position = { rest.x, rest.y }
        arm.drop_position = { rest.x, rest.y }
        if away(hand, rest) <= HOME or not arm.held_stack.valid_for_read then
          if arm.held_stack.valid_for_read then
            carried = carried + arm.held_stack.count
            arm.held_stack.clear()
          end
          which = which + 1
          idle = options.gap or 0
          phase = (idle > 0 or options.rebuild) and "idle" or "out"
          if idle <= 0 then idle = 1 end
          still, last = 0, nil
        end
      end

      -- Stalled: a hand that has not moved at all while it is meant to be going somewhere.
      if phase == "out" and last
          and math.abs(hand.x - last.x) < 1e-9 and math.abs(hand.y - last.y) < 1e-9 then
        still = still + 1
        if still >= STUCK and not stalled then
          stalled = ("stalled on number %d of %d, hand %.4f,%.4f (%.3f out), aim %.4f,%.4f"
            .. " (%.3f out), status %s"):format(which, #ring, hand.x, hand.y,
            away(hand, arm.position), aim.x, aim.y, away(aim, mount), tostring(arm.status))
          if options.unmark and underfoot and underfoot.valid then
            underfoot.cancel_deconstruction(player.force)
            stalled = stalled .. " -- then the mark was taken off"
          end
        end
      else
        still = 0
      end
      last = { x = hand.x, y = hand.y }
      return game.tick - began > 1800
    end, function()
      log(("BARE | %-40s %d of %d picked up. %s"):format(label, carried, #ring,
        stalled or "no stall"))
    end, "never ran", 1900)
  end

  --- The evidence chain, shortest last. A ring of eight one tile round the middle is the
  --- reproduction TODO 18 is written from; taking the deconstruction orders off it is the
  --- only change between the two, and it is the whole difference.
  it("PROBE: works a ring of eight standing there unmarked", function()
    run(RING, "a ring of eight, unmarked", { entities = true })
  end)

  it("PROBE: works a ring of eight standing there marked", function()
    run(RING, "a ring of eight, marked", { entities = true, mark = function() return true end })
  end)

  --- Which of the eight marks matters. The arm stands on the tile of the belt due north of
  --- the middle, which is ring entry two; the first thing it is sent for is entry one.
  it("PROBE: works with only the one it is sent for marked", function()
    run(RING, "marked: only the one it is sent for",
      { entities = true, mark = function(i) return i == 1 end })
  end)

  it("PROBE: works with only the one under the arm marked", function()
    run(RING, "marked: only the one under the arm",
      { entities = true, mark = function(i) return i == 2 end })
  end)

  --- And the whole of it, with nothing else in the world: one inserter, one box to fetch
  --- from, and one belt standing on the inserter's own tile.
  local ONE = { { -1, -1 } }

  it("PROBE: fetches with an unmarked belt under it", function()
    run(ONE, "one target, an unmarked belt under the inserter", { under = true })
  end)

  it("PROBE: fetches with a marked belt under it", function()
    run(ONE, "one target, a MARKED belt under the inserter",
      { under = true, under_marked = true })
  end)

  it("PROBE: fetches once the mark under it is taken off", function()
    run(ONE, "one target, the mark taken off once it stalls",
      { under = true, under_marked = true, unmark = true })
  end)
end)

--- Which of an inserter's several positions has to be the marked one.
---
--- In the minimal case above, three of them shared the tile the marked belt stood on: the
--- inserter's own position, the tile its hand rests in, and its drop. This pulls them apart
--- -- the pickup three tiles one way, the drop three tiles another, the hand starting in a
--- tile of its own -- and puts a single marked belt on one of them at a time.
---
--- The source is one of the mod's own boxes rather than a chest, because that box collides
--- with nothing and so a marked belt can stand on the same tile as it.
describe("one marked belt, and where it stands", function()
  local player
  local WATCH = 400

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  --- Offsets from the inserter, in tiles, for where the one marked belt goes.
  local WHERE = {
    { name = "nowhere -- nothing is marked",        at = nil },
    { name = "on the inserter's own tile",          at = { 0, 0 } },
    { name = "on the tile its hand starts in",      at = { 0, -1 } },
    { name = "on the pickup tile",                  at = { 0, -3 } },
    { name = "on the drop tile",                    at = { 3, 0 } },
    { name = "on a tile that is none of those",     at = { -3, 3 } },
    { name = "on its own tile but not marked",      at = { 0, 0 }, unmarked = true },
  }

  for _, case in ipairs(WHERE) do
    it("PROBE: " .. case.name, function()
      local surface = player.surface
      local base = { x = world.ORIGIN.x + 20.5, y = world.ORIGIN.y + 0.5 }
      local pick = { x = base.x, y = base.y - 3 }
      local drop = { x = base.x + 3, y = base.y }

      local marked
      if case.at then
        marked = surface.create_entity{ name = BELT,
          position = { base.x + case.at[1], base.y + case.at[2] },
          direction = defines.direction.east, force = player.force }
        if marked and not case.unmarked then marked.order_deconstruction(player.force) end
      end

      local arm = surface.create_entity{ name = tiers.by_level[4].inserter,
        position = base, force = player.force, direction = defines.direction.north }
      assert.is_not_nil(arm, "the inserter would not go down")
      assert.is_true(case.at == nil or marked ~= nil, "the belt would not go down")
      arm.pickup_position = { pick.x, pick.y }
      arm.drop_position = { drop.x, drop.y }

      -- A box of the mod's own as the source, since it collides with nothing.
      local source = surface.create_entity{ name = CATCHER, force = player.force,
        position = case.aside_pick and { pick.x, pick.y - 1 } or pick }
      source.get_inventory(defines.inventory.chest).insert{ name = BELT, count = 20 }

      local began, went, last = game.tick, 0, nil
      world.once(function()
        arm.energy = arm.prototype.get_max_energy_usage() * 100
        -- the two things the mod does to one every tick
        arm.teleport(base)
        arm.pickup_position = { pick.x, pick.y }
        arm.drop_position = { drop.x, drop.y }
        local hand = arm.held_stack_position
        if last then went = went + away(hand, last) end
        last = { x = hand.x, y = hand.y }
        return game.tick - began > WATCH
      end, function()
        log(("WHERE | %-38s hand travelled %6.2f, %d of 20 moved, status %s"):format(
          case.name, went,
          20 - source.get_inventory(defines.inventory.chest).get_item_count(BELT),
          STATUS[arm.status] or tostring(arm.status)))
      end, "never ran", WATCH + 60)
    end)
  end
end)

--- The same question asked of a claw that is already carrying something.
---
--- Everything above is a hand setting off empty to fetch. A delivery is the other way round
--- -- the load is in the hand and the drop is the thing being built -- and it matters which
--- of the two ends a mark has to be on to stop it, because a mod's arm delivers with its
--- pickup at the rest point, which is the tile its owner is standing on.
describe("a loaded claw, and where the mark is", function()
  local player
  local WATCH = 400

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  local WHERE = {
    { name = "nothing marked",            at = nil },
    { name = "marked on the pickup tile", at = { 0, -3 } },
    { name = "marked on the drop tile",   at = { 3, 0 } },
  }

  for _, case in ipairs(WHERE) do
    it("PROBE: delivers with " .. case.name, function()
      local surface = player.surface
      local base = { x = world.ORIGIN.x + 20.5, y = world.ORIGIN.y + 0.5 }
      local pick = { x = base.x, y = base.y - 3 }
      local drop = { x = base.x + 3, y = base.y }

      if case.at then
        local marked = surface.create_entity{ name = BELT,
          position = { base.x + case.at[1], base.y + case.at[2] },
          direction = defines.direction.east, force = player.force }
        assert.is_not_nil(marked, "the belt would not go down")
        marked.order_deconstruction(player.force)
      end

      local arm = surface.create_entity{ name = tiers.by_level[4].inserter,
        position = base, force = player.force, direction = defines.direction.north }
      arm.pickup_position = { pick.x, pick.y }
      arm.drop_position = { drop.x, drop.y }
      -- Somewhere to deliver into, which collides with nothing so a marked belt can share
      -- its tile.
      local into = surface.create_entity{ name = CATCHER, position = drop,
        force = player.force }
      -- and the load already in the hand, which is the whole point of this case
      arm.held_stack.set_stack{ name = BELT, count = 1 }

      local began, went, last, gone = game.tick, 0, nil, nil
      world.once(function()
        arm.energy = arm.prototype.get_max_energy_usage() * 100
        arm.teleport(base)
        arm.pickup_position = { pick.x, pick.y }
        arm.drop_position = { drop.x, drop.y }
        local hand = arm.held_stack_position
        if last then went = went + away(hand, last) end
        last = { x = hand.x, y = hand.y }
        if not gone and not arm.held_stack.valid_for_read then gone = game.tick - began end
        return game.tick - began > WATCH
      end, function()
        log(("LOADED | %-30s hand travelled %6.2f, %s, box holds %d, status %s"):format(
          case.name, went,
          gone and ("the load left the hand on tick " .. gone) or "the load is still held",
          into.valid and into.get_inventory(defines.inventory.chest).get_item_count(BELT) or -1,
          STATUS[arm.status] or tostring(arm.status)))
      end, "never ran", WATCH + 60)
    end)
  end
end)

--- Whether naming a target outright talks the engine round.
---
--- pickup_target and drop_target are both writable, and teleporting the entity throws
--- whatever the engine had resolved away -- so they have to be written every tick, after the
--- teleport, the way pin_to() and pin_from() do it in control.lua. The question is whether
--- naming a box that is not the marked belt is enough to get the hand moving again.
describe("a marked tile, with the target named outright", function()
  local player
  local WATCH = 400

  local function scrub()
    for _, e in ipairs(player.surface.find_entities_filtered{ position = world.ORIGIN,
          radius = 40 }) do
      if e.valid and e.type ~= "character" then e.destroy() end
    end
  end

  before_each(function() player = world.player(); world.clear(player); scrub() end)
  after_each(function() scrub(); world.clear(player) end)

  local CASES = {
    { name = "pickup blocked, nothing named",        block = "pick" },
    { name = "pickup blocked, the source named",     block = "pick", pin_pick = true },
    { name = "pickup blocked, both ends named",      block = "pick", pin_pick = true,
      pin_drop = true },
    { name = "pickup blocked, a source named on a clear tile nearby", block = "pick",
      pin_pick = true, aside_pick = true },
    { name = "drop blocked, bare ground, nothing named", block = "drop" },
    { name = "drop blocked, a box named on a clear tile nearby", block = "drop",
      aside = true, pin_drop = true },
    { name = "drop blocked, an open box on the blocked tile", block = "drop",
      pin_drop = true },
    { name = "drop blocked, a barred box on the blocked tile", block = "drop",
      pin_drop = true, barred = true },
    { name = "drop blocked, a barred box there and nothing named", block = "drop",
      barred = true, box_only = true },
  }

  for _, case in ipairs(CASES) do
    it("PROBE: " .. case.name, function()
      local surface = player.surface
      local base = { x = world.ORIGIN.x + 20.5, y = world.ORIGIN.y + 0.5 }
      local pick = { x = base.x, y = base.y - 3 }
      local drop = { x = base.x + 3, y = base.y }

      local marked = surface.create_entity{ name = BELT,
        position = (case.block == "pick") and pick or drop,
        direction = defines.direction.east, force = player.force }
      assert.is_not_nil(marked, "the belt would not go down")
      marked.order_deconstruction(player.force)

      local arm = surface.create_entity{ name = tiers.by_level[4].inserter,
        position = base, force = player.force, direction = defines.direction.north }
      arm.pickup_position = { pick.x, pick.y }
      arm.drop_position = { drop.x, drop.y }

      local source = surface.create_entity{ name = CATCHER, position = pick,
        force = player.force }
      source.get_inventory(defines.inventory.chest).insert{ name = BELT, count = 20 }
      -- Where a named drop lives: on the blocked tile itself, or a clear tile beside it.
      local into
      if case.pin_drop or case.box_only then
        into = surface.create_entity{ name = CATCHER, force = player.force,
          position = case.aside and { drop.x, drop.y - 1 } or drop }
        if into and case.barred then
          local inside = into.get_inventory(defines.inventory.chest)
          if inside and inside.supports_bar() then inside.set_bar(1) end
        end
      end

      local began, went, last = game.tick, 0, nil
      world.once(function()
        arm.energy = arm.prototype.get_max_energy_usage() * 100
        arm.teleport(base)
        arm.pickup_position = { pick.x, pick.y }
        arm.drop_position = { drop.x, drop.y }
        -- after the teleport, every tick, which is the only way one of these sticks
        if case.pin_pick and source.valid then arm.pickup_target = source end
        if case.pin_drop and into and into.valid then arm.drop_target = into end
        local hand = arm.held_stack_position
        if last then went = went + away(hand, last) end
        last = { x = hand.x, y = hand.y }
        return game.tick - began > WATCH
      end, function()
        log(("NAMED | %-46s hand travelled %6.2f, %d of 20 taken, %d delivered, status %s"
          ):format(case.name, went,
          20 - source.get_inventory(defines.inventory.chest).get_item_count(BELT),
          into and into.valid
            and into.get_inventory(defines.inventory.chest).get_item_count(BELT) or -1,
          STATUS[arm.status] or tostring(arm.status)))
      end, "never ran", WATCH + 60)
    end)
  end
end)
