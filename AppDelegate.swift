import UIKit
import BackgroundTasks

class AppDelegate: UIResponder, UIApplicationDelegate, URLSessionDelegate, URLSessionTaskDelegate {

    var window: UIWindow?
    var uploadTimer: Timer?
    var backgroundSession: URLSession?

    // Method to upload data to S3 (No need for a file path)
    @objc func uploadDataToS3() {
        // Use your existing function to fetch and upload the health data
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
        var nextUploadTime = calendar.date(bySettingHour: 10, minute: 15, second: 0, of: currentTime)

        if let nextTime = nextUploadTime, nextTime < currentTime {
            nextUploadTime = calendar.date(byAdding: .day, value: 1, to: nextTime)
        }

        if let nextUploadTime = nextUploadTime {
            let timeInterval = nextUploadTime.timeIntervalSince(currentTime)

            uploadTimer = Timer.scheduledTimer(timeInterval: timeInterval, target: self, selector: #selector(uploadDataToS3), userInfo: nil, repeats: true)
        }
    }

    // When the app is launched, schedule the task
    func applicationDidBecomeActive(_ application: UIApplication) {
        scheduleDailyUpload()
    }

    // Handle when the app is sent to the background
    func applicationDidEnterBackground(_ application: UIApplication) {
        // In background, create a background session to handle upload task
        let config = URLSessionConfiguration.background(withIdentifier: "com.yourApp.backgroundUpload")
        backgroundSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Schedule a background task
        scheduleBackgroundUploadTask()
    }

    // Handle when the app comes back to the foreground
    func applicationWillEnterForeground(_ application: UIApplication) {
        scheduleDailyUpload()
    }

    // Handle background upload completion or failure
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Background upload failed with error: \(error.localizedDescription)")
        } else {
            print("Background upload completed successfully.")
        }
    }

    // Handle the upload progress (optional)
    private func urlSession(_ session: URLSession, uploadTask: URLSessionUploadTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        print("Upload progress: \(totalBytesSent) / \(totalBytesExpectedToSend) bytes sent.")
    }

    // This method is called when the app is terminated and a background upload task is still running
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        backgroundSession?.getTasksWithCompletionHandler { (_, _, uploadTasks) in
            if uploadTasks.count == 0 {
                completionHandler() // When the upload task is done, call the completion handler
            }
        }
    }

    // Schedule a background task for uploading
    func scheduleBackgroundUploadTask() {
        let request = BGProcessingTaskRequest(identifier: "com.yourApp.backgroundUploadTask")
        request.requiresNetworkConnectivity = true // Ensure the task requires network connectivity
        request.requiresExternalPower = false // Optional: Set to true if you want the task to run only when the device is charging

        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background upload task scheduled successfully.")
        } catch {
            print("Could not schedule background upload task: \(error)")
        }
    }

    // Handle the background task when it is executed
    func handleBackgroundUploadTask(task: BGTask) {
        scheduleBackgroundUploadTask() // Reschedule the task for the next day

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        task.expirationHandler = {
            queue.cancelAllOperations()
        }

        queue.addOperation {
            self.uploadDataToS3()
            task.setTaskCompleted(success: true)
        }
    }

    // Register the background task when the app finishes launching
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.yourApp.backgroundUploadTask", using: nil) { task in
            self.handleBackgroundUploadTask(task: task as! BGProcessingTask)
        }
        return true
    }
}
