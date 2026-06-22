# Android push (FCM) setup

iOS push uses APNs (`ApnsPusher`); Android uses Firebase Cloud Messaging
(`FcmPusher`). The server code is ready; this is the one-time config to turn it
on. The `android/` Capacitor project is gitignored, so the build steps below are
done locally on the machine that builds the app.

## 1. Firebase project (console, needs Google login)

1. Firebase console, create a project (or reuse one).
2. Add an **Android app** with package name **`com.agent44labs.app`**.
3. Download **`google-services.json`** and place it at `android/app/google-services.json`.
4. Project settings, Service accounts, **Generate new private key**, save the JSON.

## 2. Server credentials (prod)

Set on the Fly app (env or Rails credentials):

- `FCM_SERVICE_ACCOUNT_JSON` = the full service-account JSON (string)
- `FCM_PROJECT_ID` = optional, defaults to `project_id` in the JSON

When these are absent (local/dev/test) `FcmPusher` is a safe no-op, so nothing
breaks before they are set.

## 3. Android build wiring (local, in the gitignored android/ project)

`@capacitor/push-notifications` is already a dependency. After dropping in
`google-services.json`:

- `android/build.gradle` classpath: `com.google.gms:google-services:4.4.2`
- `android/app/build.gradle` bottom: `apply plugin: 'com.google.gms.google-services'`
- Rebuild + install: `npx cap sync android` then `./gradlew installRelease`
  (JDK 21).

## 4. Verify

1. Open the app on the device, accept the push permission prompt.
2. A row appears in `device_tokens` with `platform = "android"` (the client
   posts the real platform via `push_controller.js`).
3. Trigger a push (e.g. a Carson nudge to that user). Confirm the per-user
   toggle in Settings, Push notifications, Android, is on.

## Notes

- Per-user delivery is gated by `users.android_push_enabled` (Settings page).
- To pilot on one device without enabling broadly, leave Android push off for
  everyone except the test user.
