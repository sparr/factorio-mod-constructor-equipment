--- One recipe per tier: the inserter whose arm it is, a circuit of the tier's own level,
--- and a plate to bolt it to. Each tier is built from parts rather than out of the tier
--- below it, so a better arm is a thing you make, not a thing you upgrade into.
local tiers = require("lib.tiers")

local recipes = {}

for _, tier in ipairs(tiers.list) do
  table.insert(recipes, {
    type = "recipe",
    name = tier.name,
    enabled = false,
    energy_required = tier.craft,
    ingredients = tier.ingredients,
    results = { { type = "item", name = tier.name, amount = 1 } }
  })
end

data:extend(recipes)
