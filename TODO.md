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

19 is a no, and measured rather than assumed: a hand resting north was asked to face east
eleven ways -- setting direction, writing orientation, rotate(), nudging the entity a
quantum, four quantums and a sixteenth of a tile, teleporting it forty tiles away and back,
and cloning it -- and every one left the hand creeping round at its own speed, tick for
tick identical to doing nothing. The rotation is the hand's own state and only building the
entity again resets it. That is written down in point(), where the decision lives.

18 is in: `building-direction-16-way` is a real entity flag, an inserter takes it, and with
it all sixteen directions stick and the hand starts exactly on its bearing. An arm is
pointed to the nearest sixteenth now. It buys nothing at a long reach, where the extension
already hid the quarter-turn rounding, and it buys the short ones: a fourth tier arm
reaching one tile ran 5 to 17 ticks depending on the bearing and now runs 6 to 10, with the
four diagonals -- 15, 17, 15 and 14 ticks -- coming down to 7, 9, 10 and 9.

1 was the showroom rather than the mod, and was eight bays rather than one: a bay's note
grows downwards and its mark's words sat a fixed distance below the mark, so any note over
three lines was written through them. The marks' words go under the bay's now. 15 was a
claw called home early -- which an ordinary reach does on purpose, so the next one can
start sooner, and a fold has no next one.

Two of them were not faults. 12, the arm emptying the chest it had just built, does not
happen: watched for two thousand ticks, the new chest keeps all 3200 plates it took while
the claw clears the shed around it, and there is a test saying so now. 14, the battery
refilling itself, is the claw handing its buffer back as it folds away -- measured, the
armour rises by exactly one buffer and the armour and the claw together rise by nothing at
all. The showroom says so now, and a test holds the ledger to it.

## 4. Spidertron: the claws are drawn over the body

The claw items draw on top of the spidertron. Reverse that if it can be done without side
effects.

## 5. Locomotive: the south side arms are based too far south

Base them at the foot of the wheels, and lift them to draw above the wheels.
