data:extend(
{
  {
    type = "technology",
    name = "constructor-equipment",
    icon = "__constructor-equipment__/graphics/long_arm_64.png",
    icon_size = 64,
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = "constructor-equipment"
      }
      -- 0.15 also stretched ghost lifetime to an hour here. ghost-time-to-live is no
      -- longer a technology modifier and is not settable from script either, so the
      -- effect is gone rather than reimplemented.
    },
    prerequisites = {"modular-armor"},
    unit =
    {
      count = 50,
      ingredients =
      {
        {"automation-science-pack", 1},
        {"logistic-science-pack", 1}
      },
      time = 15
    },
    order = "g-c",
  }
})
