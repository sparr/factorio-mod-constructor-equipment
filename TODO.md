# Outstanding, from the walks round of 2026-09-19 and 2026-09-20

## 9. An arm stops when its owner stands on what it was reaching for

It should give up on that one and go to something else rather than waiting.

Not reproduced. A walk of the whole showroom built everything that should have been built
and left standing only what each bay exists to leave standing, and a character who steps
onto a ghost mid reach gives up on it within a few ticks and builds the next one along. The
paths that could have waited are all covered: choose() passes over what its owner stands in
and sorts a pickup underfoot to the back of the queue, advance() asks again every tick and
turns to something else, and a spot a vehicle has rolled onto fails buildable() and is never
offered. So this wants the bay, the save or the tier it was seen on before there is anything
to fix.

## 12. An arm should aim where its target will be, not where it is

Done for one delivery from rest, for an arm that is already out, and for a claw working
several ghosts in a round. An arm works out where its target will be by the time its hand
could get there, holds the claw on that point as its owner carries it along, and drops the
guess for the thing itself the moment it is really in reach. A ghost that is in reach for
forty ticks against a forty three tick reach could not be built at all before and is built
now. Every tier leads; the first one meets things three times its own reach away. The
bearing a claw has to swing through is part of the sum, so a lead it cannot rotate onto in
time is not offered. All three ways a claw changes its mind mid flight -- the ghost being
taken away, a round moving on to its next, and a turn leaving the course unflyable -- are
exercised against a moving owner. A round is shopped for over its own life rather than over
the one swing the tick's search covers, since a claw refills at home and nowhere else, so
what it sets off carrying is all it will put down that journey.

What an arm cannot do is reach something square abeam of a walk, because the hand extends
slower than its owner walks: about 1.07 tiles at walking pace. Three ghosts crammed inside
that at full speed get two of them, and the same three at half speed get all three. That is
the shape of the cone rather than anything to fix.

What is left.

**The search is wider than it needs to be.** It draws the circle round a capsule that
assumes full stretch from the first tick. What an arm can really meet is a cone, and
reach.meets and reach.chain measure it exactly, but only meets is wired and only for judging
a candidate rather than for finding one. Measured on a fourth tier arm: 211 candidates and
0.084ms against 116 and 0.036ms for the cone's own circle. An area can also be given an
orientation, which is worth more than a chain of circles once a cone is long and thin -- a
car's cone returns 330 candidates in one call against 435 in four. Wants a quiet machine to
measure properly.

**Two players can reach for the same ghost.** claims() is built from one wearer's own arms,
so nothing stops a second player's arm setting off for something already spoken for. It
predates any of this, and leading makes it likelier by lengthening how long an arm is
committed.

**The walking penalty is switched off.** tiers.SLOWS, with thirty tests skipped behind it.
It is not only a cost: a slower wearer has a wider cone, so putting it back makes the low
tiers reach further to the side than they do now.

## 16. The toolbar button loses a load and confuses a fresh arm

- Switched off mid delivery, the arm comes home and puts the item on the ground rather than
  back in the inventory.
- Switched on beside a ghost, the arm is made with the item already in its claw and then
  sends the claw back to its owner before setting out, as though fetching what it holds.

Neither reproduced. What is ruled out for the first: the folding arm's own drop position,
which is its rest point, and a hand cannot come as close to its base as that point is, so
the engine never reaches it and never lets go there -- checked at two tiles and at five, and
by pressing at every fourth tick through a whole delivery against the bay's own column of
eight, which never dropped anything and never lost a belt. For the second: a loaded claw was
sampled every tick from birth at six positions round its owner, including behind and beside,
and never once went inward before delivering. Wants the save, or the arm and the ghost it
happened with.

## 18. Arms get stuck out holding nothing

Two faults wear the same face. The moving one is understood and no longer sticks; the
standing-still one is neither.

### The moving one: one arm's box catches another arm's load

**What it looks like.** A claw out at the ghost it crossed to, turning and stretching to
stay exactly on it as its owner drives away, holding nothing and doing nothing, until the
swing limit gives up five seconds later.

**What is fixed.** A round whose counter and whose claw have come apart now ends rather than
waiting for a load that is never coming. That is the symptom only; the cause below still
happens, and costs a journey each time it does.

**To reproduce.** A locomotive with eight second tier arms, ghosts two tiles either side of
the rail and a tile apart, driven up and down rather than set going -- run, ease off, stop,
back up, run again. It needs two arms: one never does it, two, four and eight all do.
`test/ft/steering.lua` has the layout.

**The cause, traced tick by tick on two arms.** At tick 2619 both hold a belt, boxes at
9.9,1.7 and 10.3,2.0. At 2620 the first arm's hand is empty, its own box is still empty, and
the second arm has revived its ghost -- while still holding its own belt, untouched. The
engine empties a hand into whatever container stands at its drop position and does not ask
whose it is, so the first arm's belt went into the second arm's box and was spent on the
second arm's ghost. They were not working the same ghost; this is not a claim going astray.

Nothing is lost by it. A ghost goes up, the thief carries its own load home, and the arm it
was taken from ends its round. What it costs is a journey, and it is why a train was the
worst of it, with eight arms working one line.

**Why two boxes are ever that close.** Not because the ghosts are. A box does not stand on
the ghost: it stands where the claw is aimed, and while a claw is leading that is the lead,
the guess at where the ghost will be by the time the hand arrives. A ghost is on the tile
grid and two of them are never nearer than a tile; a lead is a continuous point that depends
on the arm's own base, on the length of its flight and on the drift, so two arms leading from
two mounts on one hull can put their leads on top of each other however far apart their
ghosts are. Measured with two arms: 0.30 to 0.32 of a tile between the boxes while the
targets were one tile apart, and four tiles apart, with both claws still on their leads. With
eight arms two boxes reached nothing at all between them.

**Why the box is out there for the whole flight.** It only has to be where the engine will
let go, and the engine is supposed to let go at the ghost, because holding_course() drops the
guess the tick before the hand arrives. The box at the lead is insurance against that not
happening in time.

Not, as it first looked, because the handover rarely happens. It happens about two and a half
ticks per delivery, which is the design: a tick is all it needs. What is true is that ninety
two of every hundred ticks of a delivery are flown on a guess, so that is almost the whole of
the time a box is standing out there to be dropped into.

**Three ways of taking the insurance away, all measured**, on the eight arm train against a
baseline of 151 belts down, none on the ground.

- **Open the box later.** The window is two and a half tiles of approach; at six tenths it is
  155 built and none on the ground, and two boxes still come within seven hundredths of each
  other. Tightening it does not separate them, because it is the leads that coincide rather
  than the approach being long.
- **No box until the aim is the ghost.** 89 built and six on the ground. The engine does let
  go on a lead often enough to matter, so the insurance is load bearing.
- **That, and the load held in the hand while the aim is a guess** -- pickup and drop set to
  the same point, which is the trick a crossing already runs on. 87 built and two on the
  ground. Waiting for the handover and only then setting out for the ghost loses the ghost.

**So a fix has to change where the release lands, not when the box appears.** A box has to be
wherever the engine may let go, and that is anywhere along a lead.

**One fix tried and taken back out.** Refusing a box's contents unless this claw was what
emptied into it. It works, and it strands the foreign belt in a box that is then taken away
with it still inside -- seven belts destroyed over a run where before nothing was. Anything
along those lines has to settle what becomes of a load that has landed in the wrong box
before it refuses to spend it.

### The standing-still one

A different fault, not fixed, and nothing above makes any difference to it.

**To reproduce.** Eight things marked for deconstruction in a ring round a character
standing still, a fourth tier arm, headless, every run, in seconds. Three are taken up, and
then a claw takes a job on a fourth, reports itself working, and never extends towards it --
a target a tile and a half off, well inside the reach, with the hand sitting at its birth
radius. The same eight offset two tiles away go in a couple of seconds.
`test/ft/taking.lua` has the layout.

What is ruled out, all measured on that reproduction:

- **Distance.** Every one of the eight is taken when it is the only thing marked, including
  the one underfoot and the ones behind.
- **The thing underfoot.** Eight round with the middle left out stalls the same way, and the
  middle on its own is taken.
- **Power.** The arm sits on a full buffer with ninety nine megajoules in the grid beside it.
- **A box with something left in it**, which take_up() waits on for ever. It is empty.
- **The box being remade under the claw.** catcher_at() teleports an existing box rather
  than making a new one.
- **A wedged inserter.** Take the arm away mid stall and the fresh one stalls identically on
  a new target.
- **The engine refusing the shape.** An inserter of the same prototype, placed by hand with
  a chest to take from, swings out to 2.34 tiles every time -- with the source empty, with
  the drop a fifth of a tile from its base, teleported to its own position every tick, and
  re-aimed every tick. All four are things the mod does to an arm and none of them freeze a
  hand.
- **The box itself.** That same bare inserter reaches the mod's own catcher, empty, as
  readily as an iron chest, and goes on doing so with four marked belts crowded round it.
- **Something sharing the pickup tile.** Destroying the neighbour mid stall does not free
  the claw.

## 20. Deconstruction leaves items behind and will not take up what is underfoot

- About one in twenty items picked up from around three and a half tiles away is left on the
  ground, without even its deconstruct marker.
- A block of nine laid round where its owner stands gives up one and leaves the other eight.
  Half of that is fixed: the claw used to pick the first one up, come in as far as a hand can
  come in, and hang there holding it for five seconds until the swing limit gave up, once per
  item. It comes home promptly now. What is left is that it then takes a job on the next one,
  reports itself working, and never extends towards it -- a target a tile and a half off, well
  inside the reach, with the hand sitting at its birth radius. That is the same shape as 18.

## 22. An arm turns too fast

A seventh is off every tier's rotation and that is as much as the swing carries without
opening the crossing horizon up to match. Measured over the whole fixture suite: a third
off, which is what was asked for, costs a claw its crossings -- a row of four two tiles
abeam went from four built on one journey to two over two, and a block of nine marked for
deconstruction wanted thirty of the harness's cycles where it had wanted six. A quarter off
still loses a walk past marked things and a bulk claw's round of four. A fifth off costs
nothing any fixture measures.

What is left is the horizon. A claw gives up a crossing it cannot make the next bearing for
in time, and that test is what a slower turn runs into; opening it up is what would let the
full third come off.
