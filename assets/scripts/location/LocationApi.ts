import { IGeoLocation } from "./IGeoLocation";
import GeofenceManager, { IZone } from "./GeofenceManager";

export type LocationApiEvent = "UPDATE" | "ENTERED" | "EXITED";

/**
 * Backend calls described in BACKEND_API_SPEC.md:
 *   GET  {BASE_URL}/zones     -> IZone[]
 *   POST {BASE_URL}/location  -> { allowed: boolean }
 * While BASE_URL is empty nothing is sent, so the app keeps using the built-in zone.
 */
export default class LocationApi {

    // TODO: set once the backend is ready, e.g. "https://api.example.com"
    public static BASE_URL = "";
    public static userId = "";
    private static _lastFix: IGeoLocation | null = null;

    public static fetchZones(): void {
        if (!this.BASE_URL) return;
        this._request("GET", "/zones", null, (status, body) => {
            if (status !== 200 || !Array.isArray(body)) {
                cc.warn("[LocationApi] fetchZones failed, keeping current zones. status:", status);
                return;
            }
            GeofenceManager.instance.loadZones(body as IZone[]);
            cc.log(`[LocationApi] loaded ${body.length} zones`);
        });
    }

    /** Sends a full fix. Call on every LOCATION_UPDATE. */
    public static sendLocation(data: IGeoLocation, onResult?: (allowed: boolean) => void): void {
        this._lastFix = data;
        this._send(data, "UPDATE", onResult);
    }

    /**
     * Sends a zone change. Zone changes come from continuous ticks, which carry only
     * latitude/longitude, so the rest of the fields come from the last full fix.
     */
    public static sendZoneEvent(event: "ENTERED" | "EXITED", lat: number, lng: number,
                                onResult?: (allowed: boolean) => void): void {
        const base = this._lastFix;
        if (!base) return;
        this._send({ ...base, latitude: lat, longitude: lng, timestamp: Date.now() }, event, onResult);
    }

    private static _send(data: IGeoLocation, event: LocationApiEvent, onResult?: (allowed: boolean) => void) {
        if (!this.BASE_URL) return;
        const payload = { userId: this.userId, event, ...data };
        this._request("POST", "/location", payload, (status, body) => {
            const allowed = status === 200 && !!body && body.allowed === true;
            if (status !== 200) cc.warn("[LocationApi] sendLocation failed. status:", status);
            if (onResult) onResult(allowed);
        });
    }

    private static _request(method: string, path: string, payload: any,
                            done: (status: number, body: any) => void) {
        const xhr = new XMLHttpRequest();
        xhr.open(method, this.BASE_URL + path, true);
        xhr.timeout = 10000;
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== 4) return;
            let body: any = null;
            try { body = JSON.parse(xhr.responseText); } catch (e) { /* non-JSON body */ }
            done(xhr.status, body);
        };
        xhr.send(payload ? JSON.stringify(payload) : null);
    }
}
