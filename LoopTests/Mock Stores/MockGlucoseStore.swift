//
//  MockGlucoseStore.swift
//  LoopTests
//
//  Created by Anna Quinlan on 8/7/20.
//  Copyright © 2020 LoopKit Authors. All rights reserved.
//

import HealthKit
import LoopKit
@testable import Loop

class MockGlucoseStore: GlucoseStoreProtocol {
    
    init(for scenario: DosingTestScenario) {
        self.scenario = scenario // The store returns different effect values based on the scenario
        storedGlucose = loadHistoricGlucose(scenario: scenario)
    }
    
    let dateFormatter = ISO8601DateFormatter.localTimeDate()
    
    var scenario: DosingTestScenario

    var storedGlucose: [StoredGlucoseSample]?
    
    var latestGlucose: GlucoseSampleValue? {
        if let storedGlucose {
            return storedGlucose.last
        } else {
            return StoredGlucoseSample(
                sample: HKQuantitySample(
                    type: HKQuantityType.quantityType(forIdentifier: .bloodGlucose)!,
                    quantity: HKQuantity(unit: HKUnit.milligramsPerDeciliter, doubleValue: latestGlucoseValue),
                    start: glucoseStartDate,
                    end: glucoseStartDate
                )
            )
        }
    }
    
    var preferredUnit: HKUnit?
    
    var sampleType: HKSampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.bloodGlucose)!
    
    var delegate: GlucoseStoreDelegate?
    
    var managedDataInterval: TimeInterval?
    
    var healthKitStorageDelay = TimeInterval(0)

    var authorizationRequired: Bool = false
    
    var sharingDenied: Bool = false
    
    func authorize(toShare: Bool, read: Bool, _ completion: @escaping (HealthKitSampleStoreResult<Bool>) -> Void) {
        completion(.success(true))
    }
    
    func addGlucoseSamples(_ values: [NewGlucoseSample], completion: @escaping (Result<[StoredGlucoseSample], Error>) -> Void) {
        // Using the dose store error because we don't need to create GlucoseStore errors just for the mock store
        completion(.failure(DoseStore.DoseStoreError.configurationError))
    }
    
    func getGlucoseSamples(start: Date?, end: Date?, completion: @escaping (Result<[StoredGlucoseSample], Error>) -> Void) {
        completion(.success([latestGlucose as! StoredGlucoseSample]))
    }
    
    func generateDiagnosticReport(_ completion: @escaping (String) -> Void) {
        completion("")
    }
    
    func purgeAllGlucoseSamples(healthKitPredicate: NSPredicate, completion: @escaping (Error?) -> Void) {
        // Using the dose store error because we don't need to create GlucoseStore errors just for the mock store
        completion(DoseStore.DoseStoreError.configurationError)
    }
    
    func executeGlucoseQuery(fromQueryAnchor queryAnchor: GlucoseStore.QueryAnchor?, limit: Int, completion: @escaping (GlucoseStore.GlucoseQueryResult) -> Void) {
        // Using the dose store error because we don't need to create GlucoseStore errors just for the mock store
        completion(.failure(DoseStore.DoseStoreError.configurationError))
    }
    
    func counteractionEffects<Sample>(for samples: [Sample], to effects: [GlucoseEffect]) -> [GlucoseEffectVelocity] where Sample : GlucoseSampleValue {
        return [] // TODO: check if we'll ever want to test this
    }
    
    func getRecentMomentumEffect(_ completion: @escaping (_ effects: Result<[GlucoseEffect], Error>) -> Void) {
        if let storedGlucose {
            let samples = storedGlucose.filterDateRange(scenario.currentDate.addingTimeInterval(-GlucoseMath.momentumDataInterval), nil)
            completion(.success(samples.linearMomentumEffect()))
        } else {
            let fixture: [JSONDictionary] = loadFixture(momentumEffectToLoad)
            let dateFormatter = ISO8601DateFormatter.localTimeDate()

            return completion(.success(fixture.map {
                return GlucoseEffect(startDate: dateFormatter.date(from: $0["date"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue: $0["amount"] as! Double))
            }
                                      ))
        }
    }
    
    func getCounteractionEffects(start: Date, end: Date? = nil, to effects: [GlucoseEffect], _ completion: @escaping (_ effects: Result<[GlucoseEffectVelocity], Error>) -> Void) {
        if let storedGlucose {
            let samples = storedGlucose.filterDateRange(start, end)
            completion(.success(self.counteractionEffects(for: samples, to: effects)))
        } else {
            let fixture: [JSONDictionary] = loadFixture(counteractionEffectToLoad)
            let dateFormatter = ISO8601DateFormatter.localTimeDate()

            completion(.success(fixture.map {
                return GlucoseEffectVelocity(startDate: dateFormatter.date(from: $0["startDate"] as! String)!, endDate: dateFormatter.date(from: $0["endDate"] as! String)!, quantity: HKQuantity(unit: HKUnit(from: $0["unit"] as! String), doubleValue:$0["value"] as! Double))
            }))
        }
    }
}

extension MockGlucoseStore {
    public var bundle: Bundle {
        return Bundle(for: type(of: self))
    }

    public func loadFixture<T>(_ resourceName: String) -> T {
        let path = bundle.path(forResource: resourceName, ofType: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path)), options: []) as! T
    }

    public func loadHistoricGlucose(scenario: DosingTestScenario) -> [StoredGlucoseSample]? {
        if let url = bundle.url(forResource: scenario.fixturePrefix + "historic_glucose", withExtension: "json"),
           let data = try? Data(contentsOf: url)
        {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode([StoredGlucoseSample].self, from: data)
        } else {
            return nil
        }
    }
    
    var counteractionEffectToLoad: String {
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario computes counteraction effects from input data, does not used pre-canned effects")
        case .flatAndStable:
            return "flat_and_stable_counteraction_effect"
        case .highAndStable:
            return "high_and_stable_counteraction_effect"
        case .highAndRisingWithCOB:
            return "high_and_rising_with_cob_counteraction_effect"
        case .lowAndFallingWithCOB:
            return "low_and_falling_counteraction_effect"
        case .lowWithLowTreatment:
            return "low_with_low_treatment_counteraction_effect"
        case .highAndFalling:
            return "high_and_falling_counteraction_effect"
        }
    }
    
    var momentumEffectToLoad: String {
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario computes momentu effects from input data, does not used pre-canned effects")
        case .flatAndStable:
            return "flat_and_stable_momentum_effect"
        case .highAndStable:
            return "high_and_stable_momentum_effect"
        case .highAndRisingWithCOB:
            return "high_and_rising_with_cob_momentum_effect"
        case .lowAndFallingWithCOB:
            return "low_and_falling_momentum_effect"
        case .lowWithLowTreatment:
            return "low_with_low_treatment_momentum_effect"
        case .highAndFalling:
            return "high_and_falling_momentum_effect"
        }
    }
    
    var glucoseStartDate: Date {
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario uses actual glucose input data")
        case .flatAndStable:
            return dateFormatter.date(from: "2020-08-11T20:45:02")!
        case .highAndStable:
            return dateFormatter.date(from: "2020-08-12T12:39:22")!
        case .highAndRisingWithCOB:
            return dateFormatter.date(from: "2020-08-11T21:48:17")!
        case .lowAndFallingWithCOB:
            return dateFormatter.date(from: "2020-08-11T22:06:06")!
        case .lowWithLowTreatment:
            return dateFormatter.date(from: "2020-08-11T22:23:55")!
        case .highAndFalling:
            return dateFormatter.date(from: "2020-08-11T22:59:45")!
        }
    }
    
    var latestGlucoseValue: Double {
        switch scenario {
        case .liveCapture:
            fatalError("live capture scenario uses actual glucose input data")
        case .flatAndStable:
            return 123.42849966275706
        case .highAndStable:
            return 200.0
        case .highAndRisingWithCOB:
            return 129.93174411197853
        case .lowAndFallingWithCOB:
            return 75.10768374646841
        case .lowWithLowTreatment:
            return 81.22399763523448
        case .highAndFalling:
            return 200.0
        }
    }
}

