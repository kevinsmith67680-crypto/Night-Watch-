# Icon files

The app icons live in each app's asset catalog:

- `NightWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (iPhone, 1024×1024; iOS rounds the corners)
- `NightWatch Watch App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (watch, 1024×1024; watchOS crops a circle)

This folder holds a **discreet alternative**: the same heart and cross with
nothing inside the heart. To switch to it, copy each file over the matching
`AppIcon.png` above (keep the name `AppIcon.png`), then rebuild in Xcode.
