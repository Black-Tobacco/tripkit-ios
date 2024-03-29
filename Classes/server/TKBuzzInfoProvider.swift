//
//  TKBuzzInfoProvider.swift
//  TripGo
//
//  Created by Adrian Schoenig on 11/12/2015.
//  Copyright © 2015 SkedGo Pty Ltd. All rights reserved.
//

import Foundation
import RxSwift
import SwiftyJSON

public final class RegionInformation: NSObject {
  
  public let streetBikePaths: Bool
  public let streetWheelchairAccessibility: Bool
  public let transitModes: [ModeInfo]
  public let transitBicycleAccessibility: Bool
  public let transitConcessionPricing: Bool
  public let transitWheelchairAccessibility: Bool
  public let paratransitInformation: ParatransitInformation?
  
  private init(
    streetBikePaths: Bool,
    streetWheelchairAccessibility: Bool,
    transitModes: [ModeInfo],
    transitBicycleAccessibility: Bool,
    transitWheelchairAccessibility: Bool,
    transitConcessionPricing: Bool,
    paratransitInformation: ParatransitInformation?)
  {
    self.streetBikePaths = streetBikePaths
    self.streetWheelchairAccessibility = streetWheelchairAccessibility
    self.transitModes = transitModes
    self.transitBicycleAccessibility = transitBicycleAccessibility
    self.transitConcessionPricing = transitConcessionPricing
    self.transitWheelchairAccessibility = transitWheelchairAccessibility
    self.paratransitInformation = paratransitInformation
  }
  
  private class func fromJSONResponse(response: AnyObject?) -> RegionInformation? {
    guard let JSON = response as? [String: AnyObject],
      let regions = JSON["regions"] as? [[String: AnyObject]],
      let region = regions.first else {
        return nil
    }
    
    // For backwards compatibility. Can get removed, once all SkedGo servers have been updated
    let transitBicycleAccessibility =
      region["transitBicycleAccessibility"] as? Bool
        ?? region["allowsBicyclesOnPublicTransport"] as? Bool
        ?? false
    let transitWheelchairAccessibility =
      region["transitWheelchairAccessibility"] as? Bool
        ?? region["hasWheelchairInformation"] as? Bool
        ?? false
    let transitConcessionPricing =
      region["transitConcessionPricing"] as? Bool
        ?? region["supportsConcessionPricing"] as? Bool
        ?? false
    
    return RegionInformation(
      streetBikePaths: region["streetBikePaths"] as? Bool ?? false,
      streetWheelchairAccessibility: region["streetWheelchairAccessibility"] as? Bool ?? false,
      transitModes: ModeInfo.fromJSONResponse(response),
      transitBicycleAccessibility: transitBicycleAccessibility,
      transitWheelchairAccessibility: transitWheelchairAccessibility,
      transitConcessionPricing: transitConcessionPricing,
      paratransitInformation: ParatransitInformation.fromJSONResponse(response)
    )
  }
}

public final class TransitAlertInformation: NSObject, TKAlert {
  public let title: String
  public let text: String?
  public let URL: String?
  public let severity: AlertSeverity
  public let lastUpdated: NSDate?
  
  public var sourceModel: AnyObject? {
    return self
  }
  
  public var icon: UIImage? {
    var iconType: STKInfoIconType = STKInfoIconTypeNone
    
    switch severity {
    case .Info:
      iconType = STKInfoIconTypeNone
    case .Warning:
      iconType = STKInfoIconTypeWarning
    case .Alert:
      iconType = STKInfoIconTypeAlert
    }
    
    return STKInfoIcon.imageForInfoIconType(iconType, usage: STKInfoIconUsageNormal)
  }
  
  private init(title: String, text: String? = nil, url: String? = nil, severity: AlertSeverity = .Info, lastUpdated: NSDate? = nil) {
    self.title = title
    self.text = text
    self.URL = url
    self.severity = severity
    self.lastUpdated = lastUpdated
  }
  
  private class func alertsFromJSONResponse(response: AnyObject?) -> [TransitAlertInformation]? {
    guard
      let JSON = response as? [String: AnyObject],
      let array = JSON["alerts"] as? [[String: AnyObject]]
      else {
        return nil
    }
    
    let alerts = array.flatMap { dict -> TransitAlertInformation? in
      guard let alertDict = dict["alert"] as? [String: AnyObject] else {
        return nil
      }
      
      let title = alertDict["title"] as? String ?? ""
      let text = alertDict["text"] as? String
      let stringURL = alertDict["url"] as? String
      
      var severity: AlertSeverity = .Info
      if let alertSeverity = alertDict["severity"] as? String {
        switch alertSeverity {
        case "alert":
          severity = .Alert
        case "warning":
          severity = .Warning
        default:
          severity = .Info
        }
      }
      
      return TransitAlertInformation(title: title, text: text, url: stringURL, severity: severity)
    }
    
    return alerts
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

extension ModeInfo {
  private class func fromJSONResponse(response: AnyObject?) -> [ModeInfo] {
    guard let JSON = response as? [String: AnyObject],
          let regions = JSON["regions"] as? [[String: AnyObject]],
          let region = regions.first,
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
   Asynchronously fetches transit alerts for the provided region.
   
   - Note: Completion block is executed on the main thread.
   */
  public class func fetchTransitAlerts(forRegion region: SVKRegion, completion: [TransitAlertInformation]? -> Void) {
    let paras = [
      "region": region.name
    ]
    
    SVKServer.sharedInstance().hitSkedGoWithMethod(
      "GET",
      path: "alerts/transit.json",
      parameters: paras,
      region: region,
      success: { _, response in
        let result = TransitAlertInformation.alertsFromJSONResponse(response)
        completion(result)
      },
      failure: { _ in
        let result = TransitAlertInformation.alertsFromJSONResponse(nil)
        completion(result)
    })
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
      transformer: ModeInfo.fromJSONResponse,
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
      success: { _, response in
        let result = transformer(response)
        completion(result)
      },
      failure: { _ in
        let result = transformer(nil)
        completion(result)
      })
  }
  
  // MARK: - Rx variants.
  
  /**
   Asynchronously fetches transit alerts for the provided region using Rx.
   */
  public class func rx_fetchTransitAlerts(forRegion region: SVKRegion) -> Observable<[TKAlert]> {
    let paras: [String: AnyObject] = [
      "region": region.name
    ]
    
    return SVKServer.sharedInstance()
      .rx_hit(.GET, path: "alerts/transit.json", parameters: paras, region: region, repeatHandler: nil)
      .map { (_, response) -> [TKAlert] in
        if let jsonResponse = response?.dictionaryObject {
          let alerts = TransitAlertInformation.alertsFromJSONResponse(jsonResponse)
          return alerts ?? []
        } else {
          return []
        }
    }
  }
}

public struct CarParkInfo {
  public let identifier: String
  public let name: String
  public let availableSpaces: Int?
  public let totalSpaces: Int?
  public let lastUpdate: NSDate?
}

public class LocationInformation : NSObject {
  public let what3word: String?
  public let what3wordInfoURL: NSURL?
  
  public let transitStop: STKStopAnnotation?
  
  public let carParkInfo: CarParkInfo?
  
  private init(what3word: String?, what3wordInfoURL: String?, transitStop: STKStopAnnotation?, carParkInfo: CarParkInfo?) {
    self.what3word = what3word
    if let URLString = what3wordInfoURL {
      self.what3wordInfoURL = NSURL(string: URLString)
    } else {
      self.what3wordInfoURL = nil
    }
    
    self.transitStop = transitStop
    self.carParkInfo = carParkInfo
  }
  
  public var hasRealTime: Bool {
    if let carParkInfo = carParkInfo {
      return carParkInfo.availableSpaces != nil
    } else {
      return false
    }
  }
}

// MARK: - Protocol

@objc public protocol TKAlert {
  
  var icon: UIImage? { get }
  var title: String { get }
  var text: String? { get }
  var URL: String? { get }
  var lastUpdated: NSDate? { get }
  var sourceModel: AnyObject? { get }
  
}

// MARK: - Extensions

extension CarParkInfo {
  
  private init?(response: AnyObject?) {
    guard
      let JSON = response as? [String: AnyObject],
    let identifier = JSON["identifier"] as? String,
      let name = JSON["name"] as? String
      else {
        return nil
    }
    
    self.identifier = identifier
    self.name = name
    self.availableSpaces = JSON["availableSpaces"] as? Int
    self.totalSpaces = JSON["totalSpaces"] as? Int
    if let seconds = JSON["lastUpdate"] as? NSTimeInterval {
      self.lastUpdate = NSDate(timeIntervalSince1970: seconds)
    } else {
      self.lastUpdate = nil
    }
  }
  
}

extension LocationInformation {
  
  public convenience init?(response: AnyObject?) {
    guard let JSON = response as? [String: AnyObject] else {
      return nil
    }
    
    let details = JSON["details"] as? [String: AnyObject]
    let what3word = details?["w3w"] as? String
    let what3wordInfoURL = details?["w3wInfoURL"] as? String
    
    let stop: STKStopAnnotation?
    if let stopJSON = JSON["stop"] as? [String: AnyObject] {
      stop = TKParserHelper.simpleStopFromDictionary(stopJSON)
    } else {
      stop = nil
    }
    
    let carParkInfo = CarParkInfo(response: JSON["carPark"])
    
    self.init(what3word: what3word, what3wordInfoURL: what3wordInfoURL, transitStop: stop, carParkInfo: carParkInfo)
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
      success: { _, response in
        completion(LocationInformation(response: response))
      },
      failure: { _ in
        completion(nil)
      })
    
  }
  
}

