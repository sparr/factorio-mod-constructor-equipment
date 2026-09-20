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

Done for one delivery from rest. An arm works out where its target will be by the time its
hand could get there, holds the claw on that point as its owner carries it along, and drops
the guess for the thing itself the moment it is really in reach. A ghost that is in reach for
forty ticks against a forty three tick reach could not be built at all before and is built
now. Every tier leads; the first one meets things three times its own reach away.

What is left.

**A claw crossing from one ghost to the next.** A round that works through several without
coming home is untested on anything that moves. Every crossing test there is has its wearer
standing still, and a crossing claw is an arm that is not at rest, so this wants the next
item first. Note that crossing starts at one item per trip and only begins once inserter
capacity has been researched, so the whole suite runs single trips today.

**An arm that is not at rest.** reach.intercept already takes where the hand is, and
redirect works out a fresh course from it, but nothing exercises either while its owner is
moving.

**The search is wider than it needs to be.** It draws the circle round a capsule that
assumes full stretch from the first tick. What an arm can really meet is a cone, and
reach.meets and reach.chain measure it exactly, but only meets is wired and only for judging
a candidate rather than for finding one. Measured on a fourth tier arm: 211 candidates and
0.084ms against 116 and 0.036ms for the cone's own circle. An area can also be given an
orientation, which is worth more than a chain of circles once a cone is long and thin -- a
car's cone returns 330 candidates in one call against 435 in four. Wants a quiet machine to
measure properly.

**Turning is not modelled.** reach.intercept knows nothing about the bearing a claw would
have to swing through, so it can hand back a lead the claw cannot rotate onto in time. It
costs nothing that has been measured -- a circling car leaves its claw 178 degrees behind
its aim and still builds more than one driving straight -- because an arm is already coming
and going as fast as it can. Worth knowing rather than worth fixing, until something says
otherwise.

**Two players can reach for the same ghost.** claims() is built from one wearer's own arms,
so nothing stops a second player's arm setting off for something already spoken for. It
predates any of this, and leading makes it likelier by lengthening how long an arm is
committed.

**The walking penalty is switched off.** tiers.SLOWS, with thirty tests skipped behind it.
It is not only a cost: a slower wearer has a wider cone, so putting it back makes the low
tiers reach further to the side than they do now.
