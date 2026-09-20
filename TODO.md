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

## 13. The showroom assumes you arrive at rest, and you arrive walking

Leading turned every bay that is laid out east of its mark into a bay that starts before you
get to it. The mark is the only place a bay is measured from and it is no longer the place
the arm first sees the exhibit.

- **A ghost under your feet** is built before you can reach it to stand on it. Wants a
  teleport pad.
- **Four arms, four reaches** starts reaching before you arrive; its pad wants to be farther
  off.
- **A small arm leads too** deploys the fourth tier arm you are still wearing before you
  reach the pad that swaps it for a first tier one.
- **In reach, but not in time** delivers anyway. Walking in from the west leaves the ghost
  ahead and to the side for a long way, which is plenty of room to lead it; it only holds if
  you start level with it. It still delivers from the north half of the path, more than four
  tiles abeam.

## 14. Two showroom bays want a different kit

- **Take the reactor** should be a pad that equips it rather than a chest to rummage in.
- **What a swing costs** wants a fourth tier arm and more belts, so the battery visibly
  drains, and a pad before it that takes the reactor off.

## 16. The toolbar button loses a load and confuses a fresh arm

- Switched off mid delivery, the arm comes home and puts the item on the ground rather than
  back in the inventory.
- Switched on beside a ghost, the arm is made with the item already in its claw and then
  sends the claw back to its owner before setting out, as though fetching what it holds.

## 17. Items are dropped on the ground during ordinary work

- A tank dropped a belt about four tiles northeast after passing the end of its row.
- A spidertron dropped items while being moved about near its belts.
- **Met on the way** dropped a second belt at the player's feet a few tiles after a
  delivery that had already succeeded.

## 18. Arms get stuck out holding nothing

A claw sits at a ghost, tracking it as its owner moves, doing nothing. Seen on a spidertron
after movements in every direction, on a car once, and most often on the train, which is
probably where to reproduce it.

## 19. A delivery lands without the claw getting there

**A row in one trip** builds its third and fourth ghosts without the claw travelling to
them, finishing over a tile short of the fourth.

## 20. Deconstruction leaves items behind and will not take up what is underfoot

- About one in twenty items picked up from around three and a half tiles away is left on the
  ground, without even its deconstruct marker.
- The nine items the player is standing on are never picked up at all.

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
