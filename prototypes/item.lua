data:extend(
{
  {
    type = "item",
    name = "constructor-equipment",
    icon = "__constructor-equipment__/graphics/long_arm_32.png",
    icon_size = 32,
    place_as_equipment_result = "constructor-equipment",
    -- the goes-to-main-inventory flag went away in 0.17, along with the separate
    -- quickbar it was about
    subgroup = "equipment",
    order = "e[robotics]-c[constructor-equipment]",
    stack_size = 5
  }
})
