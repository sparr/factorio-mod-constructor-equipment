--- Make each tier wait for whatever unlocks the inserter it is built out of.
---
--- Every tier's recipe consumes one of the base game's inserters, so a tier researched
--- before that inserter exists is a recipe nobody can craft. Naming the technology outright
--- is right until a mod moves the inserter somewhere else, and mods that rearrange the
--- early tree are exactly the ones this would be wrong under, so the tree is read rather
--- than assumed.
---
--- This runs in final fixes because that is the first point at which every other mod has
--- finished rearranging things. Another mod's own final fixes can still move an inserter
--- after this looks, which nothing can do anything about.
---
--- If the inserter has no recipe at all, this adds nothing and the data stage fails on the
--- missing ingredient instead, which tells the player plainly that the two mods do not fit
--- together.
--- The search itself lives in lib/unlock.lua, which is handed these tables rather than
--- reaching for data.raw, so that the cases the base game does not contain -- a loop in the
--- tree, two technologies unlocking the same thing, an item nobody can make -- can be
--- written down and checked without a game.
local tiers = require("lib.tiers")
local unlock = require("lib.unlock")

local mine = {}
for _, tier in ipairs(tiers.list) do mine[tier.name] = true end

for _, tier in ipairs(tiers.list) do
  local technology = data.raw.technology[tier.name]
  if technology then
    local wait_for = unlock.gate(data.raw.recipe, data.raw.technology, tier.hand, mine)
    if wait_for then
      technology.prerequisites = technology.prerequisites or {}
      local already = false
      for _, prerequisite in pairs(technology.prerequisites) do
        if prerequisite == wait_for then already = true end
      end
      if not already then
        table.insert(technology.prerequisites, wait_for)
      end
    end
  end
end
