# Android Play releases (fastlane supply)

Promote the Agent44 Labs Android app on Google Play from the command line,
mirroring the iOS `bin/asc-push` flow. The app is a remote-URL wrapper (it loads
the live site), so the AAB you test on the internal track is the same binary you
ship to Production: promotion is the normal release path, not a rebuild.

Lanes live in `fastlane/Fastfile` (`platform :android`); `bin/play-push` is the
wrapper. The `android/` Capacitor project is gitignored, so building an AAB is a
local step on the build machine.

## 1. One-time: Play service account JSON (console, needs Google login)

`supply` talks to the Google Play Developer API with a service account, not your
login.

1. **Play Console** > Setup > **API access** > create / link a Google Cloud
   project.
2. Create a **service account** (link drops you into Google Cloud Console),
   then back in Play Console grant it access with the **Admin (or Release
   manager)** role so it can promote to Production.
3. In Google Cloud Console, open that service account > **Keys** > Add key >
   **JSON**, download it.
4. Save it at **`~/.play-keys/agent44-play.json`** (outside the repo, like the
   iOS key under `~/.appstoreconnect/`).

Override the path with `SUPPLY_JSON_KEY` if you keep it elsewhere. An optional
`~/.play-keys/env.sh` is sourced by `bin/play-push` (set `SUPPLY_JSON_KEY` or
`PLAY_AAB_PATH` there).

Verify it works:

```
bin/play-push --verify
```

## 2. Promote internal -> Production

The usual case (build is already on the internal track and tested):

```
bin/play-push                 # promote internal build -> Production at 100%
bin/play-push --rollout 0.2   # staged: 20% of users, status "in progress"
```

Finish or adjust a staged rollout later:

```
bin/play-push --finish              # bump live Production rollout to 100%
bin/play-push --finish --rollout 0.5  # set live Production rollout to 50%
```

Promote a different source track with `from:`:

```
fastlane android promote_to_production from:beta rollout:0.5
```

## 3. (Optional) upload a fresh AAB

Only when shipping actual app-shell changes (rare for a remote-URL app). Build,
then upload to the internal track:

```
cd android && ./gradlew bundleRelease   # JDK 21; signs with ~/.android-keys/agent44-upload.jks
cd .. && bin/play-push --upload          # -> internal testing track
```

Bump `versionCode` in `android/app/build.gradle` before each new binary.
`PLAY_AAB_PATH` overrides the default
`android/app/build/outputs/bundle/release/app-release.aab`.

## Notes

- `supply` only touches the **release/rollout**; the store listing, screenshots,
  data-safety form, and content rating stay managed in the Play Console UI
  (`skip_upload_*` is on for every lane).
- A first-ever Production submission still goes through full Google review and
  needs **App content** complete. After that, promotions are quick.
- Org/company developer account: no closed-testing prerequisite for Production.
- Keep the service account JSON and `~/.android-keys/agent44-upload.jks` safe;
  losing the upload key means a Play-side key reset.
