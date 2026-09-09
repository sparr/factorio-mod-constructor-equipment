--- The claw as a sprite, one per tier, for the moment an arm is put away.
---
--- An arm that simply vanished the instant it had nothing left to do read as a glitch
--- rather than as a thing being stowed. It cannot be shrunk where it stands -- an entity's
--- sprites are scaled in its prototype and nothing can change that at runtime -- so what is
--- drawn instead is a copy of the folded claw, which can be shrunk and faded because a
--- drawn sprite takes its scale and its tint from script.
local tiers = require("lib.tiers")

local sprites = {}

for _, tier in ipairs(tiers.list) do
  local size = tier.sizes.closed
  table.insert(sprites, {
    type = "sprite",
    name = tier.name .. "-claw",
    filename = "__base__/graphics/entity/" .. tier.hand .. "/"
      .. tier.hand .. "-hand-closed.png",
    priority = "extra-high",
    width = size[1],
    height = size[2],
    flags = { "icon" },
  })
end

data:extend(sprites)
