# Agent44 Labs, Google Play listing kit

Everything needed to create the Play Console listing and push the first
build to **Internal testing**. The signed AAB is already built (see bottom).

No em dashes anywhere below (house rule for external copy).

---

## App identity

- Package name (cannot change later): `com.agent44labs.app`
- App title (max 30 chars): **Agent44 Labs**
- Default language: English (United States)
- App or game: App
- Free or paid: Free
- Category: Business (alt: Productivity)
- Privacy policy URL: https://agent44labs.com/privacy
- Contact email: botwhisperer@hey.com

---

## Short description (max 80 chars)

```
Always-on AI agents that watch, post, analyze, and smoke-test your business.
```

## Full description (max 4000 chars)

```
Agent44 Labs gives a small business its own team of always-on AI agents, for pennies a day.

Each agent does one job and never clocks out:

- List Agent watches your calendar and surfaces what is coming up, with sold-out percentages and selling pace.
- Analyst Agent tracks bookings, revenue, and which classes need a push.
- Social Agent drafts and posts to your connected accounts.
- Display Agent cycles your live schedule on an in-store TV screen for walk-in customers.
- Smoke Runner checks your website around the clock and alerts you the moment something breaks.

Open the app to see every agent in one workspace, ask a question in plain language, and let the team handle the busywork.

The first customer, a cooking school in the Finger Lakes, runs four agents that watch their calendar, snapshot their data, post to social, and smoke-test their site, 24/7.

Agent44 Labs is a companion to the Agent44 web app. Sign in with your email to access your workspace.
```

---

## Graphics (all in this folder)

- App icon: `icon-512.png` (512 x 512)
- Feature graphic: `feature-graphic.png` (1024 x 500)
- Phone screenshots (1434 x 2868, 2:1, Play compliant): `screenshots/02-iphone-nyk-hub.png`, `03-iphone-list.png`, `04-iphone-social.png`, `05-iphone-display.png`

Note: the iOS "01-home" screenshot was skipped on purpose. It shows an Apple App Store badge, which Play discourages (references to a competing store).

---

## Content rating questionnaire (IARC), expected answers

- Category: Utility, Productivity, Communication, or Other
- Violence / sexual / profanity / drugs / gambling: No to all
- Expected result: Everyone

## Data safety form

- Does the app collect or share user data: Yes (collects)
- Data collected: Email address (account management), App activity. Linked to the user. Not shared with third parties. Not sold.
- Encrypted in transit: Yes
- Users can request data deletion: Yes (the in-app Delete Account flow; also referenced from the privacy policy)

## Target audience and content

- Target age: 18 and over (business tool). Keeps it out of the Families program and child-safety requirements.

---

## Steps in the Play Console (manual, needs Google login)

1. Play Console, All apps, Create app.
   - Name: Agent44 Labs, Language: en-US, App, Free, accept declarations.
2. Set up, Internal testing (left nav, Testing, Internal testing).
   - Create a new release, upload `app-release.aab`.
   - Add release name (e.g., 1.0.0 (1)) and short release notes.
3. Create an email tester list, add Caitlin's Google account, save.
4. Work through the "Set up your app" tasks the Console lists. For internal
   testing the must-haves are: App access, Ads declaration (No ads),
   Content rating, Target audience, Data safety, Government apps, Financial
   features (None), Privacy policy. Use the answers above.
5. Fill the Main store listing (title, short + full description, icon,
   feature graphic, phone screenshots) from this file and the graphics here.
6. Roll out the internal testing release, then share the tester opt-in link
   with Caitlin. She installs from that link (no public search needed).

Promotion later: internal testing, then closed testing, then production
(production needs full review). NSYB followed the same path.

---

## The build

Signed release AAB (versionCode 1, versionName 1.0.0):

```
android/app/build/outputs/bundle/release/app-release.aab
```

Rebuild after bumping versionCode in `android/app/build.gradle`:

```
cd android
export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
export ANDROID_HOME="/opt/homebrew/share/android-commandlinetools"
./gradlew bundleRelease
```

Upload keystore: `~/.android-keys/agent44-upload.jks` (alias agent44). Keep it
safe. Play App Signing makes the upload key recoverable, but do not lose it.
```
