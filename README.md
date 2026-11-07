# TAT News Card Solutions

Flutter news-card editor for Windows and Android. It collects Bengali RSS
headlines and article metadata, then lets the user compose and export a
1080 × 1080 JPEG card.

## Android compatibility checklist

| Feature | Android implementation | Status |
| --- | --- | --- |
| Google News RSS, portal feed, and time-filtered search | Flutter HTTP requests and RSS parsing | Build-verified |
| Article URL entry and redirect resolution | Android WebView through `webview_flutter`; Windows keeps `webview_windows` | Build-verified; runtime workflow not yet device-verified |
| Article headline and image metadata | HTTP response parsing and Flutter `NetworkImage` | Build-verified |
| Bengali text, fonts, frame, colors, overlays, pan, and zoom | Flutter widgets, bundled SolaimanLipi fonts, and the bundled PNG frame | Build-verified |
| Image import | `file_picker` Android system document picker; selected image is read from its cached file | Build-verified; picker workflow not yet device-verified |
| 1080 × 1080 JPEG export | `file_picker.saveFile(bytes: ...)` writes through Android's Storage Access Framework; Windows still writes to the selected desktop path | Build-verified; saved-image round trip not yet device-verified |
| Editor preferences | JSON in the app support directory via `path_provider` | Build-verified |
| Network permission | `INTERNET` in the main manifest for release and debug builds | Verified in manifest |
| Storage permissions | None; user-selected files and destinations use system pickers | Verified in manifest |
| Windows behavior | Existing Windows WebView and desktop save flow retained | Windows release build verified |
| Device/emulator runtime checks | No emulator booted in this environment because the configured Pixel 9 AVD reports insufficient disk space | Not verified |

The image-frame files under `assets/system_file/` have `.dll` names but PNG
file signatures; their existing asset references are intentionally retained.

## Build and run

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

The APKs are written to `build/app/outputs/flutter-apk/`. Release builds use
the repository's current Gradle signing configuration; configure a private
release key before distributing a production APK.
