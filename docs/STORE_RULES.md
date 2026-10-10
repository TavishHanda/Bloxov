# Store rules (Apple App Store + Google Play)

Owner (2026-10-10): Bloxov will also ship on phones, so **everything, past and future, must follow the Apple App
Store Review Guidelines and the Google Play Developer Policies**. This file is the working summary. It is not a
substitute for the real rules: before a store submission, and whenever a change touches one of the areas below,
re-read the current source (links at the bottom). The rules change every year.

## The rule for every change

Before shipping anything, check it against the list below. If a change would break a rule, don't ship it: propose
a compliant version to the owner instead (same as gameplay changes). If you're not sure, ask. Note in the
CHANGELOG entry when a change was made for store reasons.

## What Bloxov must follow

### 1. Content and age rating
- Bloxov is a shooter with human enemies and PvP. Both stores need an honest age rating: Apple's questionnaire
  in App Store Connect (ratings 4+/9+/13+/16+/18+) and Google's IARC questionnaire (gives ESRB/PEGI etc.).
  Current estimate: Apple 13+ or 16+, ESRB Teen, PEGI 12-16 (blocky violence, realistic guns, online play).
- **Keep the violence blocky.** No gore, dismemberment, realistic blood pools, torture, or killing that rewards
  cruelty. Red hit sparks are fine. Anything more graphic raises the rating and needs the owner.
- No real-world hate symbols, real terrorist groups, real ethnic/religious enemies, or real current conflicts.
  Enemy factions stay fictional (scavs, Raiders).
- No drugs, alcohol or tobacco items that are glamorized; meds and fictional "stims" framed as medical are fine.
  Any of these changes the rating questionnaire answers, so tell the owner.
- No sexual content or nudity.
- Weapons: no real gun brand or model names, logos or trademarked designs without a licence (generic names like
  "AK Rifle" and "Pistol" are fine). No instructions on real weapons. Same for any other real brand (cars, food).
- Names: check game, map and item names for trademarks before a public release. Open: "Bloxov Battlegrounds" (the
  first map; "Battlegrounds" is a trademark Krafton/PUBG has enforced).
- The game must not be put in Apple's Kids category or Google's Families program, and the store listing's target
  audience must be 13+ (or 18+ if the owner prefers). That keeps child-directed rules (COPPA, Families policy)
  from applying; if the owner ever wants under-13 players, that's a big change: raise it first.

### 2. Online play and user content (Apple 1.2, Google UGC policy)
- Anything one player writes that others can see is "user-generated content". Today that's **only player names**,
  and only party members see them (no name tags on other players, no chat).
- Every name goes through `NameFilter.clean()` on the server (`scripts/name_filter.gd`, used by
  `Matchmaker.add_player`). Any new place a player can type text that others see must use it too.
- **Before adding text chat, voice chat, custom clan names, player reports or anything else player-made that
  strangers can see**, the stores require all of: a filter for objectionable content, a way to **report** players
  and content, a way to **block/mute** a player, acting on reports quickly (a moderation plan), and published
  contact info. Voice chat also needs the microphone permission with a clear reason string. Plan these with the
  owner before building the feature.
- Name tags or anything showing names to strangers: also needs report/block first.

### 3. Privacy and data (Apple 5.1, Google User Data + Data safety)
- Today: no accounts, no analytics, no ads, no tracking. Profile and settings are saved on the device only
  (`user://`). Online play sends the server the player's name and IP address (needed to connect; the server's
  log prints names).
- **Collect only what the game needs.** No contacts, location, photos, device IDs or advertising IDs.
- **A privacy policy is required by both stores**, as a public URL on the store listing **and** reachable inside
  the game (e.g. a "Privacy" button in the hideout/settings). It must say what is collected, why, how long it's
  kept, who it's shared with (hosting: Heroku/Fly.io), and how to get it deleted. Not written yet (pre-launch).
- Fill in Apple's privacy "nutrition label" and Google's Data safety form to match exactly. Update both (and the
  policy) whenever data collection changes.
- Any third-party SDK (analytics, crash reporting, ads, login) must be listed in those forms, and on iOS needs a
  privacy manifest. Add SDKs only with the owner's OK.
- Tracking users across other companies' apps/sites needs Apple's App Tracking Transparency prompt. Don't track.
- All network traffic must be encrypted (`wss://`, `https://`). The game already defaults to `wss://`; plain
  `ws://` is only for a local test server. Uses only standard TLS, so the export-compliance answer is "exempt"
  (`ITSAppUsesNonExemptEncryption = NO`).

### 4. Accounts (Apple 5.1.1(v), 4.8; Google account deletion policy)
- No accounts today. **If accounts are ever added:**
  - The player must be able to **delete their account and its data from inside the game**, and Google also needs
    a web link for deletion requests. Not just "deactivate".
  - Don't force an account for features that don't need one (offline solo play must keep working without one).
  - If you offer Google/Facebook/Discord login on iOS, also offer Sign in with Apple (or another login that meets
    Apple 4.8's privacy rules).
  - App Review needs a working demo account (or no login needed) at review time.

### 5. Money: purchases, loot, gambling (Apple 3.1, 5.3; Google Payments, Gambling)
- No real money in the game today. In-game money and trader prices are earned in play only.
- **Anything digital sold for real money (currency, cosmetics, battle pass, stash space, skipping timers) must use
  Apple In-App Purchase on iOS and Google Play Billing on Android.** No other payment methods inside the app, and
  no buttons or links sending players to buy elsewhere (Apple has narrow, region-specific exceptions; don't rely
  on them without the owner checking).
- **Paid random rewards (loot boxes, paid crates, gacha, mystery items) must show the odds of each item before the
  purchase** (both stores). Loot crates found in a raid are not purchases and are fine.
- **No real-money gambling, and no way to cash out.** In-game items/money must never be exchangeable for real
  money or crypto, and the game must not support or encourage trading accounts or items for real money.
- No NFTs/crypto in the game.
- If items bought on web/PC carry over to phones, Apple requires those items also be buyable through IAP in the
  iOS app (3.1.3(b)). Plan cross-platform purchases with this in mind.
- Subscriptions need clear terms, price and how to cancel shown before purchase.
- Don't make paid items that give a big PvP advantage without the owner deciding it (not a store rule as such, but
  "pay-to-win" plus random rewards draws rating and review scrutiny).

#### Planned near release (owner, 2026-10-10): battle pass, skins and "a form of gambling"
Way later, near release. When it comes up, design it to these rules from the start:
- **Battle pass and skins:** sold only through Apple IAP / Google Play Billing (or premium currency bought that
  way). Show exactly what each tier gives and the price before buying; a season-length pass is fine, an
  auto-renewing one is a subscription (clear terms + how to cancel). Skins are cosmetic, which keeps it simple.
- **Gambling-style features** (crates, spins, case openings) are allowed only as *paid random rewards with odds
  shown* or as free/earned-currency chance mechanics. Hard lines: no cashing out, no real-money stakes, no
  trading winnings for real money, no betting between players with bought currency.
- Chance mechanics bought with real money raise the age rating (Apple's questionnaire asks about simulated
  gambling and loot boxes; frequent simulated gambling can push the rating to 18+; IARC adds "In-Game
  Purchases (Includes Random Items)"). Decide the target rating before designing it.
- Some countries restrict or ban paid loot boxes (e.g. Belgium; others are moving that way). Plan a way to turn
  paid random rewards off per region, or sell items directly instead.
- Offer a direct-purchase path for skins where possible; it avoids most of the above.

#### Premium currency (owner plan, 2026-10-10)
The owner plans an in-game currency bought with real money, used for the battle pass, skins and crates. That's
allowed on all three platforms if it follows these rules:
- **Phones:** the currency is sold only through Apple In-App Purchase / Google Play Billing. No links or buttons
  inside the app pointing to a cheaper web store, unless the store's current rules for that country allow it.
- **Steam:** in-game purchases in the Steam build go through Steam's own microtransaction system (Steam Wallet),
  not an outside payment page.
- **Web:** any payment provider works (it isn't a store app), but the same no-cash-out rules apply.
- Show the real-money price of each currency pack before buying. Make it clear what the currency buys.
- **No cash-out:** the currency and anything bought with it can never be turned back into real money, sent to
  other players for money, or traded off-platform.
- Anything random bought with it (crates) shows its odds first, the same as a direct paid crate (see above).
- Currency bought on one platform can only be spent on another if it is also sold through IAP there. Phones are
  planned as a separate version without crossplay, which keeps this simple: keep the phone wallet separate too.
- Earned currency (from playing) can sit alongside it; keep the two clearly separate if they behave differently.

### 6. Ads (Apple 5.1.1, Google Ads policy)
- No ads today. If added: only approved ad SDKs, declared in the privacy forms, no ads that interrupt gameplay
  unexpectedly or are hard to close, no ads unsuitable for the age rating, no tracking without ATT consent on iOS.
  Rewarded ads must be optional and clearly labelled.

### 7. The app itself (Apple 2.x, 4.x; Google technical policies)
- **Ship a native Godot iOS/Android export**, not the web build in a web-view wrapper (Apple 4.2 rejects thin web
  wrappers).
- **Never download and run code** (scripts, `.pck`/resource packs containing scripts) after install. New
  gameplay comes through a store update. Downloading data (map seeds, balance numbers, text) is fine.
- It must be complete when submitted: no placeholder text, "beta"/"test" labels, broken buttons, dead features
  or crashes. Betas go through TestFlight / Play testing tracks, not the store.
- The game must be playable with touch on phones (Apple 2.1/4.0: works as advertised on the device). Mobile
  controls are a separate project, but nothing should depend on keyboard/mouse only without a touch plan.
- Online servers must be up during review; if online play is down, offline solo must still work.
- Inside the iOS app don't mention other platforms (Android, Google Play, Steam) or other stores, and vice versa.
- Store screenshots and video must show real gameplay.
- Android: target the API level Google currently requires (within about a year of the newest Android), 64-bit,
  Android App Bundle (`.aab`). Request only the permissions the game uses (none needed today except internet).
- iOS: build with the current Xcode/SDK Apple requires at submission time.
- Respect the system's mute/volume and pause audio when the app goes to the background.
- Server-side bans or cheating detection must not collect more data than the privacy policy says.

## Current status (audit 2026-10-10, v0.11.5)

Fine as is: age-appropriate blocky violence with generic weapon and item names, fictional enemies, no real money,
no ads, no accounts, no analytics, data saved on the device, encrypted connection to the server, names only visible
to party members, offline solo play works without the server.

Fixed in 0.11.5: player names are now filtered on the server (odd characters dropped, rude/hateful names
replaced by "Player N").

Needed before a store launch (owner):
- A privacy policy page (could live on the GitHub Pages site) and a link to it in the game.
- Age rating questionnaires (Apple + IARC) and the Apple privacy label / Google Data safety form.
- A support/contact address or page (both stores ask for one).
- Native iOS/Android exports with touch controls (separate project).
- Apple and Google developer accounts in the owner's (or a parent's/guardian's, if under 18) name.

## Sources
- Apple App Store Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Apple age ratings: https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/
- Google Play Developer Policy Center: https://play.google.com/about/developer-content-policy/
- Google Play user data / Data safety: https://support.google.com/googleplay/android-developer/answer/10144311
- Google Play account deletion: https://support.google.com/googleplay/android-developer/answer/13327111
- Google Play target API level: https://developer.android.com/google/play/requirements/target-sdk
