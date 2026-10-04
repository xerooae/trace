import SwiftUI

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "swift")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("Built on Windows, running on iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("\(count)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())

                Button("Tap me") {
                    withAnimation { count += 1 }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .navigationTitle("Trace")
        }
    }
}

#Preview {
    ContentView()
}
