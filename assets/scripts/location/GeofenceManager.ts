import { LocationEvent } from "./LocationEvent";

export interface IZone {
    id: string;
    name: string;
    lat: number;
    lng: number;
    radiusKm: number;
}

// Default safe zone — when backend is ready, replace via loadZones() with API-fetched zones.
// Inside radiusKm of this point = safe zone, outside = unsafe zone.
const ZONES: IZone[] = [
    { id: "safe", name: "Safe Zone", lat: 28.628508, lng: 77.372525, radiusKm: 0.005 },
];

// Extra distance (km) beyond radiusKm before an "inside" zone is considered exited, and vice versa.
const ZONE_BUFFER_KM = 0.005; // 5m hysteresis buffer to absorb GPS jitter

export default class GeofenceManager {

    private static _instance: GeofenceManager;
    private _activeZones: Set<string> = new Set();
    private _checkedZones: Set<string> = new Set();

    public static get instance(): GeofenceManager {
        if (!this._instance) this._instance = new GeofenceManager();
        return this._instance;
    }

    public init() {
        (window as any).onLocationTick = (lat: number, lng: number) => {
            cc.log(`[Geofence] tick (${lat}, ${lng})`);
            this.checkZones(lat, lng);
        };
        this._startContinuous();
    }

    public stop() {
        if (!cc.sys.isNative) return;
        if (cc.sys.os === cc.sys.OS_IOS) {
            jsb.reflection.callStaticMethod("LocationHelper", "stopContinuousUpdates:", "");
        } else if (cc.sys.os === cc.sys.OS_ANDROID) {
            jsb.reflection.callStaticMethod("org/cocos2dx/javascript/LocationHelper", "stopContinuousUpdates", "()V");
        }
    }

    // When backend is ready: fetch zones from API and replace ZONES array
    public static showNativeAlert(title: string, message: string) {
        if (!cc.sys.isNative) { cc.warn(`${title}: ${message}`); return; }
        const params = `${title}|${message}`;
        if (cc.sys.os === cc.sys.OS_IOS) {
            jsb.reflection.callStaticMethod("LocationHelper", "showAlert:", params);
        } else if (cc.sys.os === cc.sys.OS_ANDROID) {
            jsb.reflection.callStaticMethod(
                "org/cocos2dx/javascript/LocationHelper",
                "showAlert", "(Ljava/lang/String;)V", params);
        }
    }

    public loadZones(zones: IZone[]) {
        ZONES.length = 0;
        zones.forEach(z => ZONES.push(z));
    }

    private _startContinuous() {
        if (!cc.sys.isNative) return;
        if (cc.sys.os === cc.sys.OS_IOS) {
            jsb.reflection.callStaticMethod("LocationHelper", "startContinuousUpdates:", "");
        } else if (cc.sys.os === cc.sys.OS_ANDROID) {
            jsb.reflection.callStaticMethod("org/cocos2dx/javascript/LocationHelper", "startContinuousUpdates", "()V");
        }
    }

    public checkZones(lat: number, lng: number) {
        for (const zone of ZONES) {
            const dist = this._haversine(lat, lng, zone.lat, zone.lng);
            const wasInside = this._activeZones.has(zone.id);
            // Hysteresis: once inside, must move past radius + buffer to count as exited (and vice versa).
            // Avoids alert flip-flopping from GPS jitter near the boundary.
            const threshold = wasInside ? zone.radiusKm + ZONE_BUFFER_KM : zone.radiusKm;
            const inside = dist <= threshold;
            const firstCheck = !this._checkedZones.has(zone.id);
            this._checkedZones.add(zone.id);

            if (zone.id === "safe") {
                cc.log(`[Geofence] safe zone dist=${(dist * 1000).toFixed(1)}m threshold=${(threshold * 1000).toFixed(1)}m inside=${inside}`);
            }

            if (inside && (!wasInside || firstCheck)) {
                this._activeZones.add(zone.id);
                cc.log(`[Geofence] ENTERED: ${zone.name} (${dist.toFixed(2)} km from center)`);
                cc.systemEvent.emit(LocationEvent.ZONE_ENTERED, zone);
            } else if (!inside && (wasInside || firstCheck)) {
                this._activeZones.delete(zone.id);
                cc.log(`[Geofence] EXITED: ${zone.name}`);
                cc.systemEvent.emit(LocationEvent.ZONE_EXITED, zone);
            }
        }
    }

    private _haversine(lat1: number, lng1: number, lat2: number, lng2: number): number {
        const R = 6371;
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLng = (lng2 - lng1) * Math.PI / 180;
        const a =
            Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
