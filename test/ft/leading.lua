--- Building something that is not in reach yet.
---
--- One ghost in the arena and one arm, so there is nothing for an arm to choose between and
--- nothing to set off for but the thing the test put there. Whatever happens, happened
--- because of that ghost.
---
--- What separates these from every other fixture is that the character is walking. A
--- stationary wearer reaches what is in reach and nothing else, which is what the mod has
--- always done; a walking one has a claw that can be sent to where a ghost will be.
local world = require("test.ft.world")
local tiers = require("lib.tiers")
local reach = require("lib.reach")

local BELT = "transport-belt"
local FOURTH = tiers.by_level[4]

--- Comfortably longer than a fourth tier reach, which takes 43 ticks, plus the walk up to
--- wherever the intercept is.
local A_WALK = 200

local player

--- What these tests leave behind, over the ground they actually cover.
---
--- world.clear sweeps thirty tiles around the arena, which is ample for a fixture whose
--- character stands still. These walk forty five tiles and lay ghosts at forty, so their
--- litter lands outside that box -- and world.ghosts and world.count count the whole
--- surface, so a belt left at +40 is counted by every test that runs afterwards. Measured:
--- it turned a passing suite into one failure that could not be reproduced on its own.
local function clear_the_walk(at)
  local half = 90
  for _, entity in ipairs(at.surface.find_entities_filtered{
        area = { { world.ORIGIN.x - half, world.ORIGIN.y - half },
                 { world.ORIGIN.x + half, world.ORIGIN.y + half } },
        name = { BELT, "iron-chest", "item-on-ground", "constructor-equipment-catcher",
                 "tank", "car" } }) do
    if entity.valid then entity.destroy() end
  end
  for _, ghost in ipairs(at.surface.find_entities_filtered{
        area = { { world.ORIGIN.x - half, world.ORIGIN.y - half },
                 { world.ORIGIN.x + half, world.ORIGIN.y + half } },
        type = "entity-ghost" }) do
    if ghost.valid then ghost.destroy() end
  end
end

before_each(function()
  player = world.player()
  world.clear(player)
  clear_the_walk(player)
  player.character_running_speed_modifier = 0
  world.equip(player, { FOURTH.name, "battery-equipment" }, true)
  player.insert{ name = BELT, count = 5 }
end)

after_each(function()
  player.walking_state = { walking = false }
  if player.vehicle then world.unseat(player) end
  clear_the_walk(player)
  world.clear(player)
end)

---Swap whatever is being worn for an armour with exactly this in it.
---
---The slot holds one armour. world.equip inserts another and then reads the slot back, so
---handing it a second armour while one is already on puts the new one in the pockets and
---quietly fills the old one's grid instead -- which fits by luck or does not fit at all,
---and in the full suite it did not.
---@param equipment string[]
---@param armour string?
local function rewear(equipment, armour)
  player.get_inventory(defines.inventory.character_armor).clear()
  return world.equip(player, equipment, true, armour)
end

---Walk a way for a while, then stop and check.
---@param way defines.direction
---@param ticks integer
---@param done fun()
local function walk(way, ticks, done)
  local began = game.tick
  world.once(function()
    player.walking_state = { walking = true, direction = way }
    return game.tick - began > ticks
  end, function()
    player.walking_state = { walking = false }
    done()
  end, "the walk never ended", ticks + 120)
end

---Walk a way until the ghost is gone, or until patience runs out, and say when.
---@param way defines.direction
---@param ticks integer
---@param done fun(built: integer?)
local function walk_until_built(way, ticks, done)
  local began, built = game.tick, nil
  world.once(function()
    player.walking_state = { walking = true, direction = way }
    if not built and world.ghosts(player) == 0 then built = game.tick - began end
    return built ~= nil or game.tick - began > ticks
  end, function()
    player.walking_state = { walking = false }
    done(built)
  end, "the walk never ended", ticks + 120)
end

describe("a ghost that is not in reach yet", function()
  --- Ten ahead and four to the side, which is 10.8 tiles off to begin with, twice what the
  --- arm reaches. It comes inside the five tiles when its owner has covered seven of them
  --- and is gone again six tiles later, which is forty ticks of being reachable against a
  --- reach that takes forty three to make.
  ---
  --- So an arm that waits until the ghost is in range and only then sets off arrives after
  --- it has gone. This ghost cannot be built at all without leading it, which is the point
  --- of the case: leading is not a quicker way to build something here, it is the only way.
  ---
  --- Four to the side and not four and a half, and the reason is worth writing down because
  --- it cost a wrong diagnosis. A tile's middle is at n + 0.5, which is where world.ORIGIN
  --- puts the character, so an offset from there has to be a whole number of tiles to land
  --- on another middle. Half a tile lands on a corner, and a one by one ghost asked for a
  --- corner is rounded to the next middle up: measured, +3.5 and +4.25 both become +4, and
  --- +4.5 and +4.75 both become +5.
  ---
  --- So asking for four and a half puts the ghost square abeam at exactly the full reach,
  --- where nothing can ever get to it, and the test reads as the mod failing to build
  --- something it should have. Offsets here are whole tiles for that reason.
  it("is built by a character walking past it, which nothing else could do", function()
    world.ghost(player, BELT, 10, 4)
    walk_until_built(defines.direction.east, A_WALK, function(built)
      assert.is_not_nil(built, "the ghost was never built")
      assert.are.equal(1, world.count(player, BELT), "no belt was put down")
      assert.are.equal(4, player.get_item_count(BELT), "it was not paid for out of pocket")
      -- In reach from tick 47 and gone by 88. A claw that waited for it would have set off
      -- on 47 and arrived on 90, two ticks after it had gone.
      assert.is_true(built < 70,
        ("built on tick %d, which is late enough that it was not led"):format(built))
    end)
  end)

  it("is built sooner than waiting for it would allow", function()
    -- Ten ahead and three to the side, which a character does eventually walk into range
    -- of, so this one could be built either way. What says it was led is when.
    world.ghost(player, BELT, 10, 3)
    walk_until_built(defines.direction.east, A_WALK, function(built)
      assert.is_not_nil(built, "the ghost was never built")
      -- In reach from tick 41. Waiting for that and then reaching takes until 84; leading
      -- it puts the claw there as it arrives.
      assert.is_true(built < 70,
        ("built on tick %d, which is when waiting for it would have"):format(built))
    end)
  end)

  it("is left alone by a character standing still", function()
    world.ghost(player, BELT, 10, 3)
    after_ticks(A_WALK, function()
      assert.are.equal(1, world.ghosts(player),
        "a ghost ten tiles off was built by somebody who never moved")
      assert.are.equal(5, player.get_item_count(BELT), "something was paid for")
    end)
  end)
end)

--- The heart of it, and nothing above asserts it directly: the arm is out and travelling
--- while the ghost is still nowhere near reachable. Measured on this very case, the job is
--- taken on tick 7 and the hand is moving on tick 8, against a ghost that does not come
--- inside the five tiles until tick 47.
describe("an arm with a lead to hold", function()
  it("sets off long before the ghost is in reach", function()
    -- Where it stands, read once: the entity is gone the moment it is built, and asking a
    -- built ghost where it was takes the run down.
    local at = world.ghost(player, BELT, 10, 4).position
    local out_while_unreachable, reachable_at = false, nil
    local began = game.tick
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local since = game.tick - began
      local away = reach.distance(player.position, at)
      if not reachable_at and away <= FOURTH.range then reachable_at = since end
      if world.arm(player) and not reachable_at then out_while_unreachable = true end
      return world.ghosts(player) == 0 or since > A_WALK
    end, function()
      player.walking_state = { walking = false }
      assert.is_true(out_while_unreachable,
        "the arm never came out while the ghost was still out of reach")
      assert.is_not_nil(reachable_at, "the ghost never came within reach at all")
      assert.are.equal(0, world.ghosts(player), "and it was not built")
    end, "the walk never ended", A_WALK + 120)
  end)
end)

describe("a ghost a walker can never catch", function()
  --- The cone an arm can reach into is a wedge opening the way its owner is going, because a
  --- character outruns their own hand: a fourth tier claw extends a tenth of a tile a tick
  --- against a walk of 0.148, so anything much off to the side is gone before the hand is
  --- out. Not reaching those is right. What is worth checking is that no swing is spent
  --- finding it out.
  ---
  --- Laid down once its owner is already under way, which is the whole of the case. A
  --- character standing still reaches what is in reach, including what is behind them, and
  --- should: it is only once they are moving that where they are going decides anything.
  ---@param dx number
  ---@param dy number
  ---@param complaint string
  local function never_reached_for(dx, dy, complaint)
    local deployed, laid = false, false
    local began = game.tick
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local since = game.tick - began
      -- Up to speed first, so that the arm never sees a moment of standing still.
      if since == 30 then
        world.ghost(player, BELT, dx + math.floor(player.position.x - world.ORIGIN.x), dy)
        laid = true
      end
      if laid and world.arm(player) then deployed = true end
      return since > 120
    end, function()
      player.walking_state = { walking = false }
      assert.is_true(laid, "the ghost was never laid down")
      assert.is_false(deployed, complaint)
      assert.are.equal(1, world.ghosts(player), "it was built somehow")
      assert.are.equal(5, player.get_item_count(BELT), "something was paid for")
    end, "the walk never ended", 200)
  end

  it("is not reached for, square abeam at the edge", function()
    never_reached_for(0, 5, "an arm was sent out after a ghost square abeam at full reach")
  end)

  it("is not reached for behind a walker", function()
    never_reached_for(-4, 0, "an arm was sent after a ghost its owner was walking away from")
  end)

  it("is not reached for beside a walker, a tile off the line", function()
    -- Measured: a fourth tier cone is 0.94 of a tile wide square abeam, so two tiles to the
    -- side is already outside it however near it looks.
    never_reached_for(0, 2, "an arm was sent after a ghost two tiles abeam")
  end)
end)

--- Nothing is created and nothing is lost, wherever the belt has got to: in the pocket, in
--- the claw, standing on the ground as a built belt, or lying on it as an item.
---@return integer
local function belts_anywhere()
  local held = 0
  local arm = world.arm(player)
  if arm and arm.held_stack.valid_for_read and arm.held_stack.name == BELT then
    held = arm.held_stack.count
  end
  local loose = 0
  for _, item in ipairs(player.surface.find_entities_filtered{
        name = "item-on-ground", position = player.position, radius = 40 }) do
    if item.stack and item.stack.valid_for_read and item.stack.name == BELT then
      loose = loose + item.stack.count
    end
  end
  -- Anything the claw handed over on the way is in the box it hands over through.
  local boxed = 0
  for _, box in ipairs(player.surface.find_entities_filtered{
        name = "constructor-equipment-catcher", position = player.position, radius = 40 }) do
    boxed = boxed + box.get_item_count(BELT)
  end
  return player.get_item_count(BELT) + world.count(player, BELT) + held + loose + boxed
end

describe("an owner who changes their mind mid reach", function()
  ---Walk one way, then another, and see what became of the ghost and the belt.
  ---@param first defines.direction
  ---@param then_ defines.direction? nothing at all means stopping dead
  ---@param done fun(built: boolean)
  local function turn_after(first, then_, done)
    local began = game.tick
    world.once(function()
      local since = game.tick - began
      if since < 25 then
        player.walking_state = { walking = true, direction = first }
      elseif then_ then
        player.walking_state = { walking = true, direction = then_ }
      else
        player.walking_state = { walking = false }
      end
      return since > 220
    end, function()
      player.walking_state = { walking = false }
      done(world.ghosts(player) == 0)
    end, "the walk never ended", 300)
  end

  --- A turn is not a reason to look for something else. The ghost is still the ghost, so the
  --- intercept to it is worked out again from where the hand has got to, and the reach goes
  --- on.
  it("keeps the ghost it had when the turn still leaves it reachable", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, defines.direction.southeast, function(built)
      assert.is_true(built, "a ghost still well within reach after the turn was dropped")
      assert.are.equal(5, belts_anywhere(), "a belt was made or lost")
    end)
  end)

  --- And when it does not, the reach is written off rather than stretched after something
  --- its owner has turned their back on. What matters is that the belt comes home.
  it("gives up, and keeps the belt, when the turn takes it out of reach", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, defines.direction.north, function(built)
      assert.is_false(built, "a ghost its owner walked away from was built anyway")
      assert.are.equal(1, world.ghosts(player), "the ghost is not standing where it was")
      assert.are.equal(5, belts_anywhere(), "a belt went missing when the reach was given up")
      assert.are.equal(5, player.get_item_count(BELT),
        "the belt never came back to the pocket")
    end)
  end)

  --- Stopping is a course change like any other: the drift falls to nothing, and a wearer
  --- going nowhere reaches what is in reach and nothing else. A ghost still seven tiles off
  --- is no longer coming.
  it("gives up, and keeps the belt, when its owner simply stops", function()
    world.ghost(player, BELT, 10, 4)
    turn_after(defines.direction.east, nil, function(built)
      assert.is_false(built, "a ghost seven tiles from a standing character was built")
      assert.are.equal(5, belts_anywhere(), "a belt went missing when the walk stopped")
      assert.are.equal(5, player.get_item_count(BELT),
        "the belt never came back to the pocket")
    end)
  end)
end)


--- One trip is out, do the job, and back. Everything above stops at the delivery, which is
--- half of it: the claw still has to come home to a resting point that is walking away from
--- it, and the arm still has to be put away, before the next thing can be reached for.
describe("the rest of a trip", function()
  it("brings the claw home and stows the arm, while its owner walks on", function()
    world.ghost(player, BELT, 10, 4)
    local began, built, stowed, furthest = game.tick, nil, nil, 0
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      local since = game.tick - began
      if not built and world.ghosts(player) == 0 then built = since end
      local arm = world.arm(player)
      if built then
        if arm and arm.valid then
          -- Once the belt is delivered the hand should only ever be coming in.
          furthest = math.max(furthest,
            reach.distance(arm.position, arm.held_stack_position))
        elseif not stowed then stowed = since end
      end
      return (stowed and since - stowed > 30) or since > 300
    end, function()
      player.walking_state = { walking = false }
      assert.is_not_nil(built, "the ghost was never built")
      assert.is_not_nil(stowed, "the arm was still out long after it had finished")
      assert.is_true(furthest < FOURTH.range,
        ("the hand went out to %.2f after delivering, rather than coming in"):format(furthest))
    end, "the walk never ended", 380)
  end)

  --- Three scattered fifteen tiles apart, which is about what one trip out and back costs at
  --- a walk, so each has to be led, met, delivered and left behind before the next is even
  --- worth looking at. The last of them is a decisive case in its own right: it is in reach
  --- for 41 ticks against a 43 tick reach, so an arm that waited for it would miss.
  it("does one trip after another along a scattered line", function()
    for _, dx in ipairs{ 10, 25, 40 } do world.ghost(player, BELT, dx, 4) end
    local began = game.tick
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      return world.ghosts(player) == 0 or game.tick - began > 420
    end, function()
      player.walking_state = { walking = false }
      assert.are.equal(0, world.ghosts(player),
        ("%d of three scattered ghosts were walked past"):format(world.ghosts(player)))
      assert.are.equal(3, world.count(player, BELT), "three belts were not put down")
      assert.are.equal(2, player.get_item_count(BELT), "they were not paid for one apiece")
    end, "the walk never ended", 520)
  end)
end)

describe("leading at every tier", function()
  --- Every tier leads, and the first one leads furthest in proportion: a two tile arm that
  --- is out for 37 ticks is carried five and a half tiles by its owner while the hand is
  --- reaching, so it meets things three times its own reach away. Which is the opposite of
  --- what an earlier attempt at this concluded -- that the first tier could not use a lead
  --- at all because its hand extends slower than a character walks. That is true of what it
  --- can reach to the side, and not of what it can reach straight ahead.
  for level = 1, 4 do
    local tier = tiers.by_level[level]
    --- The far tip of that tier's cone: the reach, plus the ground its owner covers while
    --- the hand is going all the way out.
    local tip = tier.range + 0.1484375 * reach.full_swing(tier)

    it("the " .. tier.name .. " arm meets something well past its own reach", function()
      local ahead = math.floor(tip) - 1
      assert.is_true(ahead > tier.range,
        ("tier %d would be led no further than it reaches"):format(level))
      rewear({ tier.name, "battery-equipment" })
      world.ghost(player, BELT, ahead, 0)
      walk_until_built(defines.direction.east, A_WALK, function(built)
        assert.is_not_nil(built,
          ("a ghost %d ahead was never built by a %g tile arm"):format(ahead, tier.range))
      end)
    end)
  end
end)

describe("wearers other than one character on foot", function()
  it("shares a walk between two arms and two ghosts", function()
    rewear({ FOURTH.name, FOURTH.name, "battery-equipment" }, "power-armor")
    -- One to either side, so neither arm can take both and each has to lead its own.
    world.ghost(player, BELT, 10, 4)
    world.ghost(player, BELT, 14, -4)
    walk_until_built(defines.direction.east, A_WALK, function()
      assert.are.equal(0, world.ghosts(player), "a walk past two ghosts left one standing")
      assert.are.equal(2, world.count(player, BELT), "both belts were not put down")
      assert.are.equal(3, player.get_item_count(BELT), "they were not paid for one apiece")
    end)
  end)

  --- A vehicle leads out of its own hold, from its own arms, on its own measured drift. A
  --- tank rather than a car only because a car's grid will not take a five tile arm.
  it("leads from a tank driving in a straight line", function()
    local tank = world.vehicle(player, "tank")
    tank.insert{ name = "nuclear-fuel", count = 5 }
    world.fit(tank, { FOURTH.name, "battery-equipment" }, true)
    tank.insert{ name = BELT, count = 5 }
    -- Thirty ahead, because a tank covers the ground a good deal faster than a walk.
    world.ghost(player, BELT, 30, 4)
    local began = game.tick
    world.once(function()
      tank.riding_state = { acceleration = defines.riding.acceleration.accelerating,
        direction = defines.riding.direction.straight }
      return world.ghosts(player) == 0 or game.tick - began > 300
    end, function()
      tank.riding_state = { acceleration = defines.riding.acceleration.nothing,
        direction = defines.riding.direction.straight }
      assert.are.equal(0, world.ghosts(player), "the tank drove past without building it")
      assert.are.equal(4, tank.get_item_count(BELT),
        "it was not paid for out of the tank's own hold")
      world.unseat(player)
      tank.destroy()
    end, "the drive never ended", 380)
  end)

  it("takes up something marked while its owner walks past", function()
    local chest = player.surface.create_entity{ name = "iron-chest",
      position = { world.ORIGIN.x + 10, world.ORIGIN.y + 4 }, force = player.force }
    chest.order_deconstruction(player.force)
    local began, lifted = game.tick, nil
    world.once(function()
      player.walking_state = { walking = true, direction = defines.direction.east }
      if not lifted and player.surface.count_entities_filtered{ name = "iron-chest" } == 0 then
        lifted = game.tick
      end
      -- Kept walking well past the moment it leaves the ground, because what a fetch picks
      -- up is in the claw until the claw is home again.
      return (lifted and game.tick - lifted > world.CYCLE) or game.tick - began > A_WALK
    end, function()
      player.walking_state = { walking = false }
      assert.is_not_nil(lifted, "a marked chest was walked past rather than taken up")
      assert.are.equal(1, player.get_item_count("iron-chest"), "it never reached the pocket")
    end, "the walk never ended", A_WALK + 200)
  end)
end)
