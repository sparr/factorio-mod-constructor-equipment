data:extend(
{
  {
    type = "technology",
    name = "constructor-equipment",
    icon = "__constructor-equipment__/graphics/long_arm_64.png",
    effects =
    {
      {
        type = "unlock-recipe",
        recipe = "constructor-equipment"
      },
      {
        type = "ghost-time-to-live",
        modifier = 60 * 60 * 60
      }
    },
    prerequisites = {"modular-armor"},
    unit =
    {
      count = 50,
      ingredients = {{"science-pack-1", 1}, {"science-pack-2", 1}},
      time = 15
    },
    order = "g-c",
  }
})