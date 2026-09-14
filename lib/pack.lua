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

--- Where an arm sits on a vehicle, which is a different question from where one sits on a
--- character. A character is a person with a back, and every arm they wear goes on it. A
--- vehicle is a hull with edges, and an arm bolted to the middle of one is an arm nobody
--- can see: the hull is drawn over it, and what a player sees of the mod is a claw coming
--- out of thin air. So the arms go on the hull's edge.
---
--- On its sides, and only on its sides. The front edge is the ground the vehicle is about
--- to drive over and the back edge the ground it has just left, so an arm on either spends
--- its reach on the one strip of ground that is no use: what a vehicle drives past is what
--- lies along its flanks. Arms on the sides also keep out of each other's way, because two
--- rows facing opposite directions never cross.
---
--- So the arms are shared between the two sides and spread along each of them, evenly from
--- the back corner to the front corner. The odd one goes to the right, which is where a lone
--- arm sits, and each further arm goes to whichever side has fewer: one is on the right, two
--- are one a side, three are the right hand corners and the middle of the left, four are the
--- four corners, and it carries on filling the sides in from there.
---
--- One arm on a side sits in the middle of it rather than at a corner, because a side with
--- one arm has no corner to prefer.

---How the arms are shared between the two sides.
---@param count integer
---@return integer right
---@return integer left
local function shared(count)
  return math.ceil(count / 2), math.floor(count / 2)
end

---Where one of a row of arms sits along a side.
---@param nth integer which of that side's arms, from 1 at the back
---@param of integer how many are on that side
---@return number -1 at the back corner, 1 at the front corner, 0 in the middle
local function along_side(nth, of)
  if of <= 1 then return 0 end
  return -1 + 2 * (nth - 1) / (of - 1)
end

---Where one arm sits on a hull, in the hull's own coordinates.
---
---Odd slots go to the right and even ones to the left, so the arms are handed out side by
---side and the first of them is the one a lone arm would be.
---@param slot integer? which arm, from 1
---@param count integer? how many arms there are altogether
---@param across number half the hull's width, in tiles
---@param along number half the hull's length, in tiles
---@return {x: number, y: number} x across to its right, y towards its front
function pack.hull(slot, count, across, along)
  count = math.max(count or 1, 1)
  slot = math.min(math.max(slot or 1, 1), count)
  local right, left = shared(count)
  local side = slot % 2 == 1 and 1 or -1
  local nth = math.ceil(slot / 2)
  return {
    x = side * across,
    y = along_side(nth, side == 1 and right or left) * along,
  }
end

---How much of a lift an arm at this offset takes, from nothing to all of it.
---
---The camera looks at the world from the south, so the side of a hull facing the camera is
---drawn above the ground it stands on: its sprite rises from the ground line to the top of
---the treads and on up the body. An arm bolted out there and left at the ground line hangs
---below the vehicle, which is the whole of this.
---
---Only the near side. An arm on the far side is drawn behind the body, where it is hidden
---and wants to stay hidden: lifting that one would poke it out over the roof. So this is how
---far south the arm sits from the middle of its hull, as a fraction, and an arm on the north
---half of one takes none of it.
---
---A fraction rather than a switch, so a vehicle part way round a turn is part way between
---the two. It is the sine of the turn for an arm out on a side, which is what it looks like
---from outside: nothing when the vehicle faces the camera, all of it when it faces across.
---@param offset {x: number, y: number} where the arm sits, from pack.mount
---@return number 0 to 1
function pack.nearness(offset)
  local out = math.sqrt(offset.x * offset.x + offset.y * offset.y)
  if out <= 0 then return 0 end
  return math.max(0, offset.y / out)
end

---Where to put the inserter, relative to the vehicle it is bolted to.
---
---Both axes turn with the vehicle, which is the difference from a character: an arm on
---somebody's back is drawn at their shoulders however they are facing, where an arm on a
---hull stays on the same plate of it as the hull turns.
---@param direction number 0 to 16, north being 0, and fractional for a vehicle
---@param slot integer? which arm this is, from 1
---@param count integer? how many arms there are altogether
---@param across number half the hull's width, in tiles
---@param along number half the hull's length, in tiles
---@return {x: number, y: number}
function pack.mount(direction, slot, count, across, along)
  local fx, fy = pack.facing(direction or 0)
  local station = pack.hull(slot, count, across, along)
  -- forward is the way it faces, and its right is a quarter turn clockwise from that
  return {
    x = -fy * station.x + fx * station.y,
    y = fx * station.x + fy * station.y,
  }
end

return pack
