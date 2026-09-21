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

## 20. Deconstruction leaves items behind

About one in twenty items picked up from around three and a half tiles away is left on the
ground, without even its deconstruct marker.

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
