import UIKit
import BackgroundTasks
import HealthKit

class AppDelegate: NSObject, UIApplicationDelegate {

    let backgroundTaskIdentifier = "com.yourapp.healthdata.upload"
    let healthStore = HKHealthStore()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleHealthDataUpload(task: task as! BGAppRefreshTask)
        }
        scheduleDailyUpload()
        requestHealthKitAuthorization()
        return true
    }
    
    func requestHealthKitAuthorization() {
        let dataTypesToRead: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]
        healthStore.requestAuthorization(toShare: nil, read: dataTypesToRead) { success, error in
            if success {
                self.enableBackgroundDeliveryForHealthData()
            } else if let error = error {
                print("HealthKit authorization failed: \(error)")
            }
        }
    }

    func enableBackgroundDeliveryForHealthData() {
        let dataTypes = [
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .appleStandTime)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.quantityType(forIdentifier: .height)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        for dataType in dataTypes {
            healthStore.enableBackgroundDelivery(for: dataType, frequency: .immediate) { success, error in
                if success {
                    print("Enabled background delivery for \(dataType.identifier)")
                } else if let error = error {
                    print("Failed to enable background delivery for \(dataType.identifier): \(error)")
                }
            }
        }
    }

    func scheduleDailyUpload() {
        print("[AppDelegate] Scheduling daily background task.")
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 24*60*60)
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[AppDelegate] Daily background task scheduled.")
        } catch {
            print("[AppDelegate] Could not schedule daily background task: \(error.localizedDescription)")
        }
    }

    func handleHealthDataUpload(task: BGAppRefreshTask) {
        print("[AppDelegate] Background task triggered.")
        Task {
            let success = await HealthStoreManager.shared.fetchAndUploadHealthData()
            if success {
                print("[AppDelegate] Upload completed successfully.")
                task.setTaskCompleted(success: true)
                self.scheduleDailyUpload()
            } else {
                print("[AppDelegate] Upload failed.")
                task.setTaskCompleted(success: false)
            }
        }
        task.expirationHandler = {
            print("[AppDelegate] Background task expired.")
            task.setTaskCompleted(success: false)
        }
    }
}

/*
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate, URLSessionDelegate, URLSessionTaskDelegate {
    var window: UIWindow?
    var uploadTimer: Timer?
    var backgroundSession: URLSession?
    
    @objc func uploadDataToS3() {
        HealthStoreManager.shared.fetchAndUploadHealthData { success in
            if success {
                print("Data uploaded successfully!")
            } else {
                print("Failed to upload data.")
            }
        }
    }
    
    func scheduleDailyUpload() {
        let calendar = Calendar.current
        let currentTime = Date()
        var nextUploadTime = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: currentTime)
        if let nextTime = nextUploadTime, nextTime < currentTime {
            nextUploadTime = calendar.date(byAdding: .day, value: 1, to: nextTime)
        }
        if let nextUploadTime = nextUploadTime {
            let timeInterval = nextUploadTime.timeIntervalSince(currentTime)
            uploadTimer = Timer.scheduledTimer(timeInterval: timeInterval, target: self, selector: #selector(uploadDataToS3), userInfo: nil, repeats: true)
        }
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        scheduleDailyUpload()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        let config = URLSessionConfiguration.background(withIdentifier: "com.yourApp.backgroundUpload")
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        uploadDataToS3()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Background upload failed with error: \(error.localizedDescription)")
        } else {
            print("Background upload completed successfully.")
        }
    }
    
    private func urlSession(_ session: URLSession, uploadTask: URLSessionUploadTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("Upload progress: \(totalBytesSent) / \(totalBytesExpectedToSend) bytes sent.")
    }
    
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSession?.getTasksWithCompletionHandler { (_, _, uploadTasks) in
            if uploadTasks.count == 0 {
                completionHandler()
            }
        }
    }
}
*/
