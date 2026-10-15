package org.cocos2dx.javascript;

import android.Manifest;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.location.Address;
import android.location.Geocoder;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxJavascriptJavaBridge;
import org.json.JSONObject;

import java.util.List;
import java.util.Locale;

// Targets minSdk 24, so the framework permission APIs (added in API 23) are safe to call directly.
public class LocationHelper {

    private static final String TAG = "LocationHelper";
    // 1001/1002 are taken by camera/microphone in txpoker, so location uses its own code.
    static final int PERMISSION_REQUEST_CODE = 3001;
    // A cached fix older than this is not reused; a fresh one is requested instead.
    private static final long MAX_CACHED_AGE_MS = 60 * 1000;
    private static final long SINGLE_FIX_TIMEOUT_MS = 30 * 1000;

    private static final String[] LOCATION_PERMISSIONS = {
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
    };

    private static boolean _waitingForLocationServices = false;
    private static boolean _waitingForPermission = false;
    private static LocationListener _continuousListener = null;

    public static void requestPermission() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;

        if (hasAnyPermission(activity)) {
            notifyPermissionResult(activity, true);
        } else {
            // Android 12+ ignores a request for FINE alone, so ask for FINE and COARSE together.
            activity.runOnUiThread(() ->
                activity.requestPermissions(LOCATION_PERMISSIONS, PERMISSION_REQUEST_CODE)
            );
        }
    }

    static void onPermissionResult() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;
        // The user may pick "approximate", which grants COARSE only; that still counts as granted.
        if (hasAnyPermission(activity)) {
            notifyPermissionResult(activity, true);
        } else {
            showPermissionDeniedAlert(activity);
        }
    }

    static void onAppResume() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;

        if (_waitingForLocationServices) {
            _waitingForLocationServices = false;
            if (isLocationEnabled(activity)) {
                requestPermission();
            } else {
                showLocationServicesAlert(activity);
            }
        } else if (_waitingForPermission) {
            _waitingForPermission = false;
            if (hasAnyPermission(activity)) {
                notifyPermissionResult(activity, true);
            } else {
                showPermissionDeniedAlert(activity);
            }
        }
    }

    public static void startContinuousUpdates() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;
        if (!hasAnyPermission(activity)) return;
        // Already running: registering again would deliver every tick twice.
        if (_continuousListener != null) return;

        LocationManager lm = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);

        _continuousListener = new LocationListener() {
            @Override
            public void onLocationChanged(Location location) {
                Log.d(TAG, "onLocationChanged: provider=" + location.getProvider()
                        + " lat=" + location.getLatitude()
                        + " lng=" + location.getLongitude()
                        + " acc=" + location.getAccuracy());
                String js = String.format(Locale.US, "window.onLocationTick(%f,%f,%f)",
                        location.getLatitude(), location.getLongitude(),
                        location.hasAccuracy() ? location.getAccuracy() : -1f);
                activity.runOnGLThread(() ->
                        Cocos2dxJavascriptJavaBridge.evalString(js));
            }
            @Override public void onStatusChanged(String p, int s, Bundle e) {}
            @Override public void onProviderEnabled(String p) {}
            @Override public void onProviderDisabled(String p) {}
        };

        final LocationListener listener = _continuousListener;
        activity.runOnUiThread(() -> {
            boolean gpsEnabled = lm.isProviderEnabled(LocationManager.GPS_PROVIDER);
            boolean networkEnabled = lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
            Log.d(TAG, "startContinuousUpdates: gpsEnabled=" + gpsEnabled + " networkEnabled=" + networkEnabled);
            try {
                if (gpsEnabled) {
                    lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, 1000, 1, listener, Looper.getMainLooper());
                }
                if (networkEnabled) {
                    lm.requestLocationUpdates(LocationManager.NETWORK_PROVIDER, 1000, 1, listener, Looper.getMainLooper());
                }
            } catch (SecurityException e) {
                Log.w(TAG, "startContinuousUpdates: " + e.getMessage());
            }
        });
    }

    public static void showAlert(String params) {
        String[] parts = params.split("\\|", 2);
        String title   = parts.length > 0 ? parts[0] : "Alert";
        String message = parts.length > 1 ? parts[1] : "";
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;
        activity.runOnUiThread(() ->
            new AlertDialog.Builder(activity)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton("OK", null)
                .show()
        );
    }

    public static void stopContinuousUpdates() {
        AppActivity activity = AppActivity.getInstance();
        if (activity != null && _continuousListener != null) {
            LocationManager lm = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);
            lm.removeUpdates(_continuousListener);
            _continuousListener = null;
        }
    }

    private static void showLocationServicesAlert(AppActivity activity) {
        activity.runOnUiThread(() ->
            new AlertDialog.Builder(activity)
                .setTitle("Location Services Disabled")
                .setMessage("Your device's Location is turned off.\n\nTo enable it:\nSettings → Location → Turn ON")
                .setPositiveButton("Open Settings", (dialog, which) -> {
                    _waitingForLocationServices = true;
                    Intent intent = new Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS);
                    activity.startActivity(intent);
                })
                .setCancelable(false)
                .show()
        );
    }

    private static void showPermissionDeniedAlert(AppActivity activity) {
        activity.runOnUiThread(() ->
            new AlertDialog.Builder(activity)
                .setTitle("Location Permission Required")
                .setMessage("Please go to Settings and enable location access for this app.")
                .setPositiveButton("Open Settings", (dialog, which) -> {
                    _waitingForPermission = true;
                    Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                    intent.setData(Uri.fromParts("package", activity.getPackageName(), null));
                    activity.startActivity(intent);
                })
                .setCancelable(false)
                .show()
        );
    }

    private static void notifyPermissionResult(AppActivity activity, boolean granted) {
        final boolean precise = hasFinePermission(activity);
        activity.runOnGLThread(() ->
            Cocos2dxJavascriptJavaBridge.evalString(
                    "window.onLocationPermission(" + granted + "," + precise + ")")
        );
    }

    public static void getLocation() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;

        if (!hasAnyPermission(activity)) {
            sendError(activity, "Permission not granted");
            return;
        }

        if (!isLocationEnabled(activity)) {
            showLocationServicesAlert(activity);
            return;
        }

        LocationManager locationManager = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);

        Location cached = getBestLastLocation(locationManager);
        if (cached != null && System.currentTimeMillis() - cached.getTime() < MAX_CACHED_AGE_MS) {
            processAndSend(activity, cached);
            return;
        }

        // No recent cached location — request a fresh fix
        activity.runOnUiThread(() -> {
            String provider = pickProvider(locationManager, hasFinePermission(activity));
            if (provider == null) {
                sendError(activity, "No location provider enabled");
                return;
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Times out by itself and returns null if no fix arrives.
                    locationManager.getCurrentLocation(provider, null, activity.getMainExecutor(), location -> {
                        if (location != null) {
                            processAndSend(activity, location);
                        } else {
                            sendError(activity, "Location timeout");
                        }
                    });
                } else {
                    requestSingleFixLegacy(activity, locationManager, provider);
                }
            } catch (SecurityException e) {
                sendError(activity, "Security exception");
            }
        });
    }

    // API 24-29: requestSingleUpdate has no timeout of its own, so add one.
    @SuppressWarnings("deprecation")
    private static void requestSingleFixLegacy(AppActivity activity, LocationManager lm, String provider) {
        final Handler handler = new Handler(Looper.getMainLooper());
        final boolean[] done = {false};
        final LocationListener listener = new LocationListener() {
            @Override
            public void onLocationChanged(Location location) {
                if (done[0]) return;
                done[0] = true;
                handler.removeCallbacksAndMessages(null);
                processAndSend(activity, location);
            }
            @Override public void onStatusChanged(String p, int s, Bundle e) {}
            @Override public void onProviderEnabled(String p) {}
            @Override public void onProviderDisabled(String p) {
                if (done[0]) return;
                done[0] = true;
                handler.removeCallbacksAndMessages(null);
                sendError(activity, "Provider disabled");
            }
        };
        lm.requestSingleUpdate(provider, listener, Looper.getMainLooper());
        handler.postDelayed(() -> {
            if (done[0]) return;
            done[0] = true;
            lm.removeUpdates(listener);
            sendError(activity, "Location timeout");
        }, SINGLE_FIX_TIMEOUT_MS);
    }

    private static boolean hasFinePermission(Context context) {
        return context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    private static boolean hasAnyPermission(Context context) {
        return hasFinePermission(context)
                || context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    private static boolean isLocationEnabled(Context context) {
        LocationManager lm = (LocationManager) context.getSystemService(Context.LOCATION_SERVICE);
        if (lm == null) return false;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return lm.isLocationEnabled();
        }
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER)
                || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
    }

    // With only COARSE granted, prefer the network provider.
    private static String pickProvider(LocationManager lm, boolean precise) {
        boolean gps = lm.isProviderEnabled(LocationManager.GPS_PROVIDER);
        boolean network = lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER);
        if (precise && gps) return LocationManager.GPS_PROVIDER;
        if (network) return LocationManager.NETWORK_PROVIDER;
        if (gps) return LocationManager.GPS_PROVIDER;
        return null;
    }

    // Newest last-known fix across providers (accuracy alone would favour a stale GPS fix).
    private static Location getBestLastLocation(LocationManager lm) {
        Location best = null;
        for (String provider : lm.getProviders(true)) {
            try {
                Location l = lm.getLastKnownLocation(provider);
                if (l != null && (best == null || l.getTime() > best.getTime())) best = l;
            } catch (SecurityException ignored) {}
        }
        return best;
    }

    @SuppressWarnings("deprecation")
    private static boolean isMock(Location location) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return location.isMock();
        }
        return location.isFromMockProvider();
    }

    private static void processAndSend(AppActivity activity, Location location) {
        new Thread(() -> {
            String city = "", state = "", country = "", countryCode = "", postcode = "";

            // City comes from the phone's geocoder only. If it fails the fields stay empty and
            // the backend should geocode from latitude/longitude.
            try {
                if (Geocoder.isPresent()) {
                    Geocoder geocoder = new Geocoder(activity, Locale.getDefault());
                    @SuppressWarnings("deprecation")
                    List<Address> addresses = geocoder.getFromLocation(
                            location.getLatitude(), location.getLongitude(), 1);
                    if (addresses != null && !addresses.isEmpty()) {
                        Address addr = addresses.get(0);
                        city        = addr.getLocality()    != null ? addr.getLocality()    : "";
                        state       = addr.getAdminArea()   != null ? addr.getAdminArea()   : "";
                        country     = addr.getCountryName() != null ? addr.getCountryName() : "";
                        countryCode = addr.getCountryCode() != null ? addr.getCountryCode() : "";
                        postcode    = addr.getPostalCode()  != null ? addr.getPostalCode()  : "";
                    }
                }
            } catch (Exception e) {
                Log.w(TAG, "Geocoder failed: " + e.getMessage());
            }

            String json;
            try {
                JSONObject obj = new JSONObject();
                obj.put("latitude", location.getLatitude());
                obj.put("longitude", location.getLongitude());
                obj.put("accuracy", location.hasAccuracy() ? location.getAccuracy() : -1);
                obj.put("timestamp", location.getTime());
                obj.put("isPrecise", hasFinePermission(activity));
                obj.put("isMock", isMock(location));
                obj.put("city", city);
                obj.put("state", state);
                obj.put("country", country);
                obj.put("countryCode", countryCode);
                obj.put("postcode", postcode);
                obj.put("platform", "android");
                json = obj.toString();
            } catch (Exception e) {
                Log.e(TAG, "processAndSend: " + e.getMessage());
                sendError(activity, "Failed to build location");
                return;
            }

            activity.runOnGLThread(() ->
                Cocos2dxJavascriptJavaBridge.evalString("window.onLocation(" + json + ")")
            );
        }).start();
    }

    private static void sendError(AppActivity activity, String msg) {
        activity.runOnGLThread(() ->
            Cocos2dxJavascriptJavaBridge.evalString("window.onLocationError(" + JSONObject.quote(msg) + ")")
        );
    }
}
