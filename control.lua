local build = require("lib.build")
local tiers = require("lib.tiers")
local power = require("lib.power")
local pack = require("lib.pack")
local reach = require("lib.reach")

--- How far an arm reaches and how often it may set off both depend on which tier it is,
--- so they live in lib/tiers.lua where the data stage reads the same numbers.
local CHECK_PER_SECOND = 10
--- Nothing about the cost of building is decided here. The arm is a real electric inserter
--- with nothing to plug into, so it is fed by hand out of the armour every tick and the
--- engine does the billing at the base game's prices for the inserter that tier borrows
--- from. How much an armour must be holding before an arm will set off is per tier too --
--- a couple of that tier's reaches, from lib/tiers.lua -- so that an arm never stops
--- halfway with an item in its hand.

--- Every set of slowdown stickers there is, one per tier that asks for the penalty. See
--- prototypes/sticker.lua for why they are stickers and not a number on the character, and
--- lib/tiers.lua for which tiers have a set at all.
local SETS = {}
for _, tier in ipairs(tiers.list) do
  if tier.stickers then table.insert(SETS, tier.stickers) end
end


local CHECK_INTERVAL = 60 / CHECK_PER_SECOND
local CHECK_TICK = CHECK_INTERVAL / 2


--- How far off the mounting point the claw is aimed when it has nowhere else to be.
---
--- Not at the mounting point itself. An inserter's hand goes home to its pickup position,
--- and a pickup sitting exactly on the arm's own base is no direction at all: the engine
--- picks one to fold through, and it picked east, so the claw swung out to full stretch
--- sideways before coming home. Anything off the base at all cures that.
---
--- Two tenths because that is where the claw ends up closest to the character, not because
--- it is the smallest that works. The hand will not retract inside a minimum extension of
--- its own, so aiming it nearer than that gains nothing, and aiming it further simply holds
--- it further out: measured against the mounting point, it rests 0.18 away at nought, 0.08
--- at a tenth, 0.02 at two tenths, and 0.42 at six tenths.
local REST = 0.2

--- How close the hand has to get to the character to count as home again, and how close to
--- the ghost to count as having arrived.
---
--- Floors rather than answers: lib/reach.lua widens both to cover however fast the hand in
--- question is actually moving, because a window narrower than a tick of travel is one the
--- hand steps over, and the engine then finishes the swing by dropping the load.
local HOME = 0.4
local ARRIVED = 0.3

---How close is close enough for one arm. See lib/reach.lua, which the tests measure the
---real thing against.
---@param tier table
---@param threshold number
---@return number
local function within(tier, threshold, moved)
  return reach.within(tier, threshold, moved)
end

--- How long the claw takes to shrink away once the arm is stowed, and how far into that
--- it also fades. Short: it is punctuation on the end of a job, not an animation anybody
--- should have to wait through.
local STOW_TICKS = 18

--- How long the arm stays out after the last thing it did. An arm that vanished the moment
--- a swing ended would flicker between one ghost and the next; one that never vanished
--- would be worn to bed.
local IDLE_TICKS = 60


--- How long a swing is allowed to take before it is written off.
---
--- Nothing should need this: a reach that cannot finish is a fault somewhere else. It is
--- here because the failure it prevents is the mod quietly stopping for good, which is
--- much worse than a swing that gives up early and tries again.
local SWING_LIMIT = 300

--- 2.0 renamed the save table from global to storage, and filling it in at load time is
--- no longer allowed: the file is run before the save is read, so anything put there
--- would be thrown away or would desync. It is set up on_init instead, and again on
--- configuration_changed for a save that predates this.
---
--- Everything about a player's arms lives in one list per player, one entry per arm:
---
---   { entity = the inserter, job = what it is reaching for, busy = when it last had
---     something to do, last = when it last started a reach }
---
--- rather than four tables keyed by player index, which is what it was when there could
--- only ever be one arm.
local function setup()
  storage.constructor_arms = storage.constructor_arms or {}
  -- claws part way through being stowed, by the id of the sprite drawn for each
  storage.constructor_stowing = storage.constructor_stowing or {}
  -- whether the ramp into the slowdown has already been run for the run in progress
  storage.constructor_ramped = storage.constructor_ramped or {}

  -- One arm per player, in four parallel tables, is what a save from before multiple
  -- equipment looks like. The arms themselves are entities in the world, so they are taken
  -- away rather than merely forgotten, and everyone starts again from nothing.
  if storage.constructor_inserter then
    for _, arm in pairs(storage.constructor_inserter) do
      if arm and arm.valid then arm.destroy() end
    end
    storage.constructor_inserter = nil
    storage.constructor_busy = nil
    storage.constructor_reach = nil
    storage.constructor_arms = {}
  end
  storage.constructor_last_build_tick = nil

  -- Older versions slowed the character by writing character_running_speed_modifier and
  -- remembering what had been there. A save from one of those can be carrying a player
  -- left at quarter speed, because the value was only put back on the tick after a build
  -- that did not happen. Give it back and forget the bookkeeping.
  local saved = storage.constructor_saved_running_speed_modifier
  if saved then
    for index, previous in pairs(saved) do
      local player = game.get_player(index)
      if player and player.character_running_speed_modifier == -0.75 then
        player.character_running_speed_modifier = previous or 0
      end
    end
    storage.constructor_saved_running_speed_modifier = nil
  end
end

---One of this mod's stickers on a character, if it is there.
---@param character LuaEntity
---@param name string
---@return LuaEntity?
local function sticker_on(character, name)
  for _, sticker in pairs(character.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---Slow the character down, or keep them slowed if they already are.
---
---Slowing is in two parts. The first build of a run puts on the slowing sticker, which
---interpolates from full speed down to the tier's own figure over its lifetime, so the
---character leans into the work rather than stopping dead. When that has run its course
---the flat sticker takes over and holds them there for as long as there is building to do.
---
---Putting the same sticker on a character who already has it does not give them two: the
---engine keeps the one and starts its life over. That is what makes a run of builds one
---unbroken slowdown, and it is also why the slowing sticker must be left alone while it
---runs: refreshing it would start the ramp again and the character would surge.
---
---Every other set has to go, whichever this one is. They are separate prototypes, so the
---engine would keep them all and multiply them together, and someone who put a second arm
---on would end up slower than either arm asks for. The recovery stickers go for the same
---reason, plus one of their own: a character who started speeding up and then found
---something else to build would otherwise keep the tail of the ramp as well.
---@param player LuaPlayer
---@param set table which tier's stickers, from lib/tiers.lua
local function slow(player, set)
  local character = player.character
  for _, other in ipairs(SETS) do
    local recovery = sticker_on(character, other.recovery)
    if recovery then recovery.destroy() end
    if other ~= set then
      local flat = sticker_on(character, other.flat)
      if flat then flat.destroy() end
      local slowing = sticker_on(character, other.slowing)
      if slowing then slowing.destroy() end
    end
  end

  local flat = sticker_on(character, set.flat)
  if flat then
    -- already at the bottom of the ramp; keep it there
    character.surface.create_entity{
      name = set.flat, position = character.position, target = character }
    return
  end

  -- Part way down. Left to run: refreshing it would start the descent again and the
  -- character would surge. It is not swapped for the flat sticker early either, which is
  -- what this used to do -- the ramp ends at exactly the speed the flat sticker holds, so
  -- letting it expire on its own makes the handover invisible, where swapping out with a
  -- fifth of its life left was a step change in speed.
  if sticker_on(character, set.slowing) then return end

  -- Neither is on. Whether that means the ramp has not run yet or that it has been and
  -- gone is not something the character can be asked, because an expired sticker leaves
  -- nothing behind, so it is remembered instead.
  --
  -- Reading it off the sticker was the bug. A run of building is not continuous: an arm
  -- that gets home before its clock is due waits a few ticks, and a ramp that ran out in
  -- one of those gaps was replaced by a second ramp rather than by the flat sticker. The
  -- character kept easing towards a speed they never reached.
  if storage.constructor_ramped[player.index] then
    character.surface.create_entity{
      name = set.flat, position = character.position, target = character }
    return
  end

  -- The ramp is cosmetic, and a missing sticker prototype is not worth ending someone's
  -- game over. It can go missing for a real reason: game.reload_mods() reloads a mod's
  -- scripts but not its prototypes, so a script that has just learnt about a new sticker
  -- runs against data that has never heard of it. That crashed a session.
  if not prototypes.entity[set.slowing] then
    character.surface.create_entity{
      name = set.flat, position = character.position, target = character }
    return
  end
  storage.constructor_ramped[player.index] = true
  character.surface.create_entity{
    name = set.slowing, position = character.position, target = character }
end

---Let a character who has run out of things to build come back up to speed.
---
---The slowdown is flat while there is work, because its own life keeps being restarted
---and the interpolation would restart with it -- which would read as stuttering rather
---than as effort. The ramp belongs at the end, where there is one of it. So the flat
---sticker is swapped for one that interpolates from where it left off back to full speed
---over its lifetime, and the engine walks it up as its life runs down.
---
---Whichever set is on is the one that ramps off, so the character comes back up from the
---speed they were actually walking at rather than from some other tier's.
---@param player LuaPlayer
local function recover(player)
  local character = player.character
  storage.constructor_ramped[player.index] = nil
  for _, set in ipairs(SETS) do
    local slowdown = sticker_on(character, set.flat) or sticker_on(character, set.slowing)
    if slowdown then
      slowdown.destroy()
      if prototypes.entity[set.recovery] then
        character.surface.create_entity{
          name = set.recovery,
          position = character.position,
          target = character,
        }
      end
      return
    end
  end
end

---Which tiers of the equipment this character has in their armour, one entry per copy.
---
---One arm each, whatever mixture they are wearing, and each arm has its own tier's reach
---and its own tier's clock. Separate from being able to use them: the arms are strapped to
---their back whether or not there is any charge to work them with, so this is what decides
---how many are drawn and what they look like.
---
---Best tier first, so that the strongest arms take the top of the circle on the back
---rather than whichever the grid happened to list first. Deterministic either way, which
---matters: the order decides which arm is which slot, and an order that wandered would
---have the arms swapping places on someone's back.
---@param character LuaEntity?
---@return integer[] the level of each arm
local function worn(character)
  local found = {}
  if not (character and character.valid) then return found end
  local grid = character.grid
  if not (grid and grid.valid) then return found end

  local counted = {}
  -- 2.0 turned get_contents into a list of { name, count, quality } rather than a
  -- table keyed by name, so it is searched instead of indexed
  for _, equipment in pairs(grid.get_contents()) do
    local tier = tiers.of(equipment.name)
    if tier then
      counted[tier.level] = (counted[tier.level] or 0) + (equipment.count or 1)
    end
  end
  for level = #tiers.list, 1, -1 do
    for _ = 1, counted[level] or 0 do
      table.insert(found, level)
    end
  end
  return found
end

---Whether this character has any of the equipment in their armour at all.
---@param character LuaEntity?
---@return boolean
local function wearing(character)
  return #worn(character) > 0
end

---What one arm is, from what a record remembers of it.
---@param record table
---@return table
local function tier_of(record)
  return tiers.by_level[record.level] or tiers.list[1]
end

---The furthest any of these arms can reach.
---@param list table[]
---@return number
local function furthest(list)
  local range = 0
  for _, record in pairs(list) do
    range = math.max(range, tier_of(record).range)
  end
  return range
end

---Whether an arm can afford to set off, which is a question about its own equipment.
---
---A full buffer, and nothing else. The equipment holds exactly one reach's reserve, so
---full is the only figure worth asking about, and the armour fills it from empty in a few
---ticks: an arm that has just finished one reach waits no noticeable time for the next.
---Asking for some fraction of a larger buffer was a second number saying the same thing.
---@param record table
---@return boolean
local function ready(record)
  local piece = record.piece
  return piece ~= nil and piece.valid and piece.energy >= piece.max_energy
end

---The pieces of a given tier's equipment in a grid, in a settled order.
---@param grid LuaEquipmentGrid
---@param name string
---@return LuaEquipment[]
local function pieces_of(grid, name)
  local found = {}
  for _, equipment in pairs(grid.equipment) do
    if equipment.name == name then table.insert(found, equipment) end
  end
  return found
end

---Take up to this much out of a piece of equipment, and say how much there was.
---@param piece LuaEquipment?
---@param wanted number
---@return number
local function draw(piece, wanted)
  if not (piece and piece.valid) then return 0 end
  local take = math.min(piece.energy, wanted)
  if take > 0 then piece.energy = piece.energy - take end
  return take
end

---Put energy back where it came from: into the arm's own equipment first, and into
---anything else in the grid that will hold it for what does not fit.
---
---The overflow matters. The armour keeps the equipment's buffer topped up, so it is
---usually full, and without somewhere else to put it an arm being put away would simply
---lose whatever was left in it. Coming and going used to hand out free charge; it should
---not cost any either.
---@param grid LuaEquipmentGrid?
---@param piece LuaEquipment?
---@param amount number
local function refund(grid, piece, amount)
  if amount <= 0 then return end
  if piece and piece.valid then
    local room = piece.max_energy - piece.energy
    local give = math.min(room, amount)
    if give > 0 then
      piece.energy = piece.energy + give
      amount = amount - give
    end
  end
  if not (grid and grid.valid) then return end
  power.spill(grid.equipment, amount)
end

---Whether an arm can afford one more delivery and the journey home afterwards.
---
---Setting off in the first place wants a full buffer. Carrying on wants less than that --
---the claw is already out -- but it wants something, or an arm with a queue keeps turning
---to fresh ghosts until it runs dry somewhere out at the end of its own arm and stands
---there until the swing limit gives up on it. One reach's worth is the measure.
---
---Enough even for the worst hop. A claw going from due east to due west travels half a
---circle at full stretch, which is further than the reach itself, so a reach's worth
---sounds tight. It is not: almost all of what a journey costs is extending out and
---retracting home, and swinging round costs very little. Measured on the fourth tier at
---its full five tiles, where a reach's worth is 200kJ, a whole journey out and back came
---to 190kJ, a second delivery a quarter turn away added 3kJ, and one a half turn away
---added 14kJ. The hop and the retraction home together are about half of what this asks
---for.
---@param record table
---@param arm LuaEntity
---@return boolean
local function afford_another(record, arm)
  local piece = record.piece
  local in_hand = (arm and arm.valid) and arm.energy or 0
  local in_store = (piece and piece.valid) and piece.energy or 0
  return in_hand + in_store >= tier_of(record).reach_energy
end

---Fill the arm's buffer back up out of the armour.
---
---The arm is an electric inserter standing on no network, so this is the whole of its
---supply. Doing it this way rather than charging a flat rate per delivery means the engine
---decides what things cost: moving costs what moving costs, and a reach right across the
---range costs more than one to the next tile. It also means an armour that has run dry
---stops the arm where it is, mid swing, instead of the mod noticing later.
---@param record table the arm, which knows which piece of equipment is its own
---@param arm LuaEntity
local function charge(record, arm)
  local short = arm.electric_buffer_size - arm.energy
  if short > 0 then
    arm.energy = arm.energy + draw(record.piece, short)
  end
end

---Where an arm is mounted on a character, and so where its hand rests.
---@param character LuaEntity
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number}
local function mounting(character, slot, count)
  local at = character.position
  local offset = pack.offset(character.direction, slot, count)
  return { x = at.x + offset.x, y = at.y + offset.y }
end

---Whether a ghost could actually be built where it stands, right now.
---
---Asked because reaching for one that cannot be is a wasted journey that repeats: the claw
---goes out, the revive fails, it comes home, and the same ghost is picked again next tick.
---Standing near a thing is enough to stop it going up -- a character half a tile from a
---power pole is inside the space the pole needs -- and that is a case a player walks into
---constantly.
---
---Asked last of the tests, because it is the only one that costs anything.
---@param ghost LuaEntity
---@return boolean
local function buildable(ghost)
  return ghost.surface.can_place_entity{
    name = ghost.ghost_name,
    position = ghost.position,
    direction = ghost.direction,
    force = ghost.force,
    build_check_type = defines.build_check_type.ghost_revive,
  }
end

---Whether a character is standing on the ground a ghost will occupy.
---
---Measured against the tiles the thing will take up, not its collision box. Plenty of
---entities have a collision box far smaller than their footprint -- a medium electric pole
---occupies a whole tile and collides across a third of one -- and using the box let the
---character stand a fifth of a tile off a pole's centre and still count as clear of it. The
---arm would then reach for something directly under its own base, fail, spring back, and
---try again for as long as the player stood there.
---@param ghost LuaEntity
---@param at {x: number, y: number}
---@return boolean
local function standing_in(ghost, at)
  local prototype = ghost.ghost_prototype
  local across = (prototype and prototype.tile_width or 1) / 2
  local down = (prototype and prototype.tile_height or 1) / 2
  local middle = ghost.position
  return at.x >= middle.x - across and at.x <= middle.x + across
     and at.y >= middle.y - down and at.y <= middle.y + down
end

---Every ghost near enough to a player that some arm of theirs might reach it.
---
---Searched once and handed to every arm, rather than each arm searching for itself. The
---search is the expensive part of a tick and the answer is the same for all of them: only
---the range each arm judges it by differs, and that is a comparison rather than a search.
---@param player LuaPlayer
---@param range number the longest reach any of their arms has
---@return LuaEntity[]
local function ghosts_near(player, range)
  -- A radius, and the same radius the reach is judged against below. Two things went wrong
  -- with the square this replaces. A square of side twice the range reaches 1.41 times as
  -- far at its corners, and find_entities_filtered returns anything whose own box merely
  -- overlaps the area, so a ghost whose centre was well over four tiles away came back as
  -- a candidate. It was then abandoned as out of range on the very next tick, and found
  -- again the tick after: the arm swung out and back for ever, and because a swing counted
  -- as under way, no ghost that was actually in reach got a turn.
  return player.surface.find_entities_filtered{
    position = player.position,
    radius = range,
    type = "entity-ghost"
  }
end

---Pick something to build out of what was found near the player.
---
---Asks nothing about power: a claw already out and carrying does not have to bank a fresh
---reserve to turn to the next ghost. Setting off in the first place does, which is
---job_for below.
---@param player LuaPlayer
---@param nearby LuaEntity[] from ghosts_near
---@param claimed table<integer, boolean>? ghosts another arm is already reaching for
---@param range number how far this arm can reach
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
local function choose(player, nearby, claimed, range)
  local character = player.character

  -- the separate quickbar went away in 0.17; what is left is the character's own
  -- inventory, and the quickbar is a set of references into it
  local inventory = player.get_inventory(defines.inventory.character_main)
  if not inventory then return nil end
  local function carried(name) return inventory.get_item_count(name) end

  local standing = character.position
  for _, ghost in pairs(nearby) do
    if ghost.valid then
      -- 2.0 turned items_to_place_this into a list of { name, count } rather than a table
      -- keyed by item name
      local item, needed =
        build.placing_item(ghost.ghost_prototype.items_to_place_this, carried)
      -- An inserter will not reach for something underneath its own base. Asked to, it
      -- twitches a tick's worth and springs back, over and over, and because a swing
      -- counts as under way no other ghost gets a look in either: standing on a ghost
      -- jammed the whole thing. Distance is the wrong way to say it -- ghosts half a tile
      -- off get built perfectly well -- so what is asked is whether the character is
      -- standing in it. Asked again every tick of the swing, further down, because walking
      -- onto the thing being built is every bit as final as walking away from it.
      --
      -- Two arms both reaching for the same ghost would mean one of them delivering into a
      -- space the other had already built in, and coming home having wasted a swing.
      if item and not (claimed and claimed[ghost.unit_number])
          and not standing_in(ghost, standing)
          and not reach.out_of_range(standing, ghost.position, range)
          and buildable(ghost) then
        return ghost, item, needed
      end
    end
  end

  return nil
end

---How many things a claw may put down in one trip out.
---
---A trip is what carries several, not the claw: it holds one at a time and is refilled
---where it stands, because a hand holding more than one is what crashes the game. What is
---saved either way is the journey home between one ghost and the next.
---
---At most how many of the same thing to go looking for.
---
---Whatever the inserter it borrows from would be holding at the same research: one for a
---plain inserter and two for a bulk one, plus the relevant capacity bonus. No tier gets a
---head start of its own on top of that, so an arm never carries more than the thing it is
---made of.
---
---An upper bound only. What the claw actually takes is whatever the engine lets it hold,
---which is read back off the hand once it is filled, so the queue of ghosts and the load in
---the claw cannot disagree -- when they did, an arm set out queued for six deliveries
---holding four, ran dry two short, and threw the rest of the journey away.
---@param force LuaForce
---@param tier table
---@return integer
local function trips_for(force, tier)
  if tier.bulk then
    return tiers.BULK_BASE + math.max(0, math.floor(force.bulk_inserter_capacity_bonus or 0))
  end
  return 1 + math.max(0, math.floor(force.inserter_stack_size_bonus or 0))
end

---How many of the same thing are worth queueing for one trip.
---
---As many as the trip allows, but never more than there is work for or the character is
---carrying: queueing more than there are ghosts for only means going home early.
---@param nearby LuaEntity[]
---@param claimed table<integer, boolean>?
---@param standing {x: number, y: number}
---@param range number
---@param item string
---@param count integer how many the ghost being reached for takes
---@param carried integer how many the character has
---@param capacity integer how many loads the claw holds
---@return integer
local function loads_for(nearby, claimed, standing, range, item, count, carried, capacity)
  if capacity <= 1 then return 1 end
  local wanted = 1
  for _, ghost in pairs(nearby) do
    if wanted >= capacity then break end
    if ghost.valid and not (claimed and claimed[ghost.unit_number])
        and not standing_in(ghost, standing)
        and not reach.out_of_range(standing, ghost.position, range) then
      local other, needed =
        build.placing_item(ghost.ghost_prototype.items_to_place_this, function() return count end)
      if other == item and needed == count then wanted = wanted + 1 end
    end
  end
  return math.max(1, math.min(wanted, math.floor(carried / count)))
end

---Pick something for an arm to set off after, which it may only do on a full buffer.
---@param player LuaPlayer
---@param nearby LuaEntity[] from ghosts_near
---@param claimed table<integer, boolean>? ghosts another arm is already reaching for
---@param record table the arm asking, which knows which equipment feeds it
---@param range number how far this arm can reach
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
---@return LuaEntity? ghost the one to reach for, if it can set off now
---@return string? item
---@return integer? count
---@return boolean waiting whether there is work but not yet the charge to do it
local function job_for(player, nearby, claimed, record, range)
  if not ready(record) then
    -- Still worth knowing whether there is anything to do. Setting off wants a full
    -- buffer, and a delivery spends some of it, so an arm that has just finished one is
    -- not ready on the very next tick. Filling it again takes a single tick from charged
    -- batteries -- measured at every tier -- but a single tick was enough: with no arm
    -- reporting work the run was declared over, the character started easing back to full
    -- speed, and a fresh slowdown began a tick later, so they oscillated instead of
    -- settling. The run ends when the work runs out, not when an arm is a tick short of
    -- being able to start the next trip.
    local ghost = choose(player, nearby, claimed, range)
    return nil, nil, nil, ghost ~= nil
  end
  local ghost, item, count = choose(player, nearby, claimed, range)
  return ghost, item, count, false
end

---The list of a player's arms, one per copy of the equipment they are wearing.
---
---Taking a copy out of the grid takes the last arm away rather than a particular one:
---which of several identical arms goes is not a question worth answering, and the ones
---that stay keep whatever they were doing.
---@param player LuaPlayer
---@return table[]
local function arms(player)
  local list = storage.constructor_arms[player.index]
  if not list then
    list = {}
    storage.constructor_arms[player.index] = list
  end
  return list
end

---The inserter for one arm, made if it is not there yet.
---@param player LuaPlayer
---@param record table
---@return LuaEntity?
local function arm_of(player, record)
  local character = player.character
  local arm = record.entity
  if not (arm and arm.valid) then
    arm = character.surface.create_entity{
      name = tier_of(record).inserter,
      position = character.position,
      force = player.force,
    }
    -- Filled the moment it exists, out of its own equipment, so that it never spends a
    -- tick on empty. Out of the equipment, not out of nothing: handing it a free bufferful
    -- here while refunding the remainder when it is put away would have made an arm coming
    -- and going a way of generating power.
    if arm and character.grid then
      charge(record, arm)
    end
    record.entity = arm
  end
  return arm
end

---Draw the claw shrinking away where the arm was.
---
---The arm itself cannot do this. An entity's sprites are scaled in its prototype, and
---nothing changes that at runtime, so the entity goes and a drawn copy of its folded claw
---takes its place for a fifth of a second: a sprite's scale and tint are script's to set.
---@param tier table
---@param surface LuaSurface
---@param at {x: number, y: number}
local function stow(tier, surface, at)
  -- Sprites are not among the prototypes script can look up, so the path is checked rather
  -- than the prototype. Worth checking at all for the same reason the stickers are: a
  -- script reloaded without its data stage runs against prototypes that never heard of it.
  if not helpers.is_valid_sprite_path(tier.claw) then return end
  local drawn = rendering.draw_sprite{
    sprite = tier.claw,
    surface = surface,
    target = { at.x, at.y },
    x_scale = tiers.SCALE,
    y_scale = tiers.SCALE,
    render_layer = "object",
  }
  if drawn then
    storage.constructor_stowing = storage.constructor_stowing or {}
    storage.constructor_stowing[drawn.id] = game.tick
  end
end

---Shrink and fade everything part way through being stowed, and clear away what is done.
local function stowing()
  storage.constructor_stowing = storage.constructor_stowing or {}
  for id, started in pairs(storage.constructor_stowing) do
    local drawn = rendering.get_object_by_id(id)
    local gone = (game.tick - started) / STOW_TICKS
    if not (drawn and drawn.valid) or gone >= 1 then
      if drawn and drawn.valid then drawn.destroy() end
      storage.constructor_stowing[id] = nil
    else
      local left = 1 - gone
      drawn.x_scale = tiers.SCALE * left
      drawn.y_scale = tiers.SCALE * left
      drawn.color = { r = 1, g = 1, b = 1, a = left }
    end
  end
end

---Take one inserter away, emptying its hand first so nothing is conjured out of it.
---
---Nothing goes back into the inventory, because nothing ever came out of it: the hand is
---filled from nothing and the inventory is only debited when something arrives. So an arm
---Put items from the box back into the claw, where they are still the player's.
---@param record table
---@param name string
---@param count integer
local function take_back(record, name, count)
  if count <= 0 then return end
  local box, arm = record.catcher, record.entity
  if box and box.valid then
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then inside.remove{ name = name, count = count } end
  end
  if arm and arm.valid then
    local held = arm.held_stack.valid_for_read and arm.held_stack.count or 0
    arm.held_stack.set_stack{ name = name, count = held + count }
  end
end

--- The box that stands on a ghost while an arm is delivering to it.
---
--- Without one, what the engine does with a claw arriving at a ghost depends on the ghost:
--- one whose entity could take the item makes the inserter wait for ever, one whose entity
--- could not is either built out of the claw or has the load dumped on the floor beside it.
--- None of those is the mod's decision and all three were reachable in play.
---
--- A container on the same tile settles it. An inserter puts things into containers, so
--- arrival stops being a distance the mod measures once a tick -- and could step clean over
--- -- and becomes a thing the engine reports by putting the item somewhere the mod owns.
--- The box collides with nothing, so the ghost underneath it stays revivable.
local CATCHER = "constructor-equipment-catcher"

--- How near the claw has to be before its box exists at all. Generous on purpose: being
--- early costs nothing, and the whole point of the box is to stop measuring arrivals
--- finely. It only has to be absent while the claw is far enough away that somebody else
--- could get a whole swing in.
local OPEN = 2.5

---The box belonging to this arm, present only while this claw is near enough to be the one
---filling it.
---
---An open box is a hole in the world: it accepts insertions, so an inserter of the
---player's own pointing at a tile a ghost stands on would quietly feed it and the mod would
---take a stranger's item for its own delivery. Whether a container accepts automated
---insertion is fixed in its prototype and cannot be turned off and on, so the box is
---created and destroyed instead of being opened and shut.
---@param record table
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param near boolean whether this claw is close enough for a delivery to be possible
---@return LuaEntity?
local function catcher_at(record, surface, at, near)
  local box = record.catcher
  if not near then
    -- nothing of ours should be in it yet, and if something is it goes back in the claw
    if box and box.valid then
      local inside = box.get_inventory(defines.inventory.chest)
      if inside then
        for _, stack in pairs(inside.get_contents()) do
          take_back(record, stack.name, stack.count)
        end
      end
      box.destroy()
    end
    record.catcher = nil
    return nil
  end
  if box and box.valid then
    if box.position.x ~= at.x or box.position.y ~= at.y then box.teleport(at) end
    return box
  end
  -- The arm's own force, not neutral: an inserter will not put anything into another
  -- force's container, and a neutral box was quietly ignored while the load went on the
  -- ground beside it.
  local owner = record.entity and record.entity.valid and record.entity.force or "player"
  box = surface.create_entity{ name = CATCHER, position = at, force = owner }
  record.catcher = box
  return box
end

---Take the box away, handing back anything left in it.
---@param record table
---@return LuaItemStack[]? what was inside
local function catcher_away(record)
  local box = record.catcher
  record.catcher = nil
  if not (box and box.valid) then return nil end
  local left = {}
  local inside = box.get_inventory(defines.inventory.chest)
  if inside then
    for _, stack in pairs(inside.get_contents()) do
      table.insert(left, { name = stack.name, count = stack.count })
    end
  end
  box.destroy()
  return left
end

---put away mid reach, whether because the character walked off or because they took the
---equipment out of their armour, costs them nothing.
---@param player LuaPlayer
---@param record table
local function put_away(player, record)
  local arm = record.entity
  catcher_away(record)
  if arm and arm.valid then
    -- whatever it was carrying was paid for out of the pockets, so it goes back in them
    -- rather than being destroyed with the arm
    local inventory = player.get_inventory(defines.inventory.character_main)
    local job = record.job
    if job and (job.escrow or 0) > 0 and job.item and inventory then
      inventory.insert{ name = job.item, count = job.escrow }
      job.escrow = 0
    end
    if arm.held_stack.valid_for_read then
      if inventory then
        inventory.insert{ name = arm.held_stack.name, count = arm.held_stack.count }
      end
      arm.held_stack.clear()
    end
    -- whatever it was holding in its buffer goes back where it came from, so that taking
    -- the arm out and putting it away again is not itself a way of burning charge
    local character = player.character
    if character and character.valid and character.grid then
      refund(character.grid, record.piece, arm.energy)
    end
    stow(tier_of(record), arm.surface, arm.position)
    arm.destroy()
  end
  record.entity = nil
  record.job = nil
  record.busy = nil
  record.run = nil
end

---Put every one of a player's arms away and forget they had any.
---@param player LuaPlayer
local function dismiss(player)
  local list = storage.constructor_arms[player.index]
  if not list then return end
  for _, record in pairs(list) do put_away(player, record) end
  storage.constructor_arms[player.index] = nil
end

---Match the list of arms to the equipment being worn, tier for tier.
---
---An arm whose tier has not changed carries on with whatever it was doing. One whose tier
---has is a different arm: it is put away, and a new one of the right sort takes its place.
---Taking a copy out of the grid therefore takes the last arm of that tier away rather than
---a particular one, which is not a question worth answering.
---@param player LuaPlayer
---@return table[]
local function muster(player)
  local list = arms(player)
  local want = worn(player.character)

  while #list > #want do
    put_away(player, list[#list])
    list[#list] = nil
  end
  for slot = 1, #want do
    local record = list[slot]
    if not record then
      list[slot] = { level = want[slot] }
    elseif record.level ~= want[slot] then
      put_away(player, record)
      list[slot] = { level = want[slot] }
    end
  end

  -- Each arm is powered by one piece of the equipment that put it there, so they are
  -- paired off: the first arm of a tier to the first piece of that tier, and so on. Which
  -- piece is which does not matter, only that two arms never feed from the same one.
  local taken = {}
  local grid = player.character.grid
  for _, record in ipairs(list) do
    local name = tier_of(record).name
    taken[name] = (taken[name] or 0) + 1
    record.piece = pieces_of(grid, name)[taken[name]]
  end
  return list
end

---Keep the inserter on the character and pointed at whatever it is reaching for.
---
---Both ends are set every tick. The pickup end is the character, so the hand comes home to
---them rather than to wherever they were standing when the swing began. The drop end has to
---be re-aimed as well, because an inserter's drop position travels with the inserter: move
---the entity and the target moves with it, so a fixed vector would drift off the ghost as
---the character walked.
---@param player LuaPlayer
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param job table? what it is reaching for, if anything
---@return LuaEntity? the inserter
local function aim(player, record, slot, count, job)
  local character = player.character
  local arm = arm_of(player, record)
  if not (arm and arm.valid) then return nil end

  -- Fed only while it has something to do. An arm idling on its owner's back still draws
  -- its inserter's standing drain, and feeding that out of the equipment left the buffer a
  -- few joules short of full for as long as the arm was out -- which, since setting off
  -- wants a full buffer, meant waiting the better part of a second between every reach.
  -- Idle, it runs its own buffer down instead, and is filled again when work arrives.
  if job then charge(record, arm) end
  local mount = mounting(character, slot, count)
  arm.teleport(mount)

  -- Where the claw rests: a little way out from the mounting point, along the bearing it
  -- is working on, so that coming home is a retraction rather than a swing. With nothing
  -- to work on it rests above the character, which is where a folded arm looks right.
  local towards = job and job.target
  local bearing = { x = 0, y = -1 }
  if towards then
    local dx, dy = towards.x - mount.x, towards.y - mount.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0.01 then bearing = { x = dx / length, y = dy / length } end
  end
  local rest = { x = mount.x + bearing.x * REST, y = mount.y + bearing.y * REST }
  record.rest = rest
  arm.pickup_position = { rest.x, rest.y }

  if job then
    if job.going == "out" then
      arm.drop_position = { job.target.x, job.target.y }
    elseif arm.held_stack.valid_for_read then
      -- Still carrying something on the way back, which happens when a reach is given up
      -- on: an empty hand comes home by itself, but a full one goes wherever it was told
      -- to drop, so it has to be told to come here.
      --
      -- Here is the resting point, not the mounting point. Sending it to the mount while
      -- home is measured from the rest point means the claw arrives somewhere nothing is
      -- watching for it, and the engine puts what it is holding on the ground before this
      -- ever notices. Aimed at the same place home is measured from, the item comes out of
      -- the hand a little before the claw gets there.
      arm.drop_position = { rest.x, rest.y }
    end
    -- An empty hand on the way back is left alone. Aiming it at the mount points it at the
    -- arm's own base, which is no direction at all, and the engine picks one: the claw
    -- swept out east at full stretch before coming home, which on a fast tier reads as the
    -- arm being flung sideways.
  end
  return arm
end

--- Declared here because deliver, below, turns to another ghost through it, and it is
--- defined after deliver. Without this the name is a global at that point, which is to say
--- nil, and the call takes the whole run down with an error the log never shows.
local redirect

---Give up on a reach without building anything.
---
---Whatever is in the hand stays in it and comes back with the claw, which is what it looks
---like from outside: the arm carries the thing home again rather than the item winking out
---of a closed claw halfway across the ground. It is taken out of the hand when the claw
---gets there. Nothing is given back to the inventory because nothing was ever taken from
---it: the hand is filled from nothing and the inventory is only debited on arrival.
---@param job table
--- Whether this player would rather have a returned item on the ground than in the claw.
---@param player LuaPlayer
---@return boolean
local function spills(player)
  local chosen = settings.get_player_settings(player)["constructor-equipment-spill-when-full"]
  return chosen and chosen.value or false
end

---Hand back what an arm is carrying, because it has already been paid for.
---
---The claw is loaded out of the character's pockets, so anything in it is the player's
---item and not a copy: destroying it on the way home would be taking it off them. If it
---will not fit, the player has said which they would rather have -- it on the ground, or
---kept in the claw with the arm holding station until there is room.
---@param player LuaPlayer
---@param record table
---@return boolean whether the claw is empty now
local function give_back(player, record)
  local arm = record.entity
  local job = record.job
  local inventory = player.get_inventory(defines.inventory.character_main)

  -- What was set aside for this round but never went into the claw goes back first. It
  -- was taken from the pockets when the arm set off and nothing was built with it, so it
  -- is simply the player's again. There is nothing holding it and nowhere for it to fall,
  -- so it does not need the spill or hold question that the claw's own load does.
  if job and (job.escrow or 0) > 0 and job.item and inventory then
    local returned = inventory.insert{ name = job.item, count = job.escrow }
    job.escrow = job.escrow - returned
    if job.escrow > 0 and spills(player) then
      local character = player.character
      if character and character.valid then
        character.surface.spill_item_stack{
          position = character.position,
          stack = { name = job.item, count = job.escrow },
          enable_looted = true,
          force = player.force,
        }
      end
      job.escrow = 0
    end
    if job.escrow > 0 then return false end
  end

  if not (arm and arm.valid and arm.held_stack.valid_for_read) then return true end
  local name, count = arm.held_stack.name, arm.held_stack.count
  local took = inventory and inventory.insert{ name = name, count = count } or 0
  if took >= count then
    arm.held_stack.clear()
    return true
  end
  if took > 0 then arm.held_stack.count = count - took end
  if spills(player) then
    local character = player.character
    if character and character.valid then
      character.surface.spill_item_stack{
        position = character.position,
        stack = { name = name, count = count - took },
        enable_looted = true,
        force = player.force,
      }
    end
    arm.held_stack.clear()
    return true
  end
  -- kept in the claw: the arm stays out rather than folding away with the player's item
  return false
end

---@param record table the arm giving up
---@param job table
local function abandon(record, job)
  job.going = "back"
  job.ghost = nil

  -- Re-aimed now rather than left to the next tick's aim(). The claw is still full and
  -- still pointed at the ghost, and the engine finishes swings on its own schedule: given
  -- a tick of grace it puts the load down on the ghost's own tile. That loses the delivery
  -- and mints a free item, because the claw is filled from nothing rather than from the
  -- inventory -- and worse, an item lying on a ghost stops that ghost being revived at
  -- all, so every attempt after the first fails the same way and drops another one.
  local arm = record and record.entity
  if arm and arm.valid and arm.held_stack.valid_for_read and record.rest then
    arm.drop_position = { record.rest.x, record.rest.y }
  end
  catcher_away(record)
end

---Put the thing down: revive the ghost, pay for it, and let the arm start coming home.
---@param player LuaPlayer
---@param record table the arm making the delivery
---@param job table
---@param claimed table<integer, boolean>? what the other arms are reaching for
local function deliver(player, record, job, claimed)
  local ghost = job.ghost
  local box = record.catcher

  -- What the box was given is the delivery. Until something is in it, nothing has
  -- arrived, and that is the whole of the arrival test: no distance, nothing to step over.
  local landed = 0
  if box and box.valid then landed = box.get_item_count(job.item) end
  if landed < 1 then return end

  -- A ghost can want more than a claw can hold: a plain inserter carries one item and a
  -- half diagonal rail takes two. The rest was taken from the pockets when the arm set off
  -- and has been travelling with the job rather than in the claw, so it is here to be
  -- spent and nothing needs asking of the pockets now.
  local short = job.count - landed
  if short > (job.escrow or 0) then
    -- the round is short of what this ghost wants, which should not happen: everything was
    -- reserved at the start. Give back what there is rather than build half a thing.
    take_back(record, job.item, landed)
    abandon(record, job)
    return
  end

  if not (ghost and ghost.valid) then
    -- the ghost went while the claw was on its way; the load goes back in the claw and
    -- comes home, since it has already been paid for
    take_back(record, job.item, landed)
    abandon(record, job)
    return
  end

  local _, built = ghost.revive()
  if not built then
    take_back(record, job.item, landed)
    abandon(record, job)
    return
  end

  -- The ghost is up, so the items that built it are spent. They came out of the pockets
  -- when the claw was loaded, so nothing is charged here: this is simply where they stop
  -- existing.
  local inside = box.get_inventory(defines.inventory.chest)
  if inside then inside.remove{ name = job.item, count = math.min(landed, job.count) } end
  if short > 0 then job.escrow = job.escrow - short end
  -- whatever else the claw brought is still the player's, and goes back in the claw for
  -- the next ghost of this round
  take_back(record, job.item, math.max(0, landed - job.count))

  -- More of this trip left, and another of the same thing in reach, means going home would
  -- be a wasted journey. So the claw turns to the next one with the rest of its load still
  -- in hand. That is the whole of what a carrying claw buys: one journey out, several
  -- ghosts, one journey back.
  local arm = record.entity
  job.left = (job.left or 1) - 1
  -- What is left of the round is what is left in the claw, not what the job set out to do.
  -- Those two came apart once: a trip loaded with two put one down, found its hand empty
  -- and carried on regardless, because only the counter was consulted.
  if job.left > 0 and arm and arm.valid
      and arm.held_stack.valid_for_read and arm.held_stack.count >= job.count
      and afford_another(record, arm)
      and redirect(player, record, job, claimed, tier_of(record).range) then
    arm.drop_position = { job.target.x, job.target.y }
    -- shut to begin with: the claw is still at the ghost it has just built, and advance
    -- opens the box once it is near the new one
    catcher_at(record, arm.surface, job.target, false)
    return
  end

  job.going = "back"
  job.ghost = nil
  catcher_away(record)
end

---Point a reach at something else that takes the same item, if there is anything.
---
---The claw is already out and already holding the right thing, so going home to fetch an
---identical item and coming back out is a wasted trip. Anything that needs something else
---does mean a trip home, because the hand can only hold one thing.
---@param player LuaPlayer
---@param job table
---@param claimed table<integer, boolean>? ghosts the other arms are reaching for
---@param range number how far this arm reaches
---@return boolean whether it found somewhere else to go
function redirect(player, record, job, claimed, range)
  local ghost, item, count =
    choose(player, ghosts_near(player, range), claimed, range)
  if not ghost then return false end
  if item ~= job.item then return false end

  -- A ghost wanting a different number of the same thing is still worth turning to. What
  -- was set aside covers the ghost the arm set out for, so turning to a smaller one hands
  -- the difference straight back rather than carrying it around: an arm that set off for a
  -- curved rail with one in the claw and two put by, and finds a straight rail instead,
  -- gives the two back on the spot.
  if count ~= job.count then
    local arm = record and record.entity
    local held = arm and arm.valid and arm.held_stack.valid_for_read
      and arm.held_stack.count or 0
    if held < count then return false end
    if (job.escrow or 0) > 0 then
      local inventory = player.get_inventory(defines.inventory.character_main)
      if inventory then
        local returned = inventory.insert{ name = job.item, count = job.escrow }
        job.escrow = job.escrow - returned
      end
      -- anything that would not fit stays put by and goes home with the arm
    end
    job.count = count
    job.left = math.floor(held / count)
    if job.left < 1 then return false end
  end

  if claimed then claimed[ghost.unit_number] = true end
  job.ghost = ghost
  job.target = ghost.position
  return true
end

---What each of a player's arms is already reaching for, so that no two go for the same
---ghost.
---@param list table[]
---@return table<integer, boolean>
local function claims(list)
  local claimed = {}
  for _, record in pairs(list) do
    local job = record.job
    if job and job.ghost and job.ghost.valid then
      claimed[job.ghost.unit_number] = true
    end
  end
  return claimed
end

---Move one arm's reach on by one tick.
---
---The swing is the inserter's own, so this does not drive it. It watches: the hand arrives
---at what it was aimed at, which is the moment of delivery, and the hand coming back to
---the character is the end of the job.
---@param player LuaPlayer
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param claimed table<integer, boolean> what the other arms are reaching for
local function advance(player, record, slot, count, claimed)
  local job = record.job
  local character = player.character

  if not (character and character.valid) then
    record.job = nil
    return
  end

  if job then
    record.busy = game.tick
    -- Which is not the same as having a job this tick. A swing that has got home waits a
    -- few ticks for its clock, and the slowdown has to hold across that gap: the ramp
    -- sticker is sixty ticks long, so one that ran out in a gap was replaced by a fresh
    -- ramp rather than handing over to the flat sticker, and the character oscillated
    -- instead of settling at the speed their tier asks for. Cleared when there is nothing
    -- left to build, which is decided on the check tick.
    record.run = game.tick
  else
    -- Nothing to do. The arm stays out for a moment in case another ghost turns up, and is
    -- put away if none does, rather than being worn while the character wanders about.
    if record.busy and game.tick - record.busy <= IDLE_TICKS then
      aim(player, record, slot, count, nil)
    else
      put_away(player, record)
    end
    return
  end

  local arm = aim(player, record, slot, count, job)
  if not arm then return end

  -- How far this hand went since the last look. The window for arriving is measured from
  -- it rather than from the tier's numbers: what the engine does on its last step is not
  -- what the prototype says its speed is, and a window narrower than the step is one the
  -- hand jumps clean over.
  local hand = arm.held_stack_position
  local moved = record.last_hand and reach.distance(record.last_hand, hand) or 0
  record.last_hand = { x = hand.x, y = hand.y }

  if job.going == "out" then
    -- The box waiting on the ghost is opened only once this claw is near enough to be the
    -- one that fills it. Left open the whole way out, any inserter of the player's own
    -- pointing at that tile could put something in it, and the mod would take a stranger's
    -- item for its own delivery.
    catcher_at(record, arm.surface, job.target,
      reach.distance(hand, job.target) <= within(tier_of(record), OPEN, moved))

    -- the character can walk off mid swing, and an arm that stretched to follow would be
    -- no kind of inserter
    if not (job.ghost and job.ghost.valid)
        or standing_in(job.ghost, character.position)
        or reach.out_of_range(character.position, job.ghost.position, tier_of(record).range)
        or game.tick - (job.started or game.tick) > SWING_LIMIT then
      local tier = tier_of(record)
      if not redirect(player, record, job, claimed, tier.range) then
        abandon(record, job)
      end
    else
      -- deliver() does nothing until the box has been given something, so there is no
      -- arrival to measure and nothing to step over: it can simply be asked every tick
      deliver(player, record, job, claimed)
    end
  elseif reach.distance(arm.held_stack_position, record.rest or mounting(character, slot, count))
        < within(tier_of(record), HOME, moved)
      or game.tick - (job.started or game.tick) > SWING_LIMIT then
    -- Home is the mounting point, which is not where the character's feet are. Anything
    -- still in the claw was paid for on the way out, so it is handed back rather than
    -- destroyed. If it will not fit and the player would rather not have it on the ground,
    -- the arm holds station with it until there is room.
    if give_back(player, record) then
      record.job = nil
      catcher_away(record)
    end
  end
end

---Hand out work to whichever of a player's arms are free.
---
---There is no clock. An arm sets off the moment it has nothing else to do and there is
---something in reach, and how often that comes round is decided by how long its claw takes
---to go out and come back -- which is the arm's own speed, and the thing a better tier
---buys. The mod used to cap the rate separately, at two builds a second whatever the arm
---was doing. That was left over from when there was no inserter to time, and it did harm:
---at short reaches the claw got home well before its next slot was due, and the arm stood
---waiting. Those gaps are what broke the slowdown ramp and the speed recovery, twice.
---
---One search serves every arm. It is the expensive part, the answer is the same for all of
---them, and only the range each judges it by differs.
---@param player LuaPlayer
---@param list table[]
---@param tick integer
---@return boolean whether any arm has anything to do
local function assign(player, list, tick)
  local claimed = claims(list)
  local nearby = ghosts_near(player, furthest(list))
  local working = false
  for slot, record in ipairs(list) do
    if record.job then
      working = true
    else
      local tier = tier_of(record)
      local ghost, item, count, waiting =
        job_for(player, nearby, claimed, record, tier.range)
      if waiting then
        -- work in reach, buffer a tick short of full: the run is still on
        working = true
        record.run = game.tick
      end
      if ghost then
        claimed[ghost.unit_number] = true
        record.job = {
          ghost = ghost,
          target = ghost.position,
          item = item,
          count = count,
          going = "out",
          started = tick,
        }
        -- Paid for on the way out, not on arrival. Filling the claw from nothing made
        -- every item in it a counterfeit, so any path where the engine put one somewhere
        -- the mod did not intend -- and there were several -- minted a real item out of
        -- air. Taking it from the pockets now means whatever happens to it afterwards,
        -- nothing is created: it is either delivered, brought back, or lost by the player
        -- who owned it. The last tier fills its claw with as many as there is work for.
        local inventory = player.get_inventory(defines.inventory.character_main)
        record.job.left = loads_for(nearby, claimed, player.character.position, tier.range,
          item, count, inventory and inventory.get_item_count(item) or count,
          trips_for(player.force, tier))
        local arm = aim(player, record, slot, #list, record.job)
        if arm then
          -- Everything the round will need comes out of the pockets now, whether or not
          -- the claw can hold it. A claw holds what its inserter holds -- one thing for a
          -- plain one -- and a curved rail wants three, so the claw takes as many as fit
          -- and the rest are set aside against this job. A construction robot carries all
          -- three at once regardless of its cargo size, so this is the same bargain by
          -- other means: the items are spent when the arm sets off and given back if it
          -- comes home without building anything.
          local want = count * record.job.left
          local taken = inventory and inventory.remove{ name = item, count = want } or 0
          if taken < count then
            -- not even one ghost's worth left in the pockets
            if taken > 0 then inventory.insert{ name = item, count = taken } end
            arm.held_stack.clear()
            record.job = nil
          else
            record.job.left = math.floor(taken / count)
            arm.held_stack.set_stack{ name = item, count = taken }
            -- what the claw actually took, and what is being carried on its behalf
            record.job.carried = arm.held_stack.valid_for_read and arm.held_stack.count or 0
            record.job.escrow = taken - record.job.carried
          end
        end
        working = true
      end
    end
  end
  return working
end

---@param event EventData.on_tick
local function on_tick(event)
  stowing()

  for _, player in pairs(game.players) do
    local character = player.character
    if character and character.valid and wearing(character) then
      local list = muster(player)
      local claimed = claims(list)
      -- Slowed for as long as an arm is working, not only at the moment one arrives.
      -- Applying it on delivery alone left a gap: the ramp ran out partway through the
      -- next swing and the character surged until the next thing was delivered.
      --
      -- One slowdown however many arms are working, and where they disagree it is the
      -- heaviest that lands: a tier that asks for nothing does not excuse the tier working
      -- beside it that does. So a good arm worn on its own costs its wearer no speed, and
      -- worn alongside an old one it costs whatever the old one costs.
      local worst, running = nil, false
      for slot, record in ipairs(list) do
        advance(player, record, slot, #list, claimed)
        if record.run then
          running = true
          local set = tier_of(record).stickers
          if set and (not worst or set.modifier < worst.modifier) then worst = set end
        end
      end
      if worst then
        slow(player, worst)
      elseif running then
        -- arms are in a run and none of them asks for any penalty, so give the speed back
        -- rather than waiting for the work to run out
        recover(player)
      end
      -- An arm in no run at all is deliberately left alone here rather than recovered.
      -- Whether there is anything left to build is asked on the check tick, where it can
      -- be answered properly, and that is what ends a run.
    else
      -- taken off, or the character is gone: no arms and no half finished swings
      dismiss(player)
    end
  end

  if event.tick % CHECK_INTERVAL ~= CHECK_TICK then return end

  for _, player in pairs(game.players) do
    local character = player.character
    if character and character.valid then
      -- Nothing left in reach is when the character starts getting their speed back, not
      -- merely no arm swinging this instant: the search runs ten times a second and a claw
      -- can be home for a few ticks before the next one, and recovering in those gaps had
      -- the character surging between one ghost and the next all the way along a
      -- blueprint. So this asks whether there is anything to build.
      local list = storage.constructor_arms[player.index] or {}
      -- No arm working after that means no arm could find anything, because an arm with
      -- nothing to do takes work the instant there is any: without a clock there is no
      -- such thing as free but not yet due. So this needs no second search of its own.
      if not assign(player, list, event.tick) then
        -- the run is over, which is what lets the slowdown ramp off
        for _, record in pairs(list) do record.run = nil end
        recover(player)
      end
    end
  end
end

script.on_init(setup)
script.on_configuration_changed(setup)
script.on_event(defines.events.on_tick, on_tick)

--- ce-tests is never published, so this can never fire on a player's machine -- which
--- matters, because info.json keeps test/ out of the package.
if script.active_mods["factorio-test"] and script.active_mods["ce-tests"] then
  require("__factorio-test__/init")({
    "test.ft.building",
    "test.ft.delivering",
    "test.ft.characterless",
    "test.ft.slowdown",
    "test.ft.interpolation",
    "test.ft.power",
    "test.ft.several",
    "test.ft.equipping",
    "test.ft.tiers",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
