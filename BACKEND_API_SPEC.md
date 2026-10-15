# GeoLocation: Backend Requirements

## Overview

The app (Android, iOS, and the web-mobile build in a browser) reads the user's location and checks whether the user is inside an allowed zone. Android and iOS also work out the city and state. This document lists what the backend needs to provide.

Today the zone is hard-coded in the app and the check runs only on the phone. A phone-side check can be bypassed with fake GPS or a modified app, so the backend must make the final decision.

## How the app works

```
App opens
  -> asks the user for location permission (the browser's prompt on web)
  -> GPS gives latitude and longitude
  -> city, state, country, postcode come from the phone's geocoder
     (empty on web, which has no geocoder)
  -> app checks the zone (distance from a centre point today)
  -> ZONE_ENTERED or ZONE_EXITED
```

Data the app has for each fix:

| Field | Type | Notes |
|---|---|---|
| latitude | number | |
| longitude | number | |
| accuracy | number | Horizontal accuracy in metres, `-1` if unknown |
| timestamp | number | When the fix was taken, milliseconds since epoch |
| isPrecise | boolean | `false` when the user allowed only approximate location. Web: always `true`, because browsers do not report it; use `accuracy`. |
| isMock | boolean | Android: mock-provider flag. iOS: catches Xcode/GPX simulation only, not third-party spoofing tools. Web: always `false`, because browsers cannot detect a faked location. |
| city | string | From the phone's geocoder. Empty on web, and when the geocoder fails (for example offline). |
| state | string | Same as city |
| country | string | Same as city |
| countryCode | string | ISO code such as `IN`. Same as city. |
| postcode | string | Same as city |
| platform | string | `android`, `ios` or `web` |

The app no longer calls OpenStreetMap Nominatim, because its usage policy does not allow periodic calls from every user's phone. When city, state or country are empty, the backend should geocode from latitude and longitude.

## What the backend needs to provide

### 1. Get zones

The app fetches the list of zones instead of using a hard-coded one.

```
GET /zones

200 OK
[
  {
    "id": "noida",
    "name": "Noida",
    "lat": 28.5355,
    "lng": 77.3910,
    "radiusKm": 12
  }
]
```

- A zone is a centre point plus a radius today.
- If exact city boundaries are needed, a zone can also carry `"polygon": [[lat, lng], ...]`. The app needs a code change to support this.
- Zones can then change without an app update.

### 2. Receive location and zone events

```
POST /location

{
  "userId": "u123",
  "event": "ENTERED",
  "latitude": 28.6285,
  "longitude": 77.3725,
  "accuracy": 12.5,
  "timestamp": 1760000000000,
  "isPrecise": true,
  "isMock": false,
  "city": "Noida",
  "state": "Uttar Pradesh",
  "country": "India",
  "countryCode": "IN",
  "postcode": "201301",
  "platform": "android"
}

200 OK
{ "allowed": true }
```

- `event` is `ENTERED`, `EXITED` or `UPDATE`.
- The app sends `UPDATE` when it opens, and `ENTERED` / `EXITED` on zone changes. It does not send every GPS tick.
- A periodic `UPDATE` (backend asked for every 10 minutes) is planned but not built yet.
- For `ENTERED` / `EXITED`, latitude, longitude and timestamp are current. The other fields come from the last full fix.

### 3. Final decision on the backend

- The backend re-checks the zone itself using the latitude and longitude.
- It rejects requests where `isMock` is `true` or the timestamp is old.
- It treats `isPrecise: false` or a large `accuracy` as not good enough for small zones.
- It can cross-check with the IP address to catch a VPN or the wrong state.
- It checks the zone before important actions such as joining a table or a deposit, instead of trusting the app's alert.

### 4. CORS for the web build

The web build calls `/zones` and `/location` from the browser. Both requests send `Content-Type: application/json`, so the browser first sends an `OPTIONS` preflight. Both endpoints must answer it and return `Access-Control-Allow-Origin` for the game's domain, with `Content-Type` in `Access-Control-Allow-Headers`.

## Known limits

- The web build gets location only on `https://` pages (and on `localhost`). Browsers report neither approximate-only access nor faked locations, so for `platform: "web"` the backend must rely on `accuracy`, the timestamp, and its own checks such as the IP address.

- On iOS, `isMock` catches only Xcode/GPX simulation. Apple confirms third-party spoofing tools may not set it, so the backend should not rely on `isMock` alone.
- Android 12+ and iOS 14+ let users share only approximate location. Coordinates can then be off by a few kilometres, which breaks small zones.
- City and state come from a geocoder that needs internet. Offline, they are empty but latitude and longitude still arrive.

## Open questions

1. Is the zone only an alert, or does it allow or block something? If it blocks, the backend check in section 3 is mandatory.
2. Is a circle enough, or do we need exact city or state boundaries (polygon)?
3. How often should the app send location?
