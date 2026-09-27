# CareRoute demo script

Two scenarios, about 2½ minutes together: a **routine** case that ends in a clinic
referral the clinician picks up live, and an **urgent** case where one sentence
jumps straight to emergency care.

What to expect at each step comes from a rehearsal run against Gemini on
2026-09-27. The AI's exact wording varies from run to run; the flow doesn't.

## Before you start (30 minutes ahead)

- [ ] **Reset the data.** Deployed: `fly ssh console -C '/app/bin/care_route eval "CareRoute.Release.demo_reset()"'`.
      Local: `mix care_route.demo_reset --yes`.
- [ ] **Paid AI key in place** (`GEMINI_API_KEY` on a paid plan, ideally `ANTHROPIC_API_KEY`
      too as automatic backup). On the free tier each answer took 9–36 seconds in rehearsal.
- [ ] **Two screens.** The phone is the patient. The laptop is the clinician: open
      `/clinician`, log in (staff credentials from `.env`), leave it on the queue.
- [ ] **Phone permissions granted once, beforehand**, so no pop-ups appear on stage:
      open the chat and tap the mic once (allow the microphone); open a results page
      (allow or deny location — outside Nairobi, deny it, or the page shows an
      "outside the demo area" notice).
- [ ] Phone volume up if you'll show questions being read aloud; on a hotspot, not venue Wi-Fi.
- [ ] Optional: "Add to Home Screen" on the phone so CareRoute opens full-screen like an app.

## Scenario A — routine: feverish toddler → clinic referral (≈ 1½ min)

**On the phone**

1. Landing page → **Describe what's going on**.
2. Start screen: English · Name `Amina` · Age `3` · tick the consent box → **Start**.
3. Type:
   > My 3-year-old daughter has had a fever for two days.

   *Expect:* a single follow-up, e.g. "Is she drinking plenty of fluids and having wet
   diapers as usual?" The progress bar moves.
4. **Answer by voice** — tap the mic and say (it covers what the AI tends to ask next):
   > She's drinking well and has normal wet diapers, she's breathing normally, and she's still playing, just a bit tired.

   Show the words appearing in the box, then press send. The bubble gets a small mic mark.
5. If it asks anything else, answer in one line:
   > No rash, no vomiting, and her temperature is around 38.5.

   *Expect:* "Thanks — that's everything I need…" with **See my recommendation**.
6. **See my recommendation** → *Expect:* **Clinic visit**, "Moderate urgency · see a
   clinician soon", reasons that reassure (she's drinking and playing), and three
   warning signs (breathing, unusual sleepiness, dehydration).
   *(If it comes back as Self-care instead, carry on — "Find a clinic near me" still works.)*
7. Scroll to the map → tap **Request referral** on **Kilimani Community Clinic**.
   *Expect:* "Referral sent to Kilimani Community Clinic…", the map zooms to it.

**On the laptop (clinician)**

8. The referral appears at the top of the queue with a pulsing dot and a notice.
9. Open it: the **AI handoff summary** fills in within a few seconds (chief complaint,
   history, "Red flags: none reported", what to assess), then the question-and-answer
   transcript — point at the **spoken** tag on the voice answer.
10. **Accept referral** → the status changes, "Avg. response time" updates.

## Scenario B — urgent: one sentence to emergency care (≈ 30 s)

1. On the phone, **Start over** (top right) → Start screen → tick consent → **Start**.
2. Type:
   > My father is 58. He has chest pain spreading to his left arm and he is sweating.

   *Expect (≈ 4 s):* no follow-up questions — "Based on what you've shared, please seek
   urgent care now… call 999 or 112 now." The progress bar turns red.
3. **See my recommendation** → **Urgent care**, "High urgency · seek care now", the
   danger signs in red, and a big red **Call 999** button first. Hospitals only, nearest first.
4. **Send referral to a clinician** (one tap, nearest hospital).
5. On the laptop: the new referral jumps to the **top** of the queue — **Urgent** sorts
   above everything else.

## Optional extras (if you have time)

- **Kiswahili:** Start screen → Kiswahili; the whole page switches, including the
  emergency banner ("Piga 999"). One line to try: *"Mtoto wangu ana homa kwa siku mbili."*
- **Read aloud:** the speaker button in the chat header reads each question (only shown
  when the phone has a voice for the language).
- **Network overview:** `/admin` — live counts and the level-of-care split.

## 2½-minute video / pitch timeline

| Time | Show | Say |
|---|---|---|
| 0:00–0:15 | Landing page | "When you're unwell, the hardest question is often *where* to go. CareRoute is an AI navigator — not an AI doctor." |
| 0:15–1:25 | Scenario A on the phone | Adaptive questions, answering by voice, a clear recommendation with warning signs, nearby facilities on a map. |
| 1:25–1:50 | Clinician laptop | "The clinic sees the referral instantly, with an AI handoff summary and the full transcript — triage in seconds." |
| 1:50–2:15 | Scenario B | "Danger signs always win: one sentence and CareRoute sends you to emergency care." |
| 2:15–2:30 | Results page safety note | "It never diagnoses — the AI extracts, code decides, and clinicians see the evidence." |

## If something goes wrong

| Problem | What to do |
|---|---|
| An answer takes long | Narrate: "it's working out the next most useful question." Free-tier answers took up to 36 s in rehearsal — use a paid key. |
| "I'm having trouble connecting… Try again" | Tap **Try again**. It re-asks the AI with the same answer. |
| Summary shows "Summary unavailable" | Tap **Retry summary**; the transcript and rationale are already there to talk through. |
| The AI service is down entirely | Switch to the offline stand-in and restart: `fly secrets set AI_PROVIDER=stub` (locally `AI_PROVIDER=stub mix phx.server`). The stand-in asks "How long…", "How severe…", then about breathing/chest pain/confusion; words like *breathing* or *chest* trigger the urgent path. Afterwards: `fly secrets unset AI_PROVIDER`. |
| Venue network drops | Switch the phone and laptop to the phone's hotspot. |
| Browser asks for the staff login | Credentials are in `.env` (`STAFF_USERNAME` / `STAFF_PASSWORD`). |
| Mic button missing | The browser has no speech recognition (e.g. Firefox) — use Chrome, or type. |
