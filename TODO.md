# Outstanding, from the walk round of 2026-09-19

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
