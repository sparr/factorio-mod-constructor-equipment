--- Where on the character the inserter sits.
---
--- The character sprite stands about 1.8 tiles tall with their feet a little below their
--- own position, so two thirds of the way up them is about seven tenths of a tile above
--- it, which is roughly where a backpack would be.
---
--- It also sits on whichever side of them is their back, which is a question of facing
--- rather than a fixed spot: an arm coming out of the middle of someone reads as coming
--- out of their chest when they are walking towards you. None of that needs a game, so it
--- is all here where it can be checked against numbers.
---
--- The whole entity goes up there rather than just its pictures. Shifting the pictures
--- moves the arm without moving the arm's geometry: the engine works out where the hand is
--- from the entity's position, so the drawn arm stops matching the hand it is supposed to
--- end at, and the item being carried comes away from the claw.
local pack = {}

--- 2.0 counts sixteen directions, north being nought and rising clockwise.
pack.DIRECTIONS = 16

--- How far above the character the middle of their back is, and so where a lone arm is
--- mounted and where the circle of several of them is centred.
pack.HEIGHT = -0.7

--- How far behind them, along whichever way they are facing.
pack.BACK = 0.18

--- How far out from the middle of the back the arm bases sit when there is more than one
--- of them. Wide enough that two read as two arms rather than one thick one, and small
--- enough that the whole circle stays on the character's back.
pack.RADIUS = 0.25

---Which way a facing points, as a vector on the map. North is nought, and the y axis grows
---southwards, so north is negative y.
---@param direction integer 0 to 15, north being 0
---@return number x
---@return number y
function pack.facing(direction)
  local turns = (direction % pack.DIRECTIONS) / pack.DIRECTIONS
  local angle = turns * 2 * math.pi
  return math.sin(angle), -math.cos(angle)
end

---Where on the back an arm sits, in body coordinates: how far across the shoulders and
---how far down the back, in tiles, before any of it is turned to face anywhere.
---
---One arm sits in the middle of the back, where a lone arm has always sat. Everything
---beyond that goes round a circle centred on the same spot, evenly spaced, and turned half
---a step so that no arm sits at the very top of it and the arrangement is a mirror image
---of itself left to right. Three make a triangle of two shoulders and a lower back, four a
---square of shoulders and elbows, and it carries on round the circle from there.
---
---Two is the exception. Evenly spaced they would sit either side of the middle at the
---widest part of the circle, which reads as a pair of hips rather than a pair of
---shoulders, so they take the top two places of the arrangement of four instead.
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are altogether
---@return number across positive to the character's right
---@return number down positive towards their feet
function pack.station(slot, count)
  count = math.max(count or 1, 1)
  slot = math.max(slot or 1, 1)
  if count == 1 then return 0, 0 end

  local places, place = count, slot - 1
  if count == 2 then
    -- the top two of the four, rather than the widest two of the two
    places, place = 4, slot == 1 and 3 or 0
  end
  -- half a step round, so the top of the circle falls between two arms rather than on one
  local angle = (place + 0.5) * 2 * math.pi / places
  return pack.RADIUS * math.sin(angle), -pack.RADIUS * math.cos(angle)
end

---Where to put the inserter, relative to the character it belongs to.
---
---Up at the middle of the back, and back along the way they are facing, so it stays on the
---far side of them from wherever they are looking.
---
---Two axes, and only one of them turns with the character. Across the shoulders is a
---quarter turn from the way they are looking and so rotates with the facing; down the back
---is how far down the body an arm is strapped, which is the same however they are stood.
---@param direction integer 0 to 15, north being 0
---@param slot integer? which arm this is, from 1
---@param count integer? how many arms there are altogether
---@return {x: number, y: number}
function pack.offset(direction, slot, count)
  local fx, fy = pack.facing(direction or 0)
  local across, down = pack.station(slot, count)
  return {
    x = -fx * pack.BACK - fy * across,
    y = pack.HEIGHT - fy * pack.BACK + fx * across + down,
  }
end

return pack
