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

--- How far above the character the arm is mounted.
pack.HEIGHT = -0.7

--- How far behind them, along whichever way they are facing.
pack.BACK = 0.18

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

---Where to put the inserter, relative to the character it belongs to.
---
---Up at shoulder height, and back along the way they are facing, so it stays on the far
---side of them from wherever they are looking.
---@param direction integer 0 to 15, north being 0
---@return {x: number, y: number}
function pack.offset(direction)
  local fx, fy = pack.facing(direction or 0)
  return { x = -fx * pack.BACK, y = pack.HEIGHT - fy * pack.BACK }
end

return pack
