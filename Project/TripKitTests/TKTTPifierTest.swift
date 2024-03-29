//
//  TKTTPifierTest.swift
//  RioGo
//
//  Created by Adrian Schoenig on 23/06/2016.
//  Copyright © 2016 SkedGo. All rights reserved.
//

import XCTest

@testable import TripKit

class TKTTPifierTest: XCTestCase {

  var worker: TKTTPifier!
  
  override func setUp() {
    super.setUp()
    
    worker = TKTTPifier()
  }
  
  override func tearDown() {
    super.tearDown()
    
    worker = nil
  }
  
  func testListOrdering() {
    let list = [
      stay(),
      game(1, hour: 8),
      game(2, hour: 18),
      place(3, order: 1),
      place(4, order: 2),
      place(10),
    ]
    
    let _ = (1...100).map { _ in
      let sorted = list.shuffle().sort { $0.beforeInList($1) }
      XCTAssert(sorted ~= list)
    }
  }

  func testOverwrittenOrdering() {
    let list = [
      stay(),
      place(3, order: 1),
      game(1, hour: 8, order: 2),
      place(4, order: 3),
      game(2, hour: 18, order: 4),
      place(10),
    ]
    
    let _ = (1...100).map { _ in
      let sorted = list.shuffle().sort { $0.beforeInList($1) }
      XCTAssert(sorted ~= list)
    }
  }
  
  
  func testListSetWithPlaces() {
    let input = [
      stay(),
      place(1),
      place(2),
    ]
    
    let (list, set) = TKTTPifier.split(input)
    
    XCTAssertEqual(2, list.count)
    XCTAssertEqual(2, set.count)
    XCTAssert(list ~= [input[0], input[0]])
    XCTAssert(set  ~= [input[1], input[2]])
  }
  
  func testListSetWithSorted() {
    let input = [
      stay(),
      place(1, order: 1),
      place(2, order: 2),
      place(3),
    ]
    
    let (list, set) = TKTTPifier.split(input)
    
    XCTAssertEqual(4, list.count)
    XCTAssertEqual(1, set.count)
    XCTAssert(list ~= [input[0], input[1], input[2], input[0]])
    XCTAssert(set  ~= [input[3]])
  }
  

  func testListSetWithOneGame() {
    let input = [
      stay(),
      place(1),
      place(2),
      game(3, hour: 8)
    ]
    
    let (list, set) = TKTTPifier.split(input)
    
    XCTAssertEqual(3, list.count)
    XCTAssertEqual(2, set.count)
    XCTAssert(list ~= [input[0], input[3], input[0]])
    XCTAssert(set  ~= [input[1], input[2]])
  }

  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }

  private func stay() -> TKAgendaInputItem {
    let input = TestInput(id: 0, start: NSDate(), startFixed: false, order: 0, isStay: true)
    return .Event(input)
  }

  private func place(id: Int, order: Int? = nil) -> TKAgendaInputItem {
    let input = TestInput(id: id, start: NSDate(), startFixed: false, order: order, isStay: false)
    return .Event(input)
  }

  private func game(id: Int, hour: Int, order: Int? = nil) -> TKAgendaInputItem {
    let input = TestInput(id: id, start: NSDate(timeIntervalSinceNow: Double(hour) * 3600), startFixed: true, order: order, isStay: false)
    return .Event(input)
  }
  
  
  private class TestInput: NSObject, TKAgendaEventInputType {
    @objc let endDate: NSDate? = nil
    @objc let coordinate = CLLocationCoordinate2D(latitude: 5, longitude: 20)
    @objc let sourceModel: AnyObject? = nil
    
    @objc let startDate: NSDate?
    @objc let identifier: String?
    @objc let fixedOrder: NSNumber?
    @objc let timesAreFixed: Bool
    @objc let isStay: Bool
    
    init(id: Int, start: NSDate?, startFixed: Bool, order: Int?, isStay: Bool) {
      self.identifier = "\(id)"
      self.startDate = start
      self.timesAreFixed = startFixed
      self.fixedOrder = (order != nil) ? NSNumber(integer: order!) : nil
      self.isStay = isStay
    }
  }
}

extension CollectionType {
  /// Return a copy of `self` with its elements shuffled
  func shuffle() -> [Generator.Element] {
    var list = Array(self)
    list.shuffleInPlace()
    return list
  }
}

extension MutableCollectionType where Index == Int {
  /// Shuffle the elements of `self` in-place.
  mutating func shuffleInPlace() {
    // empty and single-element collections don't shuffle
    if count < 2 { return }
    
    for i in 0..<count - 1 {
      let j = Int(arc4random_uniform(UInt32(count - i))) + i
      guard i != j else { continue }
      swap(&self[i], &self[j])
    }
  }
}


func ~=(lhs: [TKAgendaInputItem], rhs: [TKAgendaInputItem]) -> Bool {
  guard lhs.count == rhs.count else {
    return false
  }
  
  for (left, right) in zip(lhs, rhs) {
    if !(left ~= right) {
      return false
    }
  }
  return true
}

func ~=(lhs: TKAgendaInputItem, rhs: TKAgendaInputItem) -> Bool {
  switch (lhs, rhs) {
  case (.Event(let left), .Event(let right)):
    return left ~= right
  case (.Trip, .Trip):
    return true
  default:
    return false
  }
}

func ~=(lhs: TKAgendaEventInputType, rhs: TKAgendaEventInputType) -> Bool {
  return lhs.equalsForAgenda(rhs)
}

func <(lhs: TKAgendaInputItem, rhs: TKAgendaInputItem) -> Bool {
  return lhs.beforeInList(rhs)
}

