# Threshold — refined plan (v2)

Revises [`threshold-concept.md`](threshold-concept.md), which is kept unchanged next to this file. Where the two differ, this file wins. Written 2026-10-26.

## 1. In one page

Threshold is a belief layer on top of an ordinary camera pipeline. It keeps one probabilistic model of the property (who is where, which objects are at rest where), forecasts where people are heading, and chooses actions by cost: notify, switch on a light, look closer, or stay quiet. Every alert explains itself and takes one tap of feedback.

What this version changes:

1. **No radar. The camera is the only sensor.** The cheap always-on tier is gone, so "energy as a decision" moves to the two places where it still works: compute tiers on the hub, and the light, which is switched on only when the belief says it is worth it. Cameras are wired (PoE). Solar is dropped.
2. **The map is optional.** The belief lives on a *zone graph* drawn on the camera image. A metric map, from a 4-point calibration done with the camera alone, is an upgrade for display and speed features, not a dependency.
3. **No IR. Night vision is measured, not assumed.** Phase 0 finds, for the real camera in the real yard, the light level below which person detection and then face matching stop working. Light is the fallback. IR stays off.
4. **Build on Frigate and build only the new part.** Detection, tracking, zones, recording, pre-roll and face matching already exist. Threshold is the layer above them.
5. **"Intent" becomes "forecast of observable outcomes".** The system predicts "reaches the porch", "touches the bike", "leaves with it". The logs label those automatically. Nobody can label intent.
6. **Evaluation is designed for one site.** Episodes are labelled once, then every policy (baselines, ablations, the full system) is replayed over the same footage. The headline figure is false alerts per 24 h against staged recall.
7. **Scope has cut lines.** A core that gives a defensible result, then an ordered stretch list.

Two ideas still carry the project.
**Custody:** an object at rest appears or disappears, and the change is attributed to whoever was in reach. The same computation gives a theft or a delivery, depending on direction and on who.
**Cost-aware action:** every action, including spending compute or light, is priced in the same unit as a false alert.

**Is a no-IR camera enough at night?** Partly. Expect it to be enough to *detect* people and vehicles wherever moonlight, a streetlamp or a house light reaches the scene, and *not* enough to recognise *faces* in the dark parts of a yard. This is the largest technical risk in the plan, so it comes first and has a pass/fail gate (section 4).

## 2. Claim, metric, definitions

**Claim.** At the same recall on staged incidents, Threshold raises fewer false alerts per 24 h than the best hand-tuned detector-plus-zones setup, on the same camera and the same days.

**Why this metric.** If most alerts are not worth reading, people turn notifications off and detection accuracy stops mattering. Vendors do not publish this number. The household feels it.

Definitions. Freeze them before any evaluation data is collected.

| Term | Meaning |
|---|---|
| Episode | From the first person track or custody event on the property to 60 s after the last one ends. All metrics are per episode. |
| Alert-worthy | A human label on the episode (`yes`, `no`, `unsure`), given blind, without seeing what any policy did. `unsure` is reported but never counted as a false alert. |
| Alert | A push that interrupts. Digest entries are not alerts. |
| False alert | An alert raised on an episode labelled `no`. |
| Recall | On the staged set: the share of `yes` episodes that raised an alert within T seconds of the scenario's defining moment, which the protocol sets per scenario (for example T = 10 s after a hand touches the bike). |
| Operating point | Chosen on the calibration split to reach 90% recall, then applied unchanged to the test split and to the natural days. |

## 3. Architecture and hardware

```
 camera(s) ─RTSP─► Frigate ──events (MQTT), snapshots, clips──┐
                   detect · track · zones · record · face     │
 lux logger ─────────────────────MQTT─────────────────────────┤
 phone presence ──────────────────────────────────────────────┤
 slot classifier  (reads Frigate snapshots) ──────────────────┤
 health prober ───────────────────────────────────────────────┤
                                                              ▼
                              Threshold core (one Python process)
                              ├─ event log  SQLite, hash-chained, replayable
                              ├─ belief     zone graph · people · slots · house
                              ├─ forecast   where is this track going
                              └─ decide     cost → notify · light · look closer · log
                                         │
          web app (PWA) ◄────────────────┴────► ntfy / Web Push ──► phone
          same app on a wall tablet (kiosk mode, optional)
```

**Rule: Threshold consumes events, not pixels.** Everything the belief knows arrives as a timestamped record from an *evidence provider* (Frigate, the slot classifier, the lux logger, phone presence, the health prober). A decision is a pure function of the log. So any recorded week can be replayed under any policy in minutes, and a bad week of perception can be told apart from a bad belief.

**Hub.** Used mini PC with an Intel iGPU (6th generation or newer, or N100/N150), 8 GB RAM, and an SSD of 500 GB–1 TB. Frigate's hardware page lists about 15 ms per inference for MobileNetV2 and 25–30 ms for 320-px YOLO variants on an N100, which is ample for one or two cameras. A second network port lets the cameras sit on an isolated network. Stack: Frigate, Mosquitto and ntfy in Docker Compose; Python (asyncio) with SQLite in WAL mode; FastAPI and a small PWA.

**Cameras.** PoE IP cameras with a large sensor and a fast lens (checklist in section 4). One camera first. A home-built board node (Pi plus sensor module) is possible later, but the weatherproofing and reliability work is not worth it now: the pipeline only needs an RTSP stream.

**Side sensors (cheap, no radar).** A lux logger (TSL2591 on an ESP32, about €15) publishing to MQTT. It is the instrument for Phase 0 and a permanent input to the belief. Phone presence on the home network, opt-in per household member. A metered plug on the hub for power.

## 4. Night vision without IR

### What to expect

| Light | Approximate illuminance |
|---|---|
| Overcast, no moon | 0.0001 lx |
| Clear, no moon | 0.002 lx |
| Full moon | 0.1–0.3 lx |
| Residential street, at the road | 2–10 lx |
| Near a porch or house light | 5–50 lx |

These are orders of magnitude, not measurements. A spec sheet's "minimum illumination" is quoted at a slow shutter and a loose image-quality bar. As a rule of thumb, a detector that must see a walking person at 1/30 s needs 10–100 times more light than that number. Light collected per pixel scales with pixel area, with exposure time and with 1/(f-number)². An f/1.0 lens collects 4× the light of f/2.0, and a 1/1.8" sensor has about 2.4× the area of a 1/2.8" sensor, so at the same resolution each pixel collects about 2.4× the light. Sensor size, lens speed and the longest shutter allowed matter more than megapixels.

Detection degrades gracefully with noise. Faces do not: matching needs a sharp, evenly lit, front-facing face. Frigate's own guidance is to avoid IR and grayscale images, because its embedding models are trained on color. That is a real argument for no-IR, and it also means a face at night needs actual light on it.

Face size, for a face about 0.15 m wide. The 60 px figure is a rule of thumb to be replaced by the measured curve:

| Camera | Distance at which a face is 60 px wide |
|---|---|
| 1080p, 100° lens | about 2 m |
| 4K, 100° lens | about 4 m |
| 4K, 70° lens | about 7 m |

So identity is a *choke-point* job. Put the identity camera where people walk toward it (door or gate, facing outward), 2.2–2.8 m up. Elsewhere on the property, the belief carries identity along the track instead.

### Phase 0 experiment: the night capability curve

1. Mount the camera where it will live. Turn IR and any built-in white LED off and force color mode. Cap the shutter at 1/30 s (try 1/15 s as a test), raise the gain limit, and set 3D noise reduction to low or medium (heavy 3D noise reduction smears moving people).
2. Log lux next to the scene every 10 s for at least three nights that differ: moon, cloud, street lights, house lights.
3. Stage walk-throughs: 4 distances × 2 clothing tones (dark, light) × 5 passes, at three or more light levels. Record the raw main and sub streams.
4. Offline, run the same detector (and the face matcher, at the identity camera) over the recordings. Plot detection rate and face-match rate against lux, per distance.
5. Also look for: headlights sweeping the scene, insects at the lens, and auto-exposure swings that create ghost detections.

**Gate G0** (example thresholds, adjust to taste): a person is detected in at least 95% of frames within 10 m above 0.05 lx; a resident's face matches in at least 80% of passes within 4 m at the identity camera above 1 lx. The output is a table of *where the system may claim what*. The belief accepts face evidence only above the lux where it was shown to work.

### If the curve is bad: the ladder

Stop at the first step that fixes it.

1. Re-aim or move the camera so existing light is in view and headlights are out of it.
2. Tune the camera's image settings: shutter cap, gain, noise reduction, binning.
3. Swap the optics: a faster lens, a larger sensor.
4. Add visible light: a dim warm path light that is always on (1–3 W), and/or a shielded warm-white floodlight that the hub switches on through a relay or smart plug. The light is also a deterrent. Allow about 2 s for the relay and for auto-exposure to settle. The first frames are in the dark, so first detection must work without it.
5. Last resort: use the camera's own IR as a *detect-only* mode (monochrome, no identity), marked as low-evidence in the belief.

### Camera checklist

- RTSP or ONVIF, H.264 or H.265, a separate low-resolution sub-stream, works with no cloud account.
- IR and white LEDs can be switched off. Manual controls for maximum shutter, maximum gain, WDR and noise reduction.
- Sensor 1/1.8" or larger (STARVIS or STARVIS 2 class). 4K, so a 2×2-binned image still has 1080p. Lens f/1.6 or faster.
- PoE. Firmware can be blocked from the internet. An SD card slot, enabled as a last-resort record if the hub is down.
- Judge the *night clip*, not the spec sheet. Record the same walk-through on any candidate before buying more than one.

## 5. Believe

One state, four parts, all updated from the same event stream.

**Places.** A zone graph: zones drawn on the image, an *off-property* node, and *unseen* nodes for blind spots (behind the shed, inside the house). Edges carry transit-time distributions learned from the log. A person who walks behind the garage is still on the property: their probability mass moves to the unseen node and decays. This is what stops a "new person" alert every time a track resets.

**People.** Per person: a zone, and an identity from {each resident, known guest, unrecognised, unverified}. `unverified` means no usable face was seen. `unrecognised` means a good face was seen and matched nobody. At night the default is `unverified`, and treating it like `unrecognised` would alert on every resident coming home with a hood up.
Evidence:
- Face: Frigate's `sub_label` and score, accepted only when a quality gate (face size, blur, lux) passes, and mapped to a likelihood ratio using genuine and impostor scores from the household's own enrolment. The score is a running average, not a probability.
- Phone presence and normalcy, both as priors.
- Appearance of today's clothes, only if the development days show identity gaps.

**Slots.** Declared places where an object rests: bike rack, doorstep, shed door, bin spot, car spot. Each has contents from {empty, bike, parcel, bin, other}. Evidence: a small classifier on the slot crop (30–100 crops per state, day and night, MobileNet class); change against a reference crop as a class-agnostic second opinion; and a visibility estimate. Frigate 0.17 has built-in state classification, but a bug report says it did not publish to MQTT on 0.17.0 (section 15), so the default is a small classifier of Threshold's own, run on snapshots from Frigate's HTTP API: 1 Hz while a person is in reach, every 10 s otherwise.

**House.** Occupied or not, from phones on the network, door transitions and a car in the drive. Certainty decays without new evidence.

**System health.** Stream heartbeat, frozen or black frame, scene shift. Treated as evidence about everything above.

### The queries

"One belief" means these questions are read from the same state, not answered by separate detectors with a rule file on top.

| Question | Read from |
|---|---|
| Where is everyone? | places × people |
| Is this track the person who vanished 20 s ago? | places (transit time) × people (identity, appearance) |
| Who is this? | people: face, phones, normalcy |
| Who changed that object? | slots × who was in reach |
| Is anyone home? | house |

To be exact about it: this is several small filters sharing one clock and one log, not one joint model. The claim is that the same evidence updates all of them and the queries read the same state. The only coupling between parts is the custodian gate between people and slots.

### Rules that make it work

1. **Absence counts only where it can be seen.** Each slot has a visibility estimate from lux, occlusion and camera health. When it is low, belief drifts toward "unknown", never to "empty". This prevents "bike gone" at 03:00 because the bike is simply too dark to see.
2. **Contents change only with a custodian in reach.** A change with nobody in reach is one of two things. With low visibility or a lighting change, it is an artifact: log it. With high visibility and stable light, it is a *missed detection*, which is the worst case: alert as "bike gone, nobody seen".
3. **Two independent cues to suppress.** A face match lowers severity. It never silences a custody loss on its own. A resident who matches on face and whose phone is at home passes. A face match alone does not, so a printed photo cannot switch the system off.
4. **Identity travels along the track.** Faces are rare. The person seen at the door at 17:00 is the same person in the yard later. Appearance vectors of *household members* expire after 24 h. Those of *unrecognised people* live only for the episode (section 13).
5. **Usually there are zero or one people.** Association across occlusion or cameras is easy with a tiny gallery. The hard cases are two or more people, so the tests target those.
6. **Normalcy is a prior, not a detector.** Smoothed counts per zone × time bin × day type, from the first days. A 40 s dwell is unremarkable at 18:00 and rare at 03:00 without any extra model.

### Optional metric map, from the camera alone

Skip it and nothing else breaks. If wanted:

1. Pick 4–6 ground points in view (cones, tape marks, paving joints, door corners). Measure the distances between them with a tape and place them on a sketch or a satellite screenshot.
2. Click the same points in a still frame. If the lens is wide, undistort first (a printed checkerboard, ten minutes).
3. Fit a homography (RANSAC). Hold two points out and report the error in metres. A typical result is 0.3–1 m at 5–15 m, but measure it, and accept the map only if it is good enough for the zones that matter. Use the bottom centre of the box as the foot point. The ground must be roughly flat.
4. Check drift daily by feature-matching a reference frame. If the view has shifted, raise `health.camera_moved` and re-fit, or fall back to zones.
5. What it buys: a to-scale map on the panel, speed and heading features, distance to slots. Custody, identity and alerts do not need it. Frigate's zone speed estimation already uses a 4-point perspective fit with real side lengths, so a first version may be a configuration change.

### Build order within Believe

1. Zones and dwell from Frigate events.
2. Identity posterior.
3. Slots and custody.
4. Unseen nodes.
5. House.
6. Cross-camera association (stretch).

## 6. Predict

**Forecast observable outcomes, not intent.** From a partial track, estimate P(reaches zone Z within T s), P(touches slot S), P(leaves with the object). The future of every logged track is its own label, so training data accumulates with no annotation. Staged episodes add the rare outcomes. Alert text says what is observed and what is likely next ("heading for the bike rack"), never what someone is thinking.

- **Core (v0).** A Markov chain on the zone graph, conditioned on time of day and identity class, plus a dwell-time hazard. It feeds the decision (heading toward a slot that holds something raises urgency) and is scored by log-loss.
- **Stretch (the study).** The earliness curve: truncate stored tracks at k seconds or at a fraction of their length, and measure accuracy, Brier score and calibration. Models in order: prior; Markov; logistic regression or gradient-boosted trees on speed, heading and dwell; a small GRU only if the previous step leaves headroom. Baselines: prior frequency, last zone persists, constant velocity. Validate leave-one-participant-out.
- **Offline first.** Frigate's MQTT events are not per frame: an update fires on a better snapshot or a zone change. Check whether its event API returns per-frame path data. If not, run a small tracker on the sub-stream as a sidecar (5 fps is enough). Do the science offline. Making it live is an engineering step afterwards.
- **Expect small gains on natural traffic**, because people mostly walk to the door. The contrast to show is staged "walk past" against "go to the bike", where the lead time is seconds, not minutes. Claim only what the leave-one-participant-out result supports.

## 7. Act

**Actions** (small and discrete): `log`, `digest`, `notify-quiet`, `notify-urgent`, `light-on`, `look-closer(camera, tier)`, `ask` (request a rating). A deterrent sound is a stretch item: it needs a speaker and consideration for neighbours.

**The alert decision is a threshold in disguise.** Be explicit about it. Staged data is roughly half incidents. Real life is a tiny fraction of a percent. So:

1. Use staged data for **recall** and for the score distribution of incidents.
2. Use natural data for the score distribution of non-incidents. That is what gives false alerts per 24 h at any threshold.
3. The household states one number: **false alerts per day it will tolerate** (default 0.5, editable). The operating point follows from the natural-data curve, and the resulting staged recall is reported. In the evaluation (section 2) the same curve is read the other way round: fix recall at 90% and report false alerts per day.
4. Do not show a probability of "intent". Show *rarity*: "scored higher than 997 of the 1,000 episodes seen here", plus the reasons. Show rarity only once about 200 episodes exist.

**Where costs and expected value do real work** is the non-binary choice: digest, quiet or urgent; light or no light; look closer or not. Costs share one unit, the **alert-equivalent** (1 = one unnecessary interrupting alert). Starting values, editable by the household: digest line 0.05; quiet notification 0.3; urgent false alert 1; light switched on for nothing 0.1 plus its watt-hours at the local price; a compute tier costs its joules. Feedback moves these (below).

**Value of information.** One-step lookahead: is it worth switching on the light, or escalating a camera, to resolve identity? VOI = expected cost now − expected cost after the observation − cost of getting the observation. How often a face resolves under a given light and distance comes from the replayed logs and Phase 0.

**Compute tiers on the hub.** T0 motion on the sub-stream. T1 detector at about 5 fps. T2 full resolution, face and appearance embeddings, pre-roll clip. T3 an optional heavy model on demand. Tiers are switched per camera through Frigate's MQTT on/off topics (confirm the names for the pinned version). The detector stays on, because forecasting needs the approach.

**Explanations are counterfactuals.** For each alert, re-run the decision with each evidence input changed (identity → household, phone at home, time → 18:00, zone → other) and report the smallest change that flips the action: "No alert if the face had matched and a resident's phone had been at home."

**Failure is an event.** Stream lost, frame frozen or black, scene shifted (camera knocked or covered): `health.degraded` push. Never silent.

**Feedback adaptation.** Each tap updates a Beta posterior per context (zone × time bin × identity class) that scales the false-alert cost. About 100 labels can tune 5–10 numbers, not a model, so that is all the design adapts. Re-fit the score → false-alerts-per-day mapping weekly.

## 8. App

One web app (PWA) serves the phone and the wall tablet.

**Alert card**: four lines at most.

```
Bike missing from the rack — 02:40
Taken by someone we could not identify (no face seen, no resident phone at home).
Scored higher than 998 of 1,000 episodes here.
No alert if: a resident's phone had been at home and a face had matched.
[ clip from 02:39:50 ]   [ Mattered ]   [ Was fine ]
```

The clip starts about 10 s before the trigger (Frigate's pre-capture buffer) and is fetched only on tap. The *reasoning view* behind the card (identity bars, forecast, evidence timeline, zone-graph map with tokens) is the same screen the wall panel shows. The physical panel is only a tablet in kiosk mode: an afternoon of work once the app exists.

**Delivery.** ntfy (self-hosted) or Web Push. Payloads are text only, such as "Unrecognised person at the drive". iOS Web Push works only for apps added to the home screen, so test that on day one and keep ntfy as the fallback. Clips and live view from outside the home go over a VPN (Tailscale or WireGuard) with no open ports. The push services still learn that a push happened and when.

**Live view** on request raises that camera to T2. It is the energy decision, made by the user.

**Outage.** The hub is the brain. Without internet, alerts are delayed rather than lost (queue and retry), and a local chime on the home network still works. If the hub itself is down, the camera's SD card is the only record. A small UPS on the hub, PoE switch and router (about €40) is the cheapest resilience upgrade.

**Tamper-evident log.** Each record's hash includes the previous one. Every push carries the current head, and the phone stores the latest head it has seen. "Log intact" then means that what the phone saw is a prefix of what the hub shows. A chain checked only by the hub proves nothing. Anchoring it on the phone is what makes it meaningful.

## 9. Evaluation

**Two datasets.**

- *Natural.* Continuous logging from the end of Phase 1. Everything logged before the policy freeze (gate G2) is development data. The two weeks after the freeze are the test set: they do not exist before the freeze, so nobody can tune on them. If the deadline is tight, one development week and one test week is the minimum. Every episode is labelled once, blind, in a batch UI (about 100–400 episodes, one or two hours). Label the test set only after the freeze.
- *Staged.* About 150 episodes, written consent, at several light levels. Split by participant when there are three or more, otherwise by session.

| ID | Staged scenario | Truth | What it tests |
|---|---|---|---|
| S1 | Take the bike from the rack, walk away | alert | custody loss by a non-resident |
| S2 | Take the bike, ride away | alert | custody loss with a fast exit |
| S3 | Pick up a delivered parcel, leave | alert | parcel loss |
| S4 | Loiter at the door or gate for 60 s, look around, try the handle | alert | dwell, normalcy, forecast |
| S5 | Drop a parcel at the door, leave | digest | custody gain is a delivery |
| S6 | Resident returns at night, hood up, no face | no alert | `unverified` is not a stranger |
| S7 | Resident moves their own bike | no alert | household custody needs two cues |
| S8 | Passer-by walks along the boundary | no alert | zone discipline |
| S9 | Two people, one resident, one unknown | alert if the unknown one acts | association under crowding |
| S10 | Person stands in front of the bike for 20 s, leaves, the bike stays | no alert | absence needs visibility |

10 scenarios × 5 repeats × 3 light levels = 150 episodes.

**Baselines.** Run in shadow mode: they log what they would have sent, and the household sees only Threshold.
- B0: raw motion.
- B1: a person detected anywhere.
- B2: B1 plus masks, zones, dwell and time rules, hand-tuned with a budget of two hours on the development days. Threshold has to beat B2.

**Ablation ladder.** Same data, false alerts per day at 90% staged recall: B2 → + identity posterior → + normalcy prior → + slots and custody → + feedback adaptation. Some rungs may not help. That is a result too.

| Claim | Experiment | Metric |
|---|---|---|
| Fewer false alerts at equal recall | Replay natural days and the staged set under every policy | False alerts per 24 h at 90% recall; the curve over recall; per-day counts, not just the mean |
| Each part earns its place | Ablation ladder | Change in false alerts per day per rung |
| Feedback helps | Replay the test days in order, feeding each alert's blind label back as if it were a tap, with and without adaptation. Separately report the real tap rate and its agreement with the blind labels | False alerts per day, with vs without. A counterfactual, not a falling curve that weather and novelty could explain |
| Custody works | Staged S1–S3, S5, S7, S10 plus natural events | Precision and recall per event type; time to call |
| The score means something | Score → false-alerts-per-day mapping; rarity percentiles | Calibration plot |
| Night | Phase 0 curves | Detection and face-match rate against lux |
| Energy | 24 h per configuration on the metered plug: always-on full, gated, idle. Light study if the light is used | Wh per day; iGPU-seconds per episode; Wh per night of lighting |
| Perception misses | Spot-check 20 random hours a week of the continuous sub-stream | Share of people the detector missed |
| Early forecast (stretch) | Truncated tracks | Accuracy and Brier score against fraction observed; lead time |
| Robustness (stretch) | Lens cover, flashlight dazzle, printed-face photo, unplug or freeze | Detected? Time to health alert? |
| Explanations (optional) | 6–10 people judge 20 recorded alerts, with and without the explanation | Decision accuracy, time taken |

**Honesty rules.** One site and one household: report a case study, not a population result. Give counts and intervals (Wilson for recall, bootstrap over days for false alerts per day). Claim nothing about whether people "leave notifications on" beyond this household's own mutes, time to open and ratings. A second household's footage, if a friend allows it, is worth more than another week at the first.

## 10. Build plan

Assumed: one builder, 10–15 h per week, about 12 weeks including a buffer. **Start the data clock early** (Phase 1). The logging weeks cannot be rushed, and everything else can run alongside them. If the deadline is shorter, cut from the bottom.

| Phase | Weeks | Work | Gate |
|---|---|---|---|
| 0 Night | 1 | Hub, Frigate (pinned version), one camera, lux logger. Three nights of the capability protocol. Benchmark inference. Check whether Frigate's event API returns per-frame paths. | **G0**: the curve exists and the ladder step is chosen |
| 1 Log and baselines | 2–3 | Ingest Frigate events into the hash-chained log. Replay command. Baselines B0–B2 in shadow mode. Minimal episode-labelling UI. Retention: events with pre/post-roll at full resolution, plus the continuous sub-stream (about 20 GB per day at 2 Mbps) for miss spot-checks. | **G1**: replaying yesterday reproduces yesterday's decisions exactly |
| 2 Belief and decide | 3–6 | Zone graph, identity posterior, normalcy, slots and custody, forecast v0, score → false-alerts-per-day mapping, feedback adaptation (developed in replay, fed by labels), counterfactual explanations, health alerts. | **G2**: beats B2 on the development days at equal staged recall (calibration split). If not, diagnose before building the app. If yes, **freeze** the policy, the operating-point rule and the protocol |
| 3 App | 6–8 | PWA, push, alert card, reasoning view, tap buttons, VPN. Test-set logging runs during this phase. | **G3**: the household keeps notifications on for 3 days |
| 4 Evaluate | 9–11 | Label the test set, run the staged test split, ablations, power measurements, write-up. | The protocol was frozen before the test set was labelled |
| Buffer | 12 | Pick *one* stretch item. | |

Phases 0 and 1 plus two weeks of logging are already a result: night capability curves and a baseline false-alert rate.

**Stretch, in this order** (one at a time):

1. Early-forecast study (offline, reuses the logs).
2. Red-team lite: lens cover, flashlight dazzle, printed-face photo, unplug or freeze. Each failure gets a mitigation, and detected tampering becomes an event.
3. Metric map and the wall tablet in kiosk mode.
4. Second camera: cross-camera association on the zone graph.
5. Light as an actuator, as an energy study. It moves into the core if Phase 0 says the light is needed.
6. A second site (hawk deterrence): see section 14.

**This week.**
1. Choose the camera position and sketch the zone graph on paper: five zones, off-property, one unseen. Measure the distances to the door, gate, bike and parcel spot.
2. Get the hub and one camera, or use a camera already owned as the Phase 0 subject.
3. Install Frigate and mask public areas.
4. Run the capability protocol for three nights.
5. Write the definitions in section 2 down as the draft of the frozen protocol.

## 11. Rough budget

EU used market, one camera. Treat as rough.

| Item | € |
|---|---|
| Hub: used mini PC (Intel 6th gen or newer, or N100), 8 GB RAM | 80–150 |
| SSD of 500 GB–1 TB, rated for continuous writes | 40–70 |
| PoE camera, large sensor, f/1.6 or faster | 70–200 |
| PoE injector or small switch | 15–40 |
| Lux logger (TSL2591 + ESP32) | 12–20 |
| Metered smart plug | 10–20 |
| Light and relay or smart plug (if Phase 0 needs it) | 15–30 |
| Tablet for the wall panel (optional) | 0–60 |
| **Core total** | **about 250–450** |

## 12. Risks

| Risk | Early signal | Mitigation |
|---|---|---|
| Night image too poor | The G0 curve | The ladder in section 4. Narrow the claims to the lux range shown to work |
| Perception noise swamps the belief (track flicker, identity switches) | Many tracks per real person | Treat detections as soft evidence. Log raw. Evaluate perception separately from the belief |
| One site, one household | | Case-study framing. A second household's footage if possible |
| Scope creep | A phase passes its week budget | Gates, cut lines, one stretch item at a time |
| Weather and mounting | Scene shifts, fog, condensation | Rigid mount, drip loop, desiccant. The scene-shift check against a reference frame becomes a health event |
| Label bias (the builder rates their own system) | | Blind batch labelling. A second household member labels 20%. Report agreement (Cohen's kappa) |
| Frigate version drift | Config or schema changes (0.17 had breaking changes) | Pin the image tag. Keep the evidence-provider boundary thin |
| Clock skew | Clips misaligned with events | NTP on the hub, with the cameras taking time from it. Store offsets |
| Security of the system itself | | Isolated camera network, no cloud features on cameras, strong credentials, VPN only, minimal push payloads |

## 13. Constraints

- **Local.** All processing stays on the property. The only outbound traffic is the push ping. Web Push payloads are end-to-end encrypted, but the push service still sees that a push occurred and when.
- **Biometrics.** Face embeddings only for enrolled household members, with explicit, revocable consent, on an encrypted disk. Unrecognised people are never enrolled: their appearance vectors exist only to link tracks during an episode and are dropped when it closes.
- **Footage.** Raw video is kept only for the study window, then deleted automatically. Evaluation data shared with others goes out as feature logs, not video.
- **Masks.** Public areas and neighbours' windows are masked, for privacy and for fewer false alerts.
- **Participants.** Written consent, the right to withdraw, no deception, guardian consent for minors, no staging in public space. Tell neighbours if the camera sees their property.
- **Light.** Warm-white, shielded, aimed at own property.
- **If in the EU.** The household exemption does not cover filming public space (CJEU, *Ryneš*, C-212/13), and face templates used to identify people are special-category data (GDPR art. 9). This is not legal advice; check the national data-protection authority's guidance.

## 14. Deferred or cut

| Item | Why | Comes back if |
|---|---|---|
| mmWave radar | Decision: camera only. Side effect: the property is not tracked while cameras are off | |
| Solar or battery nodes | Continuous sensing needs about 2–5 W per camera, and forecasting needs a continuous view of the approach | A low-power wake tier is added and the forecast study is dropped |
| IR illumination | Face models are trained on color. IR flooding is an attack surface. Insects | Phase 0 fails and ladder steps 1–4 do not fix it |
| PIR-gated battery cameras | They wake after the approach, which defeats forecasting | Not in this design |
| A vision-language model judging "suspicious" | Slow on an N100, and the local-only rule applies. Frigate 0.17's GenAI review labels (normal, suspicious, dangerous) are an off-the-shelf comparator | A GPU box is available, as an extra comparison row |
| Hawk-deterrence site | Needs a base rate of at least one visit per week to say anything about habituation, and a legal check on deterring a protected species. Acoustic only, and the effect on the chickens is monitored too | The base rate has been measured first with a camera on the run |
| Third camera and attention allocation | Compute is not scarce with one or two cameras | The camera count outgrows the hub's budget |

## 15. Facts checked, and facts still to check

Checked on 2026-10-26 against Frigate's docs on GitHub (`dev` branch) and the v0.17.0 release notes. They were read through a summarising fetch tool, so re-read the exact page before depending on a detail.

- `frigate/events` carries `new`, `update` and `end` with box, zones, `stationary`, `sub_label`, estimated speed and angle. Updates fire on a better snapshot or a zone change. No per-frame boxes are published over MQTT. ([MQTT docs](https://github.com/blakeblackshear/frigate/blob/dev/docs/docs/integrations/mqtt.md))
- Face recognition adds a `sub_label`. The small model is FaceNet (CPU), the large one ArcFace (GPU or NPU recommended). The default `min_area` is 750 px. The docs advise against IR and grayscale images because the models are trained on color. ([face recognition docs](https://github.com/blakeblackshear/frigate/blob/dev/docs/docs/configuration/face_recognition.md))
- Hardware page: Intel iGPU 6th generation and newer; on an N100 about 15 ms for MobileNetV2 and 25–30 ms for 320-px YOLO variants; one detector instance. ([hardware docs](https://github.com/blakeblackshear/frigate/blob/dev/docs/docs/frigate/hardware.md))
- 0.17.0 added state and object classification training, GenAI review summaries with normal, suspicious and dangerous labels, and semantic-search triggers. ([release notes](https://github.com/blakeblackshear/frigate/releases/tag/v0.17.0))
- Zone speed estimation takes a 4-point ground zone plus real side lengths. ([source mirror of `util/velocity.py`](https://git.laurivan.com/Mirrors/blakeblackshear.frigate/src/branch/dev/frigate/util/velocity.py))

Still to check:

- Whether Frigate's event API returns per-frame paths (`GET /api/events/<id>`). If not, a sidecar tracker is needed. (Phase 0)
- Whether state classification publishes over MQTT on the pinned version. A user reports it did not on 0.17.0 ([discussion #22157](https://github.com/blakeblackshear/frigate/discussions/22157)). Default: Threshold's own slot classifier.
- Frigate's MQTT on/off topic names for detect, recordings and snapshots.
- The camera's night performance, which no document can tell. (Phase 0)
- That iOS Web Push needs the app on the home screen. This is from general knowledge and was not checked here.
- All prices and the lux table: rough.

## 16. Decisions still open

1. **Deadline, and who judges the result.** It sets how far down the stretch list to go, and whether four weeks of natural logging fit.
2. **The camera.** Already owned, or to buy? Can a cable be run to the camera position?
3. **What the first camera covers** (door, drive, yard, bike rack), and whether any light reaches it.
4. **Country and consent.** The EU is assumed. Will the household members consent to face enrolment and phone presence?
5. **Participants.** Can two or three people take part in the staged trials?
