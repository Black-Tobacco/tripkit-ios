//
//  TripRequest+Classify.m
//  TripGo
//
//  Created by Adrian Schoenig on 11/06/2015.
//  Copyright (c) 2015 SkedGo Pty Ltd. All rights reserved.
//

#import "TripRequest+Classify.h"

#import "TKTripKit.h"

@implementation TripRequest (Classify)

- (void)updateTripGroupClassificationsUsingClassifier:(nonnull id<TKTripClassifier>)classifier
{
  NSSet *tripGroups = [self tripGroups];
  [classifier prepareForClassifictionOfTripGroups:tripGroups];
  for (TripGroup *group in tripGroups) {
    group.classification = [classifier classificationOfTripGroup:group];
  }
}

@end