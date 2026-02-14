import SwiftUI

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                Button(action: { viewModel.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoading)
            }

            Divider()

            if let error = viewModel.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                    .font(.caption)
            }

            if let usage = viewModel.usage {
                UsageLimitRow(label: "Session (5-hour)", limit: usage.fiveHour)
                UsageLimitRow(label: "Weekly (7-day)", limit: usage.sevenDay)

                if let opus = usage.sevenDayOpus, opus.utilization > 0 {
                    UsageLimitRow(label: "Opus (7-day)", limit: opus)
                }

                if let sonnet = usage.sevenDaySonnet, sonnet.utilization > 0 {
                    UsageLimitRow(label: "Sonnet (7-day)", limit: sonnet)
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                if let lastUpdated = viewModel.lastUpdated {
                    Text("Updated \(lastUpdated, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct UsageLimitRow: View {
    let label: String
    let limit: UsageLimit

    private var color: Color {
        switch limit.tier {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(limit.utilization))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(color)
            }

            ProgressView(value: limit.utilization, total: 100)
                .tint(color)

            if let resetDate = limit.resetDate, resetDate > Date() {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
