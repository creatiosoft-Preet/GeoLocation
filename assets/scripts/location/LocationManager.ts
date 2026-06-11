import { IGeoLocation } from "./IGeoLocation";
import { LocationEvent } from "./LocationEvent";

export default class LocationManager {

    private static _instance: LocationManager = null!;

    public static get instance() {
        if (!this._instance) {
            this._instance = new LocationManager();
        }
        return this._instance;
    }

    public init() {
        (window as any).onLocation = (data: IGeoLocation) => {
            cc.log("[LocationManager] onLocation received:", JSON.stringify(data));
            cc.systemEvent.emit(LocationEvent.LOCATION_UPDATE, data);
        };
        (window as any).onLocationError = (error: string) => {
            cc.log("[LocationManager] onLocationError received:", error);
            cc.systemEvent.emit(LocationEvent.LOCATION_ERROR, error);
        };
    }

    public getLocation() {
        cc.log("[LocationManager] getLocation called, isNative:", cc.sys.isNative, "os:", cc.sys.os);

        if (!cc.sys.isNative) return;

        if (cc.sys.os === cc.sys.OS_ANDROID) {
            cc.log("[LocationManager] calling Android getLocation");
            jsb.reflection.callStaticMethod(
                "org/cocos2dx/javascript/LocationHelper",
                "getLocation",
                "()V"
            );
        } else if (cc.sys.os === cc.sys.OS_IOS) {
            cc.log("[LocationManager] calling iOS getLocation");
            jsb.reflection.callStaticMethod(
                "LocationHelper",
                "getLocation:",
                ""
            );
        }
    }

}
