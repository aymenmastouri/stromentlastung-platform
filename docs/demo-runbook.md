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

Docker is running. Everything else lives in the images.

```bash
cd ~/stromentlastung/stromentlastung-platform
docker compose -p stromentlastung --profile full --profile fixed build
```

The first build takes several minutes because the four Java services and the Angular
application are compiled inside the images. Later builds reuse the layer cache.

The `fixed` profile builds its image from a checkout of the delivered branch under
`../.demo/zahlung-strom4`. Create it once:

```bash
git -C ~/stromentlastung/stromentlastung-zahlung worktree add ../.demo/zahlung-strom4 codegen/STROM-4
```

## 1 · Start

Both worlds at once:

```bash
docker compose -p stromentlastung --profile full --profile fixed up -d
```

Only the world with the defect, if the fix is not part of the session:

```bash
docker compose -p stromentlastung --profile full up -d
```

Wait until everything answers. Keycloak is the slowest, roughly half a minute. The user
interface answers long before sign-in works, so the check has to include the realm:

```bash
until curl -fsS -o /dev/null http://localhost:9091/realms/stromentlastung \
   && curl -fsS -o /dev/null http://localhost:8090/api/unternehmen/v3/api-docs \
   && curl -fsS -o /dev/null http://localhost:8095/api/zahlungen/v3/api-docs \
   && curl -fsS -o /dev/null http://localhost:8090/; do sleep 3; done; echo ready
```

| Address | World | Late-payment surcharge |
| --- | --- | --- |
| http://localhost:8090 | `main`, without the fix | 373.80 € |
| http://localhost:8095 | branch `codegen/STROM-4` | 372.00 € |

Sign in with `mastouri@stromentlastung.dev` and the password `stromentlastung` in both.
Other accounts are listed in the README.

Only the treasury service exists twice. Register, case, notices and the user interface are
the same containers in both worlds, and each treasury keeps its own database with the
identical seed. That is the statement for the audience: same data, different rule.

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

Back to the seeded state, both worlds:

```bash
docker compose -p stromentlastung --profile full --profile fixed down -v
```

`down -v` removes the database volumes, so the next start seeds again. Without `-v` the
databases survive and the demonstration keeps whatever was clicked.

Stop without losing the data:

```bash
docker compose -p stromentlastung --profile full --profile fixed stop
```

## 6 · If something goes wrong

**A page answers 502.** A service was restarted and the gateway lost it. Both gateways
resolve their targets per request, so this should not happen; if it does, restart them:
`docker compose -p stromentlastung restart gateway gateway-fixed`.

**Sign-in fails after a rebuild of Keycloak.** The realm is imported on first start only.
Remove the container and start again: `docker compose -p stromentlastung up -d --force-recreate keycloak`.

**Both worlds show the same number.** The gateways are pointing at the same treasury.
Check `docker compose -p stromentlastung ps` for `zahlung` and `zahlung-fixed`, both must
be up.

**Keycloak does not start and its log says no space left on device.** The Docker virtual
machine has run out of disk. Freeing the build cache is always safe and usually enough:
`docker builder prune -f`, then `docker compose -p stromentlastung up -d --force-recreate keycloak`.
Check the headroom with `docker system df` before a demonstration.

**Port already in use.** The development stack from `scripts/stromentlastung.sh` may still
be running. Stop it with `scripts/stromentlastung.sh stop`. The two setups keep separate
databases and must not run at the same time.
