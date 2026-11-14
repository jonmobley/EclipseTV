# Privacy policy: proposed changes (draft, owner decides)

Page: https://moxieapps.io/eclipse/privacy (source: `moxie-site/src/content/apps/eclipse.json`,
last updated October 19, 2026). Checked against the iPhone 1.0 prep branch on 2026-11-13.
Nothing below has been published. Wording is a suggestion; the owner picks it.

## Things the page says that are no longer true

1. **Crash reports are not Mac-only.** iPhone/iPad and Apple TV also send crash
   and freeze reports to Sentry (release builds only). They have no off switch
   in the app.
   - Collected list, replace the Mac crash-report line with:
     "Anonymous crash reports from all Eclipse apps (on Mac you can turn them
     off; on iPhone, iPad and Apple TV they cannot be turned off) and, on Mac
     only, opt-in anonymous usage events — to fix stability problems and see
     which features are used"
   - Services, Sentry line: "Sentry — receives anonymous crash reports from
     Eclipse on Mac, iPhone, iPad and Apple TV. Reports hold no names, emails,
     photos or install ID."
   - Intro sentence: drop "and the Mac app can send optional crash reports",
     or say "and the apps send anonymous crash reports".
   - Owner choice: add an in-app off switch on iPhone instead of the wording above.

2. **QuestPoll sign-in is a 6-digit code on iPhone, not only a link.**
   "Email address (QuestPoll only) — to email you a one-time sign-in link or code".

3. **Remote-album codes.** The album-code feature is hidden in iPhone 1.0 for
   review. Keep the line (it returns after approval) or remove it until then.

## Things the page does not mention yet

4. **Create (Mac).** Prompts typed into Create go through our server to
   Anthropic to make graphics. Suggested Services line:
   "Anthropic — receives the text you type into Create on Mac to make
   graphics; it is not used to train their models" (check Anthropic's
   current API terms before promising the last part).

5. **Show Live (iPhone/iPad).** Devices signed in to the same iCloud account
   run a show together over the local network. Suggested "What stays on your
   device" addition: "Show Live connects your own iPhones and iPads directly
   over your local network; we do not receive it."

6. **iCloud sync wording.** Current: "syncs your Shows and captures between
   your own iPhones". Suggested: "between your own iPhones, iPads and Macs, in
   your private iCloud database, which we cannot read".

## App Store "App Privacy" answers to match

- Crash data: Diagnostics > Crash data, not linked to the user, not used for
  tracking. (With session tracking now off there is no install ID, so no
  "Identifiers" entry is needed for Sentry.)
- Email address: linked to the user, App Functionality (QuestPoll sign-in).
- Photos or videos / Other user content: only if counted as collected through
  iCloud; Apple's guidance says data in the user's own private CloudKit
  database that the developer cannot access is not "collected".
