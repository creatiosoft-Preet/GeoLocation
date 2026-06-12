#import "LocationHelper.h"
#import <CoreLocation/CoreLocation.h>
#import "cocos2d.h"
#include "scripting/js-bindings/jswrapper/SeApi.h"

static CLLocationManager *_locationManager = nil;
static LocationHelper *_delegate = nil;
static BOOL _alertShowing = NO;
static UIAlertController *_permissionAlert = nil;
static id _becomeActiveObserver = nil;
static BOOL _continuousMode = NO;

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

+ (void)requestPermission {
    if (![CLLocationManager locationServicesEnabled]) {
        [LocationHelper showLocationServicesAlert];
        return;
    }

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];

    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [LocationHelper notifyPermission:YES];
    } else if (status == kCLAuthorizationStatusDenied ||
               status == kCLAuthorizationStatusRestricted) {
        [LocationHelper showPermissionDeniedAlert];
    } else {
        // NotDetermined: create the manager now and request — delegate handles the response
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
                            CLAuthorizationStatus s = [CLLocationManager authorizationStatus];
                            if (s == kCLAuthorizationStatusDenied || s == kCLAuthorizationStatusRestricted) {
                                [LocationHelper showPermissionDeniedAlert];
                            }
                        });
                    }];
                NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            }]];

        _permissionAlert = alert;
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        [root presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)getLocation {
    if (![CLLocationManager locationServicesEnabled]) {
        [LocationHelper showLocationServicesAlert];
        return;
    }

    CLAuthorizationStatus status = [CLLocationManager authorizationStatus];
    if (status != kCLAuthorizationStatusAuthorizedWhenInUse &&
        status != kCLAuthorizationStatusAuthorizedAlways) {
        [LocationHelper evalJS:@"window.onLocationError('Permission not granted')"];
        return;
    }

    CLLocation *last = [LocationHelper sharedManager].location;
    if (last) {
        [LocationHelper reverseGeocode:last];
    } else {
        [[LocationHelper sharedManager] startUpdatingLocation];
    }
}

+ (void)startContinuousUpdates {
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
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        [root presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)stopContinuousUpdates {
    _continuousMode = NO;
    [_locationManager stopUpdatingLocation];
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

        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        [root presentViewController:alert animated:YES completion:nil];
    });
}

+ (void)notifyPermission:(BOOL)granted {
    NSString *js = granted ? @"window.onLocationPermission(true)" : @"window.onLocationPermission(false)";
    [LocationHelper evalJS:js];
}

+ (void)reverseGeocode:(CLLocation *)location {
    // Try CLGeocoder first
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        NSString *city = @"", *state = @"", *country = @"", *postcode = @"";

        if (!error && placemarks.count > 0) {
            CLPlacemark *place = placemarks[0];
            city     = place.locality          ?: @"";
            state    = place.administrativeArea ?: @"";
            country  = place.country            ?: @"";
            postcode = place.postalCode          ?: @"";
            [LocationHelper sendLocation:location city:city state:state country:country postcode:postcode];
        } else {
            // Fallback: Nominatim API
            [LocationHelper nominatimFallback:location];
        }
    }];
}

+ (void)nominatimFallback:(CLLocation *)location {
    NSString *urlStr = [NSString stringWithFormat:
        @"https://nominatim.openstreetmap.org/reverse?format=json&lat=%f&lon=%f&zoom=18&addressdetails=1",
        location.coordinate.latitude, location.coordinate.longitude];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlStr]];
    [request setValue:@"GeoLocationApp/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setTimeoutInterval:5.0];

    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *city = @"", *state = @"", *country = @"", *postcode = @"";
        if (data && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSDictionary *address = json[@"address"];
            if (address) {
                city     = address[@"city"]     ?: address[@"town"] ?: address[@"village"] ?: address[@"county"] ?: @"";
                state    = address[@"state"]    ?: @"";
                country  = address[@"country"]  ?: @"";
                postcode = address[@"postcode"] ?: @"";
            }
        }
        [LocationHelper sendLocation:location city:city state:state country:country postcode:postcode];
    }] resume];
}

+ (void)sendLocation:(CLLocation *)location
                city:(NSString *)city
               state:(NSString *)state
             country:(NSString *)country
            postcode:(NSString *)postcode {
    BOOL isMock = NO;
    NSString *js = [NSString stringWithFormat:
        @"window.onLocation({\"latitude\":%f,\"longitude\":%f,\"city\":\"%@\",\"state\":\"%@\",\"country\":\"%@\",\"postcode\":\"%@\",\"isMock\":%@})",
        location.coordinate.latitude,
        location.coordinate.longitude,
        [self escape:city],
        [self escape:state],
        [self escape:country],
        [self escape:postcode],
        isMock ? @"true" : @"false"];
    [LocationHelper evalJS:js];
}

+ (void)evalJS:(NSString *)js {
    std::string jsStr = std::string([js UTF8String]);
    dispatch_async(dispatch_get_main_queue(), ^{
        se::ScriptEngine::getInstance()->evalString(jsStr.c_str());
    });
}

+ (NSString *)escape:(NSString *)s {
    s = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    s = [s stringByReplacingOccurrencesOfString:@"'" withString:@"\\'"];
    return s;
}

// CLLocationManagerDelegate
- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    CLLocation *location = locations.lastObject;
    if (_continuousMode) {
        NSString *js = [NSString stringWithFormat:@"window.onLocationTick(%f,%f)",
            location.coordinate.latitude, location.coordinate.longitude];
        [LocationHelper evalJS:js];
    } else {
        [manager stopUpdatingLocation];
        [LocationHelper reverseGeocode:location];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [LocationHelper evalJS:[NSString stringWithFormat:@"window.onLocationError('%@')", error.localizedDescription]];
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorizedAlways) {
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
