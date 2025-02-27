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
