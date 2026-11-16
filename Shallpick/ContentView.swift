import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text("Shallpick")
                .font(.title.bold())
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
