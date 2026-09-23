# CareRoute AI

An AI healthcare navigator (not a diagnostic tool). It turns a patient's plain-language
description into a next step (self-care, clinic, or urgent care) and a clinician handoff.

## Setup

    mix setup                        # deps, DB, migrations, seeds, assets
    set -a; . ./.env; set +a         # loads GEMINI_API_KEY (gitignored)
    mix phx.server

AI provider is picked by which key is set: `GEMINI_API_KEY`, then `ANTHROPIC_API_KEY`,
else an offline stub. Tests always use the stub.

- Patient intake: http://localhost:4000/
- Clinician queue: http://localhost:4000/clinician

## Layout

| Context | Module | Role |
|---|---|---|
| Intake | `CareRoute.Intake` | Patients, conversations, transcript, symptom reports |
| Routing | `CareRoute.Routing` | Deterministic state machine on `next_action` |
| Referrals | `CareRoute.Referrals` | Referral records + `referrals` PubSub topic |
| Facilities | `CareRoute.Facilities` | Simulated facility directory, clinicians |

`CareRoute.Workers.IntakeWorker` (Oban, `ai` queue) runs each extraction call against the
JSON schema in `CareRoute.AI.IntakePrompt`, via `CareRoute.AI.Gemini` (structured output,
falls back across the models in `config :care_route, :gemini` when one is overloaded) or
`CareRoute.AI.Claude` (forced tool use). `CareRoute.AI.IntakeStub` returns the same contract offline.
