# Redline Rush (Android build)

`www/index.html` is the entire game. It is one file with no build step.

## Make an APK

You need Node.js 18+ and Android Studio, which brings the Android SDK.

```bash
npm install
npx cap add android
npx cap sync android
npx cap open android
```

In Android Studio, use **Build > Build Bundle(s) / APK(s) > Build APK(s)**, or press Run with a phone plugged in.

Optional: to lock the game to portrait, open `android/app/src/main/AndroidManifest.xml` and add
`android:screenOrientation="portrait"` to the `<activity>` tag.

After you change `www/index.html`, run `npx cap sync android` again.
