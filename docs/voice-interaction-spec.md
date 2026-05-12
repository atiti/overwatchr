# Voice Interaction Spec

Date: 2026-05-11
Status: Implemented baseline; realtime SDK/WebSocket upgrade remains open

## Goal

Add a low-latency push-to-talk voice dictation mode to Overwatchr. While the user holds a global shortcut, Overwatchr captures microphone audio for Azure Speech Services, receives transcription text, and inserts the final text into the currently focused app. A visible floating listening indicator appears for the duration of capture and shows success or failure at the end.

The first useful version should optimize for hands-on agent operation: hold shortcut, speak a response, release shortcut, have the response appear in the focused terminal or editor. Optionally, a spoken command such as "press enter" should submit the inserted text.

## Non-Goals

- Full voice assistant behavior or spoken responses.
- Wake-word always-on listening.
- Local speech recognition in the first implementation.
- Agent-specific prompt routing.
- Complex command grammar beyond submit handling.
- Cross-platform support outside macOS.

## User Experience

### Primary Flow

1. User focuses any text target: terminal, editor, browser input, chat app, etc.
2. User holds the voice shortcut.
3. Overwatchr shows a small floating indicator near the menu bar or active screen center edge.
4. Overwatchr records microphone audio while the shortcut is held.
5. User releases the shortcut.
6. Overwatchr sends the short audio capture to Azure Speech Services.
7. Overwatchr inserts the returned text into the focused target.
8. If command mode detects a submit phrase, Overwatchr also sends Return.

### Indicator States

- `idle`: no floating indicator.
- `listening`: microphone icon, active accent ring, audio level, optional elapsed timer.
- `transcribing`: live partial transcript line while speech is being recognized.
- `processing`: spinner or pulsing icon after release if the provider still needs to finalize.
- `inserted`: brief success state, then fade out.
- `failed`: brief error state with concise reason; menu bar settings should expose the last full error.

The indicator should be implemented as a borderless floating `NSPanel` owned by the app, not as a new menu-bar pane. It should avoid stealing focus and should be visible over terminal windows.

### Shortcut Model

Overwatchr already has a configurable global jump shortcut backed by Carbon. Voice should have its own configurable push-to-talk shortcut with a separate default, for example `Control + Option + Command + Space`.

The existing `GlobalHotKeyMonitor` only handles key-down hotkey events. Voice needs press and release semantics, so the hotkey layer should grow into a small reusable monitor that can register:

- one-shot shortcuts for existing jump behavior
- hold shortcuts with `pressed` and `released` callbacks for voice capture

If Carbon release events prove unreliable for a registered hotkey, use a local/global `NSEvent` modifier/key monitor as a narrowly scoped fallback while the hold shortcut is active.

## Provider Strategy

Use a provider abstraction from the start, but make streaming the primary interface. Recorded-file transcription should remain as a fallback path for providers that do not support low-latency sessions.

```swift
protocol VoiceTranscriptionProvider {
    var displayName: String { get }
    func startSession(options: VoiceTranscriptionOptions) async throws -> VoiceTranscriptionSession
}

protocol VoiceTranscriptionSession {
    var events: AsyncThrowingStream<VoiceTranscriptionEvent, Error> { get }
    func appendAudio(_ buffer: VoiceAudioBuffer) async throws
    func finish() async throws
    func cancel() async
}
```

Initial provider targets:

- `AzureSpeechTranscriptionProvider`
- `AzureOpenAITranscriptionProvider`
- `OpenAITranscriptionProvider`

Future provider targets:

- `AppleSpeechTranscriptionProvider`
- local/offline provider if a good macOS-native option emerges

### Recommended First Slice

Use the lowest-latency path that still preserves the current Swift Package distribution. The implemented baseline uses Azure Speech Services short-audio recognition over REST on shortcut release, because it avoids introducing the Azure Speech SDK packaging problem into the first version. A true realtime provider remains the next upgrade behind the same capture/controller/provider boundaries.

The first slice should support:

- Azure Speech Services short-audio recognition as the implemented baseline provider.
- Azure Speech Services real-time speech-to-text as the preferred next provider once SDK/WebSocket packaging is settled.
- Azure OpenAI realtime audio if the user's deployment supports it.
- OpenAI Realtime transcription as the non-Azure realtime provider.
- File transcription with OpenAI/Azure OpenAI as a fallback, not the primary UX.
- A provider setting that captures provider kind, endpoint, region, deployment/model, API version, language, and auth mode.

Current docs support the next realtime direction: Azure Speech SDK is explicitly intended for real-time recognition and supports Swift/macOS through the Objective-C framework; OpenAI has transcription-only Realtime sessions; Azure OpenAI exposes realtime audio via WebRTC/WebSocket.

### Provider Decision

Recommended default order:

1. `AzureSpeechTranscriptionProvider`: implemented first with short-audio REST, then upgrade to realtime SDK/WebSocket.
2. `AzureOpenAIRealtimeTranscriptionProvider`: useful if the user wants OpenAI-family recognition behind Azure deployments.
3. `OpenAIRealtimeTranscriptionProvider`: useful fallback outside Azure.
4. `FileTranscriptionProvider`: reliable fallback and test harness.

Azure Speech Services has one important repo-level tradeoff: the official macOS Swift path uses the Microsoft Cognitive Services Speech framework through CocoaPods or a downloaded xcframework, while Overwatchr is currently a dependency-free Swift Package. The spec therefore treats Azure Speech integration as an explicit packaging decision:

- Preferred: manually link the official `MicrosoftCognitiveServicesSpeech.xcframework` in the app bundle build flow if it can be kept small and codesignable.
- Alternative: add an Xcode project/CocoaPods wrapper only for the app target, while keeping `Core/` and CLI SwiftPM-native.
- Avoid: hiding the SDK behind an external Python/Node helper, because that would add process management and installation fragility to a menu-bar utility.

### Azure/OpenAI Configuration

Store non-secret preferences in `UserDefaults`:

- provider kind: `azureSpeech`, `azureOpenAI`, `openAI`
- Azure Speech region or endpoint
- endpoint URL for Azure
- deployment/model name
- API version for Azure
- language hint, default unset or `en`
- recognition mode: realtime streaming or fallback file transcription
- submit-command mode: off, strip phrase and press Return, or keep phrase and press Return

Store API keys in Keychain, not `UserDefaults`. Also allow environment fallbacks for development:

- `OPENAI_API_KEY`
- `AZURE_OPENAI_API_KEY`
- `AZURE_OPENAI_ENDPOINT`
- `AZURE_OPENAI_API_VERSION`
- `AZURE_OPENAI_TRANSCRIPTION_DEPLOYMENT`
- `AZURE_SPEECH_KEY`
- `AZURE_SPEECH_REGION`
- `AZURE_SPEECH_ENDPOINT`

Managed identity or Entra auth can be a later addition. For a local menu-bar utility, API key support is the fastest reliable first step.

## Architecture

### Core Layer

Keep pure parsing and provider-independent logic in `Core/`.

New core types:

- `VoiceCommandParser`: detects submit phrases and returns insertion text plus actions.
- `VoiceAudioBuffer`: provider-neutral audio chunk metadata and bytes.
- `VoiceTranscriptionEvent`: partial transcript, final transcript, speech start/end, provider diagnostics.
- `VoiceTranscriptionOptions`: language, prompt, provider options that are safe to log.
- `VoiceTranscriptionResult`: transcript text, duration, provider metadata, optional confidence.
- `VoiceInteractionState`: idle, listening, transcribing, processing, inserted, failed.

`VoiceCommandParser` should be unit-tested heavily because it controls whether Return is sent.

Suggested command rules for v1:

- Match only at the end of the utterance.
- Supported phrases: `press enter`, `hit enter`, `send it`, `submit`.
- Strip the command phrase before insertion when submit mode is enabled.
- Avoid command execution if the remaining text is empty unless a setting explicitly allows voice-only submit.
- Case-insensitive, punctuation-tolerant matching.

Examples:

- `Looks good press enter` -> insert `Looks good`, press Return.
- `Can you literally write press enter` -> insert full text, no Return if phrase is not terminal command-shaped.
- `Press enter` -> no action by default, unless voice-only submit is enabled.

### App Layer

Keep macOS-specific behavior in `App/`.

New app components:

- `VoiceInteractionController`: owns capture lifecycle, provider call, command parsing, insertion, and state.
- `AudioCaptureService`: streams microphone PCM buffers using `AVFoundation`, with optional temp-file capture for fallback/debug builds.
- `TextInsertionService`: inserts text into the focused app and optionally sends Return.
- `VoiceIndicatorPanel`: floating `NSPanel` plus SwiftUI content for state.
- `VoiceSettingsView`: settings rows for shortcut, provider, model/deployment, language, submit behavior, and microphone permission.

`AppModel` should compose the controller and publish voice state for the settings UI, but should not directly own audio encoding or HTTP details.

### Low-Latency Data Flow

1. Shortcut press creates a provider session before or immediately as microphone capture starts.
2. `AudioCaptureService` captures microphone PCM buffers and forwards them to the active session.
3. Provider emits partial transcript events; the floating indicator can show the latest partial text.
4. Shortcut release stops microphone capture and calls `finish()` on the session.
5. Provider emits a final transcript.
6. `VoiceCommandParser` splits dictation text from submit commands.
7. `TextInsertionService` pastes final text and optionally sends Return.

To reduce perceived latency, provider setup should be warm-started where safe:

- Validate credentials from settings with a lightweight test call.
- Keep provider configuration loaded in memory.
- Avoid opening network sessions before the hotkey is pressed unless the provider explicitly supports an idle connection without microphone data and without privacy ambiguity.

### Insertion Strategy

Use pasteboard-based insertion as the default:

1. Save current pasteboard contents when feasible.
2. Put transcript text on the pasteboard.
3. Send `Command + V` to the frontmost app through `CGEvent`.
4. Restore previous pasteboard contents after a short delay.
5. If submit is requested, send Return after paste completes.

This is more reliable than typing individual characters and works for long prompts. It requires Accessibility permission, which Overwatchr already surfaces for focusing.

Risks and mitigations:

- Pasteboard restoration can race with user copy actions; restore only if the pasteboard still contains the text Overwatchr inserted.
- Some secure fields block paste; show a concise failure.
- `CGEvent` key injection requires Accessibility permission; settings should clearly show this as required for voice insertion.

## Permissions

Voice interaction requires:

- Microphone permission for audio capture.
- Accessibility permission for paste/Return event injection.
- Network access to the selected provider.

The app should request microphone permission on first voice use or from settings. It should not start a capture if permission is denied. The settings pane should include direct buttons for Microphone and Accessibility privacy panes.

## Error Handling

Common failures should produce short user-facing messages:

- Microphone permission denied.
- Accessibility permission missing.
- No audio captured.
- Provider credentials missing.
- Provider request failed.
- Transcription returned empty text.
- Could not insert into focused app.

Provider errors should preserve enough detail in logs or settings for debugging, but the floating indicator should stay terse.

## Privacy And Data Handling

- Do not persist captured audio by default.
- For streaming providers, do not write audio to disk.
- If fallback temp files are used, delete them after transcription completes or fails.
- Never log transcript text by default.
- Never store API keys in repo files or `UserDefaults`.
- Add a settings note that audio is sent to the selected provider while voice mode is used.

## Testing

### Unit Tests

Add `Tests/OverwatchrCoreTests/VoiceCommandParserTests.swift` covering:

- submit phrase detection
- punctuation and casing
- false positives
- empty transcript behavior
- disabled submit mode

Provider request builders should also be testable without network calls:

- OpenAI multipart request shape
- Azure endpoint URL construction
- auth header placement
- model/deployment selection
- streaming session state transitions
- partial/final transcript ordering
- cancellation on shortcut abort

### Manual Verification

Run:

- `swift test`
- `swift build`
- `swift run overwatchr-app`

Manual smoke cases:

- Hold voice shortcut, speak text, release, verify insertion into Ghostty.
- Verify partial transcript appears before release when using Azure Speech Services.
- Speak text ending with `press enter`, verify insertion plus Return.
- Deny microphone permission, verify clean failure.
- Remove provider key, verify clean failure.
- Use a long prompt and verify pasteboard restoration.
- Confirm the floating indicator does not steal focus.

## Implementation Phases

### Phase 1: Streaming Skeleton And Mock Provider

- Add voice state model and command parser in `Core/`.
- Add hold shortcut registration.
- Add microphone PCM capture and stream session lifecycle.
- Add floating indicator panel.
- Add mock streaming provider that emits partial and final transcript events for local UI/insertion testing.
- Add pasteboard insertion service.

Exit criteria: shortcut hold shows indicator, streams mock partial text, inserts final mock text, and command parser can press Return.

### Phase 2: Azure Speech Services Provider

- Implement Azure Speech Services short-audio REST provider for the SwiftPM-buildable baseline.
- Add Azure Speech settings for key, region/endpoint, language, and connectivity test.
- Add low-latency manual smoke tests.

Exit criteria: real Azure Speech Services transcription inserts final text promptly after release.

### Phase 2.5: Azure Speech Realtime Upgrade

- Decide packaging path for the Azure Speech SDK: xcframework in build scripts, app-specific Xcode/CocoaPods wrapper, or documented WebSocket transport.
- Implement Azure Speech Services realtime recognition provider.
- Surface partial transcript text while speaking.

Exit criteria: real Azure Speech Services transcription streams partial text while speaking and inserts final text promptly after release.

### Phase 3: Azure/OpenAI Realtime Providers

- Add provider config and Keychain storage.
- Implement Azure OpenAI realtime transcription provider where deployment support exists.
- Implement OpenAI realtime transcription provider.
- Keep file transcription provider as fallback for environments without realtime access.
- Add settings rows for provider credentials and deployment/model.
- Add request-builder tests.

Exit criteria: real transcription works with Azure Speech, Azure OpenAI realtime, or OpenAI realtime and does not persist audio/transcript.

### Phase 4: Polish And Robustness

- Improve error messages and settings validation.
- Add provider connectivity test button.
- Add language/prompt options.
- Add audio level animation in the indicator.
- Add app bundle entitlements or usage descriptions needed for microphone access.

Exit criteria: feature is releasable in the normal `install.sh` and app bundle flow.

## Open Decisions

1. Default shortcut: recommended `Control + Option + Command + Space`, but this needs a collision check against the user's current macOS setup.
2. Azure Speech realtime packaging: manually link xcframework, add an app-specific Xcode/CocoaPods wrapper, implement a documented WebSocket transport, or accept REST short-audio as the buildable baseline.
3. Submit phrases: whether `send it` should be enabled by default or only `press enter`.
4. Pasteboard UX: whether to expose a setting for "restore pasteboard after insertion".
5. Latency target: recommended release-to-insert under 500 ms after final speech recognition, with partial transcript visible during speech.

## References

- OpenAI Realtime transcription: https://platform.openai.com/docs/guides/realtime-transcription
- OpenAI speech-to-text guide: https://platform.openai.com/docs/guides/speech-to-text
- OpenAI audio transcription API reference: https://platform.openai.com/docs/api-reference/audio/transcribe
- Azure OpenAI audio concepts: https://learn.microsoft.com/en-us/azure/ai-services/openai/concepts/audio
- Azure OpenAI realtime audio WebRTC: https://learn.microsoft.com/en-us/azure/ai-services/openai/how-to/realtime-audio-webrtc
- Azure Speech to text overview: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-to-text
- Azure Speech SDK overview: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/speech-sdk
- Azure Speech SDK setup for Swift/macOS: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/quickstarts/setup-platform
- Azure Speech recognition how-to: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-recognize-speech
