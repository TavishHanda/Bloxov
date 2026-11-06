# Store privacy forms: answers ready for the phone release

Written 2026-11-06 (Bloxov 0.31.5). Fill these in when the App Store Connect and Google Play Console listings are
made. Check each one against the game as it is then: anything added since (email, Steam/Apple/Google sign-in, IAP,
ads, analytics in the app, crash reports) changes the answers.

Links both stores ask for:
- Privacy policy: https://bloxov.com/privacy
- Account deletion page (Google): https://bloxov.com/privacy#delete
- Support / contact: contact@bloxov.com (check the email routing works first)

## What the game collects

| Data | Where | Why | Linked to the player? | Kept |
|---|---|---|---|---|
| PvP username | Stash database (Heroku Postgres) | the account | yes | until deleted (30-day grace), or 12 months unused |
| Name shown to others (display name) | game server, database | other players see it | yes | same |
| PvP stash, money, loadout, stats, traders, quests, raid results | database | gameplay | yes | same |
| Password | database, hashed (scrypt), never readable | signing in | yes | same |
| Recovery code, remember-me session | database, hashed | account recovery / staying signed in | yes | sessions 30 days |
| Ban dates and reason | database | anti-cheat | yes | with the account |
| IP address, name, anti-cheat catches | game server log | security, anti-cheat | yes (with the name) | short: Heroku keeps ~1,500 log lines, server restarts daily |
| PvE (solo) progress, settings | the device only | gameplay | not collected | on the device |

Not collected: email, real name, phone, location, contacts, photos, device ids, ad ids, purchases (none yet),
crash logs or analytics in the app (Cloudflare Web Analytics is on bloxov.com only, cookieless; leave it out of the
phone builds).

## Apple: App Privacy ("nutrition label")

- Data used to track you: **None**.
- Data linked to you:
  - Identifiers > **User ID** (the PvP username) - App Functionality.
  - User Content > **Gameplay Content** (stash, stats, raid results) - App Functionality.
  - Other Data (display name shown to other players) - App Functionality. (Could also go under User Content.)
- Data not linked to you: none.
- IP address in server logs: Apple doesn't ask for it on its own unless it's used for location, tracking or
  analytics; it's only for security here, so it's not declared. Re-check Apple's wording at submission.
- Account deletion: in the app (ONLINE > PvP ACCOUNT > DELETE PvP ACCOUNT) - required by guideline 5.1.1(v). Done.
- Sign in with Apple: only needed if a third-party sign-in (Google, Steam...) is added on iOS. Not now.

## Google Play: Data safety

- Does the app collect or share user data? **Yes, collects** (no sharing: Heroku/Cloudflare are service providers,
  which Google doesn't count as sharing).
- Is all data encrypted in transit? **Yes** (wss:// and https://).
- Can users ask for their data to be deleted? **Yes**: in the app, and at https://bloxov.com/privacy#delete.
- Data types:
  - Personal info > **User IDs** (username) - collected, required for online play, App functionality, Account
    management.
  - App activity > **Other user-generated content / In-app actions** (stash, stats, raid results) - collected,
    App functionality.
  - Device or other IDs: **No**. Location: **No** (IP is not used for location).
  - IP addresses: Google's form has no IP category; it's in short-lived security logs. Declare under "Fraud
    prevention, security, and compliance" if a question asks about security logs.
- Data processed only on the device (PvE save) doesn't need declaring.
- Account deletion URL (required because accounts can be made in the app): https://bloxov.com/privacy#delete

## Before submitting, also
- Age rating questionnaires (violence: realistic-ish blocky gunfights; no gore, no gambling with real money yet).
- Mobile web: turn the browser game off on phones when the store apps launch (owner, 2026-11-02).
- Apple in Canada: CRA Business Number + GST/HST account before any paid app or IAP.
