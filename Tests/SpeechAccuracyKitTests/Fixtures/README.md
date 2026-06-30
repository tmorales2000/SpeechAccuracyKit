# Audio Fixtures

Place `.wav` / `.m4a` files here and reference them from
`OnDeviceRecognitionTests.corpus`. Suggested baseline + degraded-input set:

- set_timer_10min.(wav)        "set a timer for ten minutes"   (clean)
- set_timer_noisy.(wav)        same reference, background noise
- set_timer_slow.(wav)         same reference, slow with pauses
- set_timer_accent.(wav)       same reference, accented speech

Clean fixtures can be generated with AVSpeechSynthesizer; add noise for the
degraded set. Keep the reference transcript identical across a variant group so
the harness measures robustness, not a different target.
