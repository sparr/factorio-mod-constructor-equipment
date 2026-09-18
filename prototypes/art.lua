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
---@return table
function art.hand(tier, part)
  local size = tier.sizes[part]
  return {
    filename = "__base__/graphics/entity/" .. tier.hand .. "/"
      .. tier.hand .. "-hand-" .. part .. ".png",
    priority = "extra-high",
    width = size[1],
    height = size[2],
    scale = require("lib.tiers").SCALE,
  }
end

---The shadow that goes with one of those hand pictures, taken from the inserter the tier
---borrows rather than written out here.
---
---The base game draws a hand's shadow from its own file, and which file that is does not
---follow from the hand's name: every tier of inserter but the bulk one shares the burner
---inserter's hand shadows, and the bulk one shares only its base. Pointing these at the
---colour art with draw_as_shadow set was wrong twice over -- it drew the silhouette of the
---wrong shape, and it left this mod claiming a shadow lived in a file that holds a hand.
---A mod that reskins inserter shadows by swapping the mod name in those filenames then
---looked for a hand where its own shadows are kept, found nothing, and took the load down
---with it. That is Enhanced Shadows, and a player brought it to this mod's discussion page:
---nothing has been said to its author, who has the harder half of the problem, since a
---missing sprite is a load failure rather than a blank graphic and the error names whoever
---declared the path.
---
---Copying the prototype keeps the two ends together: whatever file the source inserter
---says its shadow is in is the file this asks for, at this mod's own scale.
---
---draw_as_shadow has to be said out loud even though the field is called a shadow and the
---base game leaves it off. Without it the picture is drawn in the ordinary pass, over the
---arm rather than under it, and the soft edge each of these files is drawn with paints a
---pale rim around every part of the hand and over the shadow beside it. With it, the two
---shadows go into the shadow pass and lie flat, which is what a hand's shadow looks like
---everywhere else in the factory.
---@param tier table
---@param part "base"|"closed"|"open"
---@return table?
function art.hand_shadow(tier, part)
  local source = data.raw.inserter[tier.hand]
  local shadow = source and source["hand_" .. part .. "_shadow"]
  if not shadow then return nil end
  local copy = table.deepcopy(shadow)
  copy.scale = require("lib.tiers").SCALE
  copy.draw_as_shadow = true
  return copy
end

return art
