//
//  Alert.h
//  TripPlanner
//
//  Created by Adrian Schoenig on 19/03/13.
//
//

@import CoreData;
@import SGCoreKit;

@class Service, StopLocation, SGNamedCoordinate;

typedef NS_ENUM(NSInteger, AlertSeverity) {
  AlertSeverityInfo = -1,
  AlertSeverityWarning = 0,
  AlertSeverityAlert = 1,
};

NS_ASSUME_NONNULL_BEGIN

@interface Alert : NSManagedObject <STKDisplayablePoint>

@property (nonatomic, retain, nullable) SGNamedCoordinate *location;
@property (nonatomic, retain) NSNumber * hashCode;
@property (nonatomic, copy) NSString * title;
@property (nonatomic, retain, nullable) NSString * text;
@property (nonatomic, retain, nullable) NSString * url;
@property (nonatomic, retain, nullable) NSString * remoteIcon;
@property (nonatomic, retain) NSNumber * severity; // Don't access this, use alertSeverity instead
@property (nonatomic, retain, nullable) NSDate * startTime;
@property (nonatomic, retain, nullable) NSDate * endTime;
@property (nonatomic, assign) BOOL toDelete;

@property (nonatomic, retain, nullable) NSString *idService;
@property (nonatomic, retain, nullable) NSString *idStopCode;

// Non core-data properties
@property (nonatomic, assign) AlertSeverity alertSeverity;
@property (nonatomic, readonly, nullable) NSURL *imageURL;

+ (instancetype)fetchAlertWithHashCode:(NSNumber *)hashCode
                      inTripKitContext:(NSManagedObjectContext *)tripKitContext;

+ (NSArray *)fetchAlertsWithHashCodes:(NSArray *)hashCodes
                     inTripKitContext:(NSManagedObjectContext *)tripKitContext
                 sortedByDistanceFrom:(CLLocationCoordinate2D)coordinate;

+ (NSArray *)fetchAlertsForService:(Service *)service;

+ (NSArray *)fetchAlertsForStopLocation:(StopLocation *)stopLocation;

- (STKInfoIconType)infoIconType;

- (void)remove;

@end

NS_ASSUME_NONNULL_END
