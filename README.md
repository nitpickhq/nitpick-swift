# Nitpick for SwiftUI

In-app feedback for apps you build with AI. Users point at the exact thing that bugs them. Your coding agent pulls the report in over MCP and ships the fix.

Version 0.3.0.

- iOS 17 or newer, Swift 6 language mode, no third-party dependencies, public APIs only.
- When the app starts, the component asks Nitpick for the feedback settings of your app (which kinds are on, and two texts). That request carries no information about the user or the device, and nothing about it is stored on the platform. The tab shows once there are settings. Everything else waits until the user opens the panel, points, and taps Send.
- Anonymous: no name, email, account id or device name. Device model is the hardware identifier (`iPhone17,3`).
- 20 languages, chosen from the language of the device. No brand name in the panel unless you turn on the small mark.

## Install (for a coding agent)

1. Add the package. In Xcode: File > Add Package Dependencies > add this folder or its repository URL, product `Nitpick`. In a `Package.swift`:

   ```swift
   .package(path: "../path/to/packages/swift")   // or .package(url: "<repository url>", from: "0.3.0")
   // target dependency:
   .product(name: "Nitpick", package: "swift")
   ```

2. Check the deployment target is iOS 17.0 or higher. If it is lower, stop and tell the user: pointing needs iOS 17.

3. Call `configure` once at launch. That is all that is needed to get the edge tab and the panel:

   ```swift
   import SwiftUI
   import Nitpick

   @main
   struct MyApp: App {
       init() {
           Nitpick.configure(
               appKey: "npk_...",                        // public key from the Nitpick dashboard, safe to ship
               options: NitpickOptions(apiURL: URL(string: "https://<your nitpick host>")!)
           )
       }
       var body: some Scene { WindowGroup { RootView() } }
   }
   ```

   The component lives in its own windows above the app, so it also works over sheets and full screen covers. You do not have to wrap your root view. `.nitpick()` on the root view exists but is optional.

   The tab only shows when the app has settings: the last valid answer is kept on the device, and a fresh one is fetched at launch and when the app comes back to the foreground after more than an hour. No answer yet, an unknown key, an app that is not active, or both kinds switched off means no tab.

4. Prepare the five questions of `install.md` (on the Nitpick site) and ask them in one message once the screens have names (step 5), with the default for each: on which screens the tab shows (`tabScreens`), the color, the font, the side and height of the tab, and which kinds of feedback (a setting of the app, not code). "default" is a fine answer to all. See "Look" and "The tab on chosen screens only" below.

5. Name every important screen. Give a sheet or cover its own name:

   ```swift
   CheckoutView()
       .nitpickScreen("Checkout")
   ```

   A screen that stays mounted while hidden (for example in a navigation stack, or a tab bar of your own) can pass its focus, so its elements never count when the user points: `.nitpickScreen("Settings", focused: selection == .settings)`. Without `focused` nothing changes. A standard `TabView` already removes hidden tabs, so it does not need it.

6. Name the important buttons, fields and cards. Use stable names that lead to the code, as `screen.thing`:

   ```swift
   Button("Pay") { pay() }
       .nitpickElement("checkout.pay_button")
   ```

   Put the marker on the view that has the visible size. A user tap inside a marked frame matches `exact`, within 44 points of one matches `nearest`, otherwise `none`. The smallest marked frame that contains the tap wins.

7. Mark sensitive things to be covered with a black box in the picture. `SecureField` and secure `UITextField`s are covered automatically.

   ```swift
   TextField("Card number", text: $card)
       .nitpickMask()
   ```

8. Optional: your own button instead of, or next to, the tab. Hide it while there is nothing to offer:

   ```swift
   if Nitpick.isAvailable {                 // observable
       Button("Feedback") { Nitpick.present() }
   }
   // and in options: NitpickOptions(showsTab: false)
   ```

   `Nitpick.present()` does nothing, and writes one line in the developer log, when there are no settings yet, when the app is not active, or when both kinds are off.

## Options

```swift
var options = NitpickOptions(
    apiURL: URL(string: "https://<your nitpick host>")!,   // local platform: http://localhost:3000
    showsTab: true,
    tabEdge: .right,              // or .left; physical, also in an app that runs from right to left
    tabVerticalPosition: 0.5,     // the middle of the tab as a fraction of the window height, 0 top ... 1 bottom
    tabScreens: nil,              // nil: the tab shows on every screen; or a list of screen names, see below
    dryRun: false,                // true: send nothing, fetch no settings (see below)
    theme: NitpickTheme(),        // color and font, see below
    showsBrand: false,            // a small mark with the Nitpick domain under the panel
    language: nil                 // forces one of the 20 codes; for tests
)
```

The tab always stays at least 60 points from the top and the bottom edge. Which kinds of feedback are on, and the two texts `footer` and `thanks`, are not options: you set them in the Nitpick dashboard, with the CLI or through MCP, and the component fetches them.

### The tab on chosen screens only

By default the tab shows on every screen. To show it only on some, pass the names you gave with `.nitpickScreen`:

```swift
NitpickOptions(tabScreens: ["Checkout", "Settings*"])
```

A name must be equal to the screen's name (capitals count); a name that ends on `*` matches every screen whose name starts with what comes before the `*` (`"Settings*"` matches `"Settings"` and `"Settings / profile"`). The current screen is the one a report would get as `screen`: the last one that appeared and is still visible and has focus. On a screen without a name the tab does not show. An empty list shows the tab nowhere and writes one line in the developer log. `showsTab: false` always wins. The panel stays open when the screen changes, and `Nitpick.present()` works on every screen, also outside the list. The list can only hide the tab: it never shows it where the settings say there is nothing to offer.

`dryRun: true` is the way to test without a server: it writes `payload.json` and `screenshot.jpg` to `Documents/nitpick-dryrun` (set `dryRunDirectory` to choose the folder), fetches no settings, shows the tab at once, has both kinds on and uses the built-in translations.

## Look

The component has the design Papier: a dense, calm surface with hairlines, small precise type and room. No transparency and no blur. The tab is narrow (22 points wide, 76 high, rounded on the inner side, flush with the screen edge, tap area at least 44 by 76 points). The panel has the two choices as rows (the row Point at something starts pointing at once; with only one kind on in the settings there is no panel with one row: the tab, `present()` and `Nitpick.present()` open that kind at once), the panel slides down when it closes (with Reduce Motion it only fades), pointing shows a compact pill at the top, and Send is a button on the right (44 points high, at least 112 wide). Only the color and the font are chosen in code. The rest is fixed: surface `#FFFFFF` in light and `#1C1C1E` in dark, text `#111111` / `#F2F2F2`, second text `#5C5C5C` / `#A1A1A6`, hairlines black at 12 percent / white at 14 percent. The tap spot and the frame of the element are always red `#FF3B30`. Light or dark follows the window of the app at the moment the component opens, and follows changes. All values are in `docs/ontwerp/component/papier.md`.

```swift
options.theme = NitpickTheme(
    color: .accent(Color("BrandBlue")),   // or .standard (default): ink, near black in light and near white in dark
    fontName: "Inter-SemiBold"            // PostScript name of a font that is already in the app; nil = system font
)
```

- The color is used for the Send button, the rim of the tab (2 points, only on the side of the app: on the left of a tab on the right). The component picks black or white on top of it, whichever has the higher contrast.
- The font is used for headings and buttons only; running text stays the system font. For Arabic, Hindi, Japanese, Korean and Chinese the component always uses the system font. A font that is not in the app is ignored.

## Texts and languages

20 languages: `en`, `nl`, `de`, `fr`, `es`, `pt`, `it`, `pl`, `tr`, `ru`, `uk`, `sv`, `da`, `nb`, `ja`, `ko`, `zh-Hans`, `zh-Hant`, `ar`, `hi`. The component takes the first of the device's preferred languages that fits, otherwise English. Arabic runs from right to left in the panel, also in an app that runs from left to right.

The texts come from `packages/teksten`. `scripts/generate-texts.mjs` makes `Sources/Nitpick/GeneratedTexts.swift` from them, so the package needs nothing outside its own folder. After a change in `packages/teksten`: `node scripts/generate-texts.mjs`; `node scripts/generate-texts.mjs --check` fails when the file is out of date.

Only two texts can be changed, per language, in the Nitpick settings: `footer` (the line under Send, at most 3 lines) and `thanks` (after sending, at most 4 lines). They are shown as literal text, never as Markdown or HTML. By default the line under Send is "Your feedback goes to the maker of this app." The final wording is still to be decided.

## Errors

The component looks at `error.code`, not only at the status, and never shows `error.message` to the user (it goes to the developer log). A send that fails shows a fixed text and Try again. With `app_inactive` or `monthly_limit` the panel shows "Feedback is not available right now.", the draft is dropped, there is no Try again, and the tab goes away until the next valid answer for the settings.

## What the picture contains

The component draws the app's own window with `drawHierarchy`. Its own tab, pointing layer and panel are separate windows and are not in the picture. JPEG, longest side at most 1600 pixels, and smaller than 1 MB (quality 0.7 first, lower until it fits). The system keyboard and status bar are not part of the app window. See `PROEF.md` for what happens with web pages, maps and video.

## What is sent

`POST <apiURL>/api/v1/feedback` with header `X-Nitpick-Key` and `multipart/form-data` (`payload` JSON plus `screenshot`). Fields follow `docs/specs/api-v1.md`: `kind`, `comment`, `screen`, `element`, `element_match`, `element_frame`, `tap`, `viewport`, `platform`, `sdk`, `app_version`, `build`, `device`, `client_ts`.

Also `GET <apiURL>/api/v1/config` with the header `X-Nitpick-Key` (and `Accept: application/json`), at launch and when the app returns to the foreground after more than an hour. The operating system adds the IP address and a User-Agent to every request; the component sends nothing about the user or the device. The last valid answer is kept in `UserDefaults.standard` under `nitpick.config.<sha256(apiURL + appKey)>`, with the time of fetching.

## Privacy

`PrivacyInfo.xcprivacy` ships as a package resource. It declares: no tracking; collected data (not linked to the user, for app functionality): customer support (the comment), other user content (the picture), product interaction (screen, element and tap), other diagnostic data (device model, OS version, locale, app version); and one required-reason API: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` (the component keeps its own settings there).

For App Store Connect (App Privacy) the app maker declares the same data types, not linked to identity, not used for tracking. The full answers for Apple and Google Play, and the paragraph for the privacy policy (with the required sentence about the request at app start), are in `docs/privacy.md` on the Nitpick site (`/docs/privacy.md`). A coding agent reads that page, not only this README.

In a `List`, put `.nitpickElement(...)` on the content of a row (a `VStack` or `HStack`), not on a `Button` that is the row itself: that marker is not found when the user points at it. See `/docs/screens-elements-masking.md`.

## Demo and tests

- `Demo/`: demo app. Run `xcodegen generate` in `Demo`, then open `NitpickDemo.xcodeproj`. Dry run by default; set `NITPICK_DEMO_MODE=send`, `NITPICK_KEY` and optionally `NITPICK_API_URL` (default `http://localhost:3000`) to send.
- Unit tests: `xcodebuild test -scheme Nitpick -destination 'platform=iOS Simulator,name=iPhone 16'` in this folder.
- UI tests: `xcodebuild test -project Demo/NitpickDemo.xcodeproj -scheme NitpickDemo -destination 'platform=iOS Simulator,name=iPhone 16'`. Variables for the demo: `NITPICK_DEMO_COLOR=RRGGBB`, `NITPICK_DEMO_FONT`, `NITPICK_DEMO_LANGUAGE`, `NITPICK_DEMO_TAB=off|left`, `NITPICK_DEMO_VERTICAL`, `NITPICK_DEMO_BRAND=1`.

## Diagnostics

`Nitpick.diagnostics` returns a read-only snapshot (registered elements, frame updates, timing of the last pick and picture). Meant for tests and measuring.
