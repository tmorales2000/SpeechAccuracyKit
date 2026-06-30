# SpeechAccuracyKit

An on-device speech-recognition **quality harness** for Apple platforms. It runs
`SFSpeechRecognizer` fully on-device, scores each transcription, and gates a
build (XCTest) when recognition regresses past a recorded baseline.

It is the speech-domain sibling of
[`ai-content-accuracy-checker`](https://github.com/tmorales2000/ai-content-accuracy-checker):
that project grades LLM answers against a knowledge base (RAG + NLI, faithfulness
score, CI gate). This one grades recognized speech against reference transcripts.
Same idea, one layer down the stack.

## Why this exists: the tamarind problem

Ask a voice assistant *"what is tamarind?"* (the fruit) and you may get back an
answer about **Tammaron**, a place in Texas. That single wrong answer can come
from three completely different broken stages:

1. **Recognition** mishears "tamarind" as "tammaron" (acoustic / phonetic).
2. **Comprehension** hears it right but resolves the entity to the wrong thing.
3. **Response** has both right but still retrieves the wrong entity.

Same symptom, three root causes, three different owners, three different fixes.
A test that only checks the final answer can tell you it's *wrong*. It cannot
tell you *which stage broke*, which is the only thing that lets you route the
defect to the team that owns it. SpeechAccuracyKit separates the stages so a
failure is localized and actionable.

This is not hypothetical. Run the on-device suite in this repo and Apple's own
`SFSpeechRecognizer` reproduces the bug: it transcribes "tamarind" as **"tamarin"**
(dropping the final consonant), and under degraded audio as **"Cameron."** The
harness catches it and pins it to the recognition stage.

## What it is

A small Swift package plus a SwiftUI demo. Three stages, each answering a
different question:

- **Recognition (ASR)** — *what did it hear?* Word Error Rate vs the reference.
- **Comprehension (NLU)** — *what did it understand?* Intent/slot match, run on
  both the clean reference and the ASR output, so a comprehension failure is
  distinguishable from a recognition failure.
- **Response** — *is the answer in the right neighborhood?* On-device semantic
  proximity.

`StagedResult.diagnose(...)` collapses the three into a single verdict:
`recognition`, `comprehension`, `response`, or `none`.

The on-device recognition suite is a **characterization test**: each fixture
carries its own measured WER/proximity baseline, and the gate fails only when
recognition gets *worse* than that baseline. It catches regressions without
pretending the recognizer is perfect. See `ARCHITECTURE.md` for the reasoning.

## Quickstart

Requires macOS with Xcode/Swift and an installed English voice
(`say -v '?' | grep en_US` should list at least one).

```bash
# 1. Build and run the platform-independent logic tests.
swift test

# 2. Generate the audio fixture corpus (NOT committed to git, see below).
swift run fixture-gen Tests/SpeechAccuracyKitTests/Fixtures

# 3. Rebuild so the fixtures bundle, then run the full suite including the
#    on-device recognition gate.
swift build
swift test
```

Pick a specific synthesis voice (keeps the corpus reproducible):

```bash
swift run fixture-gen Tests/SpeechAccuracyKitTests/Fixtures --voice "Samantha"
```

If the requested voice is not installed, the tool lists the available English
voices and exits without writing anything.

> **Fixtures are not in git.** The generated `*.wav` files are gitignored because
> they are reproducible build artifacts. A fresh clone has no audio, so the
> on-device test **skips** until you run `fixture-gen` and rebuild. This is
> expected. Resources bundle at build time, so always `swift build` after
> generating fixtures.

## The demo app

`Demo/` contains a SwiftUI app that runs the three-stage diagnosis live with
editable inputs and three presets (tamarind, mishear, clean). It shows which
stage owns a failure without needing recorded audio. See `Demo/README.md`.

## Status

Working and tested: WER grader, three-stage harness and diagnosis (incl. the
tamarind case), rule-based NLU classifier, NLEmbedding and lexical proximity
graders, on-device recognition with characterization baselines, the fixture
generator, and the SwiftUI demo.

Stubbed with documented upgrade paths: `CoreMLSentenceGrader`, `NLIGrader`,
`CoreMLIntentClassifier`.

## Scope and honesty

This demonstrates the **methodology** of automated, on-device speech-quality
measurement on Apple frameworks. It is not a replica of any production Siri test
infrastructure, acoustic lab, or device farm. The recognizer is the public
`SFSpeechRecognizer`. The fixtures are synthetic speech with synthetic
degradation, useful for illustrating degradation *categories* and for regression
testing, but not a substitute for physical-device acoustic testing. The
characterization baselines are specific to the recognizer version and the
generated audio on the machine that recorded them; re-characterize when either
changes. `ARCHITECTURE.md` is explicit about every one of these boundaries.

MIT.
