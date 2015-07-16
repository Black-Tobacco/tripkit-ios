//
//  BHBuzzRouter.m
//  TripGo
//
//  Created by Adrian Schönig on 2/03/11.
//  Copyright 2011 SkedGo. All rights reserved.
//

#import "TKBuzzRouter.h"

#import "TKTripKit.h"

#import "TripRequest+Classify.h"

#define kBHRoutingTimeOutSecond           30

@interface TKBuzzRouter ()

@property (nonatomic, assign) BOOL isActive;

@property (nonatomic, strong) NSError *lastWorkerError;
@property (nonatomic, strong) NSMutableDictionary *workerRouters;
@property (nonatomic, assign) NSUInteger finishedWorkers;

@end

@implementation TKBuzzRouter

#pragma mark - Public interface

- (void)cancelRequests
{
  for (TKBuzzRouter *worker in self.workerRouters) {
      if ([worker respondsToSelector:@selector(cancelRequests)]) {
          [worker cancelRequests];
      }
  }
  self.workerRouters = nil;
  self.lastWorkerError = nil;
  
  self.isActive = NO;
}

- (NSUInteger)multiFetchTripsForRequest:(TripRequest *)request
                             classifier:(nullable id<TKTripClassifier>)classifier
                               progress:(nullable void (^)(NSUInteger))progress
                             completion:(void (^)(TripRequest * __nullable, NSError * __nullable))completion
{
  [self cancelRequests];
  self.isActive = YES;
  
  NSArray *enabledModes       = [request.spanningRegion modeIdentifiers];
  NSSet *groupedIdentifiers   = [SVKTransportModes groupedModeIdentifiers:enabledModes includeGroupForAll:YES];
  NSUInteger requestCount = [groupedIdentifiers count];
  self.finishedWorkers = 0;
  
  if (!self.workerRouters) {
    self.workerRouters = [NSMutableDictionary dictionaryWithCapacity:requestCount];
  }
  
  // we'll adjust the visibility in the completion block
  request.defaultVisibility = TripGroupVisibilityHidden;

  for (NSSet *modeIdentifiers in groupedIdentifiers) {
    TKBuzzRouter *worker = self.workerRouters[modeIdentifiers];
    if (worker) {
      continue;
    }
    
    worker = [[TKBuzzRouter alloc] init];
    self.workerRouters[modeIdentifiers] = worker;
    worker.modeIdentifiers = modeIdentifiers;
    
    __weak typeof(self) weakSelf = self;
    [worker fetchTripsForRequest:request
                         success:
     ^(TripRequest *completedRequest, NSSet *completedIdentifiers) {
       typeof(weakSelf) strongSelf = weakSelf;
       if (strongSelf) {
         // Updating classifications before making results visible
         if (classifier) {
           [completedRequest updateTripGroupClassificationsUsingClassifier:classifier];
         }
         
         // We get thet minimized and hidden modes here in the completion block
         // since they might have changed while waiting for results
         NSSet *minimized = [TKUserProfileHelper minimizedModeIdentifiers];
         NSSet *hidden = [TKUserProfileHelper hiddenModeIdentifiers];
         [completedRequest adjustVisibilityForMinimizedModeIdentifiers:minimized
                                                 hiddenModeIdentifiers:hidden];
         
         strongSelf.finishedWorkers++;
         if (progress) {
           progress(strongSelf.finishedWorkers);
         }
         
         [strongSelf handleMultiFetchResult:completedRequest
                             completedModes:completedIdentifiers
                                      error:nil
                                 completion:completion];
       }
     }
                         failure:
     ^(NSError *error, NSSet *erroredIdentifiers) {
       typeof(weakSelf) strongSelf = weakSelf;
       if (strongSelf) {
         [strongSelf handleMultiFetchResult:request
                             completedModes:erroredIdentifiers
                                      error:error
                                 completion:completion];
       }
     }];
  }
  
  return requestCount;
}

- (void)handleMultiFetchResult:(TripRequest *)request
                completedModes:(NSSet *)modeIdentifiers
                         error:(NSError *)error
                    completion:(void (^)(TripRequest *, NSError *))completion
{
  [self.workerRouters removeObjectForKey:modeIdentifiers];
  
  if (self.workerRouters.count == 0) {

    NSError *errorToShow = nil;
    if (request.trips.count == 0) {
      errorToShow = error ?: self.lastWorkerError;
    }
    completion(request, errorToShow);
    
  } else {
    self.lastWorkerError = error;
  }
}

- (void)downloadTrip:(NSURL *)url
  intoTripKitContext:(NSManagedObjectContext *)tripKitContext
          completion:(void(^)(Trip * __nullable trip))completion
{
  [self hitURLForTripDownload:url completion:
   ^(NSURL *requestURL, id JSON, NSError *error) {
#pragma unused(requestURL, error)
     if (JSON) {
       DLog(@"Downloaded trip JSON for: %@", requestURL);
       [self parseJSON:JSON
     forTripKitContext:tripKitContext
            completion:^(Trip *trip) {
         trip.shareURL = url;
         if (completion) {
           completion(trip);
         }
       }];
     } else {
       // failure
       DLog(@"Failed to trip from: %@.\nError: %@", requestURL, error);
       if (completion) {
         completion(nil);
       }
     }
    }];
}

- (void)updateTrip:(Trip *)trip completion:(void(^)(Trip * __nullable trip))completion
{
  NSURL *updateURL = [NSURL URLWithString:trip.updateURLString];
//  DLog(@"Updating trip from URL: %@", updateURL);
//  DLog(@"Updating trip (%d): %@", trip.tripGroup.visibility, [trip debugString]);
  [self hitURLForTripDownload:updateURL completion:^(NSURL *requestURL, id JSON, NSError *error) {
#pragma unused(requestURL, error)
    if (JSON) {
      [self parseJSON:JSON updatingTrip:trip completion:^(Trip *updatedTrip) {
        DLog(@"Updated trip (%d): %@", updatedTrip.tripGroup.visibility, [updatedTrip debugString]);
        if (completion) {
          completion(updatedTrip);
        }
      }];
    } else if (! error) {
      // No new data (but also no error
      DLog(@"No update for trip (%d): %@", trip.tripGroup.visibility, [trip debugString]);
      if (completion) {
        completion(trip);
      }
    }
  }];
}


- (void)fetchBestTripForRequest:(TripRequest *)request
                        success:(TKRouterSuccess)success
                        failure:(TKRouterError)failure
{
  request.expandForFavorite = YES;
  self.currentRequest = request;
  return [self fetchTripsForCurrentRequestBestOnly:YES
                                           success:success
                                           failure:failure];
}

- (void)fetchTripsForCurrentRequestSuccess:(TKRouterSuccess)success
                                   failure:(TKRouterError)failure
{
  [self fetchTripsForCurrentRequestBestOnly:NO success:success failure:failure];
}

- (void)fetchTripsForCurrentRequestBestOnly:(BOOL)bestOnly
                                    success:(TKRouterSuccess)success
                                    failure:(TKRouterError)failure
{
  ZAssert(success && failure, @"Success and failure blocks are required");

	// some sanity checks
	if (nil == self.currentRequest
			|| nil == self.currentRequest.fromLocation
			|| nil == self.currentRequest.toLocation) {
		ZAssert(false, @"Tried routing for a bad request: %@", self.currentRequest);

		NSError *error = [NSError errorWithCode:81350
																		message:@"Bad request."];
		[self handleError:error
					forURLQuery:nil
							failure:failure];
		return;
	}
	
	// check from/to coordinates
	if (! CLLocationCoordinate2DIsValid([self.currentRequest.fromLocation coordinate])) {
		ZAssert(false, @"Tried routing with bad from location: %@", self.currentRequest.fromLocation);
		
		NSError *error = [NSError errorWithCode:kSVKServerErrorTypeUser
																		message:@"Start location could not be determined. Please try again or select manually."];
		
		[self handleError:error
					forURLQuery:nil
							failure:failure];
		return;
	}

	if (! CLLocationCoordinate2DIsValid([self.currentRequest.toLocation coordinate])) {
		ZAssert(false, @"Tried routing with bad to location: %@", self.currentRequest.toLocation);
		
		NSError *error = [NSError errorWithCode:kSVKServerErrorTypeUser
																		message:@"End location could not be determined. Please try again or select manually."];
		
		[self handleError:error
					forURLQuery:nil
							failure:failure];
		return;
	}

	__weak typeof(self) weakSelf = self;
  SVKServer *server = [SVKServer sharedInstance];
	[server requireRegions:^(NSError *error) {
    typeof(weakSelf) strongSelf = weakSelf;
		if (! strongSelf) {
			return;
		}
		
		if (error) {
			// could not get regions
			[strongSelf handleError:error
                  forURLQuery:nil
                      failure:failure];
			return;
		}
    
    // we are guaranteed to have regions
    SVKRegion *region = [strongSelf.currentRequest localRegion];
    if (! region) {
      error = [NSError errorWithCode:kSVKServerErrorTypeUser
                             message:@"Unsupported region."];
      [strongSelf handleError:error
                  forURLQuery:nil
                      failure:failure];
      return;
    }
    
    // we are good to send requests. create them, then tell the caller.
    self.isActive = YES;
    NSDictionary *paras = [strongSelf createRequestParametersForRequest:strongSelf.currentRequest
                                                     andModeIdentifiers:self.modeIdentifiers
                                                               bestOnly:bestOnly];
    [server initiateDataTaskWithMethod:@"GET"
                                  path:@"routing.json"
                            parameters:paras
                                region:region
                               success:
     ^(NSURLSessionDataTask *task, id responseObject) {
       typeof(weakSelf) strongSelf2 = weakSelf;
       if (! strongSelf2) {
         return;
       }
       
       DLog(@"Request returned JSON: %@", task.currentRequest.URL);
       [strongSelf2 parseJSON:responseObject
                  forURLQuery:task.currentRequest.URL.query
            forTripKitContext:strongSelf2.currentRequest.managedObjectContext
                      success:success
                      failure:failure];
     }
                               failure:
     ^(NSURLSessionDataTask *task, NSError *error2) {
       typeof(weakSelf) strongSelf2 = weakSelf;
       if (! strongSelf2) {
         return;
       }
       
       [strongSelf2 handleError:error2
                    forURLQuery:task.currentRequest.URL.query
                        failure:failure];
     }];
  }];
}




#pragma mark - Private methods

- (void)hitURLForTripDownload:(NSURL *)url completion:(void (^)(NSURL *requestURL, id JSON, NSError *error))completion
{
  // de-construct the URL
  NSString *port = nil != url.port ? [NSString stringWithFormat:@":%@", url.port] : @"";
  NSString *scheme = [url.scheme hasPrefix:@"http"] ? url.scheme : @"https"; // keep http and https, but replace stuff like $appname://
  NSString *baseURLString = [NSString stringWithFormat:@"%@://%@%@%@", scheme, url.host, port, url.path];
  NSURL *baseURL = [NSURL URLWithString:baseURLString];
  
  // use our default parameters and append those from the URL
  NSMutableDictionary *paras = [TKSettings defaultDictionary];
  NSString *query = url.query;
  for (NSString *option in [query componentsSeparatedByString:@"&"]) {
    NSArray *pair = [option componentsSeparatedByString:@"="];
    if (pair.count == 1) {
      [paras setValue:@(YES) forKey:pair[0]];
    } else if (pair.count == 2) {
      [paras setValue:pair[1] forKey:pair[0]];
    } else {
      DLog(@"Unknown option: %@", option);
    }
  }
  
  // create the request
  SVKSessionManager *manager = [SVKSessionManager jsonSessionManagerWithBaseURL:[baseURL URLByDeletingLastPathComponent]];

  NSMutableURLRequest *request = [manager.requestSerializer requestWithMethod:@"GET" URLString:[baseURL absoluteString] parameters:paras error:nil];
  NSURLSessionDataTask *task = [manager dataTaskWithRequest:request completionHandler:^(NSURLResponse *response, id responseObject, NSError *error) {
#pragma unused(response)
    completion(request.URL, responseObject, error);
  }];
  
  [task resume];
}

- (void)parseJSON:(id)json
			forURLQuery:(NSString *)urlQuery
forTripKitContext:(NSManagedObjectContext *)tripKitContext
					success:(TKRouterSuccess)success
					failure:(TKRouterError)failure
{
  ZAssert(success && failure, @"Success and failure blocks are required");
  
  if (! self.isActive) {
    // ignore responses from outdated requests
    return;
  }
	
	// make sure that the parent context is saved
  [tripKitContext performBlock:^{
    NSError *error = nil;
    BOOL saved = [tripKitContext save:&error];
    
    if (saved) {
      [self parseAndAddResult:json
           intoTripKitContext:tripKitContext
                  forURLQuery:urlQuery
                      success:
       ^(NSArray *addedTrips) {
         self.isActive = NO;
         if (addedTrips) {
           success(self.currentRequest, self.modeIdentifiers);
         }
       }
                      failure:failure];
      
    } else {
      ZAssert(false, @"Error saving: %@", error);
      self.isActive = NO;
      if (failure) {
        failure(error, self.modeIdentifiers);
      }
    }
    self.isActive = NO;
  }];
}

- (void)handleError:(NSError *)error
				forURLQuery:(NSString *)urlQuery
						failure:(TKRouterError)failure
{
	if (urlQuery) {
		if (! self.isActive) {
			// ignore responses from outdated requests
			return;
		}
	}

  DLog(@"Request failed: %@ with error %@ (%@)", urlQuery, error, [error description]);
  self.isActive = NO;
  
  dispatch_async(dispatch_get_main_queue(), ^{
		if (failure) {
			failure(error, self.modeIdentifiers);
		}
  });
}

- (void)parseJSON:(id)json
     updatingTrip:(Trip *)trip
       completion:(void(^)(Trip * __nullable trip))completion
{
  NSString *error = [json objectForKey:@"error"];
  if (error) {
    if (completion) {
      completion(nil);
    }
    return;
  }
  
  NSManagedObjectContext *tripKitContext = trip.managedObjectContext;
  TKRoutingParser *parser = [[TKRoutingParser alloc] initWithTripKitContext:tripKitContext];
  [parser parseJSON:json
       updatingTrip:trip
         completion:
   ^(Trip *updatedTrip) {
     if (updatedTrip) {
       ZAssert(updatedTrip.managedObjectContext == tripKitContext, @"Context mismatch.");
       NSError *publicError = nil;
       BOOL publicSuccess = [tripKitContext save:&publicError];
       ZAssert(publicSuccess, @"Error saving: %@", publicError);
       
       completion(updatedTrip);
     } else {
       // failure
       completion(nil);
     }
   }];
}

- (void)parseJSON:(id)json
forTripKitContext:(NSManagedObjectContext *)tripKitContext
       completion:(void(^)(Trip * __nullable trip))completion
{
  NSString *error = [json objectForKey:@"error"];
  if (error) {
    if (completion) {
      completion(nil);
    }
    return;
  }
  
  // parse it
  TKRoutingParser *parser = [[TKRoutingParser alloc] initWithTripKitContext:tripKitContext];
  [parser parseAndAddResult:json
                 completion:
   ^(TripRequest *request) {
     // make sure we save
     ZAssert(request.managedObjectContext == tripKitContext, @"Context mismatch.");
     NSError *publicError = nil;
     BOOL publicSuccess = [tripKitContext save:&publicError];
     ZAssert(publicSuccess, @"Error saving: %@", publicError);
     
     request.lastSelection = [request.tripGroups anyObject];
     [request.lastSelection adjustVisibleTrip];
     completion(request.preferredTrip);
   }];
}

#pragma mark - Single Requests

- (NSDictionary *)createRequestParametersForRequest:(TripRequest *)request
                                 andModeIdentifiers:(NSSet *)modeIdentifiers
                                           bestOnly:(BOOL)bestOnly
{
	NSMutableDictionary *paras = [TKSettings defaultDictionary];
	
	[paras setValue:[modeIdentifiers allObjects] forKey:@"modes"];
	
  // locations
  NSString *fromString = [STKParserHelper requestStringForCoordinate:[request.fromLocation coordinate]];
  NSString *toString = [STKParserHelper requestStringForCoordinate:[request.toLocation coordinate]];
	[paras setValue:fromString forKey:@"from"];
	[paras setValue:toString forKey:@"to"];

  // times
	NSDate *departure, *arrival = nil;
  switch ((SGTimeType) request.timeType.integerValue) {
    case SGTimeTypeArriveBefore:
    case SGTimeTypeLeaveAfter:
      departure = request.departureTime;
      arrival   = request.arrivalTime;
      break;

    case SGTimeTypeNone:
      // do nothing and let the server do time-independent routing
      break;

    case SGTimeTypeLeaveASAP:
      departure = [NSDate dateWithTimeIntervalSinceNow:60];
      break;
  }
  
  if (arrival) { // arrival takes precedence over departure as it's more important
                 // to arrive at the next meeting on time, than stick to the end
                 // of the previous meeting
    NSNumber *arriveBefore = @((NSInteger) [arrival timeIntervalSince1970]);
    [paras setValue:arriveBefore forKey:@"arriveBefore"];
  } else if (departure) {
    NSNumber *departAfter =  @((NSInteger) [departure timeIntervalSince1970]);
    [paras setValue:departAfter forKey:@"departAfter"];
  }
  
  if (bestOnly) {
    paras[@"bestOnly"] = @(YES);
  }
  
  return paras;
}

#pragma mark - Results

- (void)parseAndAddResult:(id)json
       intoTripKitContext:(NSManagedObjectContext *)tripKitContext
							forURLQuery:(NSString *)urlQuery
                  success:(void (^)(NSArray *addedTrips))completion
									failure:(TKRouterError)failure
{
  ZAssert(completion && failure, @"Success and failure blocks are required");
  ZAssert(tripKitContext != nil, @"Managed object context required!");
  
  // analyse result
  NSError *serverError = [SVKServer serverErrorForJSONErrorDictionary:json];
  if (serverError) {
    DLog(@"Encountered error: %@", serverError);
		[self handleError:serverError
					forURLQuery:urlQuery
							failure:failure];
    return;
  }
	
  TKRoutingParser *parser = [[TKRoutingParser alloc] initWithTripKitContext:tripKitContext];
  [parser parseAndAddResult:json
                 forRequest:self.currentRequest
                    merging:YES
                 completion:completion];
}

@end