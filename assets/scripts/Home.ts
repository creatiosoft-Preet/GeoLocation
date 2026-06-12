const { ccclass, property } = cc._decorator;

import { IGeoLocation } from "./location/IGeoLocation";
import { LocationEvent } from "./location/LocationEvent";
import GeofenceManager, { IZone } from "./location/GeofenceManager";
import LocationManager from "./location/LocationManager";
import LocationPermission from "./location/LocationPermission";

@ccclass
export default class Home extends cc.Component {

    @property(cc.Node) popup: cc.Node | null = null;
    @property(cc.Label) latLabel: cc.Label | null = null;
    @property(cc.Label) lngLabel: cc.Label | null = null;
    @property(cc.Label) locationLabel: cc.Label | null = null;

    start() {
        if (this.popup) this.popup.active = false;

        LocationManager.instance.init();

        cc.systemEvent.on(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
        cc.systemEvent.on(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
        cc.systemEvent.on(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);
        cc.systemEvent.on(LocationEvent.ZONE_ENTERED, this._onZoneEntered, this);
        cc.systemEvent.on(LocationEvent.ZONE_EXITED, this._onZoneExited, this);

        LocationPermission.request();
    }

    private _onLocationUpdate(data: IGeoLocation) {
        // App open / fresh fix: check immediately whether we're in the safe zone
        GeofenceManager.instance.checkZones(data.latitude, data.longitude);

        cc.log("Location : ", data);

        if (this.popup) this.popup.active = true;

        if (this.latLabel) this.latLabel.string = "Lat : " + data.latitude.toFixed(6);

        if (this.lngLabel) this.lngLabel.string = "Lng : " + data.longitude.toFixed(6);

        if (this.locationLabel) {
            this.locationLabel.string = `City: ${data.city}, State: ${data.state}, Country: ${data.country}`;
        }

        cc.log("Postcode : ", data.postcode);
        cc.log("Mock : ", data.isMock);
    }

    private _onLocationError(error: string) {
        cc.error("Location Error : ", error);
    }

    private _onPermissionDenied() {
        cc.warn("Location Permission Denied");
    }

    private _onZoneEntered(_zone: IZone) {
        GeofenceManager.showNativeAlert(
            "Safe Zone",
            `You are in the safe zone.`
        );
    }

    private _onZoneExited(_zone: IZone) {
        GeofenceManager.showNativeAlert(
            "Unsafe Zone",
            `Warning! You have left the safe zone.`
        );
    }

    onDestroy() {
        cc.systemEvent.off(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
        cc.systemEvent.off(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
        cc.systemEvent.off(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);
        cc.systemEvent.off(LocationEvent.ZONE_ENTERED, this._onZoneEntered, this);
        cc.systemEvent.off(LocationEvent.ZONE_EXITED, this._onZoneExited, this);
    }

}
