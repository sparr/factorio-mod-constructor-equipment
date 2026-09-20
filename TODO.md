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

A claw sits at a ghost, tracking it as its owner moves, doing nothing. Seen on a spidertron
after movements in every direction, on a car once, and most often on the train.

There is a standing-still version in 20 that reproduces every run, headless, in seconds:
eight things marked in a ring round a character. Three are taken up, then a claw takes a job
on a fourth, reports itself working, and never extends towards it. The same eight offset two
tiles away go in a couple of seconds.

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
- **Something sharing the pickup tile.** The box stands 0.7 of a tile off its target, being
  lifted the way everything else is, so on packed work a neighbour's own tile is under it
  and a transport belt is a perfectly good inserter source. Destroying the neighbour mid
  stall does not free the claw, and on a second run nothing contained the pickup point at
  all.
- **The box itself.** A bare inserter told to pick up from the mod's own catcher, empty,
  reaches it as readily as it reaches an iron chest, and goes on doing so with four marked
  belts crowded round it.

So the engine is willing and the arm is not wedged, and what the mod does every tick is not
what stops it. What is left is something about the state the mod leaves a fetch in after a
few of them have been done nearby.

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

Take a third off the rotation speed. Not done: measured, a third is more than the swing can
carry. A claw that carries several stops crossing altogether at walking pace -- a row of
four two tiles abeam went from four built on one journey to two over two, and no layout
tried still crossed -- and a block of nine marked for deconstruction went from wanting six
of the harness's cycles to wanting thirty, because a claw that cannot make the next bearing
in time comes home rather than crossing and the turn is paid for twice. A walk past three
scattered ghosts lost the last of the three. Wants a smaller reduction, or the crossing
horizon opened up to match, and the numbers above are at the edge of the noise in those
fixtures either way.
