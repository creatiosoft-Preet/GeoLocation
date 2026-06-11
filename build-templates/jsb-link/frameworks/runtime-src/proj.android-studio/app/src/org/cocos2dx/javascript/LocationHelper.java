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
import android.os.Bundle;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

import org.cocos2dx.lib.Cocos2dxJavascriptJavaBridge;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.List;
import java.util.Locale;

public class LocationHelper {

    private static final String TAG = "LocationHelper";
    static final int PERMISSION_REQUEST_CODE = 1001;

    public static void requestPermission() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;

        if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED) {
            notifyPermissionResult(activity, true);
        } else {
            activity.runOnUiThread(() ->
                activity.requestPermissions(
                    new String[]{Manifest.permission.ACCESS_FINE_LOCATION},
                    PERMISSION_REQUEST_CODE)
            );
        }
    }

    static void onPermissionResult(boolean granted) {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;
        if (granted) {
            notifyPermissionResult(activity, true);
        } else {
            showPermissionDeniedAlert(activity);
        }
    }

    private static void showPermissionDeniedAlert(AppActivity activity) {
        activity.runOnUiThread(() ->
            new AlertDialog.Builder(activity)
                .setTitle("Location Permission Required")
                .setMessage("Please go to Settings and enable location access for this app.")
                .setPositiveButton("Open Settings", (dialog, which) -> {
                    Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                    intent.setData(Uri.fromParts("package", activity.getPackageName(), null));
                    activity.startActivity(intent);
                })
                .setNegativeButton("Cancel", (dialog, which) ->
                    notifyPermissionResult(activity, false))
                .setCancelable(false)
                .show()
        );
    }

    private static void notifyPermissionResult(AppActivity activity, boolean granted) {
        activity.runOnGLThread(() ->
            Cocos2dxJavascriptJavaBridge.evalString("window.onLocationPermission(" + granted + ")")
        );
    }

    public static void getLocation() {
        AppActivity activity = AppActivity.getInstance();
        if (activity == null) return;

        if (activity.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION)
                != PackageManager.PERMISSION_GRANTED) {
            sendError(activity, "Permission not granted");
            return;
        }

        LocationManager locationManager = (LocationManager) activity.getSystemService(Context.LOCATION_SERVICE);

        Location best = getBestLastLocation(locationManager);
        if (best != null) {
            processAndSend(activity, best);
            return;
        }

        // No cached location — request fresh fix
        activity.runOnUiThread(() -> {
            String provider = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER)
                    ? LocationManager.GPS_PROVIDER
                    : LocationManager.NETWORK_PROVIDER;
            try {
                locationManager.requestSingleUpdate(provider, new LocationListener() {
                    @Override
                    public void onLocationChanged(Location location) {
                        processAndSend(activity, location);
                    }
                    @Override public void onStatusChanged(String p, int s, Bundle e) {}
                    @Override public void onProviderEnabled(String p) {}
                    @Override public void onProviderDisabled(String p) {
                        sendError(activity, "Provider disabled");
                    }
                }, Looper.getMainLooper());
            } catch (SecurityException e) {
                sendError(activity, "Security exception");
            }
        });
    }

    private static Location getBestLastLocation(LocationManager lm) {
        Location gps = null, network = null;
        try {
            if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER))
                gps = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER);
        } catch (SecurityException ignored) {}
        try {
            if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))
                network = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER);
        } catch (SecurityException ignored) {}

        if (gps != null && network != null)
            return gps.getAccuracy() <= network.getAccuracy() ? gps : network;
        return gps != null ? gps : network;
    }

    private static void processAndSend(AppActivity activity, Location location) {
        new Thread(() -> {
            String city = "", state = "", country = "", postcode = "";

            // Try Android Geocoder first
            try {
                if (Geocoder.isPresent()) {
                    Geocoder geocoder = new Geocoder(activity, Locale.getDefault());
                    List<Address> addresses = geocoder.getFromLocation(
                            location.getLatitude(), location.getLongitude(), 1);
                    if (addresses != null && !addresses.isEmpty()) {
                        Address addr = addresses.get(0);
                        city     = addr.getLocality()    != null ? addr.getLocality()    : "";
                        state    = addr.getAdminArea()   != null ? addr.getAdminArea()   : "";
                        country  = addr.getCountryName() != null ? addr.getCountryName() : "";
                        postcode = addr.getPostalCode()  != null ? addr.getPostalCode()  : "";
                    }
                }
            } catch (IOException e) {
                Log.w(TAG, "Geocoder failed, trying Nominatim: " + e.getMessage());
            }

            // Fallback: OpenStreetMap Nominatim API
            if (city.isEmpty() && country.isEmpty()) {
                try {
                    String urlStr = String.format(Locale.US,
                        "https://nominatim.openstreetmap.org/reverse?format=json&lat=%f&lon=%f&zoom=18&addressdetails=1",
                        location.getLatitude(), location.getLongitude());
                    HttpURLConnection conn = (HttpURLConnection) new URL(urlStr).openConnection();
                    conn.setRequestMethod("GET");
                    conn.setRequestProperty("User-Agent", "GeoLocationApp/1.0");
                    conn.setConnectTimeout(5000);
                    conn.setReadTimeout(5000);

                    BufferedReader reader = new BufferedReader(
                        new InputStreamReader(conn.getInputStream()));
                    StringBuilder sb = new StringBuilder();
                    String line;
                    while ((line = reader.readLine()) != null) sb.append(line);
                    reader.close();
                    conn.disconnect();

                    String response = sb.toString();
                    city     = extractJson(response, "city");
                    if (city.isEmpty()) city = extractJson(response, "town");
                    if (city.isEmpty()) city = extractJson(response, "village");
                    if (city.isEmpty()) city = extractJson(response, "county");
                    state    = extractJson(response, "state");
                    country  = extractJson(response, "country");
                    postcode = extractJson(response, "postcode");
                } catch (Exception e) {
                    Log.w(TAG, "Nominatim failed: " + e.getMessage());
                }
            }

            boolean isMock = location.isFromMockProvider();
            String json = String.format(Locale.US,
                "{\"latitude\":%f,\"longitude\":%f,\"city\":\"%s\",\"state\":\"%s\",\"country\":\"%s\",\"postcode\":\"%s\",\"isMock\":%b}",
                location.getLatitude(), location.getLongitude(),
                escape(city), escape(state), escape(country), escape(postcode), isMock);

            activity.runOnGLThread(() ->
                Cocos2dxJavascriptJavaBridge.evalString("window.onLocation(" + json + ")")
            );
        }).start();
    }

    private static String extractJson(String json, String key) {
        String search = "\"" + key + "\":\"";
        int start = json.indexOf(search);
        if (start == -1) return "";
        start += search.length();
        int end = json.indexOf("\"", start);
        if (end == -1) return "";
        return json.substring(start, end);
    }

    private static void sendError(AppActivity activity, String msg) {
        activity.runOnGLThread(() ->
            Cocos2dxJavascriptJavaBridge.evalString("window.onLocationError('" + msg + "')")
        );
    }

    private static String escape(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("'", "\\'");
    }
}
