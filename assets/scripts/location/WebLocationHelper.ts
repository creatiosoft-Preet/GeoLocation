import { IGeoLocation } from "./IGeoLocation";

// Same limits as the native LocationHelper.
const MAX_CACHED_AGE_MS = 60 * 1000;
const SINGLE_FIX_TIMEOUT_MS = 30 * 1000;

/**
 * Browser version of the native LocationHelper, used by the web-mobile build and the editor preview.
 * It reports through the same window callbacks as the native code (onLocationPermission, onLocation,
 * onLocationError, onLocationTick), so everything after that is shared with Android and iOS.
 */
export default class WebLocationHelper {

    private static _watchId: number | null = null;

    public static requestPermission() {
        const geo = this._geolocation();
        if (!geo) return;
        // Browsers have no separate permission call: the first position request shows the prompt.
        geo.getCurrentPosition(
            () => this._notifyPermission(true),
            (error) => {
                if (error.code === error.PERMISSION_DENIED) {
                    this.showAlert("Location Permission Required",
                        "Please allow location access for this site in your browser settings, then reload the page.");
                    this._notifyPermission(false);
                } else {
                    // Access was allowed and only this fix failed; getLocation and the watch try again.
                    this._notifyPermission(true);
                }
            },
            { enableHighAccuracy: true, timeout: SINGLE_FIX_TIMEOUT_MS, maximumAge: MAX_CACHED_AGE_MS }
        );
    }

    public static getLocation() {
        const geo = this._geolocation();
        if (!geo) return;
        // maximumAge lets the browser reuse a fix up to a minute old, like the native cache.
        geo.getCurrentPosition(
            (position) => (window as any).onLocation(this._toGeoLocation(position)),
            (error) => this._sendError(error),
            { enableHighAccuracy: true, timeout: SINGLE_FIX_TIMEOUT_MS, maximumAge: MAX_CACHED_AGE_MS }
        );
    }

    public static startContinuousUpdates() {
        // Already running: a second watch would deliver every tick twice.
        if (this._watchId !== null) return;
        const geo = this._geolocation();
        if (!geo) return;
        this._watchId = geo.watchPosition(
            (position) => (window as any).onLocationTick(
                position.coords.latitude, position.coords.longitude, position.coords.accuracy),
            (error) => this._sendError(error),
            { enableHighAccuracy: true, maximumAge: 0 }
        );
    }

    public static stopContinuousUpdates() {
        if (this._watchId === null) return;
        navigator.geolocation.clearWatch(this._watchId);
        this._watchId = null;
    }

    public static showAlert(title: string, message: string) {
        cc.warn(`[WebLocationHelper] ${title}: ${message}`);
        // alert() blocks the page, so let the current frame finish first.
        setTimeout(() => window.alert(`${title}\n\n${message}`), 0);
    }

    private static _geolocation(): Geolocation | null {
        // Browsers give location only to https:// pages and localhost.
        if (window.isSecureContext === false) {
            (window as any).onLocationError("Location needs HTTPS");
            return null;
        }
        if (!navigator.geolocation) {
            (window as any).onLocationError("Geolocation not supported");
            return null;
        }
        return navigator.geolocation;
    }

    private static _notifyPermission(granted: boolean) {
        // Browsers do not report approximate-only access, so precise follows granted;
        // the accuracy of each fix shows how good it really is.
        (window as any).onLocationPermission(granted, granted);
    }

    private static _toGeoLocation(position: GeolocationPosition): IGeoLocation {
        return {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy,
            timestamp: position.timestamp,
            isPrecise: true,
            // Browsers cannot tell a faked position (e.g. DevTools Sensors) from a real one.
            isMock: false,
            // There is no geocoder in the browser; the backend geocodes from latitude/longitude.
            city: "",
            state: "",
            country: "",
            countryCode: "",
            postcode: "",
            platform: "web",
        };
    }

    private static _sendError(error: GeolocationPositionError) {
        cc.warn("[WebLocationHelper] geolocation error:", error.code, error.message);
        // Same wording as the native helpers where one exists.
        let msg = "Position unavailable";
        if (error.code === error.PERMISSION_DENIED) msg = "Permission not granted";
        else if (error.code === error.TIMEOUT) msg = "Location timeout";
        (window as any).onLocationError(msg);
    }
}
