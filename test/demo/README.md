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

`test/demo/probe.sh` stands a player on every mark in turn and writes down what the arms did
to the ground round it. A bay that misbehaves here while the test covering it passes is a
difference between the showroom and the replica, and the only way to find it is to work the
showroom itself. It found three: a curved rail that had snapped two and a half tiles from a
two tile mark, a cliff that was never marked at all, and a bay whose kit had no charge in it.

It teleports on to each mark and stands there, and a teleport is deliberately not read as a
course, so every mark is probed from a standstill. That makes it blind to rows 11 and 12,
where standing still is the thing that does not work: it reports those bays as almost
nothing built, which is right for a player who never moves and says nothing about the bays.
Those two rows are covered by walking them, or by `test/ft/showroom.lua`, which walks the
same layouts headless.

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

Rows are numbered as they are laid out rather than in the source, because some of them are
only there when the mods they are about are. A row about one of AAI's vehicles is left out
of a game without that vehicle in it, and the row about quality is left out of a game with
only the one quality; the rows after close up rather than leaving a hole in the counting. So
the numbers below are what you see with everything installed, and are lower otherwise. Built
with nothing but the base game and this mod, the showroom is the first twelve rows.

**1. Building.** The plain case and the ways it declines. A ghost in reach; one six tiles
off, which a two tile arm leaves alone; a belt under your own feet, which goes up anyway
because a belt is not a thing you are standing in; a chest under your own feet, which waits
until you move off it; one you are carrying nothing to pay for; a curved rail, which wants
three rails where the claw holds one; and a run of ghosts to walk away from, which is where
the slowdown shows.

**2. Tiers and numbers.** Four arms at once, one of each tier. The mark puts you down among
four ghosts at one, two, three and four tiles, because walking up to them offers them one at
a time, nearest first, and there is no way to arrive all at once on foot. Then four copies of one tier working side by
side, and the bulk claw carrying several and turning from ghost to ghost rather than coming
home between each.

**3. Power.** An arm in a grid with no charge, which never sets off; a mark that puts a
reactor and a battery in your armour, after which the same arm builds; and a fourth tier arm
on one small battery in the middle of a ring of forty, which is enough work to watch the
charge go down rather than flicker.

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
marked for removal is an entity standing on it, and a claw with room left in its hand crosses
from one to the next without coming home between them. Two belts either side of the mark,
which go in one round for the same reason. It visits every one of them: nothing is taken up
that the claw did not travel to. And a cliff, which is not a demolition at all but a delivery:
the claw carries one explosive out and comes home with nothing.

**7. A tank** and **8. a spidertron**, the two vehicles the base game gives an equipment
grid. Get in and drive along the ghosts on either side. A tank's arms are bolted to its
turret, which sits over the middle of the hull; a spidertron's are bolted to its legs, and a
vehicle with neither carries them along its flanks. Each reaches from where it is bolted
rather than from the middle, and the vehicle pays out of its own hold rather than your
pockets.

Every vehicle in here is parked facing east, which is the way its row is laid and the way
its bay tells you to drive. It is not only tidiness: where a hull's arms are bolted is
worked out from which way the hull is pointed, so one parked across its own row shows an
arrangement nobody is going to drive in. The spidertron is the exception it has to be. Only
its torso turns, its legs do not, and its arms are on its legs -- so its body is pointed east
and its eight arms sit where they always sit.

**9. A car** and **10. a locomotive** are **not vanilla**. Neither has an equipment grid in
the base game, and the showroom adds one so there is something to look at. The locomotive
pulls a cargo wagon, which is where its belts are: a locomotive prototype has nowhere to put
a hold, so its only inventory is a three slot burner box and its arms build out of the
train's wagons instead. Their titles say
so in orange. Without it, a car is the case where a driver's own armour goes quiet and
nothing takes over.

**11. An AAI chaingunner**, **12. an ironclad** and **13. a hauler** are **not vanilla**,
and are here for the one thing the base game's four vehicles cannot show: a hull of a shape
nobody wrote the mounting against. A tank, a car and a locomotive are all roughly the same
long rectangle. A chaingunner is a tile and a half square and its four arms sit almost on top
of one another; an ironclad is twice as long as it is wide, and carries a grid of its own
rather than one the showroom added; a hauler is a big square with a hold, so its arms build
out of what it is carrying. Each is its own mod, none is a dependency, and a row whose
vehicle is not installed is not laid out at all.

The ironclad's row is a lane of shallow water forty two tiles long, because an ironclad is a
boat: its only collision is with ground tiles, so the showroom's own floor is the one thing
it cannot be on. Shallow rather than deep, and the collision masks decide it rather than the
look -- deep water collides with the player as well, which would leave the mark out of
walking reach and anybody who climbed out mid lane with nowhere to stand. The ghosts go along
the banks rather than down the middle, since the middle is the water the boat is in and a
belt cannot be built there, and each bank is worked by the arms on its own side.

**14. Leading.** The bays that have to be walked rather than stood on, because an arm aims
where its target will be by the time the claw gets there and standing still there is nowhere
else for it to be. A belt ten tiles off a five tile arm, which goes up as you pass. One four
tiles square to the side, which does not, and says why: a hand stretches out more slowly than
its owner walks, so something square abeam is past a walk before the claw could be there, and
the arm knows it and never sets off -- stop beside that one and it goes up at once. And a two tile arm meeting
something six tiles off, since leading is not only for the big ones.

**15. Rounds on the move.** The same arm with the capacity research, so its claw carries
several. Four belts ten to thirteen tiles ahead, which are past what one swing can reach or
even see when the claw leaves and go up in a single trip anyway, because the round is shopped
for over its whole life. Then a ladder of five off to one side, each rung a tile further
off your line than the last: the near three go up on the way past and the far two do not, so
what the bay shows is where the edge is rather than a count. Measured at four spacings, two,
three and four tiles abeam go up and five and six do not.

**16. Quality.** One mark per quality the game has, worst first, each handing you the same
fourth tier arm at a better quality than the last along with a block of belts to put up with
it. The equipment's quality is the arm's: the engine swings a quality inserter faster by both
its speeds and charges it proportionally more power, so what changes along the row is how
fast the same claw works and nothing else. A legendary one extends and turns two and a half
times as fast as a common one, which is the engine's own figure and is what each bay's note
quotes. Left out of a game with only the one quality in it.

## What the smoke run should say

```
ce-demo: built 12 rows of 16, 31 bays, 360 ghosts, 4 vehicles
everything placed
```

Twelve of sixteen because the smoke run is the base game and this mod and nothing else: the
three rows about AAI's vehicles and the one about quality are not laid out, and the count
says so rather than leaving it to be noticed. With all of them, it is sixteen rows, 39 bays,
540 ghosts and 7 vehicles.

A bay that quietly failed to build looks exactly like a bay demonstrating that nothing
happens, which is why the smoke run counts rather than eyeballs.

The count is what stands on the ground at the end of a build, so it does not include the
exhibits that wait for their mark to be stood on. Several bays lay their ghosts on arrival
rather than leaving them out: an arm aims where its target will be by the time the claw
could get there, so walking up to a bay is walking towards it with a cone of reach in front
of you, and a fourth tier arm meets things eleven tiles ahead of a walk. There is no
distance inside a bay that is past that, so the exhibit waits instead.
