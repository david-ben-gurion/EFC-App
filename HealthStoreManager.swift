import HealthKit
import AWSCore
import AWSS3
import AuthenticationServices
import UIKit
import Foundation

class AppleSignInProvider: NSObject, AWSIdentityProviderManager {
    var idToken: String
    init(idToken: String) {
        self.idToken = idToken
    }
    func logins() -> AWSTask<NSDictionary> {
        return AWSTask(result: [ "appleid.apple.com": idToken ] as NSDictionary)
    }
}

class HealthStoreManager: NSObject, ASAuthorizationControllerDelegate, ObservableObject {
    static let shared = HealthStoreManager()
    var healthStore: HKHealthStore?
    private var observerQuery: HKObserverQuery?
    @Published var isAuthenticated: Bool = false
    override init() {
        super.init()
        // Observe when the app becomes active
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        if let tokenString = UserDefaults.standard.string(forKey: "appleSignInToken") {
            isAuthenticated = true
            reinitializeAWSConfiguration(with: tokenString)
        } else {
            isAuthenticated = false
        }
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }
    // Called when app becomes active
    @objc func appDidBecomeActive() {
        print("App has come to the foreground, checking for token expiry...")
        if let tokenString = UserDefaults.standard.string(forKey: "appleSignInToken") {
            if isAppleTokenExpiringSoon(tokenString: tokenString) {
                print("Token is expired or expiring soon, re-authenticating user...")
                signInWithApple()
            } else {
                print("Token is still valid, refreshing AWS credentials.")
                reinitializeAWSConfiguration(with: tokenString)
            }
        } else {
            print("No token found, user might need to sign in.")
        }
    }
    func isAppleTokenExpiringSoon(tokenString: String) -> Bool {
        guard let expirationDate = getTokenExpirationDate(from: tokenString) else {
            return true // Treat as expired if we can't decode
        }
        let currentTime = Date()
        let timeIntervalToExpiration = expirationDate.timeIntervalSince(currentTime)
        // Check if the token expires within the next hour
        return timeIntervalToExpiration < 3600 // 3600 seconds = 1 hour
    }
    func getTokenExpirationDate(from token: String) -> Date? {
        // Split the token into its 3 parts: header, payload, and signature
        let segments = token.split(separator: ".")
        guard segments.count == 3 else {
            print("Invalid token")
            return nil
        }
        // Base64 decode the payload (second part of the token)
        let payloadSegment = String(segments[1])
        guard let payloadData = base64UrlDecode(payloadSegment),
              let json = try? JSONSerialization.jsonObject(with: payloadData, options: []),
              let payload = json as? [String: Any] else {
            print("Invalid payload data")
            return nil
        }
        // Extract the "exp" field from the payload (Unix timestamp)
        if let expirationTimestamp = payload["exp"] as? Double {
            return Date(timeIntervalSince1970: expirationTimestamp)
        } else {
            print("Expiration time not found")
            return nil
        }
    }
    // Helper function to Base64 URL Decode the JWT payload
    func base64UrlDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }
    func reinitializeAWSConfiguration(with tokenString: String) {
        if isAppleTokenExpiringSoon(tokenString: tokenString) {
            print("Token is expired or expiring soon in AWS configuration, triggering re-authentication.")
            signInWithApple()
            return
        }
        let provider = AppleSignInProvider(idToken: tokenString)
        let credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: .APSoutheast2,
            identityPoolId: "ap-southeast-2:e603f586-d00d-4bd7-ab36-cd453a75171d",
            identityProviderManager: provider
        )
        print("Clearing AWS credentials keychain.")
        credentialsProvider.clearKeychain()
        let configuration = AWSServiceConfiguration(
            region: .APSoutheast2,
            credentialsProvider: credentialsProvider
        )
        AWSServiceManager.default().defaultServiceConfiguration = configuration
        // Force credentials refresh
        refreshAWSCredentials()
    }
    func signInWithApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.performRequests()
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            return
        }
        // Store token in UserDefaults for future reference
        UserDefaults.standard.set(tokenString, forKey: "appleSignInToken")
        // Clear AWS credentials before reinitializing the configuration
        if let credentialsProvider = AWSServiceManager.default().defaultServiceConfiguration?.credentialsProvider as? AWSCognitoCredentialsProvider {
            credentialsProvider.clearKeychain()
        }
        // Reinitialize AWS configuration after successful sign-in
        reinitializeAWSConfiguration(with: tokenString)
        // Explicitly refresh AWS credentials
        refreshAWSCredentials()
        // Notify that the user is authenticated
        DispatchQueue.main.async {
            self.isAuthenticated = true
        }
    }
    func refreshAWSCredentials() {
        guard let credentialsProvider = AWSServiceManager.default().defaultServiceConfiguration?.credentialsProvider as? AWSCognitoCredentialsProvider else {
            print("No AWS credentials provider found.")
            return
        }
        // Explicitly refresh the credentials by calling getIdentityId
        credentialsProvider.clearKeychain()
        credentialsProvider.getIdentityId().continueWith { task in
            if let error = task.error {
                print("Failed to refresh AWS credentials: \(error.localizedDescription)")
            } else {
                print("AWS credentials refreshed successfully. Identity ID: \(String(describing: task.result))")
                // Optionally: trigger the upload to S3 here after successful credential refresh
            }
            return nil
        }
    }
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        print("Apple Sign-In failed: \(error.localizedDescription)")
    }
    // ASAuthorizationControllerPresentationContextProviding method
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            fatalError("No window scene available")
        }
        return windowScene.windows.first { $0.isKeyWindow } ?? UIWindow()
    }
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let healthStore = healthStore else { return completion(false) }
        // Define HealthKit data types
        let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let workoutType = HKObjectType.workoutType()
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let basalEnergyType = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned)!
        let standTimeType = HKObjectType.quantityType(forIdentifier: .appleStandTime)!
        let distanceWalkingRunningType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let restingHeartRateType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
        let exerciseTimeType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
        let flightsClimbedType = HKQuantityType.quantityType(forIdentifier: .flightsClimbed)!
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        // Set of data types to read
        let healthKitTypesToRead: Set<HKObjectType> = [
            stepCountType, sleepType, workoutType,
            heartRateType, activeEnergyType, basalEnergyType,
            standTimeType, distanceWalkingRunningType,
            restingHeartRateType, exerciseTimeType,
            flightsClimbedType, heightType,
            weightType// Include distanceWalkingRunningType here
        ]
        healthStore.requestAuthorization(toShare: nil, read: healthKitTypesToRead) { (success, error) in
            if let error = error {
                print("Error requesting HealthKit authorization: \(error.localizedDescription)")
            }
            completion(success)
        }
    }
    func fetchStepCount(completion: @escaping (Double) -> Void) {
        guard let healthStore = healthStore else { return completion(0.0) }
        let stepCountType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepCountType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let result = result, let sum = result.sumQuantity() else {
                completion(0.0)
                return
            }
            let stepCount = sum.doubleValue(for: HKUnit.count())
            completion(stepCount)
        }
        healthStore.execute(query)
    }
    func fetchSleepData(completion: @escaping ([String: (startTime: Date, endTime: Date, durationInMinutes: Double)]) -> Void) {
        guard let healthStore = healthStore else {
            completion([:])
            return
        }
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var startDate = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        var components = Calendar.current.dateComponents([.year, .month, .day], from: startDate)
        components.hour = 18 // 6 PM
        startDate = Calendar.current.date(from: components)!
        var endDate = Date()
        components = Calendar.current.dateComponents([.year, .month, .day], from: endDate)
        components.hour = 18 // 6 PM
        endDate = Calendar.current.date(from: components)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { query, results, error in
            guard let results = results as? [HKCategorySample], error == nil else {
                completion([:])
                return
            }
            // Filter samples to include only those from the Apple Watch based on source name
            let appleWatchSamples = results.filter { sample in
                let sourceName = sample.sourceRevision.source.name
                return sourceName.contains("Watch") || sourceName.contains("Health") || sourceName.contains("Connect")
            }
            var sleepData: [String: (startTime: Date, endTime: Date, durationInMinutes: Double)] = [
                "In Bed": (startTime: Date.distantPast, endTime: Date.distantPast, durationInMinutes: 0.0),
                "REM Sleep": (startTime: Date.distantPast, endTime: Date.distantPast, durationInMinutes: 0.0),
                "Core Sleep": (startTime: Date.distantPast, endTime: Date.distantPast, durationInMinutes: 0.0),
                "Deep Sleep": (startTime: Date.distantPast, endTime: Date.distantPast, durationInMinutes: 0.0),
                "Awake": (startTime: Date.distantPast, endTime: Date.distantPast, durationInMinutes: 0.0)
            ]
            // Helper function to update sleep data
            func updateSleepData(for stage: String, start: Date, end: Date) {
                let duration = end.timeIntervalSince(start) / 60
                if sleepData[stage]!.startTime == Date.distantPast {
                    sleepData[stage] = (startTime: start, endTime: end, durationInMinutes: duration)
                } else {
                    sleepData[stage]!.endTime = end
                    sleepData[stage]!.durationInMinutes += duration
                }
            }
            for result in appleWatchSamples {
                let sleepState = self.getSleepState(from: result)
                let sleepStart = result.startDate
                let sleepEnd = result.endDate
                let validStart = max(sleepStart, startDate)
                let validEnd = min(sleepEnd, endDate)
                if validStart < validEnd {
                    updateSleepData(for: sleepState, start: validStart, end: validEnd)
                }
            }
            completion(sleepData)
        }
        healthStore.execute(query)
    }
    func getSleepState(from sample: HKCategorySample) -> String {
        switch sample.value {
        case HKCategoryValueSleepAnalysis.inBed.rawValue:
            return "In Bed"
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
            return "REM Sleep"
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
            return "Core Sleep"
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
            return "Deep Sleep"
        case HKCategoryValueSleepAnalysis.awake.rawValue:
            return "Awake"
        default:
            return "Unknown"
        }
    }
    func uploadDataToS3(
        stepCount: Double,
        sleepData: [String: (startTime: Date, endTime: Date, durationInMinutes: Double)],
        workoutData: [Workout],
        heartRateData: [HeartRateSample],
        restingHeartRateData: [RestingHeartRateSample],
        activeEnergyData: [ActiveEnergySample],
        basalEnergyData: [BasalEnergySample],
        standTimeData: [StandTimeSample],
        distanceData: [DistanceSample],
        exerciseTimeData: [ExerciseTimeSample],
        flightsClimbedData: [FlightsClimbedSample],
        heightData: Double?,
        weightData: Double?,
        userName: String
    ) {
        let roundedStepCount = Int(stepCount)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        let uploadDate = Date() // Capture the current date and time for the upload
        let formattedUploadDate = dateFormatter.string(from: uploadDate) // Format the upload date
        // Format sleep data
        let formattedSleepData = sleepData.compactMap { (stage, data) -> [String: String]? in
            guard data.durationInMinutes > 0 else { return nil }
            let hoursPart = Int(data.durationInMinutes) / 60
            let minutesPart = Int(data.durationInMinutes) % 60
            return [
                "Stage": stage,
                "Start Time": dateFormatter.string(from: data.startTime),
                "End Time": dateFormatter.string(from: data.endTime),
                "Duration": "\(hoursPart)h \(minutesPart)m"
            ]
        }
        // Format active energy data
        let formattedActiveEnergyData = activeEnergyData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Active Energy (kcal)": "\(sample.activeEnergy)"
            ]
        }
        // Format basal energy data
        let formattedBasalEnergyData = basalEnergyData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Basal Energy (kcal)": "\(sample.basalEnergy)"
            ]
        }
        // Format workout data
        let formattedWorkoutData = workoutData.map { workout in
            return [
                "Type": workout.type,
                "Start Time": dateFormatter.string(from: workout.startTime),
                "End Time": dateFormatter.string(from: workout.endTime),
                "Duration (minutes)": "\(Int(workout.duration)) min",
                "Total Energy Burned (kcal)": "\(workout.totalEnergyBurned) kcal",
                "Total Distance (m)": "\(workout.totalDistance) m"
            ]
        }
        // Format heart rate data
        let formattedHeartRateData = heartRateData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Heart Rate (bpm)": "\(sample.heartRate)"
            ]
        }
        // Format resting heart rate data
        let formattedRestingHeartRateData = restingHeartRateData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Resting Heart Rate (bpm)": "\(sample.restingHeartRate)"
            ]
        }
        // Format stand time data
        let formattedStandTimeData = standTimeData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Stand Time (minutes)": "\(sample.standTime)"
            ]
        }
        // Format distance data
        let formattedDistanceData = distanceData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Distance (km)": "\(sample.distance)"
            ]
        }
        // Format exercise time data
        let formattedExerciseTimeData = exerciseTimeData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Exercise Time (minutes)": "1.0"
            ]
        }
        // Format flights climbed data
        let formattedFlightsClimbedData = flightsClimbedData.map { sample in
            return [
                "Start Time": dateFormatter.string(from: sample.startDate),
                "End Time": dateFormatter.string(from: sample.endDate),
                "Flights Climbed": "\(sample.flightsClimbed)"
            ]
        }
        // Format height data
        let formattedHeightData: [String: Any] = [
            "Height (cm)": heightData.map { "\($0)" } ?? "No height data available"
        ]
        // Format weight data
        let formattedWeightData: [String: Any] = [
            "Weight (kg)": weightData.map { "\($0)" } ?? "No weight data available"
        ]
        // Construct the JSON payload
        let json: [String: Any] = [
            "User Name": userName,
            "Steps Data": roundedStepCount,
            "Upload Date": formattedUploadDate, // Add the upload date here
            "Sleep Data": formattedSleepData.isEmpty ? ["Message": "No sleep data available"] : formattedSleepData,
            "Workout Data": formattedWorkoutData.isEmpty ? ["Message": "No workout data available"] : formattedWorkoutData,
            "Heart Rate Data": formattedHeartRateData.isEmpty ? ["Message": "No heart rate data available"] : formattedHeartRateData,
            "Resting Heart Rate Data": formattedRestingHeartRateData.isEmpty ? ["Message": "No resting heart rate data available"] : formattedRestingHeartRateData,
            "Active Energy Data": formattedActiveEnergyData.isEmpty ? ["Message": "No active energy data available"] : formattedActiveEnergyData,
            "Resting Energy Data": formattedBasalEnergyData.isEmpty ? ["Message": "No basal energy data available"] : formattedBasalEnergyData,
            "Stand Time Data": formattedStandTimeData.isEmpty ? ["Message": "No stand time data available"] : formattedStandTimeData,
            "Distance Data": formattedDistanceData.isEmpty ? ["Message": "No distance data available"] : formattedDistanceData,
            "Exercise Minutes Data": formattedExerciseTimeData.isEmpty ? ["Message": "No exercise time data available"] : formattedExerciseTimeData,
            "Flights Climbed Data": formattedFlightsClimbedData.isEmpty ? ["Message": "No flights climbed data available"] : formattedFlightsClimbedData,
            "Height Data": formattedHeightData,
            "Weight Data": formattedWeightData
        ]
        // Convert dictionary to JSON data
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted) else {
            print("Failed to convert dictionary to JSON")
            return
        }
        // Create a file name with date only
        let dateFormatterForFileName = DateFormatter()
        dateFormatterForFileName.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatterForFileName.string(from: Date())
        let fileName = "\(dateString).json"
        // Simulate directory structure using the userName
        let directoryPath = userName.lowercased()
        let s3Key = "\(directoryPath)/\(fileName)"
        // Set up AWS S3 client and upload request
        let s3 = AWSS3.default()
        let putObjectRequest = AWSS3PutObjectRequest()!
        putObjectRequest.bucket = "healthkit-test"
        putObjectRequest.key = s3Key
        putObjectRequest.body = data
        putObjectRequest.contentLength = NSNumber(value: data.count)
        putObjectRequest.contentType = "application/json"
        print("Uploading file with size: \(data.count) bytes and filename: \(s3Key)")
        s3.putObject(putObjectRequest).continueWith { task in
            if let error = task.error {
                print("Failed to upload health data to S3: \(error)")
            } else {
                print("Successfully uploaded health data to S3 with filename: \(s3Key)")
            }
            return nil
        }
    }
    func fetchAndUploadHealthData() async -> Bool {
        guard let userName = UserDefaults.standard.string(forKey: "userName") else {
            print("Username not found")
            return false
        }
        let authorizationSuccess = await requestAuthorization()
        guard authorizationSuccess else {
            print("Failed to get HealthKit authorization")
            return false
        }
        
        async let stepCount = fetchStepCount()
        async let sleepData = fetchSleepData()
        async let workoutData = fetchWorkoutData()
        async let heartRateData = fetchHeartRateData()
        async let restingHeartRateData = fetchRestingHeartRateData()
        async let activeEnergyData = fetchActiveEnergyData()
        async let basalEnergyData = fetchBasalEnergyData()
        async let standTimeData = fetchStandTimeData()
        async let distanceData = fetchWalkingRunningDistanceData()
        async let exerciseTimeData = fetchExerciseTimeData()
        async let flightsClimbedData = fetchFlightsClimbedData()
        async let heightInCentimeters = fetchLatestHeightData()
        async let weightInKilograms = fetchLatestWeightData()

        do {
            let (
                stepCount,
                sleepData,
                workoutData,
                heartRateData,
                restingHeartRateData,
                activeEnergyData,
                basalEnergyData,
                standTimeData,
                distanceData,
                exerciseTimeData,
                flightsClimbedData,
                heightInCentimeters,
                weightInKilograms
            ) = try await (
                stepCount,
                sleepData,
                workoutData,
                heartRateData,
                restingHeartRateData,
                activeEnergyData,
                basalEnergyData,
                standTimeData,
                distanceData,
                exerciseTimeData,
                flightsClimbedData,
                heightInCentimeters,
                weightInKilograms
            )
    
            uploadDataToS3(
                stepCount: stepCount,
                sleepData: sleepData,
                workoutData: workoutData,
                heartRateData: heartRateData,
                restingHeartRateData: restingHeartRateData,
                activeEnergyData: activeEnergyData,
                basalEnergyData: basalEnergyData,
                standTimeData: standTimeData,
                distanceData: distanceData,
                exerciseTimeData: exerciseTimeData,
                flightsClimbedData: flightsClimbedData,
                heightData: heightInCentimeters,
                weightData: weightInKilograms,
                userName: userName
            )
            
            return true
        } catch {
            print("Failed to fetch health data: \(error)")
            return false
        }
    }
    func startObservingHealthKitChanges() {
        guard let healthStore = healthStore else { return }
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let stepPredicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date())
        let sleepPredicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date())
        let stepQuery = HKObserverQuery(sampleType: stepType, predicate: stepPredicate) { _, completionHandler, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .healthDataUpdated, object: nil)
            }
            completionHandler()
        }
        let sleepQuery = HKObserverQuery(sampleType: sleepType, predicate: sleepPredicate) { _, completionHandler, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .healthDataUpdated, object: nil)
            }
            completionHandler()
        }
        healthStore.execute(stepQuery)
        healthStore.execute(sleepQuery)
        observerQuery = stepQuery // Keeping reference to observerQuery if needed for removal later
    }
    func fetchWorkoutData(completion: @escaping ([Workout]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let workoutType = HKObjectType.workoutType()
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { query, results, error in
            guard let results = results as? [HKWorkout], error == nil else {
                completion([])
                return
            }
            var workoutDetails: [Workout] = []
            for workout in results {
                let type = workout.workoutActivityType.name
                let duration = workout.duration / 60 // Convert to minutes
                let startDate = workout.startDate
                let endDate = workout.endDate
                let totalEnergyBurned = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()) ?? 0.0
                let totalDistance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0.0
                // Create a Workout instance
                let workoutData = Workout(
                    type: type,
                    duration: duration,
                    startTime: startDate,
                    endTime: endDate,
                    totalEnergyBurned: totalEnergyBurned,
                    totalDistance: totalDistance
                )
                workoutDetails.append(workoutData)
            }
            // Call the completion handler with the array of Workout objects
            completion(workoutDetails)
        }
        healthStore.execute(query)
    }
    func fetchHeartRateData(completion: @escaping ([HeartRateSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let heartRateData = results.map { sample in
                HeartRateSample(startDate: sample.startDate, endDate: sample.endDate, heartRate: sample.quantity.doubleValue(for: HKUnit(from: "count/min")))
            }
            completion(heartRateData)
        }
        healthStore.execute(query)
    }
    func fetchExerciseTimeData(completion: @escaping ([ExerciseTimeSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: exerciseType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let exerciseTimeData = results.map { sample in
                ExerciseTimeSample(startDate: sample.startDate, endDate: sample.endDate, exerciseTime: sample.quantity.doubleValue(for: HKUnit.hour()))
            }
            completion(exerciseTimeData)
        }
        healthStore.execute(query)
    }
    func fetchRestingHeartRateData(completion: @escaping ([RestingHeartRateSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let restingHeartRateType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: restingHeartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let restingHeartRateData = results.map { sample in
                RestingHeartRateSample(startDate: sample.startDate, endDate: sample.endDate, restingHeartRate: sample.quantity.doubleValue(for: HKUnit(from: "count/min")))
            }
            completion(restingHeartRateData)
        }
        healthStore.execute(query)
    }
    func fetchActiveEnergyData(completion: @escaping ([ActiveEnergySample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: activeEnergyType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let activeEnergyData = results.map { sample in
                ActiveEnergySample(
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    activeEnergy: sample.quantity.doubleValue(for: .kilocalorie())
                )
            }
            completion(activeEnergyData)
        }
        healthStore.execute(query)
    }
    func fetchBasalEnergyData(completion: @escaping ([BasalEnergySample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let basalEnergyType = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: basalEnergyType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let basalEnergyData = results.map { sample in
                BasalEnergySample(
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    basalEnergy: sample.quantity.doubleValue(for: .kilocalorie())
                )
            }
            completion(basalEnergyData)
        }
        healthStore.execute(query)
    }
    func fetchStandTimeData(completion: @escaping ([StandTimeSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let standTimeType = HKObjectType.quantityType(forIdentifier: .appleStandTime)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: standTimeType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let standTimeData = results.map { sample in
                StandTimeSample(
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    standTime: sample.quantity.doubleValue(for: .hour()) * 60 // Convert hours to minutes
                )
            }
            completion(standTimeData)
        }
        healthStore.execute(query)
    }
    func fetchWalkingRunningDistanceData(completion: @escaping ([DistanceSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        // Set start and end dates to today's date (from midnight to now)
        let startDate = Calendar.current.startOfDay(for: Date()) // Midnight of today
        let endDate = Date() // Current time
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: distanceType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([]) // Return an empty array in case of error
                return
            }
            // Map the results into a custom struct
            let distanceData = results.map { sample in
                DistanceSample(
                    startDate: sample.startDate,
                    endDate: sample.endDate,
                    distance: sample.quantity.doubleValue(for: .meterUnit(with: .kilo)) // Convert to kilometers
                )
            }
            completion(distanceData) // Pass the data points to the completion handler
        }
        healthStore.execute(query)
    }
    func fetchFlightsClimbedData(completion: @escaping ([FlightsClimbedSample]) -> Void) {
        guard let healthStore = healthStore else { return completion([]) }
        let flightsClimbedType = HKObjectType.quantityType(forIdentifier: .flightsClimbed)!
        // Set start and end dates to today's date
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Date()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: flightsClimbedType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { query, results, error in
            guard let results = results as? [HKQuantitySample], error == nil else {
                completion([])
                return
            }
            let flightsClimbedData = results.map { sample in
                FlightsClimbedSample(startDate: sample.startDate, endDate: sample.endDate, flightsClimbed: sample.quantity.doubleValue(for: HKUnit.count()))
            }
            completion(flightsClimbedData)
        }
        healthStore.execute(query)
    }
    func fetchLatestHeightData(completion: @escaping (Double?) -> Void) {
        guard let healthStore = healthStore else {
            completion(nil)
            return
        }
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { (_, samples, error) in
            if let error = error {
                print("Error fetching height data: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let heightSample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            let heightInMeters = heightSample.quantity.doubleValue(for: HKUnit.meter())
            let heightInCentimeters = heightInMeters * 100
            completion(heightInCentimeters)
        }
        healthStore.execute(query)
    }
    func fetchLatestWeightData(completion: @escaping (Double?) -> Void) {
        guard let healthStore = healthStore else {
            completion(nil)
            return
        }
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { (_, samples, error) in
            if let error = error {
                print("Error fetching weight data: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let weightSample = samples?.first as? HKQuantitySample else {
                completion(nil)
                return
            }
            let weightInKilograms = weightSample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            completion(weightInKilograms)
        }
        healthStore.execute(query)
    }
}

extension Notification.Name {
    static let healthDataUpdated = Notification.Name("healthDataUpdated")
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running:
            return "Running"
        case .walking:
            return "Walking"
        case .cycling:
            return "Cycling"
        case .hiking:
            return "Hiking"
        default:
            return "Other"
        }
    }
}
