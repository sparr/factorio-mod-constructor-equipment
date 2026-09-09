--- What the tiers look like, kept in one place so a tier is told apart the same way
--- everywhere: by the colour of the inserter whose arm it borrows.
local art = {}

--- The claw, one per tier, cut from the base game's own hand sprite for the inserter that
--- tier borrows. Already the right colour, and high enough resolution for a technology
--- icon, which wants 256 where an item wants 64.
---
--- Not the mod's own long_arm art. That comes in two files, and the 64 pixel one turns out
--- to be four copies of the 32 pixel one in a two by two grid -- an authoring slip from
--- 0.15 that nothing noticed until it was used for a technology, which drew four claws.
local CLAW = "__constructor-equipment__/graphics/claw_"

--- One slot of an equipment grid, in pixels, for working out how big a sprite has to be
--- drawn to fill the shape.
local SLOT = 32

---The icon for a tier: its own claw, in its own colour.
---@param tier table
---@param size integer 32 or 64, whichever the icon is for
---@return table[]
function art.icons(tier, size)
  return {
    {
      icon = ("%s%s_%d.png"):format(CLAW, tier.colour, size),
      icon_size = size,
    },
  }
end

---The picture of a tier in an equipment grid: its own claw, scaled to fill the shape it
---takes up without stretching it out of proportion.
---@param tier table
---@return table
function art.equipment_sprite(tier)
  local width, height = tier.sizes.closed[1], tier.sizes.closed[2]
  local fit = math.min(tier.width * SLOT / width, tier.height * SLOT / height)
  return {
    filename = "__base__/graphics/entity/" .. tier.hand .. "/"
      .. tier.hand .. "-hand-closed.png",
    width = width,
    height = height,
    priority = "medium",
    scale = fit,
  }
end

---One of the hand pictures of the inserter a tier borrows.
---@param tier table
---@param part "base"|"closed"|"open"
---@param shadow boolean?
---@return table
function art.hand(tier, part, shadow)
  local size = tier.sizes[part]
  return {
    filename = "__base__/graphics/entity/" .. tier.hand .. "/"
      .. tier.hand .. "-hand-" .. part .. ".png",
    priority = "extra-high",
    width = size[1],
    height = size[2],
    scale = require("lib.tiers").SCALE,
    draw_as_shadow = shadow or nil,
  }
end

return art
