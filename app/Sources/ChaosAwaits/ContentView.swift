import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("chaos.awaits.us")
                    .font(.title)
                    .fontWeight(.bold)

                Text("Select media to share")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Chaos Awaits")
        }
    }
}

#Preview {
    ContentView()
}
