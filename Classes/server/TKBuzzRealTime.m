//
//  BHBuzzRealTime.m
//  TripPlanner
//
//  Created by Adrian Schoenig on 2/11/12.
//
//

#import "TKBuzzRealTime.h"

#import "TKTripKit.h"

@interface TKBuzzRealTime ()

@property (nonatomic, strong) TKBuzzRouter *helperRouter;

@end

@implementation TKBuzzRealTime

- (void)cancelRequests
{
  // TODO: implement
//	SGServer *server = [SGServer sharedInstance];
//	[server.client cancelAllHTTPOperationsWithMethod:@"POST" path:@"latest.json"];
}

- (void)updateTrip:(Trip *)trip
					 success:(void (^)(Trip *trip))success
					 failure:(void (^)(NSError *error))failure
{
	if (trip == nil) {
		ZAssert(false, @"Don't call this without a trip");
		return;
	}

  if (trip.request == nil) {
    DLog(@"Not updating trip as it doesn't have a request (anymore): %@", trip);
    return;
  }
  
  [self.helperRouter updateTrip:trip
                     completion:
   ^(Trip *updatedTrip) {
     if (updatedTrip == trip) {
       success(trip);
     } else {
       failure(nil);
     }
   }];
}

- (void)updateDLSEntries:(NSSet *)entries
                inRegion:(SVKRegion *)region
                 success:(void (^)(NSSet *entries))success
                 failure:(void (^)(NSError *error))failure
{
  NSMutableArray *servicesParamsArray     = [NSMutableArray arrayWithCapacity:entries.count];
  NSMutableDictionary *objectsLookup = [NSMutableDictionary dictionaryWithCapacity:entries.count];
  for (DLSEntry *entry in entries) {
    Service *service = entry.service;
    NSString *operatorName = service.operatorName ?: @"";
    [servicesParamsArray addObject:@{
                                     @"serviceTripID" : service.code,
                                     @"operator"      : operatorName,
                                     @"startStopCode" : entry.stop.stopCode,
                                     @"endStopCode" : entry.endStop.stopCode,
                                     }];
    [objectsLookup setValue:entry forKey:service.code];
  }
  
  __weak typeof(self) weakSelf = self;
  [self fetchUpdatesForServiceParas:servicesParamsArray
                          forRegion:region
                            success:
   ^(id responseObject) {
     typeof(weakSelf) strongSelf = weakSelf;
     if (strongSelf) {
       [strongSelf updateObjects:objectsLookup
              withResponseObject:responseObject];
       success(entries);
     }
   }
                            failure:failure];}

- (void)updateEmbarkations:(NSSet *)embarkations
                  inRegion:(SVKRegion *)region
                   success:(void (^)(NSSet *embarkations))success
                   failure:(void (^)(NSError *error))failure
{
  NSMutableArray *servicesParamsArray     = [NSMutableArray arrayWithCapacity:embarkations.count];
  NSMutableDictionary *objectsLookup = [NSMutableDictionary dictionaryWithCapacity:embarkations.count];
  for (StopVisits *visit in embarkations) {
    Service *service = visit.service;
    NSString *operatorName = service.operatorName ?: @"";
    [servicesParamsArray addObject:@{
                                     @"serviceTripID" : service.code,
                                     @"operator"      : operatorName,
                                     @"startStopCode" : visit.stop.stopCode
                                     }];
    [objectsLookup setValue:visit forKey:service.code];
  }
  
  __weak typeof(self) weakSelf = self;
  [self fetchUpdatesForServiceParas:servicesParamsArray
                          forRegion:region
                            success:
   ^(id responseObject) {
     typeof(weakSelf) strongSelf = weakSelf;
     if (strongSelf) {
       [strongSelf updateObjects:objectsLookup
              withResponseObject:responseObject];
       success(embarkations);
     }
   }
                            failure:failure];
}

- (void)updateServices:(NSSet *)services
              inRegion:(SVKRegion *)region
               success:(void (^)(NSSet *services))success
               failure:(void (^)(NSError *error))failure
{
  NSMutableArray *servicesParamsArray     = [NSMutableArray arrayWithCapacity:services.count];
  NSMutableDictionary *servicesLookupDict = [NSMutableDictionary dictionaryWithCapacity:services.count];
  for (Service *service in services) {
    NSString *operatorName = service.operatorName ?: @"";
    [servicesParamsArray addObject:@{
                                     @"serviceTripID" : service.code,
                                     @"operator"      : operatorName
                                     }];
    [servicesLookupDict setValue:service forKey:service.code];
  }
  
  __weak typeof(self) weakSelf = self;
  [self fetchUpdatesForServiceParas:servicesParamsArray
                          forRegion:region
                            success:
   ^(id responseObject) {
     typeof(weakSelf) strongSelf = weakSelf;
     if (strongSelf) {
       [strongSelf updateObjects:servicesLookupDict
              withResponseObject:responseObject];
       success(services);
     }
   }
                            failure:failure];
}

- (void)fetchUpdatesForServiceParas:(NSArray *)serviceParas
                          forRegion:(SVKRegion *)region
                            success:(void (^)(id responseObject))success
                            failure:(void (^)(NSError *error))failure
{
  if (!region) {
    failure(nil);
    return;
  }
	if (! region.name) {
		ZAssert(false, @"Bad region with no name: %@", region);
		failure([NSError errorWithCode:kSVKErrorTypeInternal message:@"Region has no name."]);
		return;
	}
	
	// construct the parameters
	NSDictionary *paras = @{
		@"region"   : region.name,
		@"block"    : @(NO),
		@"services" : serviceParas,
	};
	
	// now send it off to the server
	SVKServer *server = [SVKServer sharedInstance];
  [server initiateDataTaskWithMethod:@"POST"
                                path:@"latest.json"
                          parameters:paras
                              region:region
                             success:
   ^(NSURLSessionDataTask *task, id responseObject) {
#pragma unused(task)
     success(responseObject);
   }
                             failure:
   ^(NSURLSessionDataTask *task, NSError *error) {
#pragma unused(task)
     DLog(@"Error response: %@", task.response);
     failure(error);
   }];
}

#pragma mark - Private helpers

- (void)updateObjects:(NSDictionary *)serviceIDToObjectDict
   withResponseObject:(id)responseObject
{
	ZAssert(serviceIDToObjectDict, @"Method requires map");
	
	NSArray *servicesArray = responseObject[@"services"];
	if (servicesArray.count == 0) {
		DLog(@"Received no results.");
		return;
	}
	
	for (NSDictionary *serviceDict in servicesArray) {
		NSString *serviceID = serviceDict[@"serviceTripID"];
		id object           = serviceIDToObjectDict[serviceID];

    DLSEntry *dls;
    StopVisits *visit;
    Service *service;
    if ([object isKindOfClass:[DLSEntry class]]) {
      dls = object;
      service = dls.service;
    } else if ([object isKindOfClass:[StopVisits class]]) {
      visit = object;
      service = visit.service;
    } else if ([object isKindOfClass:[Service class]]) {
      service = object;
    }
    
    
		if (! service) {
			DLog(@"No matching service for code: %@", serviceID);
			continue;
		}
		
		if (! service.managedObjectContext) {
			DLog(@"Service has no context: %@", service);
			continue;
		}
		
		// Parse the vehicle
		NSDictionary *vehicleDict = serviceDict[@"realtimeVehicle"];
		if (vehicleDict) {
			// which vehicle to update?
			Vehicle *vehicle = service.vehicle;
			
			if (! vehicle) {
				// create a new one
				vehicle = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Vehicle class])
																								inManagedObjectContext:service.managedObjectContext];
				vehicle.service = service;
			}
			
			// set the vehicle properties
			vehicle.label = vehicleDict[@"label"];
			vehicle.lastUpdate = [NSDate dateWithTimeIntervalSince1970:[vehicleDict[@"lastUpdate"] integerValue]];
			NSDictionary *locationDict = vehicleDict[@"location"];
			vehicle.latitude = locationDict[@"lat"];
			vehicle.longitude = locationDict[@"lng"];
			vehicle.bearing = locationDict[@"bearing"];
		}
				
		if (dls || visit) {
			// we have supplied a start stop code, so we only want to update that
			
			NSNumber *startTime = serviceDict[@"startTime"];
			if (! startTime)
				continue;
			if (startTime.integerValue <= 0) {
				ZAssert(false, @"Bad start time '%@' in response object:\n%@", startTime, responseObject);
				continue;
			}
			NSDate *departure = [NSDate dateWithTimeIntervalSince1970:startTime.integerValue];
			
      if (visit) {
        // we use 'time' to allow KVO
        visit.time = departure;
        service.realTime = YES;

      } else if (dls) {
        dls.departure = departure;
        NSNumber *endTime = serviceDict[@"endTime"];
        if (! endTime)
          continue;
        if (endTime.integerValue <= 0) {
          ZAssert(false, @"Bad start time '%@' in response object:\n%@", endTime, responseObject);
          continue;
        }
        dls.arrival = [NSDate dateWithTimeIntervalSince1970:endTime.integerValue];
        service.realTime = YES;
      }
			
		} else {
			// we want to update all the stops in the service
			
			// first turn it into look-up dictionaries
			NSArray *stops                  = serviceDict[@"stops"];
			if (! stops)
				continue;
      service.realTime = YES;

      NSMutableDictionary *arrivals   = [NSMutableDictionary dictionaryWithCapacity:stops.count];
			NSMutableDictionary *departures = [NSMutableDictionary dictionaryWithCapacity:stops.count];
			for (NSDictionary *stopDict in stops) {
				NSString *code = stopDict[@"stopCode"];
				NSNumber *time = stopDict[@"arrival"];
				if (time) {
          arrivals[code] = [NSDate dateWithTimeIntervalSince1970:time.integerValue];
				}
				time = stopDict[@"departure"];
				if (time) {
          departures[code] = [NSDate dateWithTimeIntervalSince1970:time.integerValue];
				}
			}
			
			// next update all the stops
			NSTimeInterval delay = 0;
			for (StopVisits *aVisit in service.sortedVisits) {
				NSString *visitCode = aVisit.stop.stopCode;
				NSDate *newArrival = arrivals[visitCode];
				if (newArrival) {
          if (aVisit.arrival) delay = [newArrival timeIntervalSinceDate:aVisit.arrival];
					aVisit.arrival = newArrival;
				}
				NSDate *newDeparture = departures[visitCode];
				if (newDeparture) {
          if (aVisit.departure) delay = [newDeparture timeIntervalSinceDate:aVisit.departure];
					// use time for KVO
					aVisit.time = newDeparture;
				}
				if (! newArrival && aVisit.arrival && fabs(delay) < 1) {
					aVisit.arrival = [aVisit.arrival dateByAddingTimeInterval:delay];
				}
				if (! newDeparture && aVisit.departure && fabs(delay) < 1) {
					// use time for KVO
					aVisit.time = [aVisit.departure dateByAddingTimeInterval:delay];
				}
			}
		}
	}
}

#pragma mark - Lazy accessors

- (TKBuzzRouter *)helperRouter
{
  if (!_helperRouter) {
    _helperRouter = [[TKBuzzRouter alloc] init];
  }
  return _helperRouter;
}

@end