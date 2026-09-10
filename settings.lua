--- What an arm should do when it is bringing something back and there is nowhere to put it.
---
--- The claw is loaded out of the character's pockets rather than from nothing, so anything
--- an arm is carrying has already been paid for and must not be quietly destroyed. That
--- leaves two honest answers when the pockets are full by the time it gets home, and which
--- one a player wants is a matter of taste rather than correctness.
data:extend{
  {
    type = "bool-setting",
    name = "constructor-equipment-spill-when-full",
    setting_type = "runtime-per-user",
    default_value = false,
    order = "a",
  },
}
