# Demonstration runbook

Reference procedure `stromentlastung` (electricity tax relief under section 9b StromStG)
and SDLC Pilot, ticket **STROM-4**.

The demonstration has three acts. The application is shown with the defect, the tool run
is shown, and the application is shown again with the delivered fix. Everything runs in
containers, so the only prerequisite on the presenting machine is Docker.

The defect: the late-payment surcharge under section 240 (1) sentence 1 of the German
Fiscal Code is one percent per commenced month **of the amount rounded down to the next
multiple of 50 euros**. The application skips the rounding step. For the seeded case it
therefore charges 373.80 euros where the law allows 372.00 euros.

---

## 0 · Prerequisites

Docker is running, and it has room. Several gigabytes of images are built here, and a full
disk shows up as Keycloak refusing to start:

```bash
docker system df
```

## 1 · Start

One command takes the ticket and does the rest. It fetches the delivered branch, works out
which repositories it actually touched, builds those, and puts a second entrance in front
of them:

```bash
cd ~/stromentlastung/stromentlastung-platform
./scripts/demo.sh up STROM-4
```

The first run takes several minutes because the services are compiled inside the images.
Later runs reuse the layer cache. The script prints, per repository, whether it differs
from main, and it warns when the branch is not on `origin` yet and had to be taken from the
pipeline clone.

| Address | World | For STROM-4 |
| --- | --- | --- |
| http://localhost:8090 | the application on `main` | surcharge 373.80 € |
| http://localhost:8095 | the same, with the delivered branch | surcharge 372.00 € |

Sign in with `mastouri@stromentlastung.dev` and the password `stromentlastung` in both.
Other accounts are listed in the README.

Only what the branch touched exists twice. For STROM-4 that is the treasury service alone;
register, case, notices and the user interface are the very same containers in both worlds,
and each duplicated service keeps its own database with the identical seed. That is the
statement for the audience: same data, different rule.

Any other ticket works the same way, and the second world grows to whatever that branch
touched:

```bash
./scripts/demo.sh up STROM-2      # or a branch name: ./scripts/demo.sh up codegen/STROM-2
./scripts/demo.sh status
```

## 2 · Act one, the application with the defect

1. Open http://localhost:8090 and sign in.
2. Choose **Rückforderungen** in the menu.
3. The row reads Ostsee Werft GmbH, recovery 6,230.00 €, due 13 March 2026, six commenced
   months, surcharge **373.80 €**.

The sentence that carries the act: a late-payment surcharge is one percent of a multiple of
50 euros, so it is always a multiple of 50 cents. A surcharge ending in 80 cents cannot be
right.

Optional, for the audience that wants to see the data: open the case
`HZA-N-9b-2024-000002` and scroll to **Zahlungen**. The stored recovery is 6,230.00 euros
and correct. The surcharge is not stored at all, it is computed on every read. The data was
never wrong. The rule was.

## 3 · Act two, the run

Shown in the SDLC Pilot desktop application, ticket STROM-4 in project `stromentlastung@main`.

The chain reads the ticket, finds section 240 of the Fiscal Code and rule R-13 of the
domain concept, plans the change, edits the code, runs the tests, and stops before delivery
because a human decision is required. That gate is the point of the act: the tool prepares,
a person decides.

What the run produced, for reference while presenting:

| | |
| --- | --- |
| Branch | `codegen/STROM-4` |
| Repositories touched | `stromentlastung-zahlung` and `stromentlastung-e2e` |
| Change | one rounding step in `SaeumnisRechner`, applied on all three return paths |
| Tests added | one unit test for an amount not divisible by 50 euros, one Playwright case |
| Verification | executed, passed, exit code 0 |

## 4 · Act three, the application with the fix

1. Open http://localhost:8095 and sign in.
2. Choose **Rückforderungen**.
3. The same row now reads **372.00 €**, and the assessment base behind it is 6,200.00 €.

Two browser tabs side by side make the point without a single further word.

The change itself, for those who ask to see code:

```
https://github.com/aymenmastouri/stromentlastung-zahlung/compare/main...codegen/STROM-4
```

## 5 · Reset and stop

Stop both worlds and keep the databases, so a second demonstration continues where the
first one ended:

```bash
./scripts/demo.sh down
```

Back to the seeded state, dropping the databases and the generated configuration:

```bash
./scripts/demo.sh reset
```

## 6 · If something goes wrong

**A page answers 502.** A service was restarted and the gateway lost it. Both gateways
resolve their targets per request, so this should not happen; if it does, restart them:
`docker compose -p stromentlastung restart gateway gateway-fixed`.

**Sign-in fails after a rebuild of Keycloak.** The realm is imported on first start only.
Remove the container and start again: `docker compose -p stromentlastung up -d --force-recreate keycloak`.

**Both worlds show the same number.** Run `./scripts/demo.sh status`. It lists which
services exist twice and prints the surcharge behind both entrances.

**Keycloak does not start and its log says no space left on device.** The Docker virtual
machine has run out of disk. Freeing the build cache is always safe and usually enough:
`docker builder prune -f`, then `docker compose -p stromentlastung up -d --force-recreate keycloak`.
Check the headroom with `docker system df` before a demonstration.

**Port already in use.** The development stack from `scripts/stromentlastung.sh` may still
be running. Stop it with `scripts/stromentlastung.sh stop`. The two setups keep separate
databases and must not run at the same time.

**The script says no runtime repository differs.** The branch exists but changed nothing
that runs in a container, for instance only documentation or tests. There is nothing to
compare, and the demonstration has no second world.
