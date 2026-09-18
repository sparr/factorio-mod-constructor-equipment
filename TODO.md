# Outstanding, from the walk round of 2026-09-18

Removed from this list as they are fixed. Numbers are stable so they can be referred to, so
the gaps are the ones already done: 2 and 3 were the tank's and the car's arms, 6 was the
extension and rotation speeds -- changed and then put back, once arms were pointed and the
change turned out to have been paying for a cost that no longer exists -- and 16 was
pointing an arm at what it is reaching for.

## 1. "Four arms, four reaches": the words overlap

The bay's description text runs down into the "STAND HERE" text below it.

## 4. Spidertron: the claws are drawn over the body

The claw items draw on top of the spidertron. Reverse that if it can be done without side
effects.

## 5. Locomotive: the south side arms are based too far south

Base them at the foot of the wheels, and lift them to draw above the wheels.

## 7. "Four arms, four reaches": the wrong arm goes first

After the teleport the tier 4 arm took the closest belt, then tier 2 and tier 3 took the
next two, and then tier 4 took the last.

## 8. "One arm for every copy": one arm does nothing

The tier 1 arm did no work at all, with the closest belt left unbuilt while everything else
went up.

## 9. "The bulk claw": it comes home mid round

Goes out, builds one, turns to a second, and comes home without building it. Unchanged by
the arc fix.

## 10. "An underground pair": both ends are dropped

Still drops both yellow undergrounds on the floor and makes a separate trip to fetch them.

## 11. "Pockets full": it deploys with nowhere to put anything

The arm deploys even with no room, and should stay in. Once space is cleared it stays out
and does nothing, while still slowing its owner. Un-marking any one belt sets it going on
the rest, which smells like a stale search.

## 12. "A chest downgraded": it empties the new chest

After picking up some of the shed, the arm goes on to empty the chest it just built, once
that is the nearest target.

## 13. "A thing taken up": it waits before starting

The arm deploys and then stands there for seconds before doing anything.

## 14. "What a swing costs": the battery refills itself

With no reactor in the armour, the charge still goes back up.

## 15. "The toolbar button": the claw does not arrive

It returns to a short distance from its owner, the item disappears early, and the arm warps
to the stowed position rather than arriving.

## 17. A round at the very edge of the range gets stuck on one ghost

Twelve ghosts on a circle of exactly five tiles, a fourth tier claw with every capacity
bonus researched: it builds five of them and then stands with six belts in its hand, aimed
at the sixth, for as long as it has been watched -- eight hundred ticks -- neither
delivering nor coming home.

Not new, and not the pointing. The same twelve measured the same way before that change:
seven left standing after two thousand four hundred ticks either way. What did change is
the same twelve close in, which went from five still standing after 2400 ticks to the whole
dozen inside 340.

Nothing about the reach itself is impossible. Measured on a bare fourth tier inserter with
a box at the drop: a load taken 4.8 tiles to the far side of an arm built facing the other
way arrives on tick 94, which is the half turn and nothing else.

It reads like the swing limit. By then the reach has run over it, and advance() answers a
reach that has run over by redirecting rather than giving up, while redirect() leaves
job.started where it was -- so the next tick has run over too, and it redirects again,
every tick, for ever. Unverified: the behaviour above is what was measured, that paragraph
is where to look.
