import SwiftUI
import NightWatchCore

/// The "not a medical device / call 999" note. Shown on every main screen.
struct DisclaimerBanner: View {
    var body: some View {
        Text(SafetyText.disclaimer)
            .font(.footnote)
            .multilineTextAlignment(.center)
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    DisclaimerBanner()
}
