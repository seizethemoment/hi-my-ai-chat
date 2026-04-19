import SwiftUI

struct HomeBackgroundView: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.white,
                Color(red: 0.992, green: 0.992, blue: 0.989)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
