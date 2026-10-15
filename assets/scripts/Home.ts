const { ccclass, property } = cc._decorator;

import { IGeoLocation } from "./location/IGeoLocation";
import { LocationEvent } from "./location/LocationEvent";
import GeofenceManager, { IZone } from "./location/GeofenceManager";
import LocationManager from "./location/LocationManager";
import LocationPermission from "./location/LocationPermission";
import LocationApi from "./location/LocationApi";

@ccclass
export default class Home extends cc.Component {

    @property(cc.Node) popup: cc.Node | null = null;
    @property(cc.Label) latLabel: cc.Label | null = null;
    @property(cc.Label) lngLabel: cc.Label | null = null;
    @property(cc.Label) locationLabel: cc.Label | null = null;

    // Set to false to hide the on-screen test panel.
    private static readonly SHOW_DEBUG = true;
    private _debugLabel: cc.Label | null = null;
    private _lastError = "-";
    private _lastMock = "-";
    private _events: string[] = [];

    private _createDebugPanel() {
        const node = new cc.Node("DebugPanel");
        node.color = cc.Color.YELLOW;
        const label = node.addComponent(cc.Label);
        label.fontSize = 22;
        label.lineHeight = 28;
        label.horizontalAlign = cc.Label.HorizontalAlign.LEFT;
        label.overflow = cc.Label.Overflow.NONE;
        node.anchorX = 0;
        node.anchorY = 1;
        this.node.addChild(node, 9999);
        const size = cc.view.getVisibleSize();
        node.setPosition(-size.width / 2 + 10, size.height / 2 - 40);
        this._debugLabel = label;
    }

    private _log(msg: string) {
        this._events.unshift(msg);
        if (this._events.length > 5) this._events.pop();
    }

    update() {
        if (!this._debugLabel) return;
        const geo = GeofenceManager.instance;
        const zones = Object.keys(geo.debugLines).map(k => geo.debugLines[k]).join("\n");
        const age = geo.lastCheckTime ? ((Date.now() - geo.lastCheckTime) / 1000).toFixed(0) + "s ago" : "never";
        this._debugLabel.string =
            `[DEBUG] checks: ${geo.checkCount}  last: ${age}\n` +
            (zones || "no zone check yet") + "\n" +
            `mock: ${this._lastMock}\n` +
            `error: ${this._lastError}\n` +
            `events:\n` + this._events.join("\n");
    }

    start() {
        if (this.popup) this.popup.active = false;
        if (Home.SHOW_DEBUG) this._createDebugPanel();

        LocationManager.instance.init();
        LocationApi.fetchZones();

        cc.systemEvent.on(LocationEvent.LOCATION_UPDATE, this._onLocationUpdate, this);
        cc.systemEvent.on(LocationEvent.LOCATION_ERROR, this._onLocationError, this);
        cc.systemEvent.on(LocationEvent.LOCATION_PERMISSION_DENIED, this._onPermissionDenied, this);
        cc.systemEvent.on(LocationEvent.ZONE_ENTERED, this._onZoneEntered, this);
        cc.systemEvent.on(LocationEvent.ZONE_EXITED, this._onZoneExited, this);

        LocationPermission.request();
    }

    private _onLocationUpdate(data: IGeoLocation) {
        cc.log("Location : ", JSON.stringify(data));

        // Fill the labels first so a problem further down cannot leave them empty.
        if (this.popup) this.popup.active = true;

        if (this.latLabel) this.latLabel.string = "Lat : " + Number(data.latitude).toFixed(6);

        if (this.lngLabel) this.lngLabel.string = "Lng : " + Number(data.longitude).toFixed(6);

        if (this.locationLabel) {
            this.locationLabel.string = `City: ${data.city || "-"}, State: ${data.state || "-"}, Country: ${data.country || "-"}`;
        }

        // An older native build does not send accuracy; treat it as unknown.
        const accuracy = typeof data.accuracy === "number" ? data.accuracy : -1;
        this._lastMock = `${data.isMock}  precise: ${data.isPrecise}  acc: ${accuracy >= 0 ? accuracy.toFixed(0) + " m" : "unknown"}`;
        this._log("location update");

        // Send before checkZones: zone events raised there reuse this fix's fields.
        LocationApi.sendLocation(data);

        // App open / fresh fix: check immediately whether we're in the safe zone
        GeofenceManager.instance.checkZones(data.latitude, data.longitude, accuracy);
    }

    private _onLocationError(error: string) {
        cc.error("Location Error : ", error);
        this._lastError = error;
        this._log("ERROR: " + error);
    }

    private _onPermissionDenied() {
        cc.warn("Location Permission Denied");
        this._log("permission DENIED");
    }

    private _onZoneEntered(_zone: IZone) {
        this._log("ZONE_ENTERED");
        const geo = GeofenceManager.instance;
        LocationApi.sendZoneEvent("ENTERED", geo.lastLat, geo.lastLng);
        GeofenceManager.showNativeAlert(
            "Safe Zone",
            `You are in the safe zone.`
        );
    }

    private _onZoneExited(_zone: IZone) {
        this._log("ZONE_EXITED");
        const geo = GeofenceManager.instance;
        LocationApi.sendZoneEvent("EXITED", geo.lastLat, geo.lastLng);
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
