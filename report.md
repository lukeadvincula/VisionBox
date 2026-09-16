# VisionBox Phase 3 — BYOK Settings & UX + First Live Gemini Validation

**REPORT_VERSION:** 4
**Date:** 2026-09-15
**Phase:** Phase 3 — BYOK Settings & UX + First Live Gemini Validation

Rolling implementation report: describes the most recently completed phase and is completely replaced (REPORT_VERSION incremented) by each subsequent implementation task. Replaces the Phase 2 report (v3).

---

## Initial Repository State

Phase 2 left the complete Gemini plumbing without user-facing key management: `GeminiDetectionService` (Interactions API, structured output, y-first box mapping), `KeychainService`, `DetectionError`, `ImageProcessing`, and a `ScanViewModel` whose photo-ready state gated a disabled Analyze button on key presence — with the noted flaw that availability checks read the Keychain during SwiftUI body evaluation. Settings was still a placeholder ("Gemini API Key — Coming soon"). 72 unit tests passed; live Gemini validation was pending because no key-entry UI existed.

---

## Implementation Performed

- **`GeminiKeyStore`** — a small `@MainActor @Observable` credential-state model backed by `KeychainService`, shared by Settings and Scan; the new single source of truth for key presence.
- **Real BYOK Settings** — `SettingsViewModel` + a rebuilt `SettingsView`: SecureField entry, Save & Test, Test Connection, masked configured state, Edit Key, Remove Key with confirmation, official "Get a Gemini API Key" link, and concise privacy copy.
- **Connection validation** — `GeminiDetectionService.validateKey()` using `models.get`, plus a live-API finding: Google returns HTTP 400 + `API_KEY_INVALID` for bad keys, now correctly classified as `unauthorized`.
- **Scan integration** — "Set Up Gemini" routing from the no-key photo state directly into Settings, "Analyze with Gemini" when configured, selected photo preserved throughout, all Phase 2 development wording removed.
- **29 new unit tests** (101 total, all passing) and updated previews across Settings and Scan.

---

## BYOK UX

- **First setup** (no key): Settings shows a "Gemini API" section with Status "Not Set Up", a SecureField ("Paste your Gemini API key", no autocapitalization/autocorrection), a Save & Test button disabled until non-whitespace input exists, the Google AI Studio link, and footers explaining Keychain storage and Demo Mode's zero-key path.
- **Configured**: Status "Configured"; the key is shown only as `••••••••••••••••` (never plaintext, never partial characters); actions are Test Connection, Edit Key, and Remove Key…, plus a connection-status row (progress while testing, green checkmark "Connected", or an orange warning with concise failure wording).
- **Edit**: "Edit Key" swaps in a "Replace API Key" section with an **empty** SecureField (the stored key is never pre-populated or exposed), Save & Test, and Cancel.
- **Remove**: "Remove Key…" presents a native alert — "Remove Gemini API Key?" with "You'll need to add a Gemini API key again to analyze personal photos. Demo Mode will keep working.", a destructive Remove Key and an explicit Cancel. (Originally a `confirmationDialog`; switched to `alert` after simulator verification showed the dialog exposed no visible Cancel affordance.)
- **Get a Gemini API Key**: a `Link` to `https://aistudio.google.com/apikey` — verified as the current official Google AI Studio destination — opening externally, with an accessibility hint.
- **Privacy/security copy** (kept short): VisionBox includes no developer key; the user's key is stored in the Keychain on this device and sent only to Google's Gemini API; Demo Mode needs no key or network. No unsupported claims about Google's data retention are made.

---

## Credential State Architecture

- **Representation**: `GeminiKeyStore.isKeyConfigured`, an observable `Bool` initialized from one Keychain read and updated by `save`/`remove`. The key material itself is deliberately **not** observable state — `currentKey()` reads the Keychain fresh, only at explicit lifecycle points.
- **Propagation to Scan**: `ScanViewModel.isLiveAnalysisAvailable` returns `keyStore.isKeyConfigured`. Because the store is `@Observable` and shared via `AppDependencies`, saving/removing a key in Settings re-renders the photo-ready screen immediately — no restart, no refresh call, no notification machinery.
- **Body-time Keychain reads eliminated**: Phase 2's `liveDetectionService() != nil` availability check (a Keychain read per body evaluation) is gone. The Keychain is now touched only at store init, save, remove, and the moment an analysis or connection test starts.
- **No stale services/keys**: nothing retains a `GeminiDetectionService`. `ScanViewModel` holds a `(String) -> any ObjectDetectionService` factory; `analyzePhoto()` reads `keyStore.currentKey()` and constructs the service fresh per analysis, so a replaced key is used on the very next analysis. Unit-tested (`analysisUsesTheCurrentKeyNotTheKeyAtCreationTime`).
- The store has an in-memory mode (`init(previewKey:)`) used by previews and unit tests so neither ever touches the real Keychain.

---

## Save & Test

- **Local input handling**: surrounding whitespace and newlines are trimmed; empty/whitespace-only input is rejected before any save (button disabled, and the model guards regardless). No format or length rules — current Google documentation gives no key-format guarantees (and notes a transition to new "auth keys"), so remote validation is the authority.
- **Save semantics**: the trimmed key is written through `GeminiKeyStore` → `KeychainService` (delete-then-add replacement, device-only accessibility). On Keychain failure the draft is kept for retry and a clear failure status is shown. On success the plaintext draft is cleared immediately and edit mode ends.
- **Remote validation** then runs automatically against the saved key (same operation as Test Connection).
- **Failure behavior**: saving and validation are distinct. A stored key is **never auto-deleted** — not on invalid-key results and especially not on network/rate-limit/server failures, since the user may have entered a valid key during a temporary outage. The UI keeps Status "Configured" alongside the failure message; the user chooses Edit or Remove. Unit-tested for both the invalid-key and network-failure cases.

---

## Gemini Connection Validation

- **Documentation checked** (ai.google.dev, 2026-09-15/16): the models API reference confirms `models.get` — `GET https://generativelanguage.googleapis.com/v1beta/models/{model}` — as a current lightweight metadata operation; the api-key docs confirm `x-goog-api-key` as the auth header and `https://aistudio.google.com/apikey` as the official key page.
- **Operation used**: `GET /v1beta/models/gemini-3.8-flash` — the exact model VisionBox relies on. Chosen because it authenticates the key and confirms access to the configured model while generating nothing: **no tokens consumed, no image sent, no request body at all**, independent of Scan state. The docs' curl samples show `?key=` query auth; VisionBox deliberately uses the header instead so the key never appears in a URL (unit-tested).
- One user action → one validation attempt; the in-flight task is retained, repeated taps are prevented (button disabled while testing), a newer request cancels the previous one, and dismissing Settings cancels an in-flight test without leaving a stuck "testing" state.
- **Live finding (fixed)**: against the real endpoint, an invalid key returns **HTTP 400 with error reason `API_KEY_INVALID`** — not 401/403 as Phase 2's mapping assumed. `error(forStatusCode:body:)` now inspects 400 bodies (via a minimal `GoogleErrorEnvelope` used for classification only, never surfaced) and maps `API_KEY_INVALID` to `.unauthorized`, so users see "Invalid API key" instead of a generic failure. Other 400s remain `.invalidResponse`. Covered by new unit tests.

---

## Scan Integration

- **No key + personal photo**: the photo-ready screen shows the photo with "Gemini API Key Required" / "Add your own Gemini API key to analyze personal photos." and actions **Set Up Gemini** (opens Settings directly), **Try Demo Mode**, and **Choose a Different Photo**. No disabled Analyze button and no development wording ("arrives in Settings next") remains anywhere.
- **Configured + personal photo**: "Photo ready to analyze." with a prominent **Analyze with Gemini** button (explicit Gemini wording per BYOK clarity) → `ImageProcessing.prepareForUpload` → fresh `GeminiDetectionService` → existing Results UI.
- **Photo preservation**: Settings is a sheet over the unchanged `photoReady` state, so the selected photo survives setup; after saving a key and tapping Done, the *same* photo immediately offers Analyze with Gemini (observable propagation, verified on-simulator both directions — including reverting to "Set Up Gemini" the moment the key is removed).
- Idle screen still leads with Try Demo Mode + Choose Photo; key setup is never forced at launch — a reviewer can go straight into Demo Mode.

---

## Demo Mode

Unchanged: `DemoDetectionService`, bundled scenes, zero key, zero network, same `ResultsView`, available regardless of key state, and no automatic fallback from failed live analysis. Re-verified end-to-end on-simulator this phase (Everyday Carry scene) and guarded by a new explicit test (`demoModeNeverNeedsAKey`).

---

## Live Gemini Validation

**LIVE VALIDATION PENDING** (for the full detection pipeline).

- What **was** exercised live: the Save & Test / Test Connection path made real HTTPS requests to `generativelanguage.googleapis.com` from the simulator using an intentionally fake key. Google's real 400/`API_KEY_INVALID` response was observed, exposed a classification bug, and drove a fix — so the validation request path, error mapping, and Settings status UX are verified against the actual live API.
- What was **not** exercised live: no real Gemini API key was available in this environment, and none was created, hard-coded, or requested — so no authenticated `models.get` success and no live `interactions` object-detection call occurred. Test Connection's success path and the full photo → Gemini → boxes flow remain fixture-tested only.
- The moment a user enters their own key through the real Settings UI, the intended validation flow is: Save & Test → Connected → choose a photograph → Analyze with Gemini → visually confirm box alignment and selection.

---

## Interactions API Response Verification

Still **fixture-tested only** — the live requests made this phase were `models.get` validation calls, not `interactions` calls, so the Phase 2 envelope assumptions (`steps[].type == "model_output"` → `content[].text`) remain unverified against a real detection response. This stays the first thing to confirm when a real key is configured. (The phase did prove the value of live checking: the first real API contact immediately corrected an assumed error contract.)

---

## Errors / Status UX

`SettingsViewModel.ConnectionStatus` models exactly what the UI needs: `untested / testing / connected / failed(String)` — deliberately small, and separate from credential presence (a stored key with a failed test shows "Configured" + the failure). Failure wording maps from the existing `DetectionError` (no parallel error hierarchy): "Invalid API key" (unauthorized, including the 400/`API_KEY_INVALID` case) · "Rate limited — wait a moment and try again" · "Could not connect — check your internet connection" (network) · "Gemini is temporarily unavailable" (5xx) · generic retry copy otherwise. Keychain save/remove failures surface as explicit status messages. No raw provider text, response bodies, or key material ever appears; Scan's analyze errors continue using `DetectionError.userMessage`.

---

## Accessibility

Phase 3 UI only (full audit remains Phase 6): SecureField has an explicit "Gemini API key" accessibility label; the masked key row is a single element reading "API key stored" (fixed a duplicate-label readout found during verification); connection status combines icon + text, never color alone; testing state uses a visible ProgressView with text; Remove Key is a destructive-role alert action with an explicit Cancel; the external link has a "Opens Google AI Studio in the browser" hint; all buttons are full text labels; no-key/configured states are explained by adjacent copy rather than a mute disabled button.

---

## Tests

Swift Testing; **101/101 passing**. UI tests were not added and were not run.

Added in Phase 3 (29):
- `GeminiKeyStoreTests` (5): initial state with/without key, save configures + exposes, replacement, removal — via the in-memory mode so suites never contend for the real keychain item.
- `SettingsViewModelTests` (16 incl. 3 parameterized): trimming (whitespace + newlines), whitespace-only rejection (no save, no validation), Save & Test success (connected, draft cleared, edit ended), invalid key keeps the stored key, network failure keeps the stored key, status-wording table, Test Connection uses the stored key, Test Connection without a key fails without validating, edit asks for a replacement without exposing the old key, replacement key saved+validated, remove clears credential and status, in-flight test cancellation returns to untested and never clobbers state.
- `ScanViewModelTests` additions (4 new: 12 total in suite): availability follows the key store; save/remove updates availability immediately; **analysis uses the current key, not the key at VM creation** (stale-credential guard); demo never needs a key; plus the existing demo/live/cancellation tests updated to the key-store initializer.
- `GeminiRequestTests` additions (2): validation request is a minimal authenticated GET to `/v1beta/models/gemini-3.8-flash`; it carries no body (no image, no personal data) and no key in the URL.
- `GeminiTransportTests` additions (3): `validateKey` end-to-end through stubbed URLSession — success, 403 → unauthorized, 429/503 mapping.
- `GeminiResponseTests` additions (2): 400 + `API_KEY_INVALID` body → `.unauthorized`; other/undecodable 400 bodies remain `.invalidResponse`.

Retained: all 72 Phase 0B–2 tests, including the unchanged `KeychainServiceTests` (round-trip, overwrite, delete, nil-when-absent). No real keys anywhere in tests — only obviously fake values.

---

## SwiftUI Previews

Standing rule (restated): **always add SwiftUI previews for new or modified SwiftUI views and reusable UI components whenever practical/necessary**, covering important states and layouts.

- `SettingsView` (all new): First setup, Configured, Testing, Connected, Invalid key, Connection failure, Editing key — every one on an in-memory `GeminiKeyStore` with a no-op validator: no Keychain writes, no networking, no real keys.
- `ScanView` (updated): Idle, Photo ready (no API key — the Set Up Gemini state), Photo ready (key configured — Analyze with Gemini), Analyzing, Gemini error — via in-memory stores and stub services.
- Results/Demo picker previews unchanged (their UI didn't change).

---

## Build & Simulator Validation

- **Build** (app + test targets): succeeded, zero warnings. **Unit tests**: 101/101. No UI tests run.
- **Simulator verification** (interactive sessions, full BYOK pass): idle intact → no-key photo flow shows the key-required state with no fake detections → Set Up Gemini routes directly into Settings → typing a deliberately fake key into the SecureField (masked throughout; never visible in screenshots, hierarchy, or logs) → Save & Test hit the **real Google endpoint** and, after the fix, shows Status "Configured" + "Invalid API key" → Done returns to the *same* photo now offering Analyze with Gemini → Test Connection re-runs cleanly → Edit Key shows an empty replacement field → Remove Key alert shows destructive Remove + Cancel, Cancel preserves the key, Remove reverts Settings to "Not Set Up" → the photo screen immediately reverts to Set Up Gemini with no restart → Demo Mode still works end-to-end → final check confirmed nothing of the fake key remains.
- Two issues found by verification were fixed and re-verified live: the 400/`API_KEY_INVALID` classification and the missing visible Cancel on the remove confirmation.

---

## Security Review

Repository-wide scan after implementation (no findings): no `AIza…` patterns; no key/secret/token literals beyond obviously fake test/preview values (`TEST-KEY-NOT-REAL`, `test-key…`, `preview-key`); no `.env`/`.xcconfig` files; no `key=` URL construction anywhere; no `print`/logging in app code (the only `print` in the repo is the demo-asset generator's output path); fixtures contain no secrets, user data, or base64 images. The fake key typed during simulator verification (`fake-key-for-testing-12345`) appears nowhere in the repository and was removed from the simulator's keychain through the app's own Remove Key flow. This report contains no credentials.

---

## Files Changed

Created:
- `VisionBox/Services/GeminiKeyStore.swift`
- `VisionBox/Features/Settings/SettingsViewModel.swift`
- `VisionBoxTests/GeminiKeyStoreTests.swift`
- `VisionBoxTests/SettingsViewModelTests.swift`

Modified:
- `VisionBox/Features/Settings/SettingsView.swift` (full BYOK UI replacing the placeholder)
- `VisionBox/Features/Scan/ScanView.swift` (Set Up Gemini routing, Analyze with Gemini, dependencies for Settings, updated previews)
- `VisionBox/Features/Scan/ScanViewModel.swift` (key store + per-analysis service factory)
- `VisionBox/App/AppDependencies.swift` (`geminiKeyStore`, `liveDetectionService(apiKey:)`, `validateAPIKey`)
- `VisionBox/Services/Gemini/GeminiDetectionService.swift` (`validateKey`, `makeValidationRequest`, shared `send`, body-aware 400 classification)
- `VisionBox/Services/Gemini/GeminiModels.swift` (`GoogleErrorEnvelope` for error classification)
- `VisionBoxTests/ScanViewModelTests.swift`, `GeminiRequestTests.swift`, `GeminiResponseTests.swift` (updates/additions)

Removed: none. `KeychainService` itself was intentionally untouched.

---

## Deferred Work

- **Phase 4 — Camera** capture (PhotosPicker remains the only personal-photo input).
- **Phase 5 — Reliability**: retry/backoff, `Retry-After` handling, richer error recovery (Test Connection and Analyze remain strictly one attempt per user action).
- **Phase 6**: iPhone Duo/fold validation, visual polish (incl. the carried selection-contrast note and the Phase 1 rotation/selection watch item), full accessibility pass.
- **Phase 7**: public release — README (including Get-a-key setup guidance), screenshots, repo cleanup.
- **First real-key validation**: authenticated Test Connection success, live `interactions` detection on a real photograph, and confirmation of the Interactions response envelope (see above).

---

## Deviations From Phase 3 Plan

- **A `SettingsViewModel` was added** (the prompt's diagrams show SettingsView → KeychainService directly). It matches the app's existing MVVM shape, and Save & Test/Test Connection state, cancellation, and message mapping genuinely need a home; the allowance for "one small additional observable state/model" was spent on `GeminiKeyStore` + this VM.
- **Remove confirmation is an `alert`, not a `confirmationDialog`**: verification showed the dialog rendered without a visible Cancel affordance; the alert guarantees both actions are explicit (accessibility win).
- **Keychain save/remove failure paths are not unit-tested**: the in-memory test mode cannot fail, and forcing failure would require test-only architecture the prompt forbids; the paths are 3 lines each and surface status messages. Documented rather than hidden.
- **Connection status is per-Settings-presentation** (a fresh VM per sheet): last-test results are not persisted across opens — credential presence is; deliberate simplicity.
- **`AppDependencies` properties became `var`** so the synthesized memberwise initializer lets previews inject in-memory stores (Swift omits `let`-with-default from memberwise inits).

---

## Issues / Follow-ups

1. **Interactions envelope still unverified live** (carried from Phase 2, unchanged priority): first real-key detection should confirm `model_output`/text extraction against an actual response.
2. **The 400-classification lesson generalizes**: other Google error reasons (e.g. quota exhaustion variants) may also arrive as 400/429 with informative `details[].reason` values; Phase 5's reliability pass should review live error bodies when a real key is available.
3. Minor: the "Set Up Gemini" key SF Symbol reads as "Passwords" in the raw accessibility hierarchy (VoiceOver reads the button's title correctly); cosmetic, Phase 6.
4. Phase 1's unreproducible rotation/selection observation: not seen again; still on the Phase 6 watch list.

---

## Recommended Next Phase

**Phase 4 — Camera.** Add camera capture as a second personal-photo source alongside PhotosPicker: a simple native capture flow (no AVFoundation live-preview stack unless the portfolio explicitly wants it — a `UIImagePickerController`-style camera wrapper is the right size), the `NSCameraUsageDescription` entry, camera availability checks (device vs simulator), and routing the captured `UIImage` into the existing `photoReady` → Analyze with Gemini pipeline — which already handles EXIF orientation normalization, downscaling, and BYOK gating unchanged. Keep Demo Mode and PhotosPicker untouched; no retry work (Phase 5), no new architecture.
