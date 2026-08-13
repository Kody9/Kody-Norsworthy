import SwiftUI

struct DisclaimerView: View {
    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Before You Start")
                        .font(.title2.bold())

                    bullet("This app is a personal note-taking tool. It captures a plate photo, reads the plate number with on-device OCR, and saves it — plate, timestamp, GPS location, and any notes you add — only on this iPhone. Nothing is uploaded anywhere.")
                    bullet("This app is not connected to NCIC, any state DMV, or any government database, and it cannot identify a vehicle's owner. Any use of official systems must go through your department's authorized, audited channels — not this app.")
                    bullet("The optional lookup buttons only open free, public tools (NHTSA's VIN decoder, NICB's stolen-vehicle check, CARFAX's free report page) in your browser. They return vehicle facts — make, model, year, stolen status, service history — never owner identity.")
                    bullet("You're responsible for using this app in compliance with your department's policy, your state's law, and the Driver's Privacy Protection Act. Treat captured data like any other personal field notes.")

                    Button(action: onAccept) {
                        Text("I Understand")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .padding()
            }
            .navigationTitle("Welcome")
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
        }
        .font(.subheadline)
    }
}
