import { LocationEvent } from "./LocationEvent";

export default class LocationPermission {

    public static request() {
        if (!cc.sys.isNative) {
            cc.systemEvent.emit(LocationEvent.LOCATION_ERROR, "Native only");
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
                "requestPermission",
                ""
            );
        }
    }

}

(window as any).onLocationPermission = (granted: boolean) => {
    if (granted) {
        cc.systemEvent.emit(LocationEvent.LOCATION_UPDATE);
    } else {
        cc.systemEvent.emit(LocationEvent.LOCATION_PERMISSION_DENIED);
    }
};
