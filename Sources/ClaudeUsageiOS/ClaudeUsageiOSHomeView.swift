import SwiftUI

struct ClaudeUsageiOSHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Claude Usage")
                    .font(.title2.weight(.semibold))

                Text("iOS host target scaffolded. Widget provider and OAuth flow land in follow-up tasks.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding()
            .navigationTitle("Usage")
        }
    }
}

#Preview {
    ClaudeUsageiOSHomeView()
}
