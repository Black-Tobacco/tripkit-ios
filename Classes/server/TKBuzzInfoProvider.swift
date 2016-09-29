//
//  TKBuzzInfoProvider.swift
//  TripGo
//
//  Created by Adrian Schoenig on 11/12/2015.
//  Copyright © 2015 SkedGo Pty Ltd. All rights reserved.
//

import Foundation

public final class RegionInformation: NSObject {
  
  public let publicTransportModes: [ModeInfo]
  public let allowsBicyclesOnPublicTransport: Bool
  public let supportsConcessionPricing: Bool
  public let hasWheelchairInformation: Bool
  public let paratransitInformation: ParatransitInformation?
  public let publicTransportOperators: [PublicOperatorInformation]?
  public let bikeSharingProviders: [BikeSharingInformation]?
  
  
  private init(transitModes: [ModeInfo], allowsBicyclesOnPublicTransport: Bool, hasWheelchairInformation: Bool,
               supportsConcessionPricing: Bool, paratransitInformation: ParatransitInformation?,
               publicTransportOperators: [PublicOperatorInformation]?, bikeSharingProviders: [BikeSharingInformation]? ) {
    
    self.publicTransportModes = transitModes
    self.allowsBicyclesOnPublicTransport = allowsBicyclesOnPublicTransport
    self.hasWheelchairInformation = hasWheelchairInformation
    self.supportsConcessionPricing = supportsConcessionPricing
    self.paratransitInformation = paratransitInformation
    self.publicTransportOperators = publicTransportOperators
    self.bikeSharingProviders = bikeSharingProviders
  }
  
  private class func fromJSONResponse(response: AnyObject?) -> RegionInformation? {
    guard let JSON = response as? [String: AnyObject],
      let regions = JSON["regions"] as? [[String: AnyObject]],
      let region = regions.first else {
        return nil
    }
    
    let transitModes = ModeInfo.transitModesFromJSONResponse(response)
    let bicyclesOnTransit = region["allowsBicyclesOnPublicTransport"] as? Bool ?? false
    let wheelies = region["hasWheelchairInformation"] as? Bool ?? false
    let concession = region["supportsConcessionPricing"] as? Bool ?? false
    let para = ParatransitInformation.fromJSONResponse(response)
    let operators = PublicOperatorInformation.fromJSONArray(region["operators"]) ?? []
    let bikeSharingProviders = BikeSharingInformation.fromJSONArray(region["bikeShare"]) ?? []
    
    return RegionInformation(transitModes: transitModes,
      allowsBicyclesOnPublicTransport: bicyclesOnTransit,
      hasWheelchairInformation: wheelies,
      supportsConcessionPricing: concession,
      paratransitInformation: para,
      publicTransportOperators: operators,
      bikeSharingProviders: bikeSharingProviders)
  }
}

/**
 Informational class for paratransit information (i.e., transport for people with disabilities).
 Contains name of service, URL with more information and phone number.
 
 - SeeAlso: `TKBuzzInfoProvider`'s `fetchParatransitInformation`
 */
public final class ParatransitInformation: NSObject {
  public let name: String
  public let URL: String
  public let number: String
  
  private init(name: String, URL: String, number: String) {
    self.name = name
    self.URL = URL
    self.number = number
  }
  
  private class func fromJSONResponse(response: AnyObject?) -> ParatransitInformation? {
    guard let JSON = response as? [String: AnyObject],
          let regions = JSON["regions"] as? [[String: AnyObject]],
          let region = regions.first,
          let dict = region["paratransit"] as? [String: String],
          let name = dict["name"],
          let URL = dict["URL"],
          let number = dict["number"] else {
      return nil
    }
    
    return ParatransitInformation(name: name, URL: URL, number: number)
  }
}

/**
 Base class for region's information components
 */
public class BaseRegionInformation: NSObject {
  func titleToShow() -> String {
    fatalError("must be implemented by childs")
  }
}

/**
 Informational class for public transport operators. Note that not all the data is
 parsed, as it isn't needed by now.
 */
public final class PublicOperatorInformation: BaseRegionInformation {
  
  public let name: String
  
  private init(name: String) {
    self.name = name
  }
  
  private class func fromJsonObject(jsonObject: [String: AnyObject?]?) -> PublicOperatorInformation? {
    guard let jsonObject = jsonObject,
              name = jsonObject["name"] as? String else {
      return nil
    }
    return PublicOperatorInformation(name: name)
  }
  
  private class func fromJSONArray(jsonArray: AnyObject?) -> [PublicOperatorInformation]? {
    guard let jsonArray = jsonArray as? [[String: AnyObject]] else {
        return nil
    }
    return jsonArray.flatMap { PublicOperatorInformation.fromJsonObject($0) }
  }
  
  override func titleToShow() -> String {
    return self.name
  }
}

  
/**
 Informational class for public Bike Sharing providers. Note that not all the data is
 parsed, as it isn't needed by now.
 */
public final class BikeSharingInformation: BaseRegionInformation {
  public let title: String
  
  private init(title: String) {
    self.title = title
  }
  
  private class func fromJsonObject(jsonObject: [String: AnyObject?]?) -> BikeSharingInformation? {
    guard let jsonObject = jsonObject,
      title = jsonObject["title"] as? String else {
        return nil
    }
    return BikeSharingInformation(title: title)
    
  }
  
  private class func fromJSONArray(jsonArray: AnyObject?) -> [BikeSharingInformation]? {
    guard let jsonArray = jsonArray as? [[String: AnyObject]] else {
      return nil
    }
    return jsonArray.flatMap { BikeSharingInformation.fromJsonObject($0) }
  }
  
  override func titleToShow() -> String {
    return self.title
  }
  
}


//MARK: ModeInfo parsing
extension ModeInfo {
  private class func regionFromJSONResponse(response: AnyObject?) -> [String: AnyObject]? {
    guard let JSON = response as? [String: AnyObject],
      let regions = JSON["regions"] as? [[String: AnyObject]] else {
        return nil
    }
    
    return regions.first
  }
  
  private class func transitModesFromJSONResponse(response: AnyObject?) -> [ModeInfo] {
    guard let region = regionFromJSONResponse(response),
          let array = region["transitModes"] as? [[String: AnyObject]] else {
      return []
    }

    return array.flatMap { ModeInfo(forDictionary: $0) }
  }

}

extension TKBuzzInfoProvider {

  /**
   Asynchronously fetches additional region information for the provided region.
   
   - Note: Completion block is executed on the main thread.
   */
  public class func fetchRegionInformation(forRegion region: SVKRegion, completion: RegionInformation? -> Void)
  {
    return fetchRegionInfo(
      region,
      transformer: RegionInformation.fromJSONResponse,
      completion: completion
    )
  }
  
  
  /**
   Asynchronously fetches paratransit information for the provided region.
   
   - Note: Completion block is executed on the main thread.
   */
  public class func fetchParatransitInformation(forRegion region: SVKRegion, completion: ParatransitInformation? -> Void)
  {
    return fetchRegionInfo(
      region,
      transformer: ParatransitInformation.fromJSONResponse,
      completion: completion
    )
  }
  
  /**
   Asynchronously fetches all available individual public transport modes for the provided region.
   
   - Note: Completion block is executed on the main thread.
   */
  public class func fetchPublicTransportModes(forRegion region: SVKRegion, completion: [ModeInfo] -> Void)
  {
    return fetchRegionInfo(
      region,
      transformer: ModeInfo.transitModesFromJSONResponse,
      completion: completion
    )
  }

  private class func fetchRegionInfo<E>(region: SVKRegion, transformer: AnyObject? -> E, completion: E -> Void)
  {
    let paras = [
      "region": region.name
    ]
    SVKServer.sharedInstance().hitSkedGoWithMethod(
      "POST",
      path: "regionInfo.json",
      parameters: paras,
      region: region,
      success: { response in
        let result = transformer(response)
        completion(result)
      },
      failure: { _ in
        let result = transformer(nil)
        completion(result)
      })
  }
}

public class LocationInformation : NSObject {
  public let what3word: String?
  public let what3wordInfoURL: NSURL?
  
  public let transitStop: TKStopAnnotation?
  
  private init(what3word: String?, what3wordInfoURL: String?, transitStop: TKStopAnnotation?) {
    self.what3word = what3word
    if let URLString = what3wordInfoURL {
      self.what3wordInfoURL = NSURL(string: URLString)
    } else {
      self.what3wordInfoURL = nil
    }
    self.transitStop = transitStop
  }
  
  private class func fromJSONResponse(response: AnyObject?) -> LocationInformation? {
    
    guard let JSON = response as? [String: AnyObject] else {
      return nil
    }

    let details = JSON["details"] as? [String: AnyObject]
    let what3word = details?["w3w"] as? String
    let what3wordInfoURL = details?["w3wInfoURL"] as? String

    let stop: TKStopAnnotation?
    if let stopJSON = JSON["stop"] as? [String: AnyObject] {
      stop = TKParserHelper.simpleStopFromDictionary(stopJSON)
    } else {
      stop = nil
    }
    
    return LocationInformation(what3word: what3word, what3wordInfoURL: what3wordInfoURL, transitStop: stop)
  }
  
}

extension TKBuzzInfoProvider {
  /**
   Asynchronously fetches additional location information for a specified coordinate.
   
   - Note: Completion block is executed on the main thread.
  */
  public class func fetchLocationInformation(coordinate: CLLocationCoordinate2D, forRegion region: SVKRegion, completion: (LocationInformation?) -> Void) {
    let paras: [String: AnyObject] = [
      "lat": coordinate.latitude,
      "lng": coordinate.longitude
    ]
    
    SVKServer.sharedInstance().hitSkedGoWithMethod(
      "GET",
      path: "locationInfo.json",
      parameters: paras,
      region: region,
      success: { response in
        let result = LocationInformation.fromJSONResponse(response)
        completion(result)
      },
      failure: { _ in
        completion(nil)
      })
    
  }
}

