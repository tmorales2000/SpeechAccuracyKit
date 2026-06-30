# SpeechAccuracyDemo

A minimal SwiftUI app that demonstrates the three-stage pipeline live. Type (or
load a preset) what a person meant, what recognition heard, and what the
assistant answered. The app runs all three stages and shows which one owns the
failure.

## Why it's structured this way

The demo lets you edit the recognized text directly so you can reproduce each
failure class without recording audio:

- **Tamarind (comprehension):** heard correctly, but intent resolves wrong even
  on clean text. The answer is about Tammaron, Texas. Diagnosis: comprehension.
- **Mishear (recognition):** the recognized text itself is wrong. Diagnosis:
  recognition.
- **Clean (pass):** all three stages succeed.

To wire in real on-device recognition, replace the editable "What Siri heard"
field with the output of `OnDeviceSpeechRecognizer.transcribe(url:)` from the
library. The grading and diagnosis code is identical either way.

## Run it

This folder holds the app sources only. To build:

1. In Xcode: File > New > Project > App (SwiftUI), name it `SpeechAccuracyDemo`.
2. Delete the generated `App` and `ContentView` files.
3. Add `SpeechAccuracyDemoApp.swift` and `ContentView.swift` from this folder.
4. File > Add Package Dependencies > Add Local, and select the repository root
   so the app links the `SpeechAccuracyKit` library.
5. Build and run on My Mac or a simulator.

On platforms with NaturalLanguage, the demo uses on-device `NLEmbedding` for
response proximity. Elsewhere it falls back to the library's lexical grader, so
it always runs.
