# Threshold

A perimeter awareness system that doesn't record what happened — it maintains a belief
about what *is* happening, predicts what is *about to* happen, and acts to change the
outcome.

## The problem

Consumer security cameras detect motion and report it. The alert stream is so noisy that
people turn notifications off, which makes the detection rate irrelevant — nobody is
reading the output. And a system that only reports is forensic: by the time it speaks,
the event is over.

So the metric that actually matters isn't accuracy. It's **false alerts per 24 hours at
fixed recall** — a number no vendor publishes.

## The idea

Three stages, each supplying something the previous one can't.

**Believe.** A probabilistic estimate of the state of the property — who is present and
where, which objects are at rest where, whether the house is occupied. Hidden state,
observed only through noisy, intermittent sensors.

The point is that this is *one* model, not a pile of features. Cross-camera
re-identification, identity fusion, object custody and occupancy are four **queries
against one belief**, not four separate detectors with a rule file on top.

**Predict.** Commit to a judgement from a partial trajectory, before the event finishes.
Forensic becomes preventive.

**Act.** Choose actions by expected cost, not by threshold. Costs are asymmetric and
real — a missed incident, an eroded user's trust, a falsely accused neighbour, and the
one that's cleanly measurable: **watts**.

## Why it isn't just a camera

Two things carry the project.

**Custody.** The core primitive is *object custody change*, and one mechanism explains
both the bad thing and the good thing. An object at rest disappears, and the change is
attributed to whoever was co-located with it. Unknown person + bike gone at 02:40 is
theft. Parcel appears + unknown person departs is a delivery. Same computation, opposite
sign.

**Energy as a decision.** A low-power radar tier runs continuously; the camera tier is
gated. The system decides for itself when the current uncertainty justifies spending the
energy to resolve it. That's a value-of-information calculation with a unit attached,
and it's measurable in joules.

## What it runs on

- **Hub** — a cheap used mini PC (x86, ~€80). Indoors, on mains. Runs the belief layer,
  the log, the message broker and the wall panel. Its Intel iGPU handles inference and
  video encoding, so no dedicated accelerator is needed.
- **Nodes** — small boards outdoors, each with a camera, an IR illuminator and a 24GHz
  mmWave radar. These are what get power-gated, and what could eventually run on solar.
- **Wall panel** — a small touchscreen showing the system *reasoning*: a property map with
  tracked entities, a live radar scope, the intent estimate rising in real time, and a
  live check that the event log hasn't been tampered with.
- **Phone app** — where the system actually reaches you. One web app serves both the panel
  and the phone, so there's a single interface to build.

## The app

This is the part the whole project is judged on, because the headline metric is whether
people leave notifications turned on.

So alerts explain themselves. Each one says *why* it fired and what would have changed it
— "unknown identity, predicted intent 0.74; had the face matched, no alert" — with the
clip attached, starting from before the trigger rather than after it.

Every alert also carries one-tap feedback: *this mattered* / *this was fine*. That
feedback tunes the system to the household over time, so the false alert rate should fall
across the deployment week without anyone configuring anything. That curve is one of the
better results the project can produce.

Live view is on request. Tapping a camera pulls that node up a power tier and starts a
stream — which is the energy decision from above, made by the user instead of the system.

Nodes hold events locally and forward them when connected, so a network outage delays
data rather than losing it. Radar telemetry is tiny enough to stream permanently, so the
property stays tracked even with every camera powered down.

## What gets measured

- Accuracy versus how much of an event has been observed (how *early* it can call it)
- Precision and recall per event type, on staged scenarios replayed through a fixed test suite
- False alerts per 24 hours over a week of real deployment
- Identity accuracy in daylight versus infrared, and what closes the gap
- Power draw across the tiers, versus always-on

## Optional, if there's time

1. **Early prediction** — the earliness/accuracy curve. Highest value, highest risk.
2. **A second site: acoustic hawk deterrence for a chicken run.** Different threat model,
   same architecture. Methodologically stronger than staged human trials, because the
   subject doesn't know it's an experiment. The real question is *habituation* — deterrents
   stop working within days, so does randomising the stimulus delay that?
3. **Attacking my own system** — spoofed faces, adversarial patches, IR flooding, lens
   occlusion, log tampering. Each failure gets a mitigation; detected tampering becomes
   an event.
4. **Learned normalcy** — model what's normal for this household rather than what's
   suspicious. A 40-second dwell is unremarkable at 18:00 and anomalous at 03:00.
5. **A third node** — trajectory events across the property, and deciding where to look
   when there isn't enough compute to watch everywhere.

## Constraints

All processing is local; nothing leaves the property but the alert. Face embeddings are
stored, not images. Public areas are masked. Staged participants consent in writing.
Raptors are protected — acoustic deterrence only, and the effect on the chickens is
monitored too.
