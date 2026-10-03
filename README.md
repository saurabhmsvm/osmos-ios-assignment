# Osmos Ad Lab

A native **SwiftUI + MVVM** assignment demo: manually render Osmos display banners, measure their visible image area, and submit impression/click events through the SDK.

> **Verification status:** Manual testing confirmed live SDK fetching, response parsing, image downloading/rendering, and impression submission. The demo service returned a 200 × 200 placeholder graphic without a landing URL. The app displays it with a missing-URL notice and skips navigation/click events. The SDK reported impression success; backend attribution has not been independently verified. There are 60 unit tests and 6 UI tests; passing test-suite results have not yet been recorded. Full live click navigation requires a creative with a landing URL.

## Open and run in Xcode

1. Open **[OsmosDemo.xcodeproj](OsmosDemo.xcodeproj)** in Xcode.
2. Allow Xcode to resolve the pinned Osmos package. Use **File → Packages → Resolve Package Versions** if necessary.
3. Select the **OsmosDemo** scheme and an iPhone simulator.
4. Choose **Product → Run**. No development team is needed for a simulator. For a physical device, select your own team under **Signing & Capabilities** and use a unique bundle identifier if needed.
5. Tap **Load Ad**. Each successful tap appends the first banner from a separate AU request. Load several to demonstrate scrolling.
6. Open **Event log** at the top to inspect event submissions and results.

**Toolchain:** Project configured for iOS 15+ and Swift 5 language mode. The pinned SPM package requires Swift tools 6.0 (Xcode 16+). Xcode 26.6 is installed on the development machine; other toolchain combinations have not been verified. No iOS 15 runtime was available during setup.

**Dependency:** [Official Osmos SPM package](https://github.com/onlinesales-ai/osmos-ios-sdk-spm), exactly **2.6.4**. This version exposes the documented switch for disabling implicit event retries. No additional third-party libraries are used.

### Safe first walkthrough

The default mode is **Live Osmos**, but **nothing is fetched until you tap Load Ad**. In a Debug build, open **Demo scenarios** and select **Successful ads** first to explore without generating real ad traffic. Fixture modes display their status prominently and use a separate fake event sender. Their example.com landing link can still open externally.

Do not paste passwords or GitHub tokens into source files. The SDK repository is public. If Xcode asks for Keychain access, read the exact macOS prompt before approving it; a simulator build does not need your distribution signing key.

## What the app does

- SwiftUI `Image` inside a `ScrollView` / `LazyVStack`, not SDK-rendered banners or UIKit view wrappers.
- Image dimensions from the response control layout; aspect-fit rendering prevents stretching.
- Loading, image-loading, no-fill, SDK failure, parsing failure, image failure, and retry states.
- Multiple independently fetched ads, with duplicate served identities rejected.
- At most one impression submission per served identity in the retained feed session.
- External landing-page opening using SwiftUI `openURL`; rapid duplicate taps suppressed.
- Local analytics plus a bounded, readable event log.
- Light/dark colors, Dynamic Type, accessibility labels, and rotation-aware layout.

## Architecture / folder structure

| Location | Responsibility |
| --- | --- |
| [App](OsmosDemo/App) | SwiftUI entry point and `@StateObject`-retained `DemoSession` composition root |
| [Configuration](OsmosDemo/Configuration) | Exact assignment configuration and validation |
| [Models](OsmosDemo/Models) | Typed banner, sanitized errors, URL validation |
| [Services/Osmos](OsmosDemo/Services/Osmos) | One retained SDK instance, fetch/event adapter, dictionary-to-model parser |
| [Services/Images](OsmosDemo/Services/Images) | Shared downloads, caching, bounded decoding, cancellation |
| [Services/Analytics](OsmosDemo/Services/Analytics) | Session impression ledger, event submission, structured logs |
| [Services/Fixtures](OsmosDemo/Services/Fixtures) | Explicit simulated responses, generated artwork, fake tracking |
| [Features/AdFeed](OsmosDemo/Features/AdFeed) | Feed ViewModel and SwiftUI presentation |
| [Features/Diagnostics](OsmosDemo/Features/Diagnostics) | Scenario selector and event log |
| [Shared/Visibility](OsmosDemo/Shared/Visibility) | Pure geometry math and SwiftUI preference key |
| [Tests](Tests) / [UITests](UITests) | Unit and fixture-only UI tests |

**Flow:** View intent → ViewModel → injected service → typed state → View.

`DemoSession` retains the screen ViewModel; views observe it with `@ObservedObject`. Business logic and SDK calls do not run in SwiftUI `body`. The event ledger belongs to `AdEventTracker`, not row-local state. Geometry is measured in the view; SDK-independent rectangle math remains separately testable. One window is supported to prevent different scenes sharing the same visibility state.

## Ad fetching and response mapping

The SDK is constructed using the throwing, on-demand builder, not the global initializer:

| Setting | Value |
| --- | --- |
| clientId | `10088010` |
| productAdsHost | `demo.o-s.io` |
| displayAdsHost | `demo-ba.o-s.io` |
| cliUbid | `Any` |
| pageType | `demo_page` |
| adUnits | `["banner_ads"]` |
| productCount | `1` |

The adapter calls `fetchDisplayAdsWithAu`. The parser unwraps the SDK's `status` / `response.code` / `response.data` envelope, decodes the string body as a JSON object, then selects `ads.banner_ads[0]` and extracts the image URL, destination URL, width, height, and both tracking URLs. Direct, already-decoded payloads remain supported for fixtures.

The envelope requires Boolean `status: true` and an integer HTTP code. Non-2xx codes use the existing HTTP error/retry policy; 204 reports no ads. JSON decoding is limited to 1 MiB, with malformed/non-object bodies rejected without logging their contents. Manual live diagnostics confirmed successful decoding with `ads.banner_ads` as an array, `elements` as an object containing image value/dimensions, and banner-level uclid/tracking URL strings. The tested response lacked a destination.

### Response assumptions that require a live check

The assignment provides a field list, not a complete response. The parser currently supports:

- `elements` as an object, or an array containing an explicitly typed `image` element.
- Optional element destination under `destination_url` (assignment spelling) or `destinationUrl` (also present in the SDK model strings). If both fields are absent, render without a destination. Every supplied value must still be a valid web URL and agree with other aliases; null, empty, unsafe, or conflicting values are rejected. Tracking URLs are never substituted for a destination.
- `width` / `height` at banner level or inside that image element, as numbers or numeric strings representing 1–100,000 pixels.
- Optional Boolean `status`; if supplied, it must be `true`.
- An explicit banner `uclid`, or the exact `uclid` query key in the tracking URLs. Every available value must agree. **No creative ID, random UUID, or undocumented query field is substituted.**

The query-key fallback is a documented implementation assumption, not a verified live contract. If the real payload differs, update [BannerResponseParser.swift](OsmosDemo/Services/Osmos/BannerResponseParser.swift) and add a sanitized fixture/test. Unsupported or inconsistent metadata shows **“Ad not available”** rather than sending incorrectly attributed events.

Images and tracking URLs require HTTPS. Landing pages accept HTTP(S), with HTTPS preferred. Credentials in URLs and non-web schemes are rejected. There is no blanket ATS exemption.

The assignment does **not** specify `eventTrackingHost`, so the SDK's documented default is retained. Confirm that the demo account uses that host before asserting live tracking works.

For an unsupported live response, check **Event log → Response Diagnostic**. It distinguishes SDK callback errors, a nil response, invalid JSON, and a parser rejection. If JSON decoding succeeds but ad mapping fails, the diagnostic describes the decoded body rather than only the outer wrapper. Diagnostics show allowlisted field names/types, array counts, and recognized status/code tokens—never full URLs, tracking ID values, or server messages. **Debug only:** inside `elements`, up to eight additional field names are marked `(unmapped)` with their types; names must contain only ASCII letters/underscores and be at most 48 characters, otherwise the name is redacted. Unknown nested dictionaries are not traversed. This is diagnostic discovery, not permission to use an unknown field as a destination.

## Xcode console diagnostics

In a Debug build, filter the Xcode debug console for **`[Osmos Live]`** after selecting Live Osmos and tapping Load Ad. Prints distinguish SDK initialization, a nil/error response, redacted response structure, parsed banner metadata, missing landing URL, image memory-cache/coalescing, HTTP status, received byte count, decoded pixel dimensions, and assignment to SwiftUI state. Image downloads use a local diagnostic ID, not an ad tracking ID. URLs, response bodies, and tracking identifiers are not printed; SDK raw debug logging remains disabled. Fixture artwork does not use this download path. Release builds do not print these diagnostics.

**`decode SUCCESS` means actual image bytes were received and decoded**, not that they contain a real advertisement. A grey “200 × 200” image can itself be placeholder artwork supplied by the demo service. A subsequent “assigned to SwiftUI state” entry confirms the image reached the view model, not proof that it was visible on screen. A missing landing URL alone does not block image rendering.

## Current live integration blocker

The latest diagnostic confirms the fifth image-element field is `omVerificationScripts`, not a destination. The returned image element has no landing URL. **Per the user's requested graceful degradation**, the app now displays the image, keeps normal 50% impression tracking, labels the card **“Landing URL unavailable”**, and shows a dismissible three-second message on load and tap. The message occupies footer space, not the measured image area. Missing-destination taps do not navigate or submit click events. The app does not invent a URL, execute verification scripts, open the image URL as a landing page, or request a tracking link as a substitute. This enables image display but does not fulfill the assignment's landing-page navigation requirement for that incomplete response.

Use **Demo scenarios → Missing landing URL** to verify this behavior locally without real tracking. Valid destinations retain normal click/navigation behavior; other invalid required fields still show **“Ad not available.”**

Ask the assignment provider/Osmos to confirm the creative destination for client `10088010`, page `demo_page`, AU `banner_ads`, and which response field supplies it. A configuration issue is possible, not proven. [Ad configuration documentation](https://dev-hub.osmos.ai/reference/ad-elements-configuration-inputs-ad-formats) describes advertiser-provided destination inputs. [Click API documentation](https://dev-hub.osmos.ai/reference/register-clicks.md) distinguishes redirecting `/click` from asynchronous `/aclick`; it does not establish that this response's missing landing URL can be recovered safely. Do not issue tracking requests merely to investigate redirects.

## How the 50% impression rule works

1. Only a successfully rendered image emits a geometry preference. Loading/error placeholders never qualify; placeholder artwork actually returned by the ad service is still a rendered creative.
2. The rendered creative and the scroll viewport are measured in one named coordinate space.
3. Aspect-fit letterboxing is excluded from the creative rectangle.
4. `visibleFraction = intersectionArea / creativeArea`. Horizontal and vertical clipping both count.
5. An active, visible, uncovered screen qualifies at **>= 0.50**, including exactly 50%. No extra dwell time is added because the assignment does not require one.
6. The main-actor event tracker reserves the served identity **before** asynchronous SDK work, then invokes `registerAdImpressionEvent` with `cliUbid`, `uclid`, and a one-based feed position.

Scrolling away/back, body reevaluation, rotation, and returning from a browser do not clear the ledger. A genuinely different served identity can count again even when the image is the same. Diagnostic sheets and inactive scenes suspend eligibility.

This is **geometric visibility in the known app layout**, not arbitrary pixel-occlusion detection or an OMID certification. There are no translucent overlays over the measured creative. Rounded card chrome sits outside the rectangular creative area. An extremely tall ad that cannot reach 50% in the viewport is not artificially counted.

### Submission is not guaranteed delivery

**Impression Fired / Click Fired** mean app-level submission initiated. Separate result entries show acknowledged, unconfirmed, simulated, or failed. A Boolean `status: true` response is treated as acknowledgement; other non-nil response shapes remain unconfirmed. The event receipt handler does not independently validate a nested HTTP response code. The displayed “server acknowledged” label therefore means SDK-reported success, not independently verified backend attribution.

SDK event batching and automatic retry batching are disabled for the pinned release. The app does not manually ping tracking URLs as well, and it does not retry ambiguous impression failures. This prevents duplicate app submissions; network exactly-once delivery is not guaranteed without server idempotency. Event tasks are owned outside row lifetimes, but iOS suspension can still interrupt delivery after an external link opens.

## Click handling

The ViewModel captures the selected ad identity, verifies image readiness and screen eligibility, suppresses rapid duplicate taps, initiates `registerAdClickEvent`, and returns the validated destination. The view hands it to `openURL` without waiting for tracking success.

- The system chooses the browser or associated app; there is no embedded browser wrapper.
- A rejected URL-opening request produces user feedback independently of tracking.
- Acceptance by `openURL` is **not** proof that the remote page loaded.
- A later deliberate click is allowed.
- Clicking below 50% never forces an impression.
- An absent landing URL shows a toast without navigation or a click event; impression eligibility is unchanged. Repeated eligible taps restart the toast duration, with the existing rapid-tap guard retained.

## Retry, cancellation, and resource limits

- Fetches: **3 total attempts**, with approximately 1s / 2s backoff plus small jitter for transient network/timeouts/408/429/5xx.
- No automatic retry for no-fill, invalid fields, initialization errors, or permanent client errors. Manual Retry remains available.
- The SDK exposes no Retry-After header in this API; 429 uses a minimum 5-second bounded delay rather than a tight loop.
- A main-actor guard covers fetching and retry delays. If cancellation is ignored by the SDK, the guard stays occupied until it returns; late results are discarded rather than overlapped by another request.
- Backgrounding cancels pending fetch/retry work. Returning does not automatically issue another request; the user can retry once the old operation completes.
- Images use shared URL tasks, an 8 MiB payload limit, a source-pixel limit, 1,600px maximum decoded dimension, and bounded caches. The last cancelled consumer cancels the shared download.
- Image tasks are **feed-owned**, not tied to lazy-row recreation; scrolling away does not cancel and restart an otherwise useful download. Switching demo scenarios cancels obsolete feed-owned work. Identity checks prevent wrong-row updates.
- A session is capped at **20 banners** to bound retained images and state. Relaunch to start a new feed.
- SDK initialization errors require fixing configuration and relaunching; a fetch retry cannot repair an invalid configuration.

## Tests to run in Xcode

Choose **Product → Test** on the **OsmosDemo** scheme.

**60 unit tests + 6 UI tests are included; execution results are not yet recorded.** They cover SDK envelope/JSON decoding, rendering/impressions/toasts without a destination, destination aliases and conflicting/unsafe URLs, HTTP/no-content handling, redacted and scoped unmapped-field diagnostics, exact config values, malformed fields, URL schemes, dimension bounds, 49.9%/50% boundaries, clipping/letterboxing, retry policy, concurrent tap suppression, cancellation, duplicate ad identities, once-only impressions, click failure independence, image decoding/cache/coalescing, and bounded logs.

Unit tests use service doubles and an isolated `URLProtocol`. The shared test scheme sets `OSMOS_TEST_MODE=1`; UI tests explicitly launch fixture scenarios. Automated tests do not intentionally fetch live ads or send Osmos events. Live SDK argument/host behavior still needs a controlled manual integration check.

For a reproducible launch scenario, add `--scenario` and `success` (or another enum raw value) under **Edit Scheme → Run → Arguments** in a Debug build. Remove those arguments to return to default Live Osmos. Debug fixtures are not a hidden fallback for real failures.

## Demo recording and submission

Record a short walkthrough showing:

1. Live SDK loading and the returned banner rendering; identify the current demo graphic as placeholder artwork.
2. Several banners in the feed and scrolling across the 50% threshold.
3. Returning to an already-counted banner without another impression.
4. The live missing-URL notice, followed by a clearly labeled Successful ads fixture demonstrating destination opening and simulated click logging. Do not present fixture events as live tracking.
5. Labeled fixture scenarios showing no-fill/broken image/retry recovery.

**App artifact:** Clarify whether the evaluator expects a zipped simulator `.app` or a signed device `.ipa`. They are not interchangeable. Produce the artifact from the **final, verified Xcode build**. Device export needs suitable signing/provisioning. Do not commit certificates, passwords, profiles, or private keys.

**Delivery status:** A final app artifact and demo recording are not included yet. Add them before final submission, or attach them to a GitHub Release and add actual download links here if the evaluator accepts that format. Do not upload an entire DerivedData folder or an old build as the final artifact.

## Assumptions and challenges

- The PDF mixes iOS requirements with Android hyperlink targets/terminology. Correct iOS documentation and lifecycle APIs are used.
- “ImageView” is interpreted as an image-displaying component; all authored app UI uses SwiftUI `Image`, per the selected approach.
- SDK documentation examples omit some details: the actual 2.6.4 builder throws, and its inspected public interface does not expose the documented `isConfigured` property. The adapter uses `try`, optional component checks, and sanitized failures instead.
- The event API requires a `uclid`, omitted from the assignment's field list. Attribution must fail closed until a supported identity is available.
- Manual live verification received HTTP 200 from both the SDK ad request and image download, decoded 1,661 bytes into a 200 × 200 image, reported 100% visibility, and submitted an impression with SDK-reported acknowledgement. Full threshold-boundary/rotation/deduplication testing, live destination navigation, and backend attribution remain **pending verification**.
- SwiftUI view appearance is not proof of visibility. Geometry and retained service state are deliberately separated from view lifetime.
- This is an assignment demo, not an App Store-ready advertising SDK. Before production distribution, audit Osmos privacy requirements/manifests, consent obligations, and signing/distribution requirements. Advertising-ID sharing is disabled; the app does not request ATT permission or create a real user identifier.

## Project maintenance

[project.yml](project.yml) is the XcodeGen source specification. The generated Xcode project is included, so XcodeGen is **not required to open or build it**. If adding/removing files through the filesystem, regenerate with XcodeGen's `generate` command, or add the files to the appropriate target in Xcode. Keep the resolved SPM dependency file in version control.

Official references: [Initialization](https://dev-hub.osmos.ai/docs/init-the-ios-sdk) · [Ad fetching](https://dev-hub.osmos.ai/docs/ad-fetching-ios) · [Event registration](https://dev-hub.osmos.ai/docs/register-events-ios).