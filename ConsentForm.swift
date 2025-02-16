import SwiftUI

struct ConsentFormView: View {
    @Binding var isConsentGiven: Bool
    @Environment(\.dismiss) var dismiss
    var onConsentGiven: () -> Void

    var body: some View {
        VStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Welcome to the Essendon FC Athlete Performance App!")
                        .font(.title2)
                        .bold()
                        .padding(.bottom)

                    Text("""
                                        Before using this app, please review the following important information about how we handle your data:

                                        **1. Data Privacy and Security**
                                        
                                        Your privacy and data security are our top priorities. All information collected through this app is securely stored and processed in accordance with strict privacy and security protocols. No data will be ingested or used without your explicit consent.

                                        **2. Apple Health Data Collection**
                                        
                                        This app requires access to data from your Apple Health app, including metrics such as activity levels, heart rate, sleep data, and other available health information. Data collection will begin only after you provide explicit permission for the app to access this data. You will always have control over which metrics are shared.

                                        **3. Authentication and Authorization**
                                        
                                        We use AWS Cognito with Apple Sign-In to securely authenticate and authorize your account. This ensures that your data is protected and that only you have the ability to authorize the app to upload your health data. We apply the least privilege principle to ensure that only the necessary permissions are granted for data uploads to AWS S3.

                                        **4. Manual Data Uploads**
                                        
                                        Once permissions are granted, your Apple Health data will be uploaded to a secure AWS S3 bucket. This can be done by using the 'Upload' button inside the app.

                                        **5. Data Processing and Storage**
                                        
                                        The data uploaded to AWS S3 will be securely stored in a cloud-based data lake and subsequently processed, where it will be used for advanced analysis to support athlete performance management.

                                        **6. Control Over Data Collection**
                                        
                                        You can stop data collection at any time by deleting the app from your device. Once the app is deleted, all future data uploads will cease immediately, and no further data will be collected from your Apple Health app.
                                        
                                        Please agree to the following to continue:
                                        • I understand that my Apple Health data will be collected and securely uploaded to AWS S3.
                                        • I consent to the use of AWS Cognito for authentication and authorization.
                                        • I agree that the app will automatically upload my data when the Upload button is used inside the app.
                                        • I understand that I can stop data collection by deleting the app at any time.
                                        """)
                        .padding()
                        .font(.body)
                }
                .padding()
            }

            Spacer()

            Button(action: {
                isConsentGiven = true
                UserDefaults.standard.set(true, forKey: "isConsentGiven") // Save consent to UserDefaults
                onConsentGiven()
                dismiss()
            }) {
                Text("Agree and Continue")
                    .font(.title2)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.bottom)
        }
        .padding()
    }
}
