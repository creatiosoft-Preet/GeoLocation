import { LocationEvent } from "./LocationEvent";
import LocationManager from "./LocationManager";
import GeofenceManager from "./GeofenceManager";
import WebLocationHelper from "./WebLocationHelper";

export default class LocationPermission {

    /** false when the user granted only approximate location. */
    public static isPrecise = false;

    public static request() {
        if (!cc.sys.isNative) {
            WebLocationHelper.requestPermission();
            return;
        }

        if (cc.sys.os === cc.sys.OS_ANDROID) {
            jsb.reflection.callStaticMethod(
                "org/cocos2dx/javascript/LocationHelper",
                "requestPermission",
                "()V"
            );
        } else if (cc.sys.os === cc.sys.OS_IOS) {
            jsb.reflection.callStaticMethod(
                "LocationHelper",
                "requestPermission:",
                ""
            );
        }
    }

}

(window as any).onLocationPermission = (granted: boolean, precise: boolean) => {
    if (granted) {
        LocationPermission.isPrecise = !!precise;
        if (!precise) cc.warn("[LocationPermission] only approximate location granted");
        LocationManager.instance.getLocation();
        GeofenceManager.instance.init();
    } else {
        cc.systemEvent.emit(LocationEvent.LOCATION_PERMISSION_DENIED);
    }
};
