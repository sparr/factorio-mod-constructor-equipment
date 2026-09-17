-- One of every thing Constructor Equipment does, in labelled bays on a surface of its own.
--
-- The point is to be walked round rather than asserted about. Every bay says where to stand
-- and what to do, on the ground above it, so nothing here needs a manual open beside it.
--
-- Rows are kitted rather than cumulative. A pad at the west end of each row gives the
-- character the armour, the equipment and the items that row wants and takes away what it
-- does not, so a row can be walked into cold; a pad at the east end carries you to the next
-- row's west pad. Walking to any row directly and standing on its pad does the same thing,
-- so nothing here has to be done in order.
--
--   /ce-demo    build it all again
--
-- The last four rows are vehicles. Two of them are vehicles the base game gives no
-- equipment grid: the showroom adds one so there is something to look at, and says so.

local BAY = 12          -- how wide a bay is: past the longest reach, and past its own words
local ROW = 14          -- how far apart the rows are
local SURFACE = "ce-demo"

local TIERS = { "constructor-equipment", "constructor-equipment-2",
                "constructor-equipment-3", "constructor-equipment-4" }

local function ground()
  return game.surfaces[SURFACE]
end

---Where a row's west pad stands. Bays run east from there.
---@param row integer counting from 1
---@return number x
---@return number y
local function row_at(row)
  return 0, (row - 1) * ROW
end

---@param x number
---@param y number
---@param text string
---@param note string?
---@param colour table?
local function label(x, y, text, note, colour)
  rendering.draw_text{ text = text, surface = ground(), target = { x, y },
    color = colour or { 1, 0.9, 0.6 }, scale = 1.8, alignment = "left",
    scale_with_zoom = false }
  if not note then return end
  -- Broken into lines rather than written as one. A bay is twenty two tiles wide and a
  -- sentence is longer than that, so left whole it runs across its neighbour's exhibit and
  -- both become unreadable.
  local line, at = "", 0
  local function draw(text_line)
    rendering.draw_text{ text = text_line, surface = ground(),
      target = { x, y + 1.3 + at * 1.1 },
      color = { 0.72, 0.78, 0.85 }, scale = 1.1, alignment = "left",
      scale_with_zoom = false }
    at = at + 1
  end
  for word in note:gmatch("%S+") do
    if #line + #word + 1 > 40 then draw(line) line = word
    else line = (line == "") and word or (line .. " " .. word) end
  end
  if line ~= "" then draw(line) end
end

---@param name string
---@param x number
---@param y number
---@param extra table?
---@return LuaEntity?
local function place(name, x, y, extra)
  local args = { name = name, position = { x + 0.5, y + 0.5 }, force = "player" }
  for key, value in pairs(extra or {}) do args[key] = value end
  local made = ground().create_entity(args)
  if not made then
    log(("ce-demo: could not place %s at %d,%d"):format(name, x, y))
  end
  return made
end

---A ghost of something, which is the thing most of this is about.
---@param name string
---@param x number
---@param y number
---@param extra table?
---@return LuaEntity?
local function ghost(name, x, y, extra)
  local args = { inner_name = name }
  for key, value in pairs(extra or {}) do args[key] = value end
  return place("entity-ghost", x, y, args)
end

---The mark to stand on: one tile, so that standing on it means standing where the bay was
---measured from. A three by three patch let you stand a tile and a half off, which on a two
---tile arm is the difference between working and not.
---@param x number
---@param y number
---@param tile string
local function pad(x, y, tile)
  ground().set_tiles{ { name = tile, position = { x, y } } }
end

-- --------------------------------------------------------------------------- the rows

--- What each row is, what it gives the character who stands on its pad, and what it builds.
---
--- A kit is the whole of what the character has: the armour is replaced, the grid is filled
--- from scratch and the pockets are emptied first, so a row never inherits the one before
--- it. That is what lets any row be walked into directly.
local ROWS = {
  {
    title = "1. Building",
    note = "Modular armour, one first tier arm, a pocketful of belts.",
    kit = {
      armour = "modular-armor",
      equipment = { "constructor-equipment", "battery-equipment" },
      items = { ["transport-belt"] = 50, ["rail"] = 20, ["iron-chest"] = 5 },
    },
    bays = {
      { "A ghost in reach",
        "Stand on the mark. The arm comes out of your back and builds it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 5, y + 6)
        end },
      { "A ghost out of reach",
        "Stand on the mark. The first tier reaches two tiles and this one is six away.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 9, y + 6)
        end },
      { "A ghost under your feet",
        "Stand on the mark, which is the ghost. An arm will not reach under its own base.",
        function(x, y)
          pad(x + 4, y + 6, "refined-hazard-concrete-left")
          ghost("transport-belt", x + 4, y + 6)
        end },
      { "Nothing to pay with",
        "Stand on the mark. You are carrying no steel chest, so it stays a ghost.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          ghost("steel-chest", x + 5, y + 6)
        end },
      { "A ghost that takes three",
        "Stand on the mark. A curved rail wants three rails and the claw holds one:",
        function(x, y)
          pad(x + 4, y + 6, "refined-hazard-concrete-left")
          -- Two tiles from the mark, since that is all a first tier arm has. It sat at six
          -- and nothing ever went out to it.
          ghost("curved-rail-a", x + 6, y + 6, { direction = defines.direction.north })
        end },
      { "The slowdown",
        "Stand on the mark and walk east along them. A first tier arm costs you speed while it works.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- laid the way you will be walking, so the work keeps up with you
          for i = 0, 8 do ghost("transport-belt", x + 3 + i, y + 6) end
        end },
    },
  },

  {
    title = "2. Tiers and numbers",
    note = "Power armour, one arm of every tier, and the capacity research done.",
    kit = {
      armour = "power-armor-mk2",
      equipment = { TIERS[1], TIERS[2], TIERS[3], TIERS[4],
                    "fission-reactor-equipment", "battery-mk2-equipment" },
      items = { ["transport-belt"] = 200 },
      -- inserter-capacity-bonus-1 is the one that raises a bulk hand; the others raise a
      -- plain one. The bulk arm reads the first, so it is here along with what it follows.
      research = { "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "Four arms, four reaches",
        "Walk east along the mark. Each is set so the arm that suits it meets it first: five tiles, then four, three, two.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- Staggered rather than in a line. Four ghosts at two, three, four and five
          -- tiles from one spot are all inside the green arm's five, and it takes the lot.
          -- Set out along the walk with the furthest first, each arm meets its own a moment
          -- before a longer one is free to take it.
          for step = 5, 2, -1 do
            ghost("transport-belt", x + 2 + (5 - step) * 3, y + 6 - step)
          end
        end },
      { "One arm for every copy",
        "Stand on the mark. Four arms work at once, and none of them reaches for the same thing.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 3 do
            ghost("transport-belt", x + 5, y + 4 + i)
            ghost("transport-belt", x + 6, y + 4 + i)
          end
        end },
      { "The bulk claw",
        "Stand on the mark. Five tiles out, so only the green arm reaches: it carries several and turns from one to the next.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- An arc rather than a column: every one of these is between four and five tiles
          -- from the mark, which is past every other arm's reach and inside the green one's.
          -- A straight column at five tiles has its ends at five and a half, so standing on
          -- the mark only reached the middle of it.
          for _, at in pairs{ { 5, -2 }, { 5, 2 }, { 4, -3 }, { 4, 3 }, { 5, 0 } } do
            ghost("transport-belt", x + 1 + at[1], y + 6 + at[2])
          end
        end },
    },
  },

  {
    title = "3. Power",
    note = "Power armour with nothing but an arm in it, then one with a reactor.",
    kit = {
      armour = "power-armor",
      equipment = { "constructor-equipment" },
      charged = false,
      items = { ["transport-belt"] = 100 },
    },
    bays = {
      { "Flat batteries",
        "Stand on the mark. Your grid has no charge, so the arm never sets off.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 3 do ghost("transport-belt", x + 5, y + 5 + i) end
        end },
      { "Take the reactor",
        "Put the reactor and the battery from this chest into your armour. Now it builds, and the battery is what the next bay is watched on.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local chest = place("iron-chest", x + 3, y + 6)
          if chest then
            chest.insert{ name = "fission-reactor-equipment", count = 1 }
            -- The small battery, not the mark two. A mark two holds so much that a swing
            -- takes an invisible bite out of it, and the next bay is about watching it go
            -- down.
            chest.insert{ name = "battery-equipment", count = 1 }
          end
          for i = 0, 3 do ghost("transport-belt", x + 6, y + 5 + i) end
        end },
      { "What a swing costs",
        "Open your armour and watch the batteries. Everything here is in reach from the mark, so you can stand still and watch it drain.",
        function(x, y)
          pad(x + 5, y + 6, "refined-hazard-concrete-left")
          -- A ring round the mark rather than a line beside it: a first tier arm reaches
          -- two tiles, and a column of eight meant walking the length of it to get the
          -- far ones, which is a poor way to watch a battery.
          for dx = -2, 2 do
            for dy = -2, 2 do
              if not (dx == 0 and dy == 0) and (dx * dx + dy * dy) <= 5 then
                ghost("transport-belt", x + 5 + dx, y + 6 + dy)
              end
            end
          end
        end },
    },
  },

  {
    title = "4. Switching off, and full pockets",
    note = "Power armour, one arm, and a pocketful you will be asked to fill up.",
    kit = {
      armour = "power-armor",
      equipment = { "constructor-equipment", "battery-mk2-equipment" },
      items = { ["transport-belt"] = 100 },
      -- The button is unlocked by the first tier's technology, and without it there is no
      -- button on the toolbar to press.
      research = { "constructor-equipment" },
    },
    bays = {
      { "The toolbar button",
        "Stand on the mark, then press the arm button on the toolbar. It stops mid reach, and what the claw was carrying comes back. Take the arm out of your armour and the button greys out.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 7 do ghost("transport-belt", x + 5, y + 2 + i) end
        end },
      { "Pockets full",
        "Empty these chests into your pockets until nothing more will fit, then mark the belts for deconstruction yourself.",
        function(x, y)
          pad(x + 1, y + 6, "refined-hazard-concrete-left")
          -- Four full chests rather than one. A character's pockets grow with research and
          -- with what they are wearing, and one chest of stone is not always enough to fill
          -- them.
          for i = 0, 3 do
            local chest = place("steel-chest", x + 3, y + 4 + i)
            if chest then chest.insert{ name = "stone", count = 48 * 50 } end
          end
          -- Left unmarked on purpose: marking them is the thing to do here.
          for i = 0, 3 do place("transport-belt", x + 5, y + 4 + i) end
        end },
    },
  },

  {
    title = "5. The upgrade planner",
    note = "Power armour, the bulk arm, and better belts to pay with.",
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-mk2-equipment" },
      items = {
        ["fast-transport-belt"] = 50, ["fast-underground-belt"] = 20,
        ["iron-chest"] = 10, ["upgrade-planner"] = 1,
      },
      -- Without this a bulk claw holds one thing, and every bay about carrying several
      -- shows it carrying one.
      research = { "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "A belt upgraded",
        "Stand on the mark. These are marked already: the claw swaps each and brings the old one back.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 4 do
            local belt = place("transport-belt", x + 5, y + 4 + i,
              { direction = defines.direction.east })
            if belt then
              belt.order_upgrade{ force = game.forces.player,
                target = prototypes.entity["fast-transport-belt"] }
            end
          end
        end },
      { "An underground pair",
        "Stand on the mark. Both ends go together for the price of two, and the tunnel keeps its load.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          local near = place("underground-belt", x + 4, y + 6,
            { direction = defines.direction.east, type = "input" })
          local far = place("underground-belt", x + 8, y + 6,
            { direction = defines.direction.east, type = "output" })
          for _, one in pairs{ near, far } do
            if one then
              one.order_upgrade{ force = game.forces.player,
                target = prototypes.entity["fast-underground-belt"] }
            end
          end
          if near then
            for line = 3, 4 do
              for spot = 0.2, 1.4, 0.6 do
                near.get_transport_line(line).insert_at(spot, { name = "iron-plate" })
              end
            end
          end
        end },
      { "A chest downgraded",
        "Stand on the mark. What the smaller chest cannot hold is left on the floor, marked, as a robot leaves it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local chest = place("steel-chest", x + 5, y + 6)
          if chest then
            chest.insert{ name = "iron-plate", count = 4800 }
            chest.order_upgrade{ force = game.forces.player,
              target = prototypes.entity["iron-chest"] }
          end
        end },
    },
  },

  {
    title = "6. The deconstruction planner",
    note = "Power armour, the bulk arm, a planner and a charge for the cliff.",
    kit = {
      armour = "power-armor",
      equipment = { TIERS[4], "fission-reactor-equipment", "battery-mk2-equipment" },
      items = { ["deconstruction-planner"] = 1, ["cliff-explosives"] = 5 },
      research = { "cliff-explosives", "bulk-inserter", "inserter-capacity-bonus-1",
                   "inserter-capacity-bonus-2", "inserter-capacity-bonus-3" },
    },
    bays = {
      { "A thing taken up",
        "Stand on the mark. The claw goes out empty and comes home with it.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          for i = 0, 4 do
            local belt = place("transport-belt", x + 5, y + 4 + i)
            if belt then belt.order_deconstruction(game.forces.player) end
          end
        end },
      { "A chest with something in it",
        "Stand on the mark. Emptied a clawful at a time, and the chest itself goes last.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local chest = place("steel-chest", x + 5, y + 6)
          if chest then
            chest.insert{ name = "copper-plate", count = 20 }
            chest.order_deconstruction(game.forces.player)
          end
        end },
      { "A patch of tiles",
        "Stand on the mark. A tile marked for removal is an entity standing on it, and a hand that holds several takes several in one trip.",
        function(x, y)
          pad(x + 3, y + 6, "refined-hazard-concrete-left")
          local tiles = {}
          for dx = 0, 2 do
            for dy = -1, 1 do
              tiles[#tiles + 1] = { name = "concrete", position = { x + 4 + dx, y + 6 + dy } }
            end
          end
          ground().set_tiles(tiles)
          for _, tile in pairs(tiles) do
            local one = ground().get_tile(tile.position[1], tile.position[2])
            if one then one.order_deconstruction(game.forces.player) end
          end
        end },
      { "Both sides in one trip",
        "Stand on the mark, between them. The claw fills its hand from anything in reach, not just from what it is standing over, so these go together.",
        function(x, y)
          pad(x + 5, y + 6, "refined-hazard-concrete-left")
          for _, away in pairs{ -4, -3, 3, 4 } do
            local belt = place("transport-belt", x + 5 + away, y + 6)
            if belt then belt.order_deconstruction(game.forces.player) end
          end
        end },
      { "A cliff wants a charge",
        "Stand on the mark. The claw carries one explosive out and comes home with nothing.",
        function(x, y)
          -- The mark goes where the cliff ended up rather than where it was asked for. A
          -- cliff lies on a grid of its own and comes to rest a tile or two off, which on a
          -- five tile arm is the difference between reaching it and standing there.
          local cliff = place("cliff", x + 7, y + 6,
            { cliff_orientation = "west-to-east", force = "neutral" })
          if cliff then
            cliff.order_deconstruction(game.forces.player)
            pad(math.floor(cliff.position.x) - 3, math.floor(cliff.position.y),
              "refined-hazard-concrete-left")
          else
            pad(x + 2, y + 6, "refined-hazard-concrete-left")
          end
        end },
      },
  },

  {
    title = "7. A tank",
    note = "A vehicle the base game gives an equipment grid. Get in and drive along the ghosts.",
    vanilla = true,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on the hull",
        "Get in and drive east. They are mounted along the sides and reach from where they are bolted,",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 14 do
            ghost("transport-belt", x + 5 + i, y + 3)
            ghost("transport-belt", x + 5 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "tank", at = { 3, 6 }, fuel = "solid-fuel" },
  },

  {
    title = "8. A spidertron",
    note = "The other vehicle the base game gives a grid, and the one that walks.",
    vanilla = true,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on the legs",
        "Get in and walk it over the ghosts. A spider loses the same share of its speed you lose of yours.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 14 do
            ghost("transport-belt", x + 5 + i, y + 3)
            ghost("transport-belt", x + 5 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "spidertron", at = { 3, 6 } },
  },

  {
    title = "9. A car, with a grid the showroom added",
    note = "NOT VANILLA. A car has no equipment grid in the base game; this one has one so there is something to see.",
    vanilla = false,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on a car",
        "Get in and drive east. Without the grid the showroom gave it, your own armour would go quiet in here.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = 0, 14 do
            ghost("transport-belt", x + 5 + i, y + 3)
            ghost("transport-belt", x + 5 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "car", at = { 3, 6 }, fuel = "solid-fuel" },
  },

  {
    title = "10. A locomotive, with a grid the showroom added",
    note = "NOT VANILLA. A locomotive has no equipment grid in the base game either.",
    vanilla = false,
    kit = { armour = "modular-armor", equipment = {}, items = {} },
    bays = {
      { "Arms on a train",
        "Get in and drive along the rail. The ghosts are beside the track on both sides.",
        function(x, y)
          pad(x + 2, y + 6, "refined-hazard-concrete-left")
          for i = -2, 12 do
            place("straight-rail", x + 6 + i * 2, y + 6,
              { direction = defines.direction.east })
          end
          for i = 0, 14 do
            ghost("transport-belt", x + 6 + i, y + 3)
            ghost("transport-belt", x + 6 + i, y + 9)
          end
        end },
    },
    vehicle = { name = "locomotive", at = { 6, 6 }, fuel = "solid-fuel",
                direction = defines.direction.east, on_rail = true },
  },
}

-- --------------------------------------------------------------------------- kitting

---Give the character exactly what a row wants and nothing else.
---@param player LuaPlayer
---@param row table
local function kit(player, row)
  local wanted = row.kit or {}
  local main = player.get_inventory(defines.inventory.character_main)
  local worn = player.get_inventory(defines.inventory.character_armor)
  if main then main.clear() end
  if worn then worn.clear() end

  if wanted.armour then
    player.insert{ name = wanted.armour, count = 1 }
    local armour = worn and worn[1]
    if armour and armour.grid then
      for _, name in pairs(wanted.equipment or {}) do
        if prototypes.equipment[name] then armour.grid.put{ name = name } end
      end
      for _, piece in pairs(armour.grid.equipment) do
        piece.energy = (wanted.charged == false) and 0 or piece.max_energy
      end
    end
  end

  for name, count in pairs(wanted.items or {}) do
    if prototypes.item[name] then player.insert{ name = name, count = count } end
  end

  for _, name in pairs(wanted.research or {}) do
    local technology = player.force.technologies[name]
    if technology then technology.researched = true end
  end
end

-- --------------------------------------------------------------------------- building

local function clear_and_build()
  local made = ground()
  if not made then
    made = game.create_surface(SURFACE, { width = 2000, height = 2000 })
  end
  made.always_day = true

  local width = 0
  for _, row in pairs(ROWS) do width = math.max(width, #row.bays * BAY + BAY) end
  local tall = #ROWS * ROW + ROW

  made.request_to_generate_chunks({ width / 2, tall / 2 },
    math.ceil(math.max(width, tall) / 32) + 2)
  made.force_generate_chunk_requests()

  local left, top, right, bottom = -BAY, -ROW, width + BAY, tall
  for _, thing in pairs(made.find_entities_filtered{
      area = { { left, top }, { right, bottom } } }) do
    if thing.valid and thing.type ~= "character" then thing.destroy() end
  end
  for _, drawn in pairs(rendering.get_all_objects("ce-demo")) do drawn.destroy() end

  -- The checkerboard the testing scenarios use. Solid white is too bright to look at for
  -- long, and a floor with no pattern in it gives the eye nothing to judge a tile against.
  local floor = {}
  for x = left, right do
    for y = top, bottom do
      floor[#floor + 1] = {
        name = ((x + y) % 2 == 0) and "lab-dark-1" or "lab-dark-2",
        position = { x, y },
      }
    end
  end
  made.set_tiles(floor)
  -- Tiles alone do not clear the ground: the grass and the rocks the generator scattered
  -- are decoratives rather than entities, and they survive both the tiling above and the
  -- sweep of entities before it.
  made.destroy_decoratives{ area = { { left, top }, { right, bottom } } }

  storage.pads = {}
  for index, row in ipairs(ROWS) do
    local rx, ry = row_at(index)
    label(rx, ry + 1, row.title, row.note,
      row.vanilla == false and { 1, 0.65, 0.4 } or nil)

    -- the west pad, which kits whoever stands on it, and the east one, which moves them on
    pad(rx + 1, ry + 6, "refined-concrete")
    label(rx - 1, ry + 7.6, "STAND HERE",
      "for what this row wants", { 0.55, 0.9, 0.6 })
    storage.pads[index] = { west = { x = rx + 1.5, y = ry + 6.5 } }

    for bay, what in ipairs(row.bays) do
      local x = rx + bay * BAY
      label(x, ry + 3, what[1], what[2])
      what[3](x, ry)
    end

    local east = rx + (#row.bays + 1) * BAY
    if index < #ROWS then
      pad(east, ry + 6, "refined-hazard-concrete-right")
      label(east - 2, ry + 7.6, "STAND HERE",
        row.vehicle and ("to go to row %d, vehicle and all"):format(index + 1)
          or ("to go to row %d"):format(index + 1), { 0.95, 0.8, 0.4 })
      storage.pads[index].east = { x = east + 0.5, y = ry + 6.5 }
    end

    if row.vehicle then
      local where = { rx + row.vehicle.at[1] + BAY, ry + row.vehicle.at[2] }
      local made_vehicle
      if row.vehicle.on_rail then
        -- A locomotive goes where a rail is rather than where the tape measure says: rails
        -- lie on a grid of their own and the one built for it is not quite where it was
        -- asked for.
        local rails = made.find_entities_filtered{
          position = { where[1] + 0.5, where[2] + 0.5 }, radius = 8,
          type = "straight-rail" }
        for _, rail in pairs(rails) do
          for _, facing in pairs{ rail.direction, (rail.direction + 8) % 16 } do
            if not made_vehicle then
              made_vehicle = made.create_entity{ name = row.vehicle.name,
                position = rail.position, direction = facing, force = "player" }
            end
          end
        end
        if not made_vehicle then
          log(("ce-demo: could not put a %s on the rail"):format(row.vehicle.name))
        end
      else
        made_vehicle = place(row.vehicle.name, where[1], where[2],
          { direction = row.vehicle.direction })
      end
      if made_vehicle then
        if row.vehicle.fuel then
          made_vehicle.insert{ name = row.vehicle.fuel, count = 50 }
        end
        made_vehicle.insert{ name = "transport-belt", count = 200 }
        local grid = made_vehicle.grid
        if grid then
          grid.put{ name = TIERS[3] }
          grid.put{ name = TIERS[3] }
          grid.put{ name = "fission-reactor-equipment" }
          grid.put{ name = "battery-mk2-equipment" }
          for _, piece in pairs(grid.equipment) do piece.energy = piece.max_energy end
        end
      end
    end
  end

  local ghosts = made.count_entities_filtered{ type = "entity-ghost" }
  local vehicles = 0
  for _, row in pairs(ROWS) do if row.vehicle then vehicles = vehicles + 1 end end
  local bays = 0
  for _, row in pairs(ROWS) do bays = bays + #row.bays end
  log(("ce-demo: built %d rows, %d bays, %d ghosts, %d vehicles"):format(
    #ROWS, bays, ghosts, vehicles))

  for _, player in pairs(game.players) do
    if player.character then
      player.teleport({ 1.5, 6.5 }, made)
    else
      player.set_controller{ type = defines.controllers.god }
      player.create_character()
      player.teleport({ 1.5, 6.5 }, made)
    end
    kit(player, ROWS[1])
  end
end

-- --------------------------------------------------------------------------- the pads

--- Which row a player last had a kit from, so that standing on a pad does not hand them one
--- every tick for as long as they are on it.
local function on_pad(player, at)
  local dx, dy = player.position.x - at.x, player.position.y - at.y
  return (dx * dx + dy * dy) < 2.25
end

script.on_event(defines.events.on_tick, function()
  if game.tick % 15 ~= 0 then return end
  local made = ground()
  if not (made and storage.pads) then return end
  for _, player in pairs(game.connected_players) do
    if player.surface == made and (player.character or player.vehicle) then
      -- Standing on a mark kits you once. Stepping off it and back on kits you again, which
      -- is what somebody who has spent their belts wants: the marks were one use only.
      local anywhere = false
      for _, pads in pairs(storage.pads) do
        if on_pad(player, pads.west) or (pads.east and on_pad(player, pads.east)) then
          anywhere = true
        end
      end
      if not anywhere then storage.standing = nil end

      for index, pads in pairs(storage.pads) do
        if pads.east and on_pad(player, pads.east) then
          local next_row = storage.pads[index + 1]
          if next_row and storage.standing ~= index + 1 then
            -- A player in a vehicle cannot be teleported out from under it: the vehicle
            -- goes too, or nothing moves and the message repeats at somebody sitting still
            -- on the pad.
            local riding = player.vehicle
            if riding and riding.valid then
              riding.teleport({ next_row.west.x + 3, next_row.west.y })
            end
            player.teleport({ next_row.west.x, next_row.west.y }, made)
            kit(player, ROWS[index + 1])
            storage.standing = index + 1
            player.print(ROWS[index + 1].title .. " -- " .. ROWS[index + 1].note)
          end
          break
        elseif on_pad(player, pads.west) and storage.standing ~= index then
          kit(player, ROWS[index])
          storage.standing = index
          player.print(ROWS[index].title .. " -- " .. ROWS[index].note)
          break
        end
      end
    end
  end
end)

script.on_init(function()
  if remote.interfaces["freeplay"] then
    remote.call("freeplay", "set_disable_crashsite", true)
    remote.call("freeplay", "set_skip_intro", true)
  end
  clear_and_build()
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  if not ground() then clear_and_build() end
  player.teleport({ 1.5, 6.5 }, ground())
  kit(player, ROWS[1])
  storage.standing = 1
end)

commands.add_command("ce-demo", "Build the showroom again", function()
  clear_and_build()
  storage.standing = nil
end)
