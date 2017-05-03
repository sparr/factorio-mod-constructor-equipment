data:extend(
{
  {
    type = "movement-bonus-equipment",
    name = "constructor-equipment",
    sprite =
    {
      filename = "__base__/graphics/entity/long-handed-inserter/long-handed-inserter-hand-closed.png",
      width = 18,
      height = 41,
      priority = "medium"
    },
    shape =
    {
      width = 2,
      height = 4,
      type = "full"
    },
    energy_source =
    {
      type = "electric",
      usage_priority = "secondary-input"
    },
    energy_consumption = "0kW",
    movement_bonus = 0.0,
    categories = {"armor"}
  }
})