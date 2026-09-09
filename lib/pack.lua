--- Which side of the character the arm hangs off.
---
--- The camera looks from the south, so a character walking north has their back to it and
--- the arm should be in view, and one walking south should have it hidden behind their
--- body. With the arm drawn by hand that was a choice of render layer. It is an entity
--- now, and entities are drawn in order of how far south they are, so the same decision
--- is a nudge of a tenth of a tile one way or the other.
local pack = {}

--- 2.0 counts sixteen directions, north being nought and rising clockwise.
pack.DIRECTIONS = 16

--- How far north or south of the character to put the inserter. Enough to settle which of
--- the two is drawn first, and not enough to see.
pack.NUDGE = 0.1

---Whether the arm is between the camera and the character.
---
---True for a character facing anywhere in the northern half of the compass, which is when
---the camera is looking at their back.
---@param direction integer 0 to 15, north being 0
---@return boolean
function pack.visible_from_camera(direction)
  return direction < 4 or direction > 12
end

---Where to put the inserter, relative to the character it belongs to.
---
---South of them to be drawn after them and so in front, north of them to be drawn first
---and so behind.
---@param direction integer 0 to 15, north being 0
---@return {x: number, y: number}
function pack.offset(direction)
  local nudge = pack.visible_from_camera(direction) and pack.NUDGE or -pack.NUDGE
  return { x = 0, y = nudge }
end

return pack
