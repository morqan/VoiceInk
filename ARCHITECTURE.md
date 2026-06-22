# Architecture

A map for getting productive in this codebase fast. For build/run steps see
[BUILDING.md](BUILDING.md).

## What the app is

VoiceInk is a macOS voice-dictation app. You press a hotkey, speak, and the
transcribed (optionally AI-polished) text is pasted into whatever field has focus.
On top of that it records per-dictation speech metrics and shows analytics.

## The critical path (read this first)

This is the one flow that matters most — everything else supports it:

```
hotkey  ->  record audio (CoreAudioRecorder)  ->  Whisper transcription
        ->  [optional] AI enhancement (AIEnhancementService -> provider)
        ->  paste into the focused app
        ->  (after paste, OFF the critical path) record SpeechMetric -> Speech analytics
```

Two rules that explain a lot of the design:

- **Nothing slow runs before the paste.** Metrics, prosody analysis, vault sync and
  history work all happen *after* the text is inserted, on background tasks, so
  dictation feels instant.
- **The audio capture callback is realtime.** `CoreAudioRecorder`'s input callback
  fires hundreds of times per second on a high-priority thread and must finish in
  microseconds — do not add work to it.

## Architecture pattern

Plain **SwiftUI "MV"** (Model–View), not MVVM/VIPER:

- **Views** (`SwiftUI`) observe **services** that are `ObservableObject`s. There is no
  ViewModel layer per screen — a view talks to the services it needs directly.
- **SwiftData** (`@Model` types in `Models/`) is the persistence layer.
- A view-model is introduced only where a screen genuinely needs one (e.g.
  `PowerModeFormModel` for the 26-field Power Mode form). It is the exception, not the
  rule — don't add ViewModels by default.

This is intentional: the app is mid-sized and a heavier architecture would add
ceremony without payoff.

## Folder map

Top level under `VoiceInk/`:

| Folder | Owns |
| --- | --- |
| `App/` | App entry point, app delegate, window / menu-bar / history-window managers |
| `AudioCapture/` | Realtime mic capture (`CoreAudioRecorder`) + CoreAudio device lookups |
| `Sound/` | Start/stop sounds and playback control |
| `Transcription/` | The transcription engine: Whisper, streaming, the pipeline, model managers |
| `Services/` | Non-UI logic, grouped by domain (see below) |
| `Models/` | SwiftData `@Model` types + small value types, grouped by domain |
| `Views/` | SwiftUI screens, grouped by feature |
| `PowerMode/` | Power Mode feature (per-app/site config profiles) |
| `Shortcuts/` | Global hotkeys and shortcut handling |
| `Notifications/`, `Paste/`, `AppIntents/`, `Extensions/` | Smaller cross-cutting helpers |

`Services/` subfolders: `Audio/`, `Transcription/`, `SpeechCoaching/` (speech metrics,
fillers, voice-profile matching, daily exercise), `AIEnhancement/`, `Prosody/` (on-device
pitch / pause / loudness analysis), `Licensing/`, `Backup/`, `Metrics/`, `Dictionary/`,
`Utilities/`, `Infrastructure/`.

`Views/` subfolders include `Speech/` (+ `Tabs/`, `Coach/`, `Components/`), `History/`,
`Metrics/`, `AI Models/`, `Settings/`, `AudioPlayer/`, `Recorder/` (mini / notch recorder),
`Dictionary/` (dictionary + Vault Sync), `Onboarding/`, `Common/`, `Components/`.

## Where do I find…

| I want to change… | Look at |
| --- | --- |
| What happens when you finish dictating | `Transcription/Engine/TranscriptionPipeline.swift`, `VoiceInkEngine.swift` |
| Mic recording / device handling | `AudioCapture/CoreAudioRecorder.swift`, `Services/Audio/AudioDeviceManager.swift` |
| AI text enhancement / providers | `Services/AIEnhancement/` (`AIEnhancementService`, `EnhancementProviderDispatcher`) |
| Speech metrics + analytics | `Services/SpeechCoaching/`, `Views/Speech/SpeechAnalyticsView.swift` (the Speech sidebar screen) |
| Power Mode config screen | `PowerMode/` (`PowerModeConfigView` + `PowerModeFormModel` + sections) |
| The sidebar / main window | `Views/ContentView.swift` |
| Global hotkeys | `Shortcuts/` |
| Persisted data shape | `Models/` grouped by domain (`Transcription`, `SpeechMetric`; `SpeechCoaching/VoiceProfileTarget` defines the target speaking-style profiles scored by Match Score) |

## Conventions

- One primary type per file; the file is named after it.
- Keep view files focused — split a screen into sections/subviews rather than growing
  one large `body`.
- Heavy work goes off the main thread (background `ModelContext`, `Task.detached`);
  only `Sendable` values cross actor boundaries — never pass a SwiftData `@Model`
  across, re-fetch it by id in the background context instead.
