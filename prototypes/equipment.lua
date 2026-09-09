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
    -- 0.15 accepted "0kW" here. It must be positive now, so this is nominal: the real
    -- cost of a build is taken straight out of the grid's batteries in control.lua.
    energy_consumption = "1W",
    movement_bonus = 0.0,
    categories = {"armor"}
  }
})