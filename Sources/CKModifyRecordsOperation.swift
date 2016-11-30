//
//  CKModifyRecordsOperation.swift
//  OpenCloudKit
//
//  Created by Benjamin Johnson on 8/07/2016.
//
//

import Foundation

public enum CKRecordSavePolicy : Int {
    case IfServerRecordUnchanged
    case ChangedKeys
    case AllKeys
}

let CKErrorRetryAfterKey = "CKRetryAfter"
let CKErrorRedirectURLKey = "CKRedirectURL"
let CKPartialErrorsByItemIDKey: String = "CKPartialErrors"

struct CKSubscriptionFetchErrorDictionary {
    
    static let subscriptionIDKey = "subscriptionID"
    
    static let reasonKey = "reason"
    
    static let serverErrorCodeKey = "serverErrorCode"
    
    static let redirectURLKey = "redirectURL"
    
    let subscriptionID: String
    
    let reason: String
    
    let serverErrorCode: String
    
    let redirectURL: String?
    
    init?(dictionary: [String: Any]) {
        guard
        let subscriptionID = dictionary[CKSubscriptionFetchErrorDictionary.subscriptionIDKey] as? String,
        let reason = dictionary[CKSubscriptionFetchErrorDictionary.reasonKey] as? String,
        let serverErrorCode = dictionary[CKSubscriptionFetchErrorDictionary.serverErrorCodeKey] as? String else {
                return nil
        }
        
        self.subscriptionID = subscriptionID
        self.reason = reason
        self.serverErrorCode = serverErrorCode
        self.redirectURL = dictionary[CKSubscriptionFetchErrorDictionary.redirectURLKey] as? String
        
    }
}

struct CKRecordFetchErrorDictionary {
    
    static let recordNameKey = "recordName"
    static let reasonKey = "reason"
    static let serverErrorCodeKey = "serverErrorCode"
    static let retryAfterKey = "retryAfter"
    static let uuidKey = "uuid"
    static let redirectURLKey = "redirectURL"
    
    let recordName: String?
    let reason: String
    let serverErrorCode: String
    let retryAfter: NSNumber?
    let uuid: String?
    let redirectURL: String?
    
    init?(dictionary: [String: Any]) {
        
        guard  let reason = dictionary[CKRecordFetchErrorDictionary.reasonKey] as? String,
        let serverErrorCode = dictionary[CKRecordFetchErrorDictionary.serverErrorCodeKey] as? String  else {
                return nil
        }
        
        self.recordName = dictionary[CKRecordFetchErrorDictionary.recordNameKey] as? String
        self.reason = reason
        self.serverErrorCode = serverErrorCode
        
        self.uuid = dictionary[CKRecordFetchErrorDictionary.uuidKey] as? String
        
        
        self.retryAfter = (dictionary[CKRecordFetchErrorDictionary.retryAfterKey] as? NSNumber)
        self.redirectURL = dictionary[CKRecordFetchErrorDictionary.redirectURLKey] as? String
        
    }
}

public class CKModifyRecordsOperation: CKDatabaseOperation {

    public override init() {
        super.init()
    }
    
    public convenience init(recordsToSave records: [CKRecord]?, recordIDsToDelete recordIDs: [CKRecordID]?) {
        self.init()

        recordsToSave = records
        recordIDsToDelete = recordIDs
    }
    
    public var savePolicy: CKRecordSavePolicy = .IfServerRecordUnchanged
    
    public var recordsToSave: [CKRecord]?
    
    public var recordIDsToDelete: [CKRecordID]?
    
    var recordsByRecordIDs: [CKRecordID: CKRecord] = [:]
    
    /* Determines whether the batch should fail atomically or not. YES by default.
     This only applies to zones that support CKRecordZoneCapabilityAtomic. */
    public var isAtomic: Bool = false
    
    public var zoneID: CKRecordZoneID?
    
    /* Called repeatedly during transfer.
     It is possible for progress to regress when a retry is automatically triggered.
     */
    public var perRecordProgressBlock: ((CKRecord, Double) -> Swift.Void)?
    
    /* Called on success or failure for each record. */
    public var perRecordCompletionBlock: ((CKRecord?, NSError?) -> Swift.Void)?
    
    
    /*  This block is called when the operation completes.
     The [NSOperation completionBlock] will also be called if both are set.
     If the error is CKErrorPartialFailure, the error's userInfo dictionary contains
     a dictionary of recordIDs to errors keyed off of CKPartialErrorsByItemIDKey.
     This call happens as soon as the server has
     seen all record changes, and may be invoked while the server is processing the side effects
     of those changes.
     */
    public var modifyRecordsCompletionBlock: (([CKRecord]?, [CKRecordID]?, Error?) -> Swift.Void)?


    
    
    override func performCKOperation() {

        // Generate the CKOperation Web Service URL
        let request = CKModifyRecordsURLRequest(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete, isAtomic: isAtomic, database: database!, savePolicy: savePolicy, zoneID: zoneID)
        request.accountInfoProvider = CloudKit.shared.defaultAccount

        request.completionBlock = { (result) in
            // Check if cancelled
            if self.isCancelled {
                // Send Cancelled Error to CompletionBlock
                let cancelError = NSError(domain: CKErrorDomain, code: CKErrorCode.OperationCancelled.rawValue, userInfo: nil)
                self.modifyRecordsCompletionBlock?(nil, nil, cancelError)
            }
            switch result {
            case .error(let error):
                self.modifyRecordsCompletionBlock?(nil, nil, error.error)
            case .success(let dictionary):
                
                // Process Records
                if let recordsDictionary = dictionary["records"] as? [[String: Any]] {
                    // Parse JSON into CKRecords
                    for recordDictionary in recordsDictionary {
                        
                        
                        if let record = CKRecord(recordDictionary: recordDictionary) {
                            // Append Record
                            self.recordsByRecordIDs[record.recordID] = record
                            
                            // Call RecordCallback
                            self.perRecordCompletionBlock?(record, nil)
                            
                        } else if let recordFetchError = CKRecordFetchErrorDictionary(dictionary: recordDictionary) {
                            
                            // Create Error
                            let error = NSError(domain: CKErrorDomain, code: CKErrorCode.PartialFailure.rawValue, userInfo: [NSLocalizedDescriptionKey: recordFetchError.reason])
                            self.perRecordCompletionBlock?(nil, error)
                        } else {
                            
                            if let _ = recordDictionary["recordName"],
                                let _ = recordDictionary["deleted"] {
                                
                            } else {
                                fatalError("Couldn't resolve record or record fetch error dictionary")
                            }
                        }
                    }
                }
            }
            
            // Call the final completionBlock
            let recordIDs = Array(self.recordsByRecordIDs.keys)
            let records = Array(self.recordsByRecordIDs.values)
            self.modifyRecordsCompletionBlock?(records, recordIDs, nil)
            
            // Mark operation as complete
            self.finish(error: [])
            
        }
        
        request.performRequest()

        
        
        /*
        
        urlSessionTask = CKWebRequest(container: operationContainer).request(withURL: url, parameters: request) { (dictionary, error) in
            
            // Check if cancelled
            if self.isCancelled {
                // Send Cancelled Error to CompletionBlock
                let cancelError = NSError(domain: CKErrorDomain, code: CKErrorCode.OperationCancelled.rawValue, userInfo: nil)
                self.modifyRecordsCompletionBlock?(nil, nil, cancelError)
            }
            
            if let error = error {
                self.modifyRecordsCompletionBlock?(nil, nil, error)
                
            } else if let dictionary = dictionary {
                // Process Records
                if let recordsDictionary = dictionary["records"] as? [[String: Any]] {
                    // Parse JSON into CKRecords
                    for recordDictionary in recordsDictionary {
                        
                        
                        if let record = CKRecord(recordDictionary: recordDictionary) {
                            // Append Record
                            self.recordsByRecordIDs[record.recordID] = record
                            
                            // Call RecordCallback
                            self.perRecordCompletionBlock?(record, nil)
                            
                        } else if let recordFetchError = CKRecordFetchErrorDictionary(dictionary: recordDictionary) {
                            
                            // Create Error
                            let error = NSError(domain: CKErrorDomain, code: CKErrorCode.PartialFailure.rawValue, userInfo: [NSLocalizedDescriptionKey: recordFetchError.reason])
                            self.perRecordCompletionBlock?(nil, error)
                        } else {
                            
                            if let _ = recordDictionary["recordName"],
                            let _ = recordDictionary["deleted"] {
                                
                            } else {
                                fatalError("Couldn't resolve record or record fetch error dictionary")
                            }
                        }
                    }
                }
            }
            
            // Call the final completionBlock
            let recordIDs = Array(self.recordsByRecordIDs.keys)
            let records = Array(self.recordsByRecordIDs.values)
            self.modifyRecordsCompletionBlock?(records, recordIDs, nil)
                
            // Mark operation as complete
            self.finish(error: [])
            
        }
 
    }
    */

    }
}
