//
//  BHBuzzInfoProvider.m
//  TripPlanner
//
//  Created by Adrian Schoenig on 29/11/12.
//
//

#import "TKBuzzInfoProvider.h"

#import "TKTripKit.h"

typedef enum {
	SGDeparturesResultAddedStops      = 1 << 0,
  SGDeparturesResultAddedDepartures = 1 << 1
} SGDepartures;


@implementation TKBuzzInfoProvider

- (void)downloadDeparturesForStop:(StopLocation *)stop
												 fromDate:(NSDate *)date
														limit:(NSInteger)limit
											 completion:(SGDeparturesStopSuccessBlock)completion
													failure:(void(^)(NSError *error))failure
{
  NSParameterAssert(stop);
  NSParameterAssert(date);
  NSParameterAssert(completion);
  
	// construct the parameters
  if (! stop.stopCode) {
    // this can happen if the stop got deleted while we were looking at it.
    if (failure) {
      failure([NSError errorWithCode:kSGInfoProviderErrorStopWithoutCode
                             message:@"Provided stop has no code or children."]);
    }
    return;
  }
  
	SVKServer *server = [SVKServer sharedInstance];
  [server requireRegions:^(NSError *error) {
    if (error) {
      if (failure) {
        failure(error);
      }
      return;
    }
    
    SVKRegion *region = stop.region;
    if (! region) {
      failure([NSError errorWithCode:kSVKErrorTypeInternal
                             message:@"Region not fetched yet."]);
      return;
    }
    
    NSArray *stops = @[stop.stopCode];
    
    NSDictionary *paras = @{
                            @"region"						: region.name,
                            @"timeStamp"			  : @((NSInteger) [date timeIntervalSince1970]),
                            @"embarkationStops" : stops,
                            @"limit" 						: @(limit),
                            @"config"           : [TKSettings defaultDictionary],
                            };
    
    
    __weak typeof(self) weakSelf = self;
    [server initiateDataTaskWithMethod:@"POST"
                                  path:@"departures.json"
                            parameters:paras
                                region:region
                               success:
     ^(NSURLSessionDataTask *task, id responseObject) {
#pragma unused(task)
       typeof(self) strongSelf = weakSelf;
       if( !strongSelf) {
         return;
       }
       
       [stop.managedObjectContext performBlock:^{
         NSNumber *rawFlags = [strongSelf addDeparturesToStop:stop
                                                 fromResponse:responseObject
                                           intoTripKitContext:stop.managedObjectContext];
         
         NSInteger flags = [rawFlags integerValue];
         if ((flags & SGDeparturesResultAddedDepartures) != 0) {
           // save it
           NSError *anError = nil;
           ZAssert([stop.managedObjectContext save:&anError], @"Could not save: %@", anError);
           
           if (anError) {
             failure(anError);
           } else if (completion) {
             completion((flags & SGDeparturesResultAddedStops) != 0);
           }
           
         } else {
           DLog(@"Nothing found: %@", task.response);
           if (failure) {
             NSError *anError = [NSError errorWithCode:kSGInfoProviderErrorNothingFound
                                               message:@"Nothing found"];
             failure(anError);
           }
         }
       }];
     }
                               failure:
     ^(NSURLSessionDataTask *task, NSError *anError) {
#pragma unused (task)
       if (failure) {
         failure(anError);
       }
     }];
  }];
}

+ (NSDictionary *)queryParametersForDLSTable:(TKDLSTable *)table
                                    fromDate:(NSDate *)date
                                       limit:(NSInteger)limit
{
  NSParameterAssert(table);
  NSParameterAssert(date);
  
  return @{
           @"region"             : table.region.name,
           @"timeStamp"          : @((NSInteger) [date timeIntervalSince1970]),
           @"embarkationStops"   : @[table.startStopCode],
           @"disembarkationStops": @[table.endStopCode],
           @"limit"              : @(limit),
           @"config"             : [TKSettings defaultDictionary],
           };
}

- (void)downloadDeparturesForDLSTable:(TKDLSTable *)table
                             fromDate:(NSDate *)date
                                limit:(NSInteger)limit
                           completion:(SGDeparturesDLSSuccessBlock)completion
                              failure:(void(^)(NSError *error))failure
{
  NSParameterAssert(table);
  NSParameterAssert(date);
  NSParameterAssert(completion);
  
	SVKServer *server = [SVKServer sharedInstance];
  [server requireRegions:^(NSError *error) {
    if (error) {
      if (failure) {
        failure(error);
      }
      return;
    }
    
    NSDictionary *paras = [[self class] queryParametersForDLSTable:table
                                                          fromDate:date
                                                             limit:limit];
    __weak typeof(self) weakSelf = self;
    // now send it off to the server
    [server initiateDataTaskWithMethod:@"POST"
                                  path:@"departures.json"
                            parameters:paras
                                region:table.region
                               success:
     ^(NSURLSessionDataTask *task, id responseObject) {
#pragma unused(task)
       typeof(self) strongSelf = weakSelf;
       if( !strongSelf) {
         return;
       }
       
       [table.tripKitContext performBlock:^{
         NSSet *identifiers = [strongSelf addDeparturesToStop:nil
                                                 fromResponse:responseObject
                                           intoTripKitContext:table.tripKitContext];
         
         // save it
         NSError *saveError = nil;
         ZAssert([table.tripKitContext save:&saveError], @"Could not save: %@", saveError);
         if (saveError) {
           failure(saveError);
         } else {
           completion(identifiers);
         }
       }];
     }
                               failure:
     ^(NSURLSessionDataTask *task, NSError *operationError) {
#pragma unused(task)
       if (failure) {
         failure(operationError);
       }
     }];
  }];
}

- (void)downloadContentOfService:(Service *)service
							forEmbarkationDate:(NSDate *)date
												inRegion:(SVKRegion *)regionOrNil
											completion:(SGServiceCompletionBlock)completion
{
  NSParameterAssert(service);
  NSParameterAssert(date);
  NSParameterAssert(completion);
  
  ZAssert(service.managedObjectContext, @"Service with a context needed.");
  
  if (service.isRequestingServiceData) {
    return; // don't send multiple requests
  }
  
  service.isRequestingServiceData = YES;
	SVKServer *server = [SVKServer sharedInstance];
  [server requireRegions:
   ^(NSError *error) {
     if (error) {
       DLog(@"Error fetching regions: %@", error);
       completion(service, NO);
       return;
     }
     
     SVKRegion *region = regionOrNil ?: service.region;
     if (! region) {
       completion(service, NO);
       return;
     }
     
     NSString *operatorName = service.operatorName ?: @"";
     
     // construct the parameters
     ZAssert(service && service.managedObjectContext, @"Service with a context needed.");
     NSDictionary *paras = @{
                             @"region"						: region.name,
                             @"serviceTripID"	    : service.code,
                             @"operator"	        : operatorName,
                             @"embarkationDate"	  : @([date timeIntervalSince1970]),
                             @"encode"						: @(YES)
                             };
     
     // now send it off to the server
     __weak typeof(self) weakSelf = self;
     [server initiateDataTaskWithMethod:@"GET"
                                   path:@"service.json"
                             parameters:paras
                                 region:region
                                success:
      ^(NSURLSessionDataTask *task, id responseObject) {
#pragma unused(task)
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) {
          return;
        }
        
        if (! responseObject[@"error"]) {
          ZAssert(service && service.managedObjectContext, @"Service with a context needed.");
          NSManagedObjectContext *temporaryContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
          temporaryContext.parentContext = service.managedObjectContext;
          [temporaryContext performBlock:^{
            Service *privateService = (Service *) [temporaryContext objectWithID:service.objectID];
            [strongSelf addContentToService:privateService
                               fromResponse:responseObject];
            NSError *saveError = nil;
            [temporaryContext save:&saveError];
            if (saveError) {
              DLog(@"Error saving temporary context: %@", saveError);
            } else {
              [service.managedObjectContext performBlock:^{
                completion(service, YES);
              }];
            }
          }];
          
        } else {
          [service.managedObjectContext performBlock:^{
            completion(service, NO);
          }];
        }
        service.isRequestingServiceData = NO;
      }
                                failure:
      ^(NSURLSessionDataTask *task, NSError *operationError) {
#pragma unused(task, operationError)
        DLog(@"Error response: %@. %@", task.response, operationError);
        [service.managedObjectContext performBlock:^{
          completion(service, NO);
        }];
        service.isRequestingServiceData = NO;
      }];
   }];
}

+ (NSError *)errorForUserForBrokenStop
{
  NSDictionary *info = @{
                         NSLocalizedDescriptionKey: NSLocalizedString(@"Could not find transit stop.", "Error title when server could not find a given transit stop."),
                         NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Search for this stop again or try again later..", "Error recovery suggestion for when when server could not find a given transit stop."),
                         };
  return [NSError errorWithDomain:@"com.buzzhives.TripKit" code:831571 userInfo:info];
}

+ (void)fillInStop:(StopLocation *)stop
        completion:(void (^)(NSError *))completion
{
  NSParameterAssert(stop);
  NSParameterAssert(completion);
  
  // now send it off to the server
  SVKServer *server = [SVKServer sharedInstance];
  
  [server requireRegions:^(NSError *error) {
    if (error) {
      DLog(@"Error filling in stop: %@", error.localizedDescription);
      completion(error);
      return;
    }
    
    SVKRegion *region = stop.region;
    if (! region) {
      // We have regions, but this stop doesn't match any known region
      completion([TKBuzzInfoProvider errorForUserForBrokenStop]);
      return;
    }
    
    // construct the parameters
    NSDictionary *paras = @{
                            @"app"       : [SGKConfig regionEligibility],
                            @"region"    : region.name,
                            @"stopCodes" : @[stop.stopCode],
                            };
    
    [server initiateDataTaskWithMethod:@"GET"
                                  path:@"stops.json"
                            parameters:paras
                                region:region
                               success:
     ^(NSURLSessionDataTask *task, id responseObject) {
#pragma unused(task)
       NSManagedObjectContext *temporaryContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
       temporaryContext.parentContext = stop.managedObjectContext;
       
       [temporaryContext performBlock:
        ^{
          // get the private equivalent
          StopLocation *privateStop = (StopLocation *)[temporaryContext objectWithID:stop.objectID];
          ZAssert([privateStop.stopCode isEqualToString:stop.stopCode], @"Public cell (%@) doesn't match ours (%@)", stop, privateStop);
          
          // set the stop properties
          BOOL success = [self addStop:privateStop fromResponse:responseObject];
          
          // save it
          if (success) {
            NSError *privateError = nil;
            success = [temporaryContext save:&privateError];
            ZAssert(success, @"Could not save context: %@", privateError);
          }
          if (success) {
            completion(nil);
          } else {
            completion([TKBuzzInfoProvider errorForUserForBrokenStop]);
          }
        }];
       
     }
                               failure:
     ^(NSURLSessionDataTask *task, NSError *anotherError) {
#pragma unused(task, anotherError)
       DLog(@"Error response: %@", task.response);
       completion(anotherError);
     }];
  }];
}

- (void)addContentToService:(Service *)service
               fromResponse:(NSDictionary *)responseDict
{
  NSParameterAssert(service);
  NSParameterAssert(responseDict);
  
  NSManagedObjectContext *context = service.managedObjectContext;
  
  // real time status
  NSString *realTimeStatus = responseDict[@"realTimeStatus"];
  if (realTimeStatus) {
    [TKParserHelper adjustService:service
          forRealTimeStatusString:realTimeStatus];
  }
  
  // real time vehicles
  [TKParserHelper updateVehiclesForService:service
                            primaryVehicle:responseDict[@"realtimeVehicle"]
                       alternativeVehicles:responseDict[@"realtimeVehicleAlternatives"]];
  
  // alert
  [TKParserHelper updateOrAddAlerts:responseDict[@"alerts"]
                   inTripKitContext:context];
  
  // mode info
  ModeInfo *modeInfo = [ModeInfo modeInfoForDictionary:responseDict[@"modeInfo"]];
  
  // parse the shapes
  NSArray *shapesArray = responseDict[@"shapes"];
  [TKParserHelper insertNewShapes:shapesArray
                       forService:service
                     withModeInfo:modeInfo];
}

#pragma mark - Private methods

/**
 @return If `stop`: a NSNumber for the flags. If `stop == nil`: a set of `pairIdentifiers`.
 */
- (id)addDeparturesToStop:(StopLocation *)stopOrNil
             fromResponse:(id)responseObject
       intoTripKitContext:(NSManagedObjectContext *)context

{
  BOOL forSingleStop = (stopOrNil != nil);
  
  NSInteger flags = 0;
  NSMutableSet *pairIdentifiers  = [NSMutableSet set];

  NSMutableSet *processedStops   = [NSMutableSet set];
  if (forSingleStop) {
    // fill in parents with additional information (optional)
    NSDictionary *parentDict = responseObject[@"parentInfo"];
    if (parentDict) {
      BOOL addedStops = [TKParserHelper updateStopLocation:stopOrNil
                                            fromDictionary:parentDict];
      if (addedStops) {
        flags |= SGDeparturesResultAddedStops;
      }
    }
    [processedStops addObject:stopOrNil];

  } else {
    // DLS
    NSArray *stops = responseObject[@"stops"];
    for (NSDictionary *stopDict in stops) {
      StopLocation *stopLocation = [TKParserHelper insertNewStopLocation:stopDict
                                                        inTripKitContext:context];
      [processedStops addObject:stopLocation];
    }
  }
  
  // get the potential stops to add the embarkations to
  NSMutableDictionary *stopsDict = [NSMutableDictionary dictionary];
  for (StopLocation *stop in processedStops) {
    if (stop.children.count > 0) {
      for (StopLocation *child in stop.children) {
        if (child.stopCode) {
          stopsDict[child.stopCode] = child;
        }
      }
    } else if (stop.stopCode) {
      stopsDict[stop.stopCode] = stop;
    }
  }
	
	// add the embarkations
	NSArray *stops = responseObject[@"embarkationStops"];
	NSInteger addedCount = 0;
  NSString *entityName = NSStringFromClass(forSingleStop ? [StopVisits class] : [DLSEntry class]);
	for (NSDictionary *stopDict in stops) {
		NSString *stopCode = stopDict[@"stopCode"];
		StopLocation *stopToAddTo = stopsDict[stopCode];
		if (! stopToAddTo)
			continue;
		
		NSArray *departureList = stopDict[@"services"];
		
		for (NSDictionary *departureDict in departureList) {
			addedCount++;

			// add the service
			Service *service = [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass([Service class])
																											 inManagedObjectContext:context];
			service.frequency     = departureDict[@"frequency"];
			service.number        = departureDict[@"serviceNumber"];
      service.lineName      = departureDict[@"serviceName"];
      service.direction     = departureDict[@"serviceDirection"];
			service.code          = departureDict[@"serviceTripID"];
			service.color         = [TKParserHelper colorForDictionary:departureDict[@"serviceColor"]];
			service.modeInfo      = [ModeInfo modeInfoForDictionary:departureDict[@"modeInfo"]];
      service.operatorName  = departureDict[@"operator"];
			
			// the real-time status
			NSString *realTimeStatus = departureDict[@"realTimeStatus"];
			[TKParserHelper adjustService:service
            forRealTimeStatusString:realTimeStatus];
			
			// the real-time vehicles
      [TKParserHelper updateVehiclesForService:service
                                primaryVehicle:departureDict[@"realtimeVehicle"]
                           alternativeVehicles:departureDict[@"realtimeVehicleAlternatives"]];
			
			// the alerts
			[TKParserHelper updateOrAddAlerts:departureDict[@"alerts"]
                       inTripKitContext:context];
			
			// add the visit information
			StopVisits *visit = [NSEntityDescription insertNewObjectForEntityForName:entityName
																												inManagedObjectContext:context];
			NSNumber *startTimeRaw = departureDict[@"startTime"];
			if (nil != startTimeRaw) {
				// we use 'time' to allow KVO
				visit.time = [NSDate dateWithTimeIntervalSince1970:[startTimeRaw longValue]];
			}
			NSNumber *endTimeRaw = departureDict[@"endTime"];
			if (nil != endTimeRaw) {
				visit.arrival = [NSDate dateWithTimeIntervalSince1970:[endTimeRaw longValue]];
			}
      
      visit.originalTime = [visit time];
			
			visit.searchString = departureDict[@"searchString"];
      
      // dls info
      if (! forSingleStop) {
        NSString *endStopCode = departureDict[@"endStopCode"];
        NSString *pairIdentifier = [NSString stringWithFormat:@"%@-%@", stopCode, endStopCode];
        [pairIdentifiers addObject:pairIdentifier];

        DLSEntry *entry = (DLSEntry *)visit;
        entry.pairIdentifier = pairIdentifier;
        
        StopLocation *end = stopsDict[endStopCode];
        ZAssert(end, @"We need an end stop!");
        entry.endStop = end;
      }
			
			// connect visit to stop
			visit.service = service;
			ZAssert(visit.stop == nil || visit.stop == stopToAddTo, @"We shouldn't have a stop already! %@", visit.stop);
			visit.stop = stopToAddTo;
			ZAssert(visit.stop != nil, @"Visit needs a stop!");

			// do this last to make sure it has a stop
			[visit adjustRegionDay];
		}
	}
  if (addedCount > 0) {
    flags |= SGDeparturesResultAddedDepartures;
  }
	
	// add the alerts for the stop itself
	[TKParserHelper updateOrAddAlerts:responseObject[@"alerts"]
                   inTripKitContext:context];
	
  if (forSingleStop) {
    return @(flags);
  } else {
    return pairIdentifiers;
  }
}

+ (BOOL)addStop:(StopLocation *)stop
   fromResponse:(id)responseObject
{
  NSManagedObjectContext *tripKitContext = stop.managedObjectContext;
  
  NSArray *groups = responseObject[@"groups"];
  for (NSDictionary *groupDict in groups) {
    NSString *key = groupDict[@"key"];
    if (! [key isEqualToString:stop.stopCode])
      continue;
    
    NSArray *stopList = groupDict[@"stops"];
    for (NSDictionary *stopDict in stopList) {
      NSString *code = stopDict[@"code"];
      
      // is this our stop?
      if ([stop.stopCode isEqualToString:code]) {
        [TKParserHelper updateStopLocation:stop
                            fromDictionary:stopDict];
        
      } else {
        // we always add all the stops, because the cell is new
        StopLocation *newStop = [TKParserHelper insertNewStopLocation:stopDict
                                                     inTripKitContext:tripKitContext];
        
        // make sure we have an ID
        NSError *error = nil;
        [tripKitContext obtainPermanentIDsForObjects:@[newStop] error:&error];
        ZAssert(! error, @"Error obtaining permanent ID for '%@': %@", newStop, error);
      }
    }
    return stopList.count > 0;
  }
  return NO;
}

@end
