# Outstanding, from the walk round of 2026-09-18

Removed from this list as they are fixed. Numbers are stable so they can be referred to, so
the gaps are the ones already done: 2 and 3 were the tank's and the car's arms, 6 was the
extension and rotation speeds -- changed and then put back, once arms were pointed and the
change turned out to have been paying for a cost that no longer exists -- and 16 was
pointing an arm at what it is reaching for.

Pointing carried four more off with it, which is what the walk round's dispatch and
delivery complaints turned out to be: 7 was the wrong arm going first, 8 was an arm that
did nothing, 9 was the bulk claw coming home mid round, and 10 was an underground pair
going on the floor. 13 was not pointing at all -- a claw that deployed and then stood there
was its box landing on the neighbour's tile, where an inserter cannot see it. 11 was an arm
setting off for something it had nowhere to put, and 17 was a reach that had run over its
limit turning to another ghost instead of giving up, every tick, for ever.

Two of them were not faults. 12, the arm emptying the chest it had just built, does not
happen: watched for two thousand ticks, the new chest keeps all 3200 plates it took while
the claw clears the shed around it, and there is a test saying so now. 14, the battery
refilling itself, is the claw handing its buffer back as it folds away -- measured, the
armour rises by exactly one buffer and the armour and the claw together rise by nothing at
all. The showroom says so now, and a test holds the ledger to it.

## 1. "Four arms, four reaches": the words overlap

The bay's description text runs down into the "STAND HERE" text below it.

## 4. Spidertron: the claws are drawn over the body

The claw items draw on top of the spidertron. Reverse that if it can be done without side
effects.

## 5. Locomotive: the south side arms are based too far south

Base them at the foot of the wheels, and lift them to draw above the wheels.

## 15. "The toolbar button": the claw does not arrive

It returns to a short distance from its owner, the item disappears early, and the arm warps
to the stowed position rather than arriving.

## 18. Can an arm be pointed more finely than the four cardinals?

Pointing an arm at what it is reaching for rounds its bearing to the nearest quarter,
because `direction` on an inserter takes the four cardinals and truncates anything else.
That leaves an eighth of a turn to swing through at worst, which hides behind the extension
at any reach worth making and does not at a short one.

Look for the prototype flag that lets an entity be built facing eight or sixteen ways
rather than four, and whether an inserter can carry it. If it can, an arm can be pointed to
within a sixteenth and the residual turn goes away entirely.

## 19. Point an arm without building it again

Pointing one now means destroying it and building a new one facing the right way, because
setting `direction` on an inserter that already exists does not move its hand. Worth trying
instead: nudge the claw's own position a few quantums -- a quantum is 1/256 of a tile --
toward where it is being sent, which may make the engine recompute the rotation on the
spot. If it does, an arm is re-pointed without being rebuilt, which costs nothing, keeps
whatever is in the hand, and would work mid round as well as at a departure.
