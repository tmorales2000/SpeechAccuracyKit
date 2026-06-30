# Architecture & Design Decisions

This document explains *why* SpeechAccuracyKit is built the way it is. The
README covers what it does and how to run it; this covers the reasoning,
tradeoffs, and boundaries.

## The three-stage decomposition

Spoken-language understanding is a pipeline, and its failures are not
interchangeable:

```
audio ──▶ [ ASR ] ──▶ text ──▶ [ NLU ] ──▶ intent ──▶ [ response ] ──▶ answer
            │                     │                        │
        "what did            "what did it             "is the answer
         it hear?"            understand?"             on target?"
         WER vs ref           intent/slot match        semantic proximity
```

Why separate them at all? Because the same wrong answer can originate in any
stage, and the fix belongs to a different owner each time:

- **ASR is the gate for everything downstream.** Its errors are silent: nothing
  later knows the input was misheard, so the error propagates unflagged. That is
  why ASR gets the tightest scrutiny and is measured first.
- **NLU is measured twice on purpose**, once on the perfect reference transcript
  and once on the actual ASR output. If NLU is correct on clean text but wrong on
  the ASR output, the recognition stage is at fault. If NLU is wrong even on the
  perfect transcript, comprehension itself is broken. Comparing the two
  *localizes* the failure. This is the core diagnostic move of the whole project.
- **Response** is the open-ended-output problem: you cannot string-match a
  generated answer, so it is scored by semantic proximity to a reference.

`StagedResult.diagnose(...)` encodes the localization logic and returns one of
`recognition`, `comprehension`, `response`, or `none`.

### The tamarind case as the worked example

Asking about "tamarind" and getting "Tammaron" decomposes cleanly:

| What happened | Stage at fault | Fix owner |
|---|---|---|
| ASR heard "tammaron" | recognition | acoustic / pronunciation |
| ASR heard "tamarind", NLU resolved the wrong entity | comprehension | entity resolution |
| Both correct, generation pulled the wrong entity | response | retrieval / grounding |

The unit tests encode all three. The demo app's seeded entity misresolution
(`tamarind → tammaron`) produces a *genuine* comprehension failure on perfectly
recognized text, not a staged one, so the demo does not fake its own headline.

## Decision: characterization testing, not correctness testing

The on-device recognition suite asserts each fixture against its own **measured
baseline**, not against perfection. The recognizer transcribes "tamarind" at
~0.33 WER (it drops the final consonant); the fixture's baseline is set just
above that, and the test fails only if recognition gets *worse*.

Why this and not a strict correctness gate:

- A correctness gate on a real ASR system never passes. You will always have hard
  words, accents, and noise conditions the model gets wrong. A suite that is
  always red is ignored.
- The reliability/stability question is not "is it perfect" but "did this change
  make it worse." That is a **regression** question, and a characterization
  baseline answers it directly.
- The asymmetry is correct: if recognition *improves* (a better model finally
  gets "tamarind"), the test still passes, because better-than-baseline is fine.

The known weakness, stated honestly: a characterization test can lock in a bug as
"acceptable." The mitigation is that the baseline is a **regression floor**, not a
substitute for a defect backlog. "tamarind is misrecognized" belongs on a list of
known issues someone is trying to fix; the test only ensures it does not silently
get worse while it waits. Regression floor and improvement backlog are two
different jobs.

Baselines are environment-specific: they depend on the recognizer version and the
exact generated audio. Re-characterize when either changes. A small tolerance
absorbs floating-point and minor model variation without hiding real regressions.

## Decision: pure DSP for degradation, not AVAudioEngine

The fixture generator degrades audio with direct math on the sample buffer
(additive noise at a target SNR, a one-pole low-pass for muffling, gain). It does
**not** use `AVAudioEngine`.

The engine path was tried first and abandoned. Offline effect-graph rendering
through the engine's mixer is fragile: connecting nodes in manual-rendering mode
threw `kAudioUnitErr_FormatNotSupported` (-10868) on format negotiation at the
mixer, and chasing format fixes into that corner was a poor trade. Pure DSP has
no engine, no mixer, no manual-rendering mode, and no format negotiation, so it
cannot hit that class of failure. It is also deterministic and the noise/filter
math is unit-verified.

The cost is losing audio-unit effects (reverb, distortion presets). For a
robustness *illustration*, additive noise and a low-pass muffle are the two most
defensible degradations anyway, so the trade favors simplicity and correctness.

## Decision: NLEmbedding first, Core ML later

Response proximity uses Apple's `NLEmbedding` (NaturalLanguage) in v1: on-device,
zero dependencies, no model bundling, runs immediately. A `LexicalProximityGrader`
(Jaccard token overlap) is the dependency-free fallback so the harness runs even
where NaturalLanguage is unavailable.

The documented upgrade is a sentence-transformer exported to Core ML for stronger
sentence-level intent discrimination, the same on-device export pipeline used for
vision-language models. NLEmbedding is the right *first* choice (speed, zero
setup); the Core ML path is the right *next* choice (quality) when the proximity
signal needs to be sharper.

## Why NLI for the response grader is a deliberate choice

The sibling Python project grades faithfulness with NLI (entailment), not a large
LLM-as-judge. That choice carries over here as the documented `NLIGrader` upgrade:
a small, deterministic entailment classifier is faster, cheaper, more stable
across runs, and far easier to calibrate than an LLM judge, exactly where the
oracle problem would otherwise tempt you toward a heavyweight judge with its own
non-determinism and version drift.

## Extension seams

Every stage is a protocol so strategies swap without touching call sites:

- `IntentClassifier`: `RuleBasedClassifier` (ships) → `CoreMLIntentClassifier` (stub)
- `SemanticGrader`: `NLEmbeddingGrader` / `LexicalProximityGrader` (ship) →
  `CoreMLSentenceGrader`, `NLIGrader` (stubs)

```
UtteranceFixture (audio + reference + baseline)
        │
        ▼
OnDeviceSpeechRecognizer ── SFSpeechRecognizer, on-device, file-based
        │ hypothesis
        ▼
AccuracyHarness
   ├── WERGrader            stage 1: edit distance (pure Swift)
   ├── IntentClassifier     stage 2: NLU, run on reference AND hypothesis
   └── SemanticGrader       stage 3: response proximity
        │
        ▼
StagedResult ── diagnose() ──▶ recognition | comprehension | response | none
```

## Design choices in the recognizer wrapper

- **File-based recognition** (`SFSpeechURLRecognitionRequest`), not live mic, so
  the test suite is deterministic and headless.
- **`requiresOnDeviceRecognition = true`**: no network; results reflect the
  on-device model, which is what a reliability test should measure.

## Boundaries (what this is not)

- Not a replica of any production Siri test infrastructure, acoustic lab, or
  device farm.
- The recognizer is the public `SFSpeechRecognizer`, not any internal system.
- Fixtures are synthetic speech with synthetic degradation. They illustrate
  degradation *categories* and serve regression testing. They are not a physical
  acoustic path, microphone array, or real noise field. Physical-device acoustic
  testing is a separate, higher-fidelity tier and is where front-end validation
  (beamforming, echo cancellation, wake-word robustness) actually belongs.
- Characterization baselines are specific to the recognizer version and the
  generated audio; they are regression floors, not correctness guarantees.
