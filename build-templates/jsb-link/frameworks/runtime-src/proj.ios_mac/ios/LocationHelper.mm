#import "LocationHelper.h"
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import "cocos2d.h"
#include "scripting/js-bindings/jswrapper/SeApi.h"

// Written for iOS 15.6+ (txpoker's deployment target): uses the iOS 14 instance
// authorizationStatus / accuracyAuthorization and iOS 15 sourceInformation.

// A cached fix older than this is not reused; a fresh one is requested instead.
static const NSTimeInterval kMaxCachedAge = 60.0;

static CLLocationManager *_locationManager = nil;
static LocationHelper *_delegate = nil;
static BOOL _alertShowing = NO;
static UIAlertController *_permissionAlert = nil;
static id _becomeActiveObserver = nil;
static BOOL _continuousMode = NO;
static BOOL _pendingSingleFix = NO;

@implementation LocationHelper

+ (CLLocationManager *)sharedManager {
    if (!_locationManager) {
        _delegate = [LocationHelper new];
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = _delegate;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    }
    return _locationManager;
}

+ (void)requestPermission:(NSString *)ignored       { [LocationHelper requestPermission]; }
+ (void)getLocation:(NSString *)ignored             { [LocationHelper getLocation]; }
+ (void)startContinuousUpdates:(NSString *)ignored  { [LocationHelper startContinuousUpdates]; }
+ (void)stopContinuousUpdates:(NSString *)ignored   { [LocationHelper stopContinuousUpdates]; }

+ (BOOL)isAuthorized:(CLAuthorizationStatus)status {
    return status == kCLAuthorizationStatusAuthorizedWhenInUse ||
           status == kCLAuthorizationStatusAuthorizedAlways;
}

+ (BOOL)isPrecise {
    return [LocationHelper sharedManager].accuracyAuthorization == CLAccuracyAuthorizationFullAccuracy;
}

// keyWindow is deprecated since iOS 13; find the key window of the active scene instead.
+ (UIViewController *)topViewController {
    UIWindow *window = nil;
    UIWindow *fallback = nil;
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (!fallback) fallback = w;
            if (w.isKeyWindow) { window = w; break; }
        }
        if (window) break;
    }
    if (!window) window = fallback;
    UIViewController *vc = window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

+ (void)requestPermission {
    if (![CLLocationManager locationServicesEnabled]) {
        [LocationHelper showLocationServicesAlert];
        return;
    }

    CLAuthorizationStatus status = [LocationHelper sharedManager].authorizationStatus;

    if ([LocationHelper isAuthorized:status]) {
        [LocationHelper notifyPermission:YES];
    } else if (status == kCLAuthorizationStatusDenied ||
               status == kCLAuthorizationStatusRestricted) {
        [LocationHelper showPermissionDeniedAlert];
    } else {
        // NotDetermined: the delegate receives the user's answer
        [[LocationHelper sharedManager] requestWhenInUseAuthorization];
    }
}

+ (void)showPermissionDeniedAlert {
    if (_alertShowing) return;
    _alertShowing = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Location Permission Required"
            message:@"Please go to Settings and enable location access for this app."
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction
            actionWithTitle:@"Open Settings"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                _alertShowing = NO;
                [LocationHelper sharedManager]; // delegate set karo taaki return par status change fire ho
                // Observer: agar user bina enable kiye wapas aaye to alert dobara dikhao
                _becomeActiveObserver = [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:_becomeActiveObserver];
                        _becomeActiveObserver = nil;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                            dispatch_get_main_queue(), ^{
                            CLAuthorizationStatus s = [LocationHelper sharedManager].authorizationStatus;
                            if (s == kCLAuthorizationStatusDenied || s == kCLAuthorizationStatusRestricted) {
                                [LocationHelper showPermissionDeniedAlert];
                            }
                        });
                    }];
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }]];

        _permissionAlert = alert;
        [[LocationHelper topViewController] presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)getLocation {
    if (![CLLocationManager locationServicesEnabled]) {
        [LocationHelper showLocationServicesAlert];
        return;
    }

    CLLocationManager *mgr = [LocationHelper sharedManager];
    if (![LocationHelper isAuthorized:mgr.authorizationStatus]) {
        [LocationHelper sendError:@"Permission not granted"];
        return;
    }

    CLLocation *last = mgr.location;
    if (last && -[last.timestamp timeIntervalSinceNow] < kMaxCachedAge) {
        [LocationHelper reverseGeocode:last];
        return;
    }
    // The next update from the delegate is used for this request.
    _pendingSingleFix = YES;
    [mgr startUpdatingLocation];
}

+ (void)startContinuousUpdates {
    if (_continuousMode) return; // already running
    _continuousMode = YES;
    CLLocationManager *mgr = [LocationHelper sharedManager];
    mgr.distanceFilter = 1.0;
    mgr.desiredAccuracy = kCLLocationAccuracyBest;
    [mgr startUpdatingLocation];
}

+ (void)showAlert:(NSString *)params {
    NSArray *parts = [params componentsSeparatedByString:@"|"];
    NSString *title   = parts.count > 0 ? parts[0] : @"Alert";
    NSString *message = parts.count > 1 ? parts[1] : @"";
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:title
            message:message
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
            style:UIAlertActionStyleDefault handler:nil]];
        [[LocationHelper topViewController] presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)stopContinuousUpdates {
    _continuousMode = NO;
    // Keep updating if a single fix is still pending; the delegate stops it afterwards.
    if (!_pendingSingleFix) [_locationManager stopUpdatingLocation];
}

+ (void)showLocationServicesAlert {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"Location Services Disabled"
            message:@"Your device's Location is turned off.\n\nTo enable it:\nPhone Settings → Privacy & Security → Location Services → Turn ON"
            preferredStyle:UIAlertControllerStyleAlert];

        [alert addAction:[UIAlertAction
            actionWithTitle:@"Open Settings"
            style:UIAlertActionStyleDefault
            handler:^(UIAlertAction *a) {
                __block id observer = [[NSNotificationCenter defaultCenter]
                    addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
                        [[NSNotificationCenter defaultCenter] removeObserver:observer];
                        observer = nil;
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                            dispatch_get_main_queue(), ^{
                            if ([CLLocationManager locationServicesEnabled]) {
                                [LocationHelper requestPermission];
                            } else {
                                [LocationHelper showLocationServicesAlert];
                            }
                        });
                    }];
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }]];

        [[LocationHelper topViewController] presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)notifyPermission:(BOOL)granted {
    BOOL precise = granted && [LocationHelper isPrecise];
    [LocationHelper evalJS:[NSString stringWithFormat:@"window.onLocationPermission(%@,%@)",
        granted ? @"true" : @"false", precise ? @"true" : @"false"]];
}

// City comes from CLGeocoder only. If it fails the fields stay empty and the
// backend should geocode from latitude/longitude.
+ (void)reverseGeocode:(CLLocation *)location {
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        CLPlacemark *place = (!error && placemarks.count > 0) ? placemarks[0] : nil;
        [LocationHelper sendLocation:location placemark:place];
    }];
}

+ (void)sendLocation:(CLLocation *)location placemark:(CLPlacemark *)place {
    // Catches Xcode / GPX simulation. Apple says third-party spoofing tools may not set it,
    // so the backend must not rely on this flag alone.
    BOOL isMock = location.sourceInformation.isSimulatedBySoftware;

    NSDictionary *data = @{
        @"latitude":    @(location.coordinate.latitude),
        @"longitude":   @(location.coordinate.longitude),
        @"accuracy":    @(location.horizontalAccuracy),
        @"timestamp":   @((long long)([location.timestamp timeIntervalSince1970] * 1000)),
        @"isPrecise":   @([LocationHelper isPrecise]),
        @"isMock":      @(isMock),
        @"city":        place.locality           ?: @"",
        @"state":       place.administrativeArea ?: @"",
        @"country":     place.country            ?: @"",
        @"countryCode": place.ISOcountryCode     ?: @"",
        @"postcode":    place.postalCode         ?: @"",
        @"platform":    @"ios",
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:data options:0 error:nil];
    if (!jsonData) {
        [LocationHelper sendError:@"Failed to build location"];
        return;
    }
    NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [LocationHelper evalJS:[NSString stringWithFormat:@"window.onLocation(%@)", json]];
}

+ (void)sendError:(NSString *)msg {
    // Encode as a JSON string so quotes in the message cannot break the JS call.
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:@[msg ?: @""] options:0 error:nil];
    NSString *arr = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [LocationHelper evalJS:[NSString stringWithFormat:@"window.onLocationError(%@[0])", arr]];
}

+ (void)evalJS:(NSString *)js {
    std::string jsStr = std::string([js UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        se::ScriptEngine::getInstance()->evalString(jsStr.c_str());
    });
}

// CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = locations.lastObject;
    if (_pendingSingleFix) {
        _pendingSingleFix = NO;
        [LocationHelper reverseGeocode:location];
    }
    if (_continuousMode) {
        NSString *js = [NSString stringWithFormat:@"window.onLocationTick(%f,%f,%f)",
            location.coordinate.latitude, location.coordinate.longitude, location.horizontalAccuracy];
        [LocationHelper evalJS:js];
    } else {
        [manager stopUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    // kCLErrorLocationUnknown is temporary; Core Location keeps trying.
    if (error.code == kCLErrorLocationUnknown) return;
    _pendingSingleFix = NO;
    [LocationHelper sendError:error.localizedDescription];
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus status = manager.authorizationStatus;
    if ([LocationHelper isAuthorized:status]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_permissionAlert) {
                [_permissionAlert dismissViewControllerAnimated:YES completion:nil];
                _permissionAlert = nil;
                _alertShowing = NO;
            }
        });
        [LocationHelper notifyPermission:YES];
    } else if (status == kCLAuthorizationStatusDenied ||
               status == kCLAuthorizationStatusRestricted) {
        [LocationHelper showPermissionDeniedAlert];
    }
}

@end
