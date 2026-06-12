# GeoLocation Integration Guide
## Cocos Creator 2.4.13 — iOS & Android

---

## Overview

This document describes how the native location feature was implemented in Cocos Creator 2.4.13 (jsb-link), and how to integrate it into any other Cocos Creator project.

The implementation handles:
- Requesting location permission from the user
- Fetching GPS coordinates (latitude, longitude)
- Reverse geocoding to get city, state, country, postcode
- Permission denied — show native alert with "Open Settings"
- Location Services globally OFF — show native alert with instructions
- Detecting when user returns from Settings without enabling
- Works on both iOS and Android

---

## Architecture

```
Cocos Creator (TypeScript)
        ↕  jsb.reflection.callStaticMethod
   Native Code (Objective-C / Java)
        ↕  evalJS / evalString
   Cocos Creator (window callbacks)
```

Cocos JS cannot call native functions directly. The `jsb.reflection` bridge is used to call native static methods. Native code returns data back by evaluating a JS string (`window.onLocation(...)`, `window.onLocationPermission(...)`).

---

## Project Structure

### JavaScript/TypeScript (Cocos side)
```
assets/scripts/location/
├── IGeoLocation.ts          Interface for location data
├── LocationEvent.ts         Event name constants
├── LocationManager.ts       Calls native getLocation, handles window.onLocation callback
└── LocationPermission.ts    Calls native requestPermission, handles window.onLocationPermission callback
```

### iOS Native
```
build-templates/jsb-link/frameworks/runtime-src/proj.ios_mac/ios/
├── LocationHelper.h         Header file
├── LocationHelper.mm        All location logic (Objective-C)
└── Info.plist               NSLocation permission strings added here
```

### Android Native
```
build-templates/jsb-link/frameworks/runtime-src/proj.android-studio/
├── app/src/org/cocos2dx/javascript/LocationHelper.java    All location logic
├── app/src/org/cocos2dx/javascript/AppActivity.java       onResume + onRequestPermissionsResult hooked here
├── app/AndroidManifest.xml                                Location permissions declared here
└── gradle.properties                                      targetSdkVersion set to 34
```

> **Important:** `build-templates/` is the source of truth. Every time you build from Cocos Creator, the `build/` folder is overwritten and `build-templates/` contents are copied into it. Always make native changes in `build-templates/`, not just in `build/`.

---

## Complete Flow

### 1. App Start
**File:** `assets/scripts/Home.ts`

```typescript
start() {
    LocationManager.instance.init();       // Register window.onLocation and window.onLocationError callbacks

    cc.systemEvent.on(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
    cc.systemEvent.on(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
    cc.systemEvent.on(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);

    LocationPermission.request();          // Start permission flow
}
```

### 2. Permission Request (JS → Native)
**File:** `assets/scripts/location/LocationPermission.ts`

```typescript
// Calls native requestPermission via JSB bridge
jsb.reflection.callStaticMethod("LocationHelper", "requestPermission:", "")         // iOS
jsb.reflection.callStaticMethod("org/cocos2dx/javascript/LocationHelper", "requestPermission", "()V")  // Android
```

### 3. iOS Permission Logic
**File:** `LocationHelper.mm`

```
requestPermission
    ↓
locationServicesEnabled == NO?
    → showLocationServicesAlert
        Title: "Location Services Disabled"
        Message: "Your device's Location is turned off.
                  To enable: Phone Settings → Privacy & Security → Location Services → Turn ON"
        Button: "Open Settings" → opens UIApplicationOpenSettingsURLString
        Observer: UIApplicationDidBecomeActiveNotification
            Return with Location ON  → requestPermission() (retry)
            Return with Location OFF → showLocationServicesAlert again
    ↓
authorizationStatus == Authorized?
    → notifyPermission(YES)

authorizationStatus == Denied/Restricted?
    → showPermissionDeniedAlert
        Title: "Location Permission Required"
        Message: "Please go to Settings and enable location access for this app."
        Button: "Open Settings" → opens UIApplicationOpenSettingsURLString
        Observer: UIApplicationDidBecomeActiveNotification
            Return with permission granted  → didChangeAuthorizationStatus fires → dismiss alert + notifyPermission(YES)
            Return with permission denied   → showPermissionDeniedAlert again

authorizationStatus == NotDetermined?
    → requestWhenInUseAuthorization (system dialog)
        User taps Allow     → didChangeAuthorizationStatus → notifyPermission(YES)
        User taps Don't Allow → showPermissionDeniedAlert
```

> **iOS Quirk:** When Location Services is globally OFF, `authorizationStatus` also returns `Denied` — same as app permission denied. This is why `locationServicesEnabled` must be checked FIRST before `authorizationStatus`.

> **iOS Limitation:** iOS 16+ does not allow deep-linking directly to Privacy & Security → Location Services. The best available option is `UIApplicationOpenSettingsURLString` (opens app-specific settings) with manual instructions in the message.

### 4. Android Permission Logic
**File:** `LocationHelper.java`

```
requestPermission()
    ↓
checkSelfPermission == GRANTED?
    → notifyPermissionResult(true)
    ↓
NOT GRANTED → requestPermissions() → system dialog appears
    ↓  (AppActivity.onRequestPermissionsResult fires)
onPermissionResult(granted)
    GRANTED → notifyPermissionResult(true)
    DENIED  → showPermissionDeniedAlert
                Title: "Location Permission Required"
                Message: "Please go to Settings and enable location access for this app."
                Button: "Open Settings" → ACTION_APPLICATION_DETAILS_SETTINGS
                _waitingForPermission = true

Location Services OFF case:
    showLocationServicesAlert
        Title: "Location Services Disabled"
        Message: "Your device's Location is turned off. To enable: Settings → Location → Turn ON"
        Button: "Open Settings" → ACTION_LOCATION_SOURCE_SETTINGS (opens Location page directly)
        _waitingForLocationServices = true

Return from Settings (AppActivity.onResume → LocationHelper.onAppResume):
    _waitingForLocationServices == true:
        Location ON  → requestPermission()
        Location OFF → showLocationServicesAlert again
    _waitingForPermission == true:
        Permission GRANTED → notifyPermissionResult(true)
        Permission DENIED  → showPermissionDeniedAlert again
```

> **Android Advantage:** `Settings.ACTION_LOCATION_SOURCE_SETTINGS` opens the Location settings page directly, unlike iOS where this deep-link is restricted.

### 5. Permission Granted → Get Location
**File:** `assets/scripts/location/LocationPermission.ts`

```typescript
window.onLocationPermission = (granted: boolean) => {
    if (granted) {
        LocationManager.instance.getLocation();    // Fetch location
    } else {
        cc.systemEvent.emit(LocationEvent.LOCATION_PERMISSION_DENIED);
    }
};
```

### 6. Get Location (JS → Native)
**File:** `assets/scripts/location/LocationManager.ts`

```typescript
jsb.reflection.callStaticMethod("LocationHelper", "getLocation:", "")             // iOS
jsb.reflection.callStaticMethod("org/cocos2dx/javascript/LocationHelper", "getLocation", "()V")  // Android
```

### 7. iOS Location Fetch
```
getLocation
    ↓
locationServicesEnabled == NO → showLocationServicesAlert
authorizationStatus != Authorized → onLocationError
    ↓
Last known location available?
    YES → reverseGeocode(lastLocation)
    NO  → startUpdatingLocation → didUpdateLocations fires → reverseGeocode(location)
    ↓
CLGeocoder.reverseGeocodeLocation
    Success → city, state, country, postcode → sendLocation
    Fail    → Nominatim API fallback
                https://nominatim.openstreetmap.org/reverse?lat=...&lon=...
                Parse JSON response → sendLocation
    ↓
evalJS("window.onLocation({latitude, longitude, city, state, country, postcode, isMock})")
```

### 8. Android Location Fetch
```
getLocation()
    ↓
checkSelfPermission != GRANTED → sendError
GPS or Network provider enabled?
    NO → showLocationServicesAlert
    ↓
getBestLastLocation (picks better accuracy between GPS and Network)
    Found → processAndSend(location)
    Null  → requestSingleUpdate → onLocationChanged fires → processAndSend(location)
    ↓
Android Geocoder.getFromLocation
    Success → city, state, country, postcode
    Fail    → Nominatim API fallback (same OpenStreetMap API)
    ↓
evalString("window.onLocation({...})")
```

### 9. Data Back to JS
**File:** `assets/scripts/location/LocationManager.ts`

```typescript
window.onLocation = (data: IGeoLocation) => {
    cc.systemEvent.emit(LocationEvent.LOCATION_UPDATE, data);
};
```

**File:** `assets/scripts/Home.ts`

```typescript
_onLocationUpdate(data: IGeoLocation) {
    latLabel.string = "Lat: " + data.latitude.toFixed(6);
    lngLabel.string = "Lng: " + data.longitude.toFixed(6);
    locationLabel.string = `City: ${data.city}, State: ${data.state}, Country: ${data.country}`;
}
```

---

## Geocoding Strategy

Both platforms use the same dual-fallback approach:

| Priority | Method | Notes |
|---|---|---|
| 1st | Device built-in Geocoder (CLGeocoder / Android Geocoder) | Fast, free, works offline |
| 2nd | OpenStreetMap Nominatim API | HTTP call, 5s timeout, User-Agent required |

Nominatim endpoint:
```
https://nominatim.openstreetmap.org/reverse?format=json&lat={lat}&lon={lon}&zoom=18&addressdetails=1
```

---

## Location Data Interface

```typescript
interface IGeoLocation {
    latitude: number;
    longitude: number;
    city: string;
    state: string;
    country: string;
    postcode: string;
    isMock: boolean;     // true if location is from a mock/fake GPS provider
}
```

---

## Events

```typescript
enum LocationEvent {
    LOCATION_UPDATE           // Fired when location data is received
    LOCATION_ERROR            // Fired when location fetch fails
    LOCATION_PERMISSION_DENIED  // Fired when user taps Cancel on permission denied alert
}
```

---

## Build Process

### iOS
1. Cocos Creator → Project → Build → Platform: iOS
2. Open `build/jsb-link/frameworks/runtime-src/proj.ios_mac/` in Xcode
3. Set Signing Team in Xcode → Signing & Capabilities
4. Select device → Cmd+R to build and run

### Android
1. Cocos Creator → Project → Build → Platform: Android
2. Open `build/jsb-link/frameworks/runtime-src/proj.android-studio/` in Android Studio
3. Wait for Gradle sync
4. Select device → Run → Run 'app'

### When to rebuild from Cocos vs just from Xcode/Android Studio

| Change Type | Action |
|---|---|
| TypeScript / JS changes | Cocos Build → then Xcode/AS Run |
| Native code changes only | Directly Xcode/AS Run (no Cocos build needed) |
| New assets added | Cocos Build → then Xcode/AS Run |
| Fresh setup / new machine | Cocos Build → then Xcode/AS Run |

---

## Integrating Into Another Cocos Creator Project

### Step 1 — Copy TypeScript Files

Copy the entire folder into the new project:
```
assets/scripts/location/
├── IGeoLocation.ts
├── LocationEvent.ts
├── LocationManager.ts
└── LocationPermission.ts
```

### Step 2 — iOS: Copy Native Files

Copy both files into the new project's `build-templates/jsb-link/frameworks/runtime-src/proj.ios_mac/ios/`:
```
LocationHelper.h
LocationHelper.mm
```

After Cocos build, open Xcode and add both files to the project:
- Right-click project in Xcode navigator → Add Files to project
- Select `LocationHelper.h` and `LocationHelper.mm`
- Check "Copy items if needed" → Add

### Step 3 — iOS: Update Info.plist

Add to `build-templates/jsb-link/frameworks/runtime-src/proj.ios_mac/ios/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>This app needs location access to show your current location.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>This app needs location access to show your current location.</string>
```

Without these keys, iOS will not show the permission dialog and the app will crash.

### Step 4 — Android: Copy LocationHelper.java

Copy to the new project's `build-templates/jsb-link/frameworks/runtime-src/proj.android-studio/app/src/org/cocos2dx/javascript/`:
```
LocationHelper.java
```

Make sure the package name at the top of `LocationHelper.java` matches the new project:
```java
package org.cocos2dx.javascript;   // update if your package is different
```

### Step 5 — Android: Update AppActivity.java

Add `LocationHelper.onAppResume()` in `onResume()`:

```java
@Override
protected void onResume() {
    super.onResume();
    SDKWrapper.getInstance().onResume();
    LocationHelper.onAppResume();    // Add this line
}
```

Add permission result handling in `onRequestPermissionsResult()`:

```java
@Override
public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
    super.onRequestPermissionsResult(requestCode, permissions, grantResults);
    if (requestCode == LocationHelper.PERMISSION_REQUEST_CODE) {
        boolean granted = grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        LocationHelper.onPermissionResult(granted);
    }
}
```

### Step 6 — Android: Add Permissions to AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

### Step 7 — Android: Update gradle.properties

In `build-templates/jsb-link/frameworks/runtime-src/proj.android-studio/gradle.properties`:

```properties
PROP_COMPILE_SDK_VERSION=34
PROP_TARGET_SDK_VERSION=34
```

This prevents the "This app isn't compatible with the latest version of Android" compatibility warning during installation.

### Step 8 — Use in Your Scene

```typescript
import LocationManager from "./location/LocationManager";
import LocationPermission from "./location/LocationPermission";
import { LocationEvent } from "./location/LocationEvent";
import { IGeoLocation } from "./location/IGeoLocation";

@ccclass
export default class YourScene extends cc.Component {

    start() {
        LocationManager.instance.init();

        cc.systemEvent.on(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
        cc.systemEvent.on(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
        cc.systemEvent.on(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);

        LocationPermission.request();
    }

    private _onLocationUpdate(data: IGeoLocation) {
        console.log("Latitude:", data.latitude);
        console.log("Longitude:", data.longitude);
        console.log("City:", data.city);
        console.log("State:", data.state);
        console.log("Country:", data.country);
        console.log("Postcode:", data.postcode);
        console.log("Mock:", data.isMock);
    }

    private _onLocationError(error: string) {
        console.error("Location Error:", error);
    }

    private _onPermissionDenied() {
        console.warn("User denied location permission");
    }

    onDestroy() {
        cc.systemEvent.off(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
        cc.systemEvent.off(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
        cc.systemEvent.off(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);
    }
}
```

---

## Integration Checklist

### iOS
- [ ] `LocationHelper.h` copied to `build-templates/.../ios/`
- [ ] `LocationHelper.mm` copied to `build-templates/.../ios/`
- [ ] `NSLocationWhenInUseUsageDescription` added to `Info.plist`
- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` added to `Info.plist`
- [ ] After Cocos build: both files added to Xcode project
- [ ] CoreLocation framework linked in Xcode (usually auto-linked)

### Android
- [ ] `LocationHelper.java` copied to `build-templates/.../javascript/`
- [ ] Package name in `LocationHelper.java` matches project
- [ ] `LocationHelper.onAppResume()` added to `AppActivity.onResume()`
- [ ] `LocationHelper.onPermissionResult()` added to `AppActivity.onRequestPermissionsResult()`
- [ ] `ACCESS_FINE_LOCATION` permission in `AndroidManifest.xml`
- [ ] `ACCESS_COARSE_LOCATION` permission in `AndroidManifest.xml`
- [ ] `PROP_TARGET_SDK_VERSION=34` in `gradle.properties`
- [ ] `PROP_COMPILE_SDK_VERSION=34` in `gradle.properties`

### Cocos / TypeScript
- [ ] `location/` folder copied to `assets/scripts/`
- [ ] `LocationManager.instance.init()` called before `LocationPermission.request()`
- [ ] `window.onLocationPermission` callback is registered (already in `LocationPermission.ts`)
- [ ] `LOCATION_UPDATE` event listener added in your scene
- [ ] `LOCATION_ERROR` event listener added in your scene

---

## Known Limitations

| Platform | Limitation |
|---|---|
| iOS | Cannot deep-link directly to Privacy & Security → Location Services (iOS 16+ restriction). App opens its own Settings page with manual instructions instead. |
| iOS | `CLLocationManager.authorizationStatus` returns `Denied` both when app permission is denied AND when Location Services is globally OFF. Must check `locationServicesEnabled` first. |
| Android | Sideloaded debug APKs show "This app isn't compatible" warning from Google Play Protect. This is normal for development and disappears after Play Store publishing. |
| Both | Nominatim API (fallback geocoding) requires internet connection and may be slow on first call. |

---

## Notes on `build-templates/`

Cocos Creator overwrites the `build/` folder every time you rebuild. The `build-templates/` folder is merged into `build/` during each Cocos build. This means:

- **Always keep native changes in `build-templates/`** — they persist across Cocos rebuilds
- **`build/` changes are temporary** — they get overwritten on next Cocos build
- For this reason, all native files in this project have been placed in `build-templates/` and kept in sync with `build/`
