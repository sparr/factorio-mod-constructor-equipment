--- One technology per tier, each unlocking that tier's recipe.
---
--- The first waits for modular armour, to have somewhere to put it, and for electronics,
--- because that is what unlocks the yellow inserter whose arm it borrows: researching it
--- first would give you an arm made of something you cannot build. Checked against
--- Factorio 2.1.17, where electronics unlocks copper cable, electronic circuits, labs, the
--- inserter and small electric poles. It sits earlier in the tree than modular armour, so
--- it does not actually gate anything today; it is here so the dependency is stated rather
--- than assumed.
---
--- Each tier after that waits for the tier below it and for one thing of its own level:
--- faster belts, then speed modules, then faster belts again.
local tiers = require("lib.tiers")
local art = require("prototypes.art")

local technologies = {}

for _, tier in ipairs(tiers.list) do
  local ingredients = {}
  for _, pack in ipairs(tier.research.packs) do
    table.insert(ingredients, { pack .. "-science-pack", 1 })
  end

  local prerequisites = {}
  if tier.below then table.insert(prerequisites, tier.below) end
  for _, requirement in ipairs(tier.requires) do
    table.insert(prerequisites, requirement)
  end

  table.insert(technologies, {
    type = "technology",
    name = tier.name,
    icons = art.icons(tier, 256),
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = tier.name
      }
      -- 0.15 also stretched ghost lifetime to an hour here. ghost-time-to-live is no
      -- longer a technology modifier and is not settable from script either, so the
      -- effect is gone rather than reimplemented.
    },
    prerequisites = prerequisites,
    unit =
    {
      count = tier.research.count,
      ingredients = ingredients,
      time = tier.research.time
    },
    order = tier.level == 1 and "g-c" or ("g-c-" .. tier.level),
  })
end

data:extend(technologies)
