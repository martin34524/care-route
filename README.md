# CareRoute AI

An AI healthcare navigator (not a diagnostic tool). It turns a patient's plain-language
description into a next step (self-care, clinic, or urgent care) and a clinician handoff.

## Setup

    mix setup                        # deps, DB, migrations, seeds, assets
    set -a; . ./.env; set +a         # loads GEMINI_API_KEY (gitignored)
    mix phx.server

Before a demo rehearsal, `mix care_route.demo_reset --yes` clears all patient data
and reseeds facilities (without `--yes` it only shows what it would delete).

`/clinician` and `/admin` use basic auth from `STAFF_USERNAME` / `STAFF_PASSWORD`
(required in production; if unset in dev they're open). Put them in `.env`.

AI provider is picked by which key is set: `GEMINI_API_KEY`, then `ANTHROPIC_API_KEY`,
else an offline stub. Tests always use the stub.

- Landing page: http://localhost:4000/ (intake starts at /start; results at /intake/:id/results)
- Clinician queue: http://localhost:4000/clinician

## Layout

| Context | Module | Role |
|---|---|---|
| Intake | `CareRoute.Intake` | Patients, conversations, transcript, symptom reports |
| Routing | `CareRoute.Routing` | Deterministic state machine on `next_action` |
| Referrals | `CareRoute.Referrals` | Referral records + `referrals` PubSub topic |
| Facilities | `CareRoute.Facilities` | Simulated facility directory (Nairobi coordinates), distances, clinicians |

`CareRoute.Workers.IntakeWorker` (Oban, `ai` queue) runs each extraction call against the
JSON schema in `CareRoute.AI.IntakePrompt`, via `CareRoute.AI.Gemini` (structured output,
falls back across the models in `config :care_route, :gemini` when one is overloaded) or
`CareRoute.AI.Claude` (forced tool use). `CareRoute.AI.IntakeStub` returns the same contract offline.

### Facility map

The patient's result screen shows the offered facilities on a Leaflet map
(`assets/js/hooks/facility_map.js`, Leaflet 1.9.4 vendored in `assets/vendor/leaflet`,
OpenStreetMap tiles). If the browser shares a location within 100 km of the network,
facilities are re-sorted by real distance; otherwise distances are from the demo origin
in `config :care_route, :demo_origin`. Re-run `mix run priv/repo/seeds.exs` any time; it
updates facilities in place.
