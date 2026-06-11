#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface LocationHelper : NSObject <CLLocationManagerDelegate>

+ (void)requestPermission;
+ (void)requestPermission:(NSString *)ignored;
+ (void)getLocation;
+ (void)getLocation:(NSString *)ignored;

@end
