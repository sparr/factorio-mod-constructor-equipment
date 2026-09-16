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

--- Every set of slowdown stickers there is: two per tier that asks for the penalty, one
--- for whatever walks or rolls and one for whatever strides. See prototypes/sticker.lua for
--- why they are stickers rather than a number on the character, and why the same penalty
--- has to be written down twice, and lib/tiers.lua for which tiers have any at all.
---
--- All of them in one list, because the one thing slowing a wearer must do is take every
--- other set off them: they are separate prototypes, so any two the engine keeps are
--- multiplied together, and that includes the two kinds of the same tier's own.
local SETS = {}
for _, tier in ipairs(tiers.list) do
  if tier.stickers then
    table.insert(SETS, tier.stickers)
    table.insert(SETS, tier.stickers.legs)
  end
end

---Which of a tier's two sets of stickers a wearer takes: the legged one if it strides,
---and the one that serves characters and wheels otherwise.
---@param wearer LuaEntity
---@param set table a tier's stickers, from lib/tiers.lua
---@return table
local function stickers_for(wearer, set)
  if wearer.type == "spider-vehicle" and set.legs then return set.legs end
  return set
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
  -- who has switched their arms off from the toolbar, by player index
  storage.constructor_off = storage.constructor_off or {}
  -- what each player's button was last told, so it is only set when it changes
  storage.constructor_button = storage.constructor_button or {}

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

--- The toolbar button, the key binding, and the entry that remembers who has pressed
--- either. One name, because they are one thing to a player. See prototypes/shortcut.lua.
local TOGGLE = "constructor-equipment-toggle"

---Whether this player has switched their arms off.
---
---Theirs alone. The equipment is worn by one person and the button sits in one person's
---toolbar, so a player who wants their arms to stop does not stop anybody else's.
---@param player LuaPlayer
---@return boolean
local function switched_off(player)
  return storage.constructor_off[player.index] or false
end

---What a player's arms hang off, and whose grid feeds them.
---
---A driver's own armour is out of the question: they are sat in a vehicle rather than
---walking about in it, so arms strapped to their back would be swinging about inside the
---cab. What a vehicle has instead is a grid of its own, and the equipment goes in it as
---readily as into armour -- every grid in the base game takes the same category of
---equipment -- so while somebody is driving, the vehicle is what wears the arms, pays for
---them out of its own grid, and takes the slowdown they ask for.
---
---The driver's, and nobody else's. One grid worn by two people would put two sets of arms
---on the same equipment, and a passenger would double what the vehicle can do by climbing
---in. A passenger is in a vehicle all the same, so their armour is off too: they get
---nothing until they take the wheel or get out.
---@param player LuaPlayer
---@return LuaEntity? the character, or the vehicle they are driving, or nothing at all
local function wearer_of(player)
  local vehicle = player.vehicle
  if not vehicle then return player.character end
  if not vehicle.valid then return nil end
  local driver = vehicle.get_driver()
  if not driver then return nil end
  -- a driver who has a character is that character; one without is the player themselves
  if driver == player.character or driver == player then return vehicle end
  return nil
end

---The pockets an arm spends out of and hands things back to.
---
---Whoever is wearing the arms pays for them. On foot that is the player's own inventory,
---which is where it has always come from. In a vehicle it is the vehicle's own hold: the
---arms are the vehicle's, and a driver who loads the boot has said what the vehicle is to
---build with. It also means a vehicle left to build does not quietly empty the pockets of
---whoever happens to be sat in it.
---
---A vehicle with nowhere to put anything -- a locomotive, say, which has only a fuel box --
---has no pockets at all, and an arm on one finds nothing to build with rather than reaching
---into its driver's.
---@param player LuaPlayer
---@param wearer LuaEntity? the character or vehicle the arms are on
---@return LuaInventory?
local function pockets(player, wearer)
  if wearer and wearer.valid and wearer.type ~= "character" then
    return wearer.get_inventory(defines.inventory.car_trunk)
        or wearer.get_inventory(defines.inventory.spider_trunk)
        or wearer.get_output_inventory()
  end
  -- the separate quickbar went away in 0.17; what is left is the character's own
  -- inventory, and the quickbar is a set of references into it
  return player.get_inventory(defines.inventory.character_main)
end

---One of this mod's stickers on a wearer, if it is there.
---@param wearer LuaEntity
---@param name string
---@return LuaEntity?
local function sticker_on(wearer, name)
  for _, sticker in pairs(wearer.stickers or {}) do
    if sticker.valid and sticker.name == name then return sticker end
  end
  return nil
end

---Slow whoever is wearing the arms down, or keep them slowed if they already are.
---
---Character or vehicle, and the same fraction of speed either way. A sticker carries a
---figure for a character and a figure for a vehicle and the engine uses whichever suits
---what it lands on, and where one figure will not do for both kinds of vehicle there is a
---second set to pick from: see stickers_for above and prototypes/sticker.lua.
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
---@param wearer LuaEntity? the character or vehicle the arms are on
---@param set table which tier's stickers, from lib/tiers.lua
local function slow(player, wearer, set)
  if not (wearer and wearer.valid) then return end
  set = stickers_for(wearer, set)
  for _, other in ipairs(SETS) do
    local recovery = sticker_on(wearer, other.recovery)
    if recovery then recovery.destroy() end
    if other ~= set then
      local flat = sticker_on(wearer, other.flat)
      if flat then flat.destroy() end
      local slowing = sticker_on(wearer, other.slowing)
      if slowing then slowing.destroy() end
    end
  end

  local flat = sticker_on(wearer, set.flat)
  if flat then
    -- already at the bottom of the ramp; keep it there
    wearer.surface.create_entity{
      name = set.flat, position = wearer.position, target = wearer }
    return
  end

  -- Part way down. Left to run: refreshing it would start the descent again and the
  -- character would surge. It is not swapped for the flat sticker early either, which is
  -- what this used to do -- the ramp ends at exactly the speed the flat sticker holds, so
  -- letting it expire on its own makes the handover invisible, where swapping out with a
  -- fifth of its life left was a step change in speed.
  if sticker_on(wearer, set.slowing) then return end

  -- Neither is on. Whether that means the ramp has not run yet or that it has been and
  -- gone is not something the character can be asked, because an expired sticker leaves
  -- nothing behind, so it is remembered instead.
  --
  -- Reading it off the sticker was the bug. A run of building is not continuous: an arm
  -- that gets home before its clock is due waits a few ticks, and a ramp that ran out in
  -- one of those gaps was replaced by a second ramp rather than by the flat sticker. The
  -- character kept easing towards a speed they never reached.
  if storage.constructor_ramped[player.index] then
    wearer.surface.create_entity{
      name = set.flat, position = wearer.position, target = wearer }
    return
  end

  -- The ramp is cosmetic, and a missing sticker prototype is not worth ending someone's
  -- game over. It can go missing for a real reason: game.reload_mods() reloads a mod's
  -- scripts but not its prototypes, so a script that has just learnt about a new sticker
  -- runs against data that has never heard of it. That crashed a session.
  if not prototypes.entity[set.slowing] then
    wearer.surface.create_entity{
      name = set.flat, position = wearer.position, target = wearer }
    return
  end
  storage.constructor_ramped[player.index] = true
  wearer.surface.create_entity{
    name = set.slowing, position = wearer.position, target = wearer }
end

---Let a wearer who has run out of things to build come back up to speed.
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
---@param wearer LuaEntity? the character or vehicle the slowdown is on
local function recover(player, wearer)
  storage.constructor_ramped[player.index] = nil
  if not (wearer and wearer.valid) then return end
  for _, set in ipairs(SETS) do
    local slowdown = sticker_on(wearer, set.flat) or sticker_on(wearer, set.slowing)
    if slowdown then
      slowdown.destroy()
      if prototypes.entity[set.recovery] then
        wearer.surface.create_entity{
          name = set.recovery,
          position = wearer.position,
          target = wearer,
        }
      end
      return
    end
  end
end

---Which tiers of the equipment this wearer has in its grid, one entry per copy.
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
---@param wearer LuaEntity? a character or a vehicle, from wearer_of
---@return integer[] the level of each arm
local function worn(wearer)
  local found = {}
  if not (wearer and wearer.valid) then return found end
  local grid = wearer.grid
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

---Whether this wearer has any of the equipment in its grid at all.
---@param wearer LuaEntity?
---@return boolean
local function wearing(wearer)
  return #worn(wearer) > 0
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

--- Which kinds of wearer are turned by an orientation rather than by a direction.
---
--- A character faces one of sixteen ways and says so in entity.direction. A vehicle turns
--- smoothly and says so in entity.orientation, as a fraction of a turn, and asking one for
--- the other raises rather than returning nothing: reading direction off a car gives the
--- last thing it was built facing and reading orientation off a character is an error. So
--- which to ask is decided by type.
local ORIENTED = {
  ["car"] = true,
  ["spider-vehicle"] = true,
  ["locomotive"] = true,
  ["cargo-wagon"] = true,
  ["fluid-wagon"] = true,
  ["artillery-wagon"] = true,
}

---Which way a wearer is facing, on the sixteen point scale lib/pack.lua works in.
---
---Fractional for a vehicle, which is the point of asking it this way: a car halfway between
---two of the sixteen has its arms halfway round with it rather than snapping between them.
---@param wearer LuaEntity
---@return number
local function facing_of(wearer)
  if ORIENTED[wearer.type] then return wearer.orientation * pack.DIRECTIONS end
  return wearer.direction
end

---How wide and how long a wearer is, in tiles either side of its middle.
---
---The selection box rather than the collision box: what the arms are being arranged around
---is the hull a player sees, and a vehicle's selection box is drawn round exactly that.
---@param wearer LuaEntity
---@return number across half its width
---@return number along half its length
local function hull_of(wearer)
  local box = wearer.prototype.selection_box
  return (box.right_bottom.x - box.left_top.x) / 2,
         (box.right_bottom.y - box.left_top.y) / 2
end

--- How far the near side of a hull is drawn above the ground it stands on, as a share of
--- the hull's own half width.
---
--- Measured on a tank at twice zoom, which is the only way to get at it: nothing in the
--- prototype says how tall a body is drawn. Its sprite stops 0.78 tiles south of its middle
--- where the selection box says 0.9, and the treads run from there up to about 0.5, so the
--- side of the hull an arm should be bolted to is four tenths of a tile above where the box
--- puts it. Four tenths of a tank's 0.9 is the fraction below, and a smaller vehicle gets a
--- smaller lift out of it, which is the right way for a guess to be wrong.
local TREADS = 0.45

---Where an arm stands on the ground, which is where its reach is measured from.
---
---Two quite different answers. A character wears their arms on their back, in a knot at the
---shoulders. A vehicle carries them along the sides of its hull, because the middle of a
---vehicle is underneath it: an arm bolted there is drawn over by the hull and the player
---sees a claw coming out of nothing. See lib/pack.lua for both.
---@param wearer LuaEntity a character or a vehicle
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number}
local function station_on(wearer, slot, count)
  local at = wearer.position
  local offset
  if wearer.type == "character" then
    -- the spot their shoulder is over, not the shoulder: how far up their back the arm is
    -- strapped is the lift below, and is no kind of distance
    offset = pack.ground(facing_of(wearer), slot, count)
  else
    local across, along = hull_of(wearer)
    offset = pack.mount(facing_of(wearer), slot, count, across, along)
  end
  return { x = at.x + offset.x, y = at.y + offset.y }
end

---How far an arm is carried up off the ground to be drawn on the body it is bolted to.
---
---Perspective rather than distance. The world is flat and the map has no up, so a sprite
---drawn above its own position is drawn a little to the north of it, and an arm put down
---where the geometry says belongs at the hull's ground line rather than on the body a player
---can see.
---
---A character's own is how far up their back the thing is strapped, which is the same
---trick at a smaller size: two thirds of the way up somebody is most of a tile north of
---their feet.
---@param wearer LuaEntity
---@param at {x: number, y: number} where the arm stands, from station_on
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return number how far north to draw it, in tiles
local function lift_of(wearer, at, slot, count)
  if wearer.type == "character" then return pack.lift(slot, count) end

  local body = wearer.prototype.height
  if body then
    -- A body that rides above its own position says so. A spider vehicle's torso is carried
    -- a tile and a half up its legs, and every arm goes up with it: the torso is all there
    -- is to bolt one to, and nothing stands in front of it to hide an arm behind.
    return body
  end

  -- A hull is a box, and the sprite draws the side of it facing the camera above the ground
  -- line. An arm out on that side is lifted to meet it; one round the far side stays where
  -- it is, because the hull is drawn over it either way and lifting it would poke it out
  -- over the roof.
  local across = hull_of(wearer)
  local offset = { x = at.x - wearer.position.x, y = at.y - wearer.position.y }
  return TREADS * across * pack.nearness(offset)
end

---Where an arm is drawn, which is where it stands carried up onto the body.
---@param wearer LuaEntity a character or a vehicle
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number} where the arm goes
---@return number how far up that is from where it stands
local function mounting(wearer, slot, count)
  local at = station_on(wearer, slot, count)
  local lift = lift_of(wearer, at, slot, count)
  return { x = at.x, y = at.y - lift }, lift
end

---Where a claw is aimed for a ghost: the ghost, carried up into the frame the arm swings in.
---
---This is what keeps a lifted arm honest. The engine swings a hand out from wherever the
---inserter stands, so an arm drawn up on a body and aimed at a ghost on the ground has
---further to stretch southward than northward -- a spidertron, whose torso rides a tile and
---a half up, was half again as slow to build behind itself as in front, and a character,
---whose pack rides two thirds of the way up them, was twice as quick to build in front of
---themselves as behind. Lifting the target by the same amount it lifted the arm makes the
---whole swing a copy of the one it would have made at ground level: same distance, same
---time, whichever way it faces.
---
---What it costs is the claw stopping a little short of the ghost, up where the arm is. That
---is not a miss. A claw holding something over a tile is drawn exactly there, because this
---game draws height as distance to the north, and the item lands on the ghost because the
---box that catches it went up with the claw. The ghost is revived where it stands.
---@param job table
---@param record table the arm, which remembers how far up it is drawn
---@return {x: number, y: number}
local function aimed_at(job, record)
  local lift = record.lift or 0
  if lift == 0 then return job.target end
  return { x = job.target.x, y = job.target.y - lift }
end

---Where an arm reaches from.
---
---Its own base on a vehicle, and its owner's own position on a character. A character wears
---every arm in one knot at their shoulders, a hand's breadth from their middle, and the
---reach a tier promises has always been the reach from the person wearing it. A hull is
---another matter: a tank is nearly three tiles long, so an arm bolted to the back of one
---and measuring from the tank's middle would be asked to stretch a tile and a half further
---than its tier sells, and would take half again as long doing it. It reaches from where it
---is bolted, so what a tier promises is what every arm wearing it can do.
---@param wearer LuaEntity
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are
---@return {x: number, y: number}
local function reaching_from(wearer, slot, count)
  if wearer.type == "character" then return wearer.position end
  -- where the arm stands rather than where it is drawn: the lift that puts it on the body
  -- is a trick of the camera, and a claw that reached a tile and a half less far to the
  -- south of a spidertron because its torso rides high would be the trick coming true
  return station_on(wearer, slot, count)
end

---How far from a wearer's middle an arm's base can sit.
---
---Nought for a character, whose arms are near enough their middle to ignore. A corner of a
---hull for a vehicle, which is what the ghost search has to be widened by: an arm out there
---reaches its own range from its own base, which can be a corner's worth further out than
---anything measured from the middle would find.
---@param wearer LuaEntity
---@return number
local function spread_of(wearer)
  if wearer.type == "character" then return 0 end
  local across, along = hull_of(wearer)
  return math.sqrt(across * across + along * along)
end

---What a piece of work leaves behind: the prototype of the thing that ends up on the tile.
---
---A ghost says so itself. An entity marked for upgrade says so through the order the
---planner hung on it, which names what to replace it with and at what quality.
---@param work LuaEntity a ghost, or an entity marked for upgrade
---@return LuaEntityPrototype?
---@return LuaQualityPrototype?
local function outcome_of(work)
  if work.type == "entity-ghost" then return work.ghost_prototype, work.quality end
  -- Nothing is put down on a cliff or on something being taken away, so neither has an
  -- outcome to ask about.
  if work.type == "cliff" or work.to_be_deconstructed() then return nil end
  return work.get_upgrade_target()
end

---How one piece of work is told from another, so that no two arms set off for the same one.
---
---A unit number where there is one, and where there is not, the ground it stands on. A
---cliff has no unit number: it is scenery the map generator laid down rather than something
---built, and a search for one comes back with nothing to key a claim on.
---@param work LuaEntity
---@return string|integer
local function claim_of(work)
  return work.unit_number or ("at " .. work.position.x .. "," .. work.position.y)
end

---Whether a piece of work is something to be taken up rather than put down.
---
---Asked before the upgrade question, because a thing marked for deconstruction is still a
---thing standing there and answers yes to both otherwise.
---@param work LuaEntity
---@return boolean
local function taking(work)
  if work.type == "entity-ghost" or work.type == "cliff" then return false end
  return work.to_be_deconstructed()
end

---Whether a piece of work is a cliff waiting to be blown up.
---
---A cliff marked for deconstruction is not a demolition the arm can carry out. It is a
---delivery: the claw brings an explosive and comes home empty, which is what a construction
---robot does with one. Measured on 2.1.17, a marked cliff stood untouched while a network
---with no explosives in it finished everything else, and went the moment one was put in a
---chest, at a cost of exactly one.
---@param work LuaEntity
---@return boolean
local function exploding(work)
  return work.type == "cliff"
end

---What a cliff asks to be brought, in the shape items_to_place_this comes in.
---
---Read off the cliff rather than named here: which explosive a cliff wants is a property of
---the cliff, and a planet that wants a different one says so in its own prototype.
---@param work LuaEntity
---@return {name: string, count: integer}[]?
local function explosive_for(work)
  local wanted = work.prototype.cliff_explosive_prototype
  if not wanted then return nil end
  return { { name = wanted, count = 1 } }
end

---The projectile an explosive throws, which is what actually breaks the cliffs.
---
---Thrown rather than the cliff simply being destroyed, so that the blast does what a blast
---does: it takes the neighbours in its radius with it, which is why a robot clearing a wall
---of cliffs does not spend one charge per cliff.
---@param name string the explosive item
---@return string?
local function projectile_of(name)
  local item = prototypes.item[name]
  local capsule = item and item.capsule_action
  local attack = capsule and capsule.attack_parameters
  local ammo = attack and attack.ammo_type
  for _, action in pairs(ammo and ammo.action or {}) do
    for _, delivery in pairs(action.action_delivery or {}) do
      if delivery.type == "projectile" then return delivery.projectile end
    end
  end
  return nil
end

---Whether a piece of work is a thing standing there waiting to be swapped rather than a
---ghost waiting to be raised.
---
---Asked of the entity every time rather than remembered on the job, so a job whose target
---has gone cannot be wrong about which of the two it was.
---@param work LuaEntity
---@return boolean
local function upgrading(work)
  return work.type ~= "entity-ghost"
end

---Whether a piece of work is still worth reaching for.
---
---A ghost is, as long as it is still a ghost. An upgrade is only while the order is still
---on it: a player can call the planner off between the arm setting out and the claw
---arriving, and the thing left standing there is then somebody's working belt rather than
---anything this mod should be pulling up.
---@param work LuaEntity?
---@return boolean
local function still_wanted(work)
  if not (work and work.valid) then return false end
  if exploding(work) or taking(work) then return work.to_be_deconstructed() end
  -- a ghost somebody has since marked for deconstruction is not something to build
  if not upgrading(work) then return not work.to_be_deconstructed() end
  return work.to_be_upgraded() and not work.to_be_deconstructed()
end

---The one item a thing turns into when it is taken up, if it is only one.
---
---Everything the replacement cannot hold is spilled on the floor by the engine, so what is
---left to bring home is the entity itself. In the base game that is a single item every
---time; anything stranger than that is left where the engine put it rather than guessed at.
---@param work LuaEntity
---@return string? name
---@return integer? count
local function sole_product(work)
  local mineable = work.prototype.mineable_properties
  local products = mineable and mineable.products
  if not products or #products ~= 1 then return nil end
  local product = products[1]
  if product.type ~= "item" then return nil end
  return product.name, product.amount or product.amount_min or 1
end

---Which end of a pair a thing is.
---
---An underground belt and a loader are each two things wearing one name, and which end
---this one is does not live in its direction. Left unsaid, both the question of whether
---the replacement fits and the swap itself treat it as an input, whichever end it is.
---@param work LuaEntity
---@return string?
local function end_of(work)
  if work.type == "underground-belt" then return work.belt_to_ground_type end
  if work.type == "loader" or work.type == "loader-1x1" then return work.loader_type end
  return nil
end

---The other end of an underground belt's pair, when that end is marked for upgrade too.
---
---A pair is one thing wearing two hulls. Replacing one end alone leaves a fast belt joined
---to a slow one until the arm comes back for the other, and turns the tunnel out: measured
---on 2.1.17, a robot upgrading one end put the eight items that were in the tunnel on the
---floor, where its network then collected them. Nothing is lost by it; it is simply a mess
---somebody has to clear up. So both ends are one piece of work, reached from whichever end
---the arm found, paid for with two items the way a curved rail is paid for with several.
---@param work LuaEntity
---@return LuaEntity? other
local function paired_with(work)
  if work.type ~= "underground-belt" then return nil end
  local other = work.underground_belt_neighbour
  if not (other and other.valid and other.to_be_upgraded()) then return nil end
  if other.to_be_deconstructed() then return nil end
  return other
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
local function buildable(work)
  -- Nothing is put down on a cliff or in the place of a thing being taken away, so there is
  -- no room to ask about. The blast makes its own space, and taking a thing up makes room
  -- rather than wanting it.
  if exploding(work) or taking(work) then return true end
  local prototype = outcome_of(work)
  if not prototype then return false end
  return work.surface.can_place_entity{
    name = prototype.name,
    position = work.position,
    direction = work.direction,
    type = end_of(work),
    force = work.force,
    -- A ghost asks the question a construction robot asks. An upgrade cannot: the thing
    -- being replaced is standing in the space its replacement needs, so every check but
    -- the manual one answers no for that reason alone. Measured on 2.1.17, a fast belt
    -- over a belt marked for upgrade is allowed under manual and refused under each of
    -- ghost_revive, script, script_ghost, manual_ghost and blueprint_ghost.
    build_check_type = upgrading(work) and defines.build_check_type.manual
      or defines.build_check_type.ghost_revive,
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
  -- Nobody stands in a cliff: it is solid, and a character next to one would otherwise
  -- count as inside it, because a cliff is four tiles across and the question is asked of
  -- the footprint rather than the collision box.
  if exploding(ghost) then return false end
  local prototype = outcome_of(ghost) or ghost.prototype
  local across = (prototype and prototype.tile_width or 1) / 2
  local down = (prototype and prototype.tile_height or 1) / 2
  local middle = ghost.position
  return at.x >= middle.x - across and at.x <= middle.x + across
     and at.y >= middle.y - down and at.y <= middle.y + down
end

---Every piece of work near enough to a wearer that some arm of theirs might reach it.
---
---Searched once and handed to every arm, rather than each arm searching for itself. The
---search is the expensive part of a tick and the answer is the same for all of them: only
---the range each arm judges it by differs, and that is a comparison rather than a search.
---Widened by how far out an arm's base can sit, because each arm judges what it found
---from its own base rather than from the middle of what it is bolted to.
---@param wearer LuaEntity the character or vehicle the arms are on
---@param range number the longest reach any of their arms has
---@return LuaEntity[]
local function work_near(wearer, range)
  -- A radius, and the same radius the reach is judged against below. Two things went wrong
  -- with the square this replaces. A square of side twice the range reaches 1.41 times as
  -- far at its corners, and find_entities_filtered returns anything whose own box merely
  -- overlaps the area, so a ghost whose centre was well over four tiles away came back as
  -- a candidate. It was then abandoned as out of range on the very next tick, and found
  -- again the tick after: the arm swung out and back for ever, and because a swing counted
  -- as under way, no ghost that was actually in reach got a turn.
  local radius = range + spread_of(wearer)
  local found = wearer.surface.find_entities_filtered{
    position = wearer.position,
    radius = radius,
    type = "entity-ghost"
  }

  -- An upgrade order is not a ghost and never was. The planner leaves the belt standing
  -- where it stood and hangs an order on it, so a search for ghosts finds nothing at all,
  -- which is the whole of why the arms ignored the upgrade planner. The orders have a
  -- search of their own.
  -- A deconstruction order is not a ghost either, and a tile marked for removal is an
  -- entity of its own -- a deconstructible-tile-proxy standing on the tile -- so the same
  -- search finds both.
  for _, marked in pairs(wearer.surface.find_entities_filtered{
        position = wearer.position,
        radius = radius,
        to_be_deconstructed = true,
      }) do
    if marked.type ~= "entity-ghost" and marked.type ~= "cliff" then
      found[#found + 1] = marked
    end
  end

  for _, cliff in pairs(wearer.surface.find_entities_filtered{
        position = wearer.position,
        radius = radius,
        type = "cliff",
        to_be_deconstructed = true,
      }) do
    found[#found + 1] = cliff
  end
  for _, marked in pairs(wearer.surface.find_entities_filtered{
        position = wearer.position,
        radius = radius,
        to_be_upgraded = true,
      }) do
    -- A ghost can carry an upgrade order too, and is in the list already. Anything with no
    -- unit number is left out rather than reached for: two arms are kept off the same
    -- piece of work by its number, and work that cannot be claimed cannot be shared out.
    if marked.type ~= "entity-ghost" then found[#found + 1] = marked end
  end

  return found
end

---Pick something to build out of what was found near the player.
---
---Asks nothing about power: a claw already out and carrying does not have to bank a fresh
---reserve to turn to the next ghost. Setting off in the first place does, which is
---job_for below.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arms are on
---@param from {x: number, y: number} where this arm reaches from, from reaching_from
---@param nearby LuaEntity[] from work_near
---@param claimed table<integer, boolean>? ghosts another arm is already reaching for
---@param range number how far this arm can reach
---@return LuaEntity? ghost
---@return string? item
---@return integer? count
---@return string? quality what quality of that item it has to be
local function choose(player, wearer, from, nearby, claimed, range)
  local inventory = pockets(player, wearer)
  if not inventory then return nil end
  ---How many of an item the wearer has at a given quality.
  ---
  ---At that quality and no other. A ghost of a legendary belt is raised legendary and an
  ---order to upgrade to one puts a legendary one down, so paying for either with a normal
  ---belt out of the pocket would be minting the difference.
  local function carried_at(quality)
    return function(name)
      return inventory.get_item_count{ name = name, quality = quality }
    end
  end

  -- Nearest first. The order find_entities_filtered hands things back in is the order they
  -- sit in the map's own index, which walks rows and then columns, so a claw clearing a
  -- patch crossed it in bands rather than working outward from itself. Sorting by how far
  -- each is from the arm makes every trip the shortest one available, which matters most to
  -- somebody walking while it works.
  local standing = wearer.position
  table.sort(nearby, function(one, other)
    if not (one.valid and other.valid) then return false end
    return reach.distance(from, one.position) < reach.distance(from, other.position)
  end)
  for _, ghost in pairs(nearby) do
    if still_wanted(ghost) then
      -- 2.0 turned items_to_place_this into a list of { name, count } rather than a table
      -- keyed by item name
      -- Written out rather than folded into an and: a Lua and yields one value, so
      -- `local item, needed = wanted and placing_item(...)` quietly throws the count away
      -- and every ghost is asked for nil of its item.
      local outcome, outcome_quality = outcome_of(ghost)
      local quality = outcome_quality and outcome_quality.name or "normal"
      local item, needed
      if taking(ghost) then
        -- Nothing is carried out to it. The claw goes empty and comes back full.
        item, needed = nil, 0
      elseif exploding(ghost) then
        item, needed = build.placing_item(explosive_for(ghost), carried_at(quality))
      elseif outcome then
        item, needed = build.placing_item(outcome.items_to_place_this, carried_at(quality))
        -- Both ends of a pair go up together, so both are paid for together. Asked for
        -- after the item is chosen, and re-asked of the pockets: a player holding one is
        -- not holding enough for a pair.
        if item and paired_with(ghost) then
          needed = needed * 2
          if carried_at(quality)(item) < needed then item = nil end
        end
      end
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
      if (item or taking(ghost)) and not (claimed and claimed[claim_of(ghost)])
          and not standing_in(ghost, standing)
          and not reach.out_of_range(from, ghost.position, range)
          and buildable(ghost) then
        return ghost, item, needed, quality
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
---@param standing {x: number, y: number} where the wearer is, for what it is standing on
---@param from {x: number, y: number} where the arm reaches from
---@param range number
---@param item string
---@param count integer how many the ghost being reached for takes
---@param carried integer how many the character has
---@param capacity integer how many loads the claw holds
---@return integer
local function loads_for(nearby, claimed, standing, from, range, item, quality, count,
                         carried, capacity)
  if capacity <= 1 then return 1 end
  local wanted = 1
  for _, ghost in pairs(nearby) do
    if wanted >= capacity then break end
    if still_wanted(ghost) and not (claimed and claimed[claim_of(ghost)])
        and not standing_in(ghost, standing)
        and not reach.out_of_range(from, ghost.position, range) then
      local outcome, outcome_quality = outcome_of(ghost)
      local other, needed
      if outcome then
        other, needed =
          build.placing_item(outcome.items_to_place_this, function() return count end)
      end
      if other == item and needed == count
          and (outcome_quality and outcome_quality.name or "normal") == quality then
        wanted = wanted + 1
      end
    end
  end
  return math.max(1, math.min(wanted, math.floor(carried / count)))
end

---Pick something for an arm to set off after, which it may only do on a full buffer.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arms are on
---@param from {x: number, y: number} where this arm reaches from
---@param nearby LuaEntity[] from work_near
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
local function job_for(player, wearer, from, nearby, claimed, record, range)
  if not ready(record) then
    -- Still worth knowing whether there is anything to do. Setting off wants a full
    -- buffer, and a delivery spends some of it, so an arm that has just finished one is
    -- not ready on the very next tick. Filling it again takes a single tick from charged
    -- batteries -- measured at every tier -- but a single tick was enough: with no arm
    -- reporting work the run was declared over, the character started easing back to full
    -- speed, and a fresh slowdown began a tick later, so they oscillated instead of
    -- settling. The run ends when the work runs out, not when an arm is a tick short of
    -- being able to start the next trip.
    local ghost = choose(player, wearer, from, nearby, claimed, range)
    return nil, nil, nil, nil, ghost ~= nil
  end
  local ghost, item, count, quality = choose(player, wearer, from, nearby, claimed, range)
  return ghost, item, count, quality, false
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
---@param wearer LuaEntity the character or vehicle it is mounted on
---@param record table
---@return LuaEntity?
local function arm_of(player, wearer, record)
  local arm = record.entity
  if not (arm and arm.valid) then
    arm = wearer.surface.create_entity{
      name = tier_of(record).inserter,
      position = wearer.position,
      force = player.force,
    }
    -- Filled the moment it exists, out of its own equipment, so that it never spends a
    -- tick on empty. Out of the equipment, not out of nothing: handing it a free bufferful
    -- here while refunding the remainder when it is put away would have made an arm coming
    -- and going a way of generating power.
    if arm and wearer.grid then
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
---@param quality string?
---@param count integer
local function take_back(record, name, quality, count)
  if count <= 0 then return end
  local box, arm = record.catcher, record.entity
  if box and box.valid then
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then inside.remove{ name = name, quality = quality, count = count } end
  end
  if arm and arm.valid then
    local held = arm.held_stack.valid_for_read and arm.held_stack.count or 0
    arm.held_stack.set_stack{ name = name, quality = quality, count = held + count }
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
          take_back(record, stack.name, stack.quality and stack.quality.name or nil, stack.count)
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
      table.insert(left, { name = stack.name, quality = stack.quality, count = stack.count })
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
  local inventory = pockets(player, record.wearer or player.character)

  -- The box goes with the arm, and what it was holding is not the box's. A claw that had
  -- just put a belt in it, or one being handed what it had come to fetch, had that thrown
  -- away with the box: catcher_away says what was left in it and nobody was listening.
  for _, stack in pairs(catcher_away(record) or {}) do
    if inventory then
      inventory.insert{ name = stack.name, quality = stack.quality, count = stack.count }
    end
  end

  if arm and arm.valid then
    -- Whatever it was carrying was paid for out of the pockets, so it goes back in them
    -- rather than being destroyed with the arm. The pockets it was mustered against, for
    -- the same reason the charge goes back to the grid it was mustered against: an arm put
    -- away as its owner climbs out of a vehicle is holding the vehicle's belt, not theirs.
    local job = record.job
    if job and (job.escrow or 0) > 0 and job.item and inventory then
      inventory.insert{ name = job.item, quality = job.quality, count = job.escrow }
      job.escrow = 0
    end
    if arm.held_stack.valid_for_read then
      if inventory then
        inventory.insert(arm.held_stack)
      end
      arm.held_stack.clear()
    end
    -- whatever it was holding in its buffer goes back where it came from, so that taking
    -- the arm out and putting it away again is not itself a way of burning charge
    --
    -- The grid the arm was mustered against, rather than whatever its owner is wearing by
    -- now. Getting into a vehicle changes which grid that is, and the arms of the one just
    -- left are put away on that very tick: refunding into the new grid would take charge
    -- out of the armour and hand it to the car.
    if record.grid and record.grid.valid then
      refund(record.grid, record.piece, arm.energy)
    end
    stow(tier_of(record), arm.surface, arm.position)
    arm.destroy()
  end
  record.entity = nil
  record.job = nil
  record.busy = nil
  record.run = nil
  record.lift = nil
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
---
---An arm belongs to the grid it was mustered against as much as to its tier: the same
---first tier equipment in a car is not the arm that was on its driver's back a tick ago,
---and carrying one over would have the armour's charge feeding the vehicle's arm. So a
---change of grid retires an arm exactly as a change of tier does.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle wearing the equipment
---@return table[]
local function muster(player, wearer)
  local list = arms(player)
  local want = worn(wearer)
  local grid = wearer.grid

  while #list > #want do
    put_away(player, list[#list])
    list[#list] = nil
  end
  for slot = 1, #want do
    local record = list[slot]
    if not record then
      list[slot] = { level = want[slot] }
    elseif record.level ~= want[slot] or record.grid ~= grid then
      put_away(player, record)
      list[slot] = { level = want[slot] }
    end
  end

  -- Each arm is powered by one piece of the equipment that put it there, so they are
  -- paired off: the first arm of a tier to the first piece of that tier, and so on. Which
  -- piece is which does not matter, only that two arms never feed from the same one.
  local taken = {}
  for _, record in ipairs(list) do
    local name = tier_of(record).name
    taken[name] = (taken[name] or 0) + 1
    record.piece = pieces_of(grid, name)[taken[name]]
    -- remembered so that putting the arm away can hand its charge and its load back where
    -- they were drawn from, whoever its owner is wearing by then
    record.grid = grid
    record.wearer = wearer
  end
  return list
end

---Keep the inserter on its wearer and pointed at whatever it is reaching for.
---
---Both ends are set every tick. The pickup end is the wearer, so the hand comes home to
---them rather than to wherever they were standing when the swing began. The drop end has to
---be re-aimed as well, because an inserter's drop position travels with the inserter: move
---the entity and the target moves with it, so a fixed vector would drift off the ghost as
---the character walked -- or, in a vehicle, as they drove.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param job table? what it is reaching for, if anything
---@return LuaEntity? the inserter
local function aim(player, wearer, record, slot, count, job)
  local arm = arm_of(player, wearer, record)
  if not (arm and arm.valid) then return nil end

  -- Fed only while it has something to do. An arm idling on its owner's back still draws
  -- its inserter's standing drain, and feeding that out of the equipment left the buffer a
  -- few joules short of full for as long as the arm was out -- which, since setting off
  -- wants a full buffer, meant waiting the better part of a second between every reach.
  -- Idle, it runs its own buffer down instead, and is filled again when work arrives.
  if job then charge(record, arm) end
  local mount, lift = mounting(wearer, slot, count)
  arm.teleport(mount)
  -- Remembered for as long as the arm is out, because everything aimed at from here is
  -- aimed in the frame the arm was drawn in, and a vehicle that turns moves that frame.
  record.lift = lift

  -- Where the claw rests: a little way out from the mounting point, along the bearing it
  -- is working on, so that coming home is a retraction rather than a swing. With nothing
  -- to work on it rests above the character, which is where a folded arm looks right.
  local towards = job and aimed_at(job, record)
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
      local target = aimed_at(job, record)
      if job.take then
        -- The other way round: the claw reaches for the thing rather than at it, and what
        -- it picks up comes back to where home is measured from.
        arm.pickup_position = { target.x, target.y }
        arm.drop_position = { rest.x, rest.y }
      else
        arm.drop_position = { target.x, target.y }
      end
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
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table
---@return boolean whether the claw is empty now
local function give_back(player, wearer, record)
  local arm = record.entity
  local job = record.job
  local inventory = pockets(player, wearer)

  -- What was set aside for this round but never went into the claw goes back first. It
  -- was taken from the pockets when the arm set off and nothing was built with it, so it
  -- is simply the player's again. There is nothing holding it and nowhere for it to fall,
  -- so it does not need the spill or hold question that the claw's own load does.
  if job and (job.escrow or 0) > 0 and job.item and inventory then
    local returned = inventory.insert{ name = job.item, quality = job.quality, count = job.escrow }
    job.escrow = job.escrow - returned
    if job.escrow > 0 and spills(player) then
      if wearer and wearer.valid then
        wearer.surface.spill_item_stack{
          position = wearer.position,
          stack = { name = job.item, quality = job.quality, count = job.escrow },
          enable_looted = true,
          force = player.force,
        }
      end
      job.escrow = 0
    end
    if job.escrow > 0 then return false end
  end

  if not (arm and arm.valid and arm.held_stack.valid_for_read) then return true end
  -- The stack as it stands rather than its name and number: what the claw is carrying may
  -- be the very thing an upgrade pulled up, which can be damaged and can be any quality.
  local count = arm.held_stack.count
  local took = inventory and inventory.insert(arm.held_stack) or 0
  if took >= count then
    arm.held_stack.clear()
    return true
  end
  if took > 0 then arm.held_stack.count = count - took end
  if spills(player) then
    if wearer and wearer.valid then
      wearer.surface.spill_item_stack{
        position = wearer.position,
        stack = arm.held_stack,
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

---A porter to be handed whatever a swap displaces, with room for all of it.
---
---A character is what create_entity will accept as the receiver, and this one is the mod's
---own rather than the player: see prototypes/porter.lua for why. It is given a slot for the
---thing being replaced and one for every stack that thing is holding, which is as many as
---the engine can possibly need, so it never has to shed or destroy any of it.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param force LuaForce
---@param work LuaEntity the thing about to be replaced
---@return LuaEntity?
local function porter_for(surface, at, force, work)
  local porter = surface.create_entity{
    name = "constructor-equipment-porter", position = at, force = force }
  if not porter then return nil end
  local slots = 1
  for index = 1, work.get_max_inventory_index() do
    local inventory = work.get_inventory(index)
    if inventory then slots = slots + (#inventory - inventory.count_empty_stacks()) end
  end
  porter.character_inventory_slots_bonus = slots
  return porter
end

---Swap a thing marked for upgrade for what it is marked to become, the way a construction
---robot does it.
---
---fast_replace is what makes this an upgrade rather than a demolition and a rebuild: the
---belt's cargo, an assembler's recipe and modules, an inserter's filters and its stack size
---override all carry over, exactly as they do when a player fast replaces by hand.
---
---Nothing is raised. The revive below raises nothing either, and the two paths say the same
---amount about themselves.
---@param porter LuaEntity who is to be handed what the swap displaces
---@param work LuaEntity
---@param quality string?
---@return LuaEntity? placed
local function swap(porter, work, quality)
  local prototype = work.get_upgrade_target()
  if not prototype then return nil end
  return work.surface.create_entity{
    name = prototype.name,
    quality = quality,
    position = work.position,
    direction = work.direction,
    -- Which way round a handed thing is built. Every entity answers this, whether or not
    -- it is the sort of thing that can be mirrored.
    mirror = work.mirroring,
    type = end_of(work),
    force = work.force,
    fast_replace = true,
    spill = false,
    character = porter,
    create_build_effect_smoke = false,
  }
end

---Replace both ends of an underground pair at once, keeping what is in the tunnel.
---
---The items between the two ends sit on the third and fourth transport lines, and replacing
---either end turns them out: the base game drops them on the floor for its network to pick
---up, and this mod would hand them to the porter and shed them. Neither loses anything, and
---both leave the player's belt line short of what was travelling in it.
---
---So they are lifted into an inventory of the mod's own before either end is touched and
---laid back down on the new pair afterwards, at the positions they were at. What was in the
---tunnel is still in the tunnel.
---
---Both ends are emptied rather than the one that holds the cargo, which is the input end:
---measured on 2.1.17, a tunnel loaded through the input kept all of it on that end's third
---and fourth lines, with nothing on the output end's. Reading the wrong one of the two left
---two of six items behind, and reading both cannot be wrong whichever end the arm reached
---for. Blueprint Shotgun picks the input end deliberately, through a variable it calls
---output.
---@param porter LuaEntity
---@param work LuaEntity the end the arm reached for
---@param partner LuaEntity the other end
---@param quality string?
---@return LuaEntity? made
---@return LuaEntity? other
local function swap_pair(porter, work, partner, quality)
  local surface, at, force = work.surface, work.position, work.force

  ---Lift the tunnel's share of one end into an inventory of our own.
  local function lift(from)
    local lines = {}
    for line = 3, 4 do
      local contents = from.get_transport_line(line).get_detailed_contents()
      local held = game.create_inventory(math.max(1, #contents))
      for index = #contents, 1, -1 do
        held[index].transfer_stack(contents[index].stack)
      end
      lines[line - 2] = { contents = contents, held = held }
    end
    return { was = from.belt_to_ground_type, lines = lines }
  end

  local rescued = { lift(work), lift(partner) }

  local made = swap(porter, work, quality)
  local other = made and swap(porter, partner, quality) or nil

  ---Put one end's share back on whichever new end is the same end of the pair.
  local function lay_back(saved)
    local onto = (made and made.belt_to_ground_type == saved.was) and made
      or ((other and other.belt_to_ground_type == saved.was) and other)
    for index, line in ipairs(saved.lines) do
      local insert = onto and onto.get_transport_line(index + 2).force_insert_at
      for slot = 1, #line.held do
        local stack = line.held[slot]
        if stack.valid_for_read then
          -- Half a swap, or a line that will not take it back, and it goes on the floor
          -- rather than into the void, which is where the base game would have left it.
          if not (insert and insert(line.contents[slot].position, stack)) then
            surface.spill_item_stack{ position = at, stack = stack,
              enable_looted = false, force = force, allow_belts = false }
          end
        end
      end
      line.held.destroy()
    end
  end

  for _, saved in ipairs(rescued) do lay_back(saved) end
  return made, other
end

---Put everything an inventory holds on the floor and mark it---Put everything an inventory holds on the floor and mark it, which is what a construction
---robot does with what it cannot carry away.
---
---Marked from the entities spill_item_stack hands straight back rather than by looking
---around afterwards: a pile spreads as the square root of its size, so there is no distance
---to search that is right for every one of them.
---
---The stacks go down as they are rather than by name and number, so a damaged thing stays
---damaged and a quality one stays that quality.
---@param surface LuaSurface
---@param at {x: number, y: number}
---@param force LuaForce
---@param inventory LuaInventory
local function shed(surface, at, force, inventory)
  for index = 1, #inventory do
    local stack = inventory[index]
    if stack.valid_for_read then
      for _, item in pairs(surface.spill_item_stack{
            position = at,
            stack = stack,
            enable_looted = false,
            force = force,
            allow_belts = false,
          } or {}) do
        if item.valid then item.order_deconstruction(force) end
      end
      stack.clear()
    end
  end
end

---Put the thing that came off in the claw, to be carried home the way a robot carries it
---back to the network.
---
---The stack itself rather than its name and number, so that whatever it carries beyond
---those comes home too: a belt pulled up damaged is still damaged, and stays the quality it
---was. Nothing is made here -- the porter was handed the real one.
---
---The claw has to be empty, which it is: a trip that is going to make a swap carries one
---thing out and nothing turns to a swap partway through.
---@param record table the arm
---@param stack LuaItemStack
local function fill_claw(record, stack)
  local arm = record.entity
  if not (arm and arm.valid) then return false end
  if arm.held_stack.valid_for_read and arm.held_stack.count > 0 then return false end
  arm.held_stack.set_stack(stack)
  return true
end

---Put one trip's worth of a thing into the box, for the claw to carry home.
---
---What it is holding goes first, a stack at a time, and the thing itself comes up only once
---it is empty. That is what a robot does: measured on 2.1.17, fifty of them took a full
---steel chest away in hundred plate mouthfuls over a minute, and the chest went last. A claw
---carries one thing at a time, so it works that way by nature rather than by arrangement,
---and mining is only ever asked of something empty -- which matters, because mining into an
---inventory too small to take the whole yield empties what it can and then fails, leaving
---the thing standing and lighter than it was.
---Only ever a clawful. A hand holds what its inserter holds, and anything put in the box
---beyond that is left there when the box goes: a hundred plates went in and one came home.
---Putting in what the claw can carry makes the box a step on the way rather than a place
---something can be left behind in.
---@param box LuaEntity
---@param work LuaEntity
---@param capacity integer how many the claw can hold
---@return boolean whether anything was put in
local function loot_into(box, work, capacity)
  local inside = box.get_inventory(defines.inventory.chest)
  if not inside then return false end

  for index = 1, work.get_max_inventory_index() do
    local held = work.get_inventory(index)
    if held and not held.is_empty() then
      for slot = 1, #held do
        local stack = held[slot]
        if stack.valid_for_read then
          local quality = stack.quality and stack.quality.name or nil
          local moved = inside.insert{ name = stack.name, quality = quality,
            count = math.min(capacity, stack.count) }
          if moved > 0 then
            if moved >= stack.count then stack.clear() else stack.count = stack.count - moved end
            return true
          end
          return false
        end
      end
    end
  end

  local surface, at, force = work.surface, work.position, work.force
  local products = work.prototype.mineable_properties.products
  local size = math.max(1, products and #products or 1)
  local room = game.create_inventory(size)
  local mined = work.mine{ inventory = room, force = false, raise_destroyed = true }
  -- Grown a slot at a time until it fits, the way Blueprint Shotgun does it: what a thing
  -- yields is not always as long as its product list, and a mine that will not fit is a
  -- mine that half happened.
  local tries = 0
  while not mined and tries < 8 do
    size = size + 1
    room.resize(size)
    mined = work.mine{ inventory = room, force = false, raise_destroyed = true }
    tries = tries + 1
  end
  if not mined then room.destroy() return false end

  local took = false
  if room[1].valid_for_read then
    local quality = room[1].quality and room[1].quality.name or nil
    local moved = inside.insert{ name = room[1].name, quality = quality,
      count = math.min(capacity, room[1].count) }
    if moved > 0 then
      took = true
      if moved >= room[1].count then room[1].clear()
      else room[1].count = room[1].count - moved end
    end
  end
  -- More than a claw can carry goes on the floor marked, where a robot leaves what it
  -- cannot take, rather than waiting on a trip that would have nowhere to put it.
  shed(surface, at, force, room)
  room.destroy()
  return took
end

---Take something up: wait for the claw to arrive, give it a load, and send it home.
---
---The mirror of a delivery, and it leans on the same box. An inserter with a container at
---its pickup position reaches out to it and waits there with an open hand -- measured, the
---hand sits at full stretch reporting no source items until something appears, and takes it
---the moment it does. So arrival is not a distance this has to measure either: it is the
---box being near enough to exist, and the claw filling itself is the engine's own report
---that it got there.
---@param player LuaPlayer
---@param wearer LuaEntity
---@param record table
---@param job table
local function take_up(player, wearer, record, job)
  local arm = record.entity
  if not (arm and arm.valid) then return end

  if arm.held_stack.valid_for_read and arm.held_stack.count > 0 then
    job.going = "back"
    job.ghost = nil
    -- Belt and braces: the box should be empty, since only a clawful ever goes in it, and
    -- anything still there would go with it.
    local box = record.catcher
    if box and box.valid then
      local inside = box.get_inventory(defines.inventory.chest)
      if inside and not inside.is_empty() then
        shed(arm.surface, box.position, arm.force, inside)
      end
    end
    catcher_away(record)
    if record.rest then arm.drop_position = { record.rest.x, record.rest.y } end
    return
  end

  -- Arrival is the inserter's own word for it. An arm reaching for a source with nothing in
  -- it stretches out and reports that it is waiting for source items, and it says so only
  -- once it is there: measured, the hand sat at full stretch in that state until something
  -- appeared and took it the tick after.
  --
  -- The box's own existence will not do, the way it does for a delivery. It is made as soon
  -- as the claw is near enough that it might arrive between one tick and the next, and that
  -- window is widened by how far the hand moved, which on the first tick of a swing is the
  -- whole re-aiming. A delivery does not mind -- the engine fills the box when it gets
  -- there -- but a fetch fills the box itself, and an early box means a thing mined while
  -- the claw is still two tiles off.
  if arm.status ~= defines.entity_status.waiting_for_source_items then return end

  local box = record.catcher
  if not (box and box.valid) then return end
  local inside = box.get_inventory(defines.inventory.chest)
  if inside and not inside.is_empty() then return end

  loot_into(box, job.ghost, trips_for(player.force, tier_of(record)))
end

---Put the thing down: raise the ghost or make the swap, pay for it, and let the arm start
---coming home.
---@param player LuaPlayer
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param from {x: number, y: number} where this arm reaches from
---@param record table the arm making the delivery
---@param job table
---@param claimed table<integer, boolean>? what the other arms are reaching for
local function deliver(player, wearer, from, record, job, claimed)
  local ghost = job.ghost
  local box = record.catcher

  -- What the box was given is the delivery. Until something is in it, nothing has
  -- arrived, and that is the whole of the arrival test: no distance, nothing to step over.
  local landed = 0
  if box and box.valid then
    landed = box.get_item_count{ name = job.item, quality = job.quality }
  end
  if landed < 1 then return end

  -- A ghost can want more than a claw can hold: a plain inserter carries one item and a
  -- half diagonal rail takes two. The rest was taken from the pockets when the arm set off
  -- and has been travelling with the job rather than in the claw, so it is here to be
  -- spent and nothing needs asking of the pockets now.
  local short = job.count - landed
  if short > (job.escrow or 0) then
    -- the round is short of what this ghost wants, which should not happen: everything was
    -- reserved at the start. Give back what there is rather than build half a thing.
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  if not still_wanted(ghost) then
    -- the ghost went, or the upgrade was called off, while the claw was on its way; the
    -- load goes back in the claw and comes home, since it has already been paid for
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  if exploding(ghost) then
    local surface, at, force = ghost.surface, ghost.position, ghost.force
    local thrown = projectile_of(job.item)

    -- The charge is spent whatever happens next: it came out of the pockets when the arm
    -- set off and it has just been handed over.
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
    if short > 0 then job.escrow = job.escrow - short end

    job.going = "back"
    job.ghost = nil
    catcher_away(record)

    if thrown then
      -- Thrown rather than the cliff simply being taken away, so the blast takes the
      -- neighbours in its radius with it the way a robot's charge does.
      surface.create_entity{ name = thrown, position = at, target = at, speed = 1,
        force = force }
    else
      -- An explosive with no projectile to throw is not something the base game has. Take
      -- the cliff down by hand rather than charging for nothing.
      ghost.destroy{ do_cliff_correction = true, raise_destroy = true }
    end
    return
  end

  if upgrading(ghost) then
    -- Everything worth knowing about what comes off is read here rather than afterwards,
    -- because afterwards there is nothing left standing to ask.
    local surface, at, force = ghost.surface, ghost.position, ghost.force
    local product = sole_product(ghost)
    local quality = ghost.quality and ghost.quality.name or "normal"

    -- Somebody has to be named to catch what the swap displaces -- name nobody and the
    -- engine destroys it -- and it is not the player: a porter is made for the job, handed
    -- the lot, emptied and destroyed, all before the tick is out. Naming the player would
    -- not lose anything either, but it would scatter it between their pockets, the floor
    -- and the new belt's own lane, and leave the mod taking it back out again.
    local porter = porter_for(surface, at, force, ghost)
    if not porter then
      take_back(record, job.item, job.quality, landed)
      abandon(record, job)
      return
    end

    local partner = paired_with(ghost)
    local made
    if partner then
      made = swap_pair(porter, ghost, partner, quality)
    else
      made = swap(porter, ghost, quality)
    end
    local carried = porter.get_main_inventory()

    if not made then
      if carried then shed(surface, at, force, carried) end
      porter.destroy()
      take_back(record, job.item, job.quality, landed)
      abandon(record, job)
      return
    end

    -- The swap is made, so what paid for it is spent. It came out of the pockets when the
    -- arm set off, so nothing is charged here: this is where it stops existing.
    local inside = box.get_inventory(defines.inventory.chest)
    if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
    if short > 0 then job.escrow = job.escrow - short end

    -- The box goes and the claw is turned for home before anything is put in its hand, in
    -- that order. An inserter standing over a container with something in its hand puts it
    -- in the container, and the box is about to be taken away with it: the belt that came
    -- off went into the box and out of the world, once, before this was written down.
    job.going = "back"
    job.ghost = nil
    catcher_away(record)
    local returning = record.entity
    if returning and returning.valid and record.rest then
      returning.drop_position = { record.rest.x, record.rest.y }
    end

    -- The thing itself rides home in the claw. Everything the replacement could not hold
    -- goes on the floor, marked, where a robot would have shed it.
    if carried then
      if product then
        local stack = carried.find_item_stack{ name = product, quality = quality }
        if stack and fill_claw(record, stack) then stack.clear() end
      end
      shed(surface, at, force, carried)
    end
    porter.destroy()
    return
  end

  local _, built = ghost.revive()
  if not built then
    take_back(record, job.item, job.quality, landed)
    abandon(record, job)
    return
  end

  -- The ghost is up, so the items that built it are spent. They came out of the pockets
  -- when the claw was loaded, so nothing is charged here: this is simply where they stop
  -- existing.
  local inside = box.get_inventory(defines.inventory.chest)
  if inside then
      inside.remove{ name = job.item, quality = job.quality,
        count = math.min(landed, job.count) }
    end
  if short > 0 then job.escrow = job.escrow - short end
  -- whatever else the claw brought is still the player's, and goes back in the claw for
  -- the next ghost of this round
  take_back(record, job.item, job.quality, math.max(0, landed - job.count))

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
      and redirect(player, wearer, from, record, job, claimed, tier_of(record).range) then
    local target = aimed_at(job, record)
    arm.drop_position = { target.x, target.y }
    -- shut to begin with: the claw is still at the ghost it has just built, and advance
    -- opens the box once it is near the new one
    catcher_at(record, arm.surface, target, false)
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
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param from {x: number, y: number} where this arm reaches from
---@param job table
---@param claimed table<integer, boolean>? ghosts the other arms are reaching for
---@param range number how far this arm reaches
---@return boolean whether it found somewhere else to go
function redirect(player, wearer, from, record, job, claimed, range)
  local ghost, item, count, quality =
    choose(player, wearer, from, work_near(wearer, range), claimed, range)
  if not ghost then return false end
  if item ~= job.item then return false end
  -- The claw is already carrying this item at the quality it set off with, and a ghost
  -- wanting another quality of the same thing is a different errand.
  if quality ~= job.quality then return false end
  -- Never onto a swap or a cliff. What comes off a swap is carried home in the claw, and a
  -- claw part way through a round is still holding the round; a charge is a round of its own.
  if upgrading(ghost) or exploding(ghost) or taking(ghost) then return false end

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
      local inventory = pockets(player, wearer)
      if inventory then
        local returned = inventory.insert{ name = job.item, quality = job.quality, count = job.escrow }
        job.escrow = job.escrow - returned
      end
      -- anything that would not fit stays put by and goes home with the arm
    end
    job.count = count
    job.left = math.floor(held / count)
    if job.left < 1 then return false end
  end

  if claimed then claimed[claim_of(ghost)] = true end
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
      claimed[claim_of(job.ghost)] = true
      local partner = paired_with(job.ghost)
      if partner then claimed[claim_of(partner)] = true end
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
---@param wearer LuaEntity the character or vehicle the arm is mounted on
---@param record table the arm
---@param slot integer which arm it is
---@param count integer how many arms there are
---@param claimed table<integer, boolean> what the other arms are reaching for
local function advance(player, wearer, record, slot, count, claimed)
  local job = record.job

  if not (wearer and wearer.valid) then
    record.job = nil
    return
  end

  -- Where this arm's own base is, which is what its reach is measured from. Asked again
  -- every tick rather than remembered: the vehicle it is bolted to turns, and an arm on the
  -- back of one that has turned round is somewhere else entirely.
  local from = reaching_from(wearer, slot, count)

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
      aim(player, wearer, record, slot, count, nil)
    else
      put_away(player, record)
    end
    return
  end

  local arm = aim(player, wearer, record, slot, count, job)
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
    local target = aimed_at(job, record)
    -- A fetch wants its box from the first tick, not once the claw is near. An inserter
    -- reaches for a source because there is a container at its pickup position: with no box
    -- there, nothing tells the claw to go, so it never gets near, so the box is never made
    -- and the arm stands out of its owner's back doing nothing at all. A delivery is the
    -- other way round and the box is held back until the claw is close, so that no other
    -- inserter of the player's can fill it first.
    catcher_at(record, arm.surface, target, job.take
      or reach.distance(hand, target) <= within(tier_of(record), OPEN, moved))

    -- the character can walk off mid swing, or the vehicle drive off, and an arm that
    -- stretched to follow would be no kind of inserter
    if not still_wanted(job.ghost)
        or standing_in(job.ghost, wearer.position)
        or reach.out_of_range(from, job.ghost.position, tier_of(record).range)
        or game.tick - (job.started or game.tick) > SWING_LIMIT then
      local tier = tier_of(record)
      if not redirect(player, wearer, from, record, job, claimed, tier.range) then
        abandon(record, job)
      end
    elseif job.take then
      take_up(player, wearer, record, job)
    else
      -- deliver() does nothing until the box has been given something, so there is no
      -- arrival to measure and nothing to step over: it can simply be asked every tick
      deliver(player, wearer, from, record, job, claimed)
    end
  elseif reach.distance(arm.held_stack_position, record.rest or mounting(wearer, slot, count))
        < within(tier_of(record), HOME, moved)
      or game.tick - (job.started or game.tick) > SWING_LIMIT then
    -- Home is the mounting point, which is not where the character's feet are. Anything
    -- still in the claw was paid for on the way out, so it is handed back rather than
    -- destroyed. If it will not fit and the player would rather not have it on the ground,
    -- the arm holds station with it until there is room.
    if give_back(player, wearer, record) then
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
---@param wearer LuaEntity the character or vehicle the arms are on
---@param list table[]
---@param tick integer
---@return boolean whether any arm has anything to do
local function assign(player, wearer, list, tick)
  local claimed = claims(list)
  local nearby = work_near(wearer, furthest(list))
  local working = false
  for slot, record in ipairs(list) do
    if record.job then
      working = true
    else
      local tier = tier_of(record)
      local from = reaching_from(wearer, slot, #list)
      local ghost, item, count, quality, waiting =
        job_for(player, wearer, from, nearby, claimed, record, tier.range)
      if waiting then
        -- work in reach, buffer a tick short of full: the run is still on
        working = true
        record.run = game.tick
      end
      if ghost then
        claimed[claim_of(ghost)] = true
        -- The far end of a pair goes up with this one, so it is spoken for too.
        local partner = paired_with(ghost)
        if partner then claimed[claim_of(partner)] = true end
        record.job = {
          ghost = ghost,
          target = ghost.position,
          item = item,
          -- What quality of it, since a ghost of a legendary belt takes a legendary belt
          -- and an order to upgrade to one takes a legendary one. Everything that moves
          -- this item afterwards moves it at this quality.
          quality = quality,
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
        local inventory = pockets(player, wearer)
        -- A trip that is going to make a swap carries one thing and no more. The claw
        -- comes home with what came off, and a claw already holding the rest of a round
        -- has nowhere to put it.
        if taking(ghost) then
          -- Nothing is carried out and one thing comes back, so there is nothing to queue.
          record.job.left = 1
          record.job.take = true
        elseif upgrading(ghost) or exploding(ghost) then
          -- A trip that is going to make a swap carries one thing; so does one carrying a
          -- charge, because the blast may take the next cliff on the list with it.
          record.job.left = 1
        else
          record.job.left = loads_for(nearby, claimed, wearer.position, from, tier.range,
            item, quality, count,
            inventory and inventory.get_item_count{ name = item, quality = quality } or count,
            trips_for(player.force, tier))
        end
        local arm = aim(player, wearer, record, slot, #list, record.job)
        if arm and record.job.take then
          -- Nothing leaves the pockets for a fetch. The claw sets off empty.
          record.job.carried = 0
          record.job.escrow = 0
        elseif arm then
          -- Everything the round will need comes out of the pockets now, whether or not
          -- the claw can hold it. A claw holds what its inserter holds -- one thing for a
          -- plain one -- and a curved rail wants three, so the claw takes as many as fit
          -- and the rest are set aside against this job. A construction robot carries all
          -- three at once regardless of its cargo size, so this is the same bargain by
          -- other means: the items are spent when the arm sets off and given back if it
          -- comes home without building anything.
          local want = count * record.job.left
          local taken =
            inventory and inventory.remove{ name = item, quality = quality, count = want } or 0
          if taken < count then
            -- not even one ghost's worth left in the pockets
            if taken > 0 then
              inventory.insert{ name = item, quality = quality, count = taken }
            end
            arm.held_stack.clear()
            record.job = nil
          else
            record.job.left = math.floor(taken / count)
            arm.held_stack.set_stack{ name = item, quality = quality, count = taken }
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
    local wearer = wearer_of(player)
    -- Greyed out when there is no arm to switch off, the way the exoskeleton's button is.
    -- Asked here rather than on an event because the answer changes for half a dozen
    -- reasons -- a piece put in, one taken out, an armour swapped, a vehicle climbed into
    -- or out of -- and only one of those has an event worth hanging it on.
    if prototypes.shortcut[TOGGLE] then
      local available = #worn(wearer) > 0
      if storage.constructor_button[player.index] ~= available then
        storage.constructor_button[player.index] = available
        player.set_shortcut_available(TOGGLE, available)
      end
    end
    if wearer and wearer.valid and wearing(wearer) and not switched_off(player) then
      local list = muster(player, wearer)
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
        advance(player, wearer, record, slot, #list, claimed)
        if record.run then
          running = true
          local set = tier_of(record).stickers
          if set and (not worst or set.modifier < worst.modifier) then worst = set end
        end
      end
      if worst then
        slow(player, wearer, worst)
      elseif running then
        -- arms are in a run and none of them asks for any penalty, so give the speed back
        -- rather than waiting for the work to run out
        recover(player, wearer)
      end
      -- An arm in no run at all is deliberately left alone here rather than recovered.
      -- Whether there is anything left to build is asked on the check tick, where it can
      -- be answered properly, and that is what ends a run.
    else
      -- taken off, switched off, the character is gone, or they are riding in a vehicle as
      -- a passenger: no arms and no half finished swings
      dismiss(player)
    end
  end

  if event.tick % CHECK_INTERVAL ~= CHECK_TICK then return end

  for _, player in pairs(game.players) do
    local wearer = wearer_of(player)
    if wearer and wearer.valid and not switched_off(player) then
      -- Nothing left in reach is when the character starts getting their speed back, not
      -- merely no arm swinging this instant: the search runs ten times a second and a claw
      -- can be home for a few ticks before the next one, and recovering in those gaps had
      -- the character surging between one ghost and the next all the way along a
      -- blueprint. So this asks whether there is anything to build.
      local list = storage.constructor_arms[player.index] or {}
      -- No arm working after that means no arm could find anything, because an arm with
      -- nothing to do takes work the instant there is any: without a clock there is no
      -- such thing as free but not yet due. So this needs no second search of its own.
      if not assign(player, wearer, list, event.tick) then
        -- the run is over, which is what lets the slowdown ramp off
        for _, record in pairs(list) do record.run = nil end
        recover(player, wearer)
      end
    end
  end
end

---Getting into or out of a vehicle changes which grid the arms come out of.
---
---The next tick would notice on its own, because an arm is retired when the grid it was
---mustered against is no longer the one being worn. This is here so that the handover
---happens on the tick it is asked for rather than the one after: a claw halfway out when
---its owner climbs into a car would otherwise spend a tick reaching from the car with the
---armour's charge behind it.
---
---The slowdown is handed back on both sides, because either of them can be carrying one. A
---driver who gets out while the arms are working leaves the vehicle slowed for as long as
---the sticker lasts, and a character who climbs in mid run would be walking slowly when
---they got out again.
---@param event EventData.on_player_driving_changed_state
local function on_driving_changed(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  dismiss(player)
  recover(player, event.entity)
  recover(player, player.character)
end

---Switch a player's arms on or off, and put the button in the matching state.
---
---Switching off is not merely a refusal to start anything new. A claw halfway out is
---brought home the same way taking the equipment off brings it home -- items back in the
---pockets, charge back in the grid -- and whatever speed the arms were costing is handed
---back on the spot rather than left to expire.
---@param player LuaPlayer
---@param on boolean
local function switch(player, on)
  storage.constructor_off[player.index] = (not on) or nil
  if prototypes.shortcut[TOGGLE] then player.set_shortcut_toggled(TOGGLE, on) end
  if on then return end
  dismiss(player)
  -- both, because the arms may be on either and a character who climbs out of a vehicle
  -- should not find their own legs still slowed
  recover(player, wearer_of(player))
  recover(player, player.character)
end

---Put the button where the save says it should be, and grey it out when there is nothing
---for it to switch off.
---
---The exoskeleton's button does the same: a toggle nobody can act on reads as a thing that
---is broken rather than a thing that is not there. Available means an arm is worn, which is
---a question about the grid in front of the player rather than about the technology, since
---the technology only decides whether the button exists at all.
---@param player LuaPlayer
local function show(player)
  if not prototypes.shortcut[TOGGLE] then return end
  player.set_shortcut_toggled(TOGGLE, not switched_off(player))
  local available = #worn(wearer_of(player)) > 0
  storage.constructor_button[player.index] = available
  player.set_shortcut_available(TOGGLE, available)
end

---Press the button: whatever the arms are doing now, do the other thing.
---
---Global, and for one reason: on_lua_shortcut is one of the events the engine will not let
---a script raise, so a test cannot press the button by pretending to be the toolbar. It can
---call this, which is what the toolbar reaches in the end.
---@param player LuaPlayer
function press(player)
  switch(player, switched_off(player))
end

---@param event EventData.on_lua_shortcut
local function on_shortcut(event)
  if event.prototype_name ~= TOGGLE then return end
  local player = game.get_player(event.player_index)
  if player then press(player) end
end

---@param event EventData.CustomInputEvent
local function on_toggle_key(event)
  local player = game.get_player(event.player_index)
  if player then press(player) end
end

---@param event EventData.on_player_created
local function on_player_created(event)
  local player = game.get_player(event.player_index)
  if player then show(player) end
end

--- Everything setup() does, and then the button, which needs a game to exist and so cannot
--- be done from on_init.
local function configured()
  setup()
  for _, player in pairs(game.players) do show(player) end
end

script.on_init(setup)
script.on_configuration_changed(configured)
script.on_event(defines.events.on_tick, on_tick)
script.on_event(defines.events.on_player_driving_changed_state, on_driving_changed)
script.on_event(defines.events.on_lua_shortcut, on_shortcut)
script.on_event(defines.events.on_player_created, on_player_created)
script.on_event(TOGGLE, on_toggle_key)

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
    "test.ft.vehicles",
    "test.ft.toggle",
    "test.ft.upgrading",
    "test.ft.cliffs",
    "test.ft.taking",
  }, {
    load_luassert = true,
    game_speed = 100,
  })
end
