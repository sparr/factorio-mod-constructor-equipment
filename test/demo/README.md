# The showroom

One of every thing this mod does, in labelled bays laid out in rows on a surface of its own,
to be walked round rather than asserted about. Every bay says where to stand and what to do,
written on the ground above it, so nothing here needs reading alongside it.

```
test/demo/run.sh                 # a graphical session, standing on the first row's pad
CE_SPACE_AGE=1 test/demo/run.sh  # with the expansion loaded
test/demo/smoke.sh               # headless: builds it and says what it built
```

The game runs out of its own data directory and the repo is symlinked in, so whatever is in
the working tree is what loads. Nothing touches your real mods, saves or settings. The save
is built fresh on every launch and loaded straight into, so there is no menu to pick anything
out of, and freeplay in particular is the wrong thing to start here since it puts you beside
a crashed ship on Nauvis rather than in the showroom.

`/ce-demo` builds it all again.

## Getting about

Rows are kitted rather than cumulative. Two pads on each row:

- **the west pad** gives you exactly what that row wants, and takes away what it does not:
  the armour is replaced, the grid is filled from scratch and the pockets are emptied first
- **the east pad** carries you to the next row's west pad

So the rows can be walked in order, or any row can be walked to directly and entered cold by
standing on its pad. Nothing here has to be done in sequence, and no row inherits the last
one's kit.

You start on row 1's pad with modular armour, one first tier arm and a pocketful of belts.

## What is in it

**1. Building.** The plain case and the four ways it declines. A ghost in reach; one six
tiles off, which a two tile arm leaves alone; one under your own feet, which an arm will not
reach beneath its own base; one you are carrying nothing to pay for; a curved rail, which
wants three rails where the claw holds one; and a run of ghosts to walk away from, which is
where the slowdown shows.

**2. Tiers and numbers.** Four arms at once, one of each tier, with ghosts at two, three,
four and five tiles so each tier takes its own. Then four copies of one tier working side by
side, and the bulk claw carrying several and turning from ghost to ghost rather than coming
home between each.

**3. Power.** An arm in a grid with no charge, which never sets off; a chest with a reactor
in it to put in your armour, after which it does; and a long run to watch the batteries
against, since a reach is billed by the tile.

**4. Switching off, and full pockets.** The toolbar button, pressed mid reach. Then a chest
of stone to fill your pockets with before marking a few belts, which is where the claw's
choice between holding what it cannot hand over and dropping it shows. That one is a per
player setting, **Drop items when your inventory is full**.

**5. The upgrade planner.** A run of belts already marked, which the claw swaps one at a time
and brings the old one back from. An underground pair, which goes as one job for the price of
two and keeps what is travelling in the tunnel. And a full steel chest marked down to an iron
one, where what the smaller chest cannot hold is left on the floor marked for deconstruction,
the way a robot leaves it.

**6. The deconstruction planner.** A run of belts taken up, the claw going out empty and
coming home loaded. A chest with something in it, which is emptied a clawful at a time before
the chest itself goes, which is what robots do with one. A patch of concrete, since a tile
marked for removal is an entity standing on it and the same claw does it. And a cliff, which
is not a demolition at all but a delivery: the claw carries one explosive out and comes home
with nothing.

**7. A tank** and **8. a spidertron**, the two vehicles the base game gives an equipment
grid. Get in and drive along the ghosts on either side. The arms are mounted along the hull
and reach from where they are bolted rather than from the middle, and the vehicle pays out of
its own hold rather than your pockets.

**9. A car** and **10. a locomotive** are **not vanilla**. Neither has an equipment grid in
the base game, and the showroom adds one so there is something to look at. Their titles say
so in orange. Without it, a car is the case where a driver's own armour goes quiet and
nothing takes over.

## What the smoke run should say

```
ce-demo: built 10 rows, 25 bays, 173 ghosts, 4 vehicles
everything placed
```

A bay that quietly failed to build looks exactly like a bay demonstrating that nothing
happens, which is why the smoke run counts rather than eyeballs.
