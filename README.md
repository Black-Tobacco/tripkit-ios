# SkedGo's TripKit for iOS

Some documentation can be found in the [Wiki](https://github.com/skedgo/tripkit-ios/wiki)

## Set-up

### Dependencies

TripKit has several required dependencies:

* Frameworks:
  * CoreData
  * CoreLocation
  * MapKit
* Selected modules from [SkedGo's shared iOS code base](https://github.com/skedgo/shared-ios)
  * RootKit
  * ServerKit
  * TransportKit
* Add RootKit's `Config.plist.default` as `Config.plist` to your project and include it in your targets.
  * TODO: what to add
* Precompiled header macros:
``` objective-c
#pragma mark -
#pragma mark Useful macro methods

#define TG_ASSERT_MAIN_THREAD ZAssert([NSThread isMainThread], @"This method must be called on the main thread")

// thanks to https://gist.github.com/1057420
#define DEFINE_SHARED_INSTANCE_USING_BLOCK(block) \
  static dispatch_once_t pred = 0; \
  __strong static id _sharedObject = nil; \
  dispatch_once(&pred, ^{ \
  _sharedObject = block(); \
  }); \
  return _sharedObject; \

// Debugging log and assertion functions
#ifdef DEBUG
  #define DLog(...) NSLog(@"%s %@", __PRETTY_FUNCTION__, [NSString stringWithFormat:__VA_ARGS__])
  #define ALog(...) [[NSAssertionHandler currentHandler] handleFailureInFunction:[NSString stringWithCString:__PRETTY_FUNCTION__ encoding:NSUTF8StringEncoding] file:[NSString stringWithCString:__FILE__ encoding:NSUTF8StringEncoding] lineNumber:__LINE__ description:__VA_ARGS__]
#else // DEBUG
  #define DLog(...) do {} while (0)
  #define ALog(...) do {} while (0)
  #ifndef NS_BLOCK_ASSERTIONS
    #define NS_BLOCK_ASSERTIONS
  #endif // end NS_BLOCK_ASSERTIONS
#endif // end else DEBUG
#define ZAssert(condition, ...) do { if (!(condition)) { ALog(__VA_ARGS__); }} while (0)
```

### In your code

* Refresh the cached information at an appropriate time, e.g., when your app finished launching or comes back to the foreground:

```  objective-c
  [[SVKServer sharedInstance] updateRegionsForced:NO];
```



## Optional dependencies

### Logging

* CocoaPods:
``` ruby
  pod 'CocoaLumberjack'
```

TODO: How to use this

### Booking features

* CocoaPods:
``` ruby
  pod 'AFNetworking', '~> 2.5.3'
  pod 'CocoaLumberjack'
```
* Modules from [SkedGo's shared iOS code base](https://github.com/skedgo/shared-ios)
  * BookingKit

TODO: How to use this

## Tracking

Calls to the SkedGo servers typically include an "X-TripGo-UUID" header which allows tracking calls from a single installation across sessions. This behaviour is **opt-out**. Opt-out by adding a Boolean with key `SVKDefaultsKeyProfileTrackUsage` and value `true` to the standard user defaults.
