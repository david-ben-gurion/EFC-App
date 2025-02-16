import SwiftUI
import HealthKit

struct DistanceSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let distance: Double // Distance in kilometers
}

struct FlightsClimbedSample: Identifiable {
    var id = UUID()
    var startDate: Date
    var endDate: Date
    var flightsClimbed: Double
}

struct StandTimeSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let standTime: Double // Represents stand time in hours
}

struct Workout: Identifiable {
    let id = UUID() // Unique identifier
    let type: String
    let duration: Double
    let startTime: Date
    let endTime: Date
    let totalEnergyBurned: Double
    let totalDistance: Double
}

struct HeartRateSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let heartRate: Double
}

struct ExerciseTimeSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let exerciseTime: Double // Time in hours (or any other unit you choose)
}

struct RestingHeartRateSample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let restingHeartRate: Double
}

struct ActiveEnergySample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let activeEnergy: Double
}

struct BasalEnergySample: Identifiable {
    let id = UUID()
    let startDate: Date
    let endDate: Date
    let basalEnergy: Double
}

struct ContentView: View {
    @StateObject private var healthStore = HealthStoreManager.shared
    @State private var stepCount: Double = 0.0
    @State private var sleepData: [String: (startTime: Date, endTime: Date, durationInMinutes: Double)] = [:]
    @State private var userName: String = ""
    @State private var isNameEntered: Bool = false
    @State private var showUploadMessage: Bool = false
    @State private var workoutData: [Workout] = []
    @State private var heartRateData: [HeartRateSample] = []
    @State private var restingHeartRateData: [RestingHeartRateSample] = [] // Added state variable
    @State private var activeEnergyData: [ActiveEnergySample] = []
    @State private var basalEnergyData: [BasalEnergySample] = []
    @State private var standTimeData: [StandTimeSample] = []
    @State private var exerciseTimeData: [ExerciseTimeSample] = [] // Added state variable for exercise time
    @State private var distanceData: [DistanceSample] = []
    @State private var flightsClimbedData: [FlightsClimbedSample] = [] // Added state variable for flights climbed
    @State private var isConsentGiven: Bool = UserDefaults.standard.bool(forKey: "isConsentGiven")
    @State private var isAuthorizationRequested: Bool = false
    @State private var heightData: Double = 0.0
    @State private var weightData: Double = 0.0// Added state variable for height

    init() {
        // Load the saved user name from UserDefaults
        if let savedName = UserDefaults.standard.string(forKey: "userName") {
            _userName = State(initialValue: savedName)
            _isNameEntered = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if !isConsentGiven {
                    ConsentFormView(isConsentGiven: $isConsentGiven, onConsentGiven: {
                        requestHealthKitAuthorization()
                    })
                } else if !healthStore.isAuthenticated {
                    Text("Please Sign In with Apple")
                        .font(.title)
                        .padding()

                    Button(action: {
                        healthStore.signInWithApple()
                    }) {
                        Text("Sign In with Apple")
                            .font(.title2)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                } else {
                    if isNameEntered {
                        mainContent
                    } else {
                        NameEntryView(userName: $userName, isNameEntered: $isNameEntered, fetchHealthData: fetchHealthData)
                    }
                }
            }
            .onAppear {
                if isConsentGiven && !isAuthorizationRequested {
                    requestHealthKitAuthorization()
                }
            }
        }
    }

    private func requestHealthKitAuthorization() {
        healthStore.requestAuthorization { success in
            if success {
                if isNameEntered {
                    fetchHealthData()
                }
                healthStore.startObservingHealthKitChanges()
                NotificationCenter.default.addObserver(forName: .healthDataUpdated, object: nil, queue: .main) { _ in
                    fetchHealthData()
                }
            }
            isAuthorizationRequested = true
        }
    }

    private func fetchHealthData() {
        // Existing fetch calls
        healthStore.fetchStepCount { count in
            DispatchQueue.main.async {
                self.stepCount = count
            }
        }
        healthStore.fetchSleepData { data in
            DispatchQueue.main.async {
                self.sleepData = data
            }
        }
        healthStore.fetchWorkoutData { workouts in
            DispatchQueue.main.async {
                self.workoutData = workouts
            }
        }
        healthStore.fetchHeartRateData { data in
            DispatchQueue.main.async {
                self.heartRateData = data
            }
        }
        healthStore.fetchRestingHeartRateData { data in
            DispatchQueue.main.async {
                self.restingHeartRateData = data
            }
        }
        healthStore.fetchActiveEnergyData { data in
            DispatchQueue.main.async {
                self.activeEnergyData = data
            }
        }
        healthStore.fetchBasalEnergyData { data in
            DispatchQueue.main.async {
                self.basalEnergyData = data
            }
        }
        healthStore.fetchStandTimeData { data in
            DispatchQueue.main.async {
                self.standTimeData = data
            }
        }
        healthStore.fetchWalkingRunningDistanceData { distance in
            DispatchQueue.main.async {
                self.distanceData = distance
            }
        }
        healthStore.fetchExerciseTimeData { data in
            DispatchQueue.main.async {
                self.exerciseTimeData = data
            }
        }
        healthStore.fetchFlightsClimbedData { data in
            DispatchQueue.main.async {
                self.flightsClimbedData = data
            }
        }
        healthStore.fetchLatestHeightData { height in
            DispatchQueue.main.async {
                self.heightData = height ?? 0.0 // Provide a default value if height is nil
            }
        }
        healthStore.fetchLatestWeightData { weight in
            DispatchQueue.main.async {
                self.weightData = weight ?? 0.0
            }
        }
    }

    private func formatHoursAndMinutes(from minutes: Double) -> String {
        let totalMinutes = Int(minutes)
        let hoursPart = totalMinutes / 60
        let minutesPart = totalMinutes % 60
        return "\(hoursPart)h \(minutesPart)m"
    }

    private func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack {
                    // Greeting Section
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Hello")
                            .font(.largeTitle)
                            .foregroundColor(.primary)
                        
                        Text(userName)
                            .font(.largeTitle)
                            .foregroundColor(.blue)
                    }
                    .padding()
                    //.offset(y: -30)
                    
                    HStack(spacing: 20) {
                        Button(action: {
                            // Directly upload all the data to S3 without fetching weight data separately
                            healthStore.uploadDataToS3(
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
                                heightData: heightData, // Ensure heightData is available
                                weightData: weightData, // Ensure weightData is handled inside uploadDataToS3 if it's fetched there
                                userName: userName
                            )

                            // Show upload success message for 2 seconds
                            showUploadMessage = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showUploadMessage = false
                            }
                        }) {
                            IconButton(iconName: "icloud.and.arrow.up", text: "Upload to S3", color: .blue)
                        }
                        Button(action: {
                            isNameEntered = false
                        }) {
                            IconButton(iconName: "pencil", text: "Change Name", color: .green)
                        }
                        
                        Button(action: {
                            fetchHealthData()
                        }) {
                            IconButton(iconName: "arrow.clockwise", text: "Refresh", color: .orange)
                        }
                    }
                    .padding()
                    
                    if showUploadMessage {
                        Text("File successfully uploaded to S3")
                            .font(.body)
                            .foregroundColor(.green)
                            .padding(.top, 5)
                            .transition(.opacity)
                    }
                    
                    
                    // Steps Metrics Section
                    VStack(alignment: .leading) {
                        Text("Steps")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        VStack {
                            Text("\(Int(stepCount))")
                                .font(.largeTitle)
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .frame(width: 150)
                                .padding()
                        }
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                        .frame(width: 150, height: 100)
                    }
                    .padding()
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Height")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        VStack {
                            Text("\(heightData, specifier: "%.1f") cm") // Display height in centimeters
                                .font(.largeTitle)
                                .foregroundColor(.primary)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                                .frame(width: 150)
                                .padding()
                        }
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                        .frame(width: 150, height: 100)
                    }
                    .padding()
                    
                    VStack(alignment: .leading, spacing: 20) {
                            Text("Weight")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.top)
                            
                            VStack {
                                Text("\(weightData, specifier: "%.1f") kg") // Display weight in kilograms
                                    .font(.largeTitle)
                                    .foregroundColor(.primary)
                                    .minimumScaleFactor(0.7)
                                    .lineLimit(1)
                                    .frame(width: 150)
                                    .padding()
                            }
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(10)
                            .frame(width: 150, height: 100)
                        }
                        .padding()

                    // Sleep Metrics Section
                    VStack(alignment: .leading) {
                        Text("Sleep Metrics")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        VStack(alignment: .leading) {
                            if let inBedValue = sleepData["In Bed"] {
                                Text("In Bed: \(formatHoursAndMinutes(from: inBedValue.durationInMinutes))")
                            }

                            Spacer().frame(height: 10)

                            let sleepMetricsMap: [String: String] = [
                                "Awake": "Awake",
                                "Core Sleep": "Core",
                                "Deep Sleep": "Deep",
                                "REM Sleep": "REM"
                            ]

                            ForEach(sleepMetricsMap.keys.sorted(), id: \.self) { key in
                                if let value = sleepData[key] {
                                    if let label = sleepMetricsMap[key] {
                                        Text("\(label): \(formatHoursAndMinutes(from: value.durationInMinutes))")
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(UIColor.systemGray6))
                        .cornerRadius(10)
                        .frame(minWidth: 150)
                    }
                    .padding()

                    // Workout Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Workouts")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        if workoutData.isEmpty {
                            Text("No workout data available")
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(10)
                        } else {
                            ForEach(workoutData) { workout in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Type: \(workout.type)")
                                    Text("Start: \(formatDate(workout.startTime))")
                                    Text("End: \(formatDate(workout.endTime))")
                                    Text("Duration: \(workout.duration, specifier: "%.2f") minutes")
                                    Text("Distance: \(workout.totalDistance, specifier: "%.2f") meters")
                                    Text("Calories Burned: \(workout.totalEnergyBurned, specifier: "%.2f") kcal")
                                }
                                .padding()
                                .background(Color(UIColor.systemGray6))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding()

                    // Heart Rate Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Heart Rate")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(heartRateData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Heart Rate: \(sample.heartRate, specifier: "%.2f") bpm")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Resting Heart Rate Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Resting Heart Rate")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(restingHeartRateData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Resting Heart Rate: \(sample.restingHeartRate, specifier: "%.2f") bpm")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Active Energy Burned Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Active Energy Burned")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(activeEnergyData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Active Energy: \(sample.activeEnergy, specifier: "%.2f") kcal")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Basal Energy Burned Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Resting Energy Burned")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(basalEnergyData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Basal Energy: \(sample.basalEnergy, specifier: "%.2f") kcal")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Stand Time Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Stand Time")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(standTimeData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Stand Time: \(sample.standTime, specifier: "%.2f") minutes")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Exercise Time Data Section
                    // Exercise Time Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Exercise Minutes")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(exerciseTimeData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Exercise Time: 1 minute") // Always display "1 minute"
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120) // Adjust height as needed
                    }
                    .padding()

                    // Walking + Running Distance Data Section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Walking + Running Distance")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(distanceData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Distance: \(sample.distance, specifier: "%.2f") kilometers")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120)
                        .padding(.horizontal, 12)
                    }
                    .padding()
                    
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Flights Climbed")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(flightsClimbedData) { sample in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Start: \(formatDate(sample.startDate))")
                                        Text("End: \(formatDate(sample.endDate))")
                                        Text("Flights Climbed: \(sample.flightsClimbed, specifier: "%.2f") floors")
                                    }
                                    .padding()
                                    .background(Color(UIColor.systemGray6))
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .frame(height: 120)
                    }
                    .padding()
                    
                    // Buttons and Upload Message Section


                    
                    // Spacer and Build Version Section at the Bottom
                    VStack {
                        Image("inapplogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 100, height: 100)
                            .padding()

                        Text("Version: \(Bundle.main.versionNumber), build: \(Bundle.main.buildNumber)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.bottom)
                    }
                    .padding(.top, 30)
                }
                .padding(.top, 70)
            }

            // Banner Image
            Image("essendonbanner") // Replace with your banner image name
                .resizable()
                .aspectRatio(contentMode: .fit) // Maintain the original aspect ratio without clipping
                .frame(maxWidth: .infinity) // Ensure the image stretches to fit the width of its container
                .clipped() // Clip any parts of the image that extend beyond the frame, if needed
                .edgesIgnoringSafeArea(.top)
            
                
        }
    }

}


struct NameEntryView: View {
    @Binding var userName: String
    @Binding var isNameEntered: Bool
    var fetchHealthData: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            Text("Welcome, please enter your FULL name:")
                .font(.largeTitle)
                .padding()

            TextField("Enter your name", text: $userName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Save") {
                UserDefaults.standard.set(userName, forKey: "userName")
                isNameEntered = true
                fetchHealthData() // Trigger data fetch when name is entered
            }
            .font(.title2)
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .padding()
    }
}

struct IconButton: View {
    let iconName: String
    let text: String
    let color: Color

    var body: some View {
        VStack {
            Image(systemName: iconName)
                .font(.system(size: 30))
                .padding()
                .background(color.opacity(0.2))
                .cornerRadius(10)
                .foregroundColor(color)

            Text(text)
                .font(.caption)
                .foregroundColor(.primary)
                .font(.system(size: 22))
        }
    }
}

extension Bundle {
    var versionNumber: String {
        return infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
    }

    var buildNumber: String {
        return infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
