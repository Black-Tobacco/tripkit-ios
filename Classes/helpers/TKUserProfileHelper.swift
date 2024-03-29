//
//  TKUserProfileHelper.swift
//  TripGo
//
//  Created by Adrian Schoenig on 9/02/2016.
//  Copyright © 2016 SkedGo Pty Ltd. All rights reserved.
//

import Foundation

import SGCoreKit

private enum DefaultsKey: String {
  case SortedEnabled = "profileSortedModeIdentifiers"
  case Minimized = "profileMinimizedModeIdentifiers"
  case Hidden = "profileHiddenModeIdentifiers"
  case Disliked = "profileDislikedTransitMode"
}

public class TKUserProfileHelper: NSObject {
  public typealias Identifier = String
  
  //MARK: - Transport modes
  
  /**
  Overwrites user preferences for each non-nil value.
  */
  public class func updateTransportModesWithEnabledOrder(enabled: [Identifier]?, minimized: Set<Identifier>?, hidden: Set<Identifier>?)
  {
    let shared = NSUserDefaults.sharedDefaults()
    if let enabled = enabled {
      shared.setObject(enabled, forKey: DefaultsKey.SortedEnabled.rawValue)
    }
    if let minimized = minimized {
      shared.setObject(Array(minimized), forKey: DefaultsKey.Minimized.rawValue)
    }
    if let hidden = hidden {
      shared.setObject(Array(hidden), forKey: DefaultsKey.Hidden.rawValue)
    }
  }
  
  public class func modeIdentifierIsMinimized(modeIdentifier: Identifier) -> Bool {
    return minimizedModeIdentifiers.contains(modeIdentifier)
  }
  
  public class func setModeIdentifier(modeIdentifier: Identifier, toMinimized minimized: Bool) {
    update(minimizedModeIdentifiers, forKey: .Minimized, modeIdentifier: modeIdentifier, include: minimized)
  }
  
  public class func modeIdentifierIsHidden(modeIdentifier: Identifier) -> Bool {
    return hiddenModeIdentifiers.contains(modeIdentifier)
  }
  
  public class func setModeIdentifier(modeIdentifier: Identifier, toHidden hidden: Bool) {
    update(hiddenModeIdentifiers, forKey: .Hidden, modeIdentifier: modeIdentifier, include: hidden)
  }
  
  private class func update(identifiers: Set<Identifier>, forKey key: DefaultsKey, modeIdentifier: Identifier, include: Bool) {
    var modes = identifiers
    if include {
      modes.insert(modeIdentifier)
    } else {
      modes.remove(modeIdentifier)
    }
    NSUserDefaults.sharedDefaults().setObject(Array(modes), forKey: key.rawValue)
  }
  
  public class func orderedEnabledModeIdentifiersForAvailableModeIdentifiers(available: [Identifier]) -> [Identifier] {
    let hidden = hiddenModeIdentifiers
    let ordered = available.filter { !hidden.contains($0) }
    
    // Once we let users sort them again, do something like this:
//    if let sorted = NSUserDefaults.sharedDefaults().objectForKey(DefaultsKey.SortedEnabled.rawValue) as? [Identifier] {
//      ordered.sortInPlace { sorted.indexOf($0) < sorted.indexOf($1) }
//    }
    
    return ordered
  }

  public class func maximizedModeIdentifiers(available: [Identifier]) -> Set<Identifier> {
    let hidden = hiddenModeIdentifiers
    let minimized = minimizedModeIdentifiers
    let ordered = available.filter { !hidden.contains($0) && !minimized.contains($0) }
    return Set(ordered)
  }
  
  
  public class var minimizedModeIdentifiers: Set<Identifier> {
    if let minimized = NSUserDefaults.sharedDefaults().objectForKey(DefaultsKey.Minimized.rawValue) as? [Identifier] {
      return Set(minimized)
    } else {
      return [SVKTransportModeIdentifierMotorbike, SVKTransportModeIdentifierTaxi, SVKTransportModeIdentifierWalking]
    }
  }
  
  public class var hiddenModeIdentifiers: Set<Identifier> {
    if let hidden = NSUserDefaults.sharedDefaults().objectForKey(DefaultsKey.Hidden.rawValue) as? [Identifier] {
      return Set(hidden)
    } else {
      return [SVKTransportModeIdentifierSchoolBuses]
    }
  }
  
  //MARK: - Preferred transit modes
  
  public class func transitModeIsPreferred(identifier: Identifier) -> Bool {
    return !dislikedTransitModes.contains(identifier)
  }
  
  public class func setTransitMode(identifier: Identifier, asPreferred preferred: Bool) {
    var modes = dislikedTransitModes
    if preferred {
      if let index = modes.indexOf(identifier) {
        modes.removeAtIndex(index)
      }
    } else {
      modes.append(identifier)
    }
    NSUserDefaults.sharedDefaults().setObject(modes, forKey: DefaultsKey.Disliked.rawValue)
  }

  public class var dislikedTransitModes: [Identifier] {
    if let disliked = NSUserDefaults.sharedDefaults().objectForKey(DefaultsKey.Disliked.rawValue) as? [Identifier] {
      return disliked
    } else {
      return []
    }
  }
  
  
}
