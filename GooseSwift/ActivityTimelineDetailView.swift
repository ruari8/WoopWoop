import SwiftUI

struct ActivityTimelineDetailView: View {
  let item: ActivityTimelineItem

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
              .font(.system(size: 26, weight: .bold))
              .foregroundStyle(tint)
              .frame(width: 50, height: 50)
              .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
              Text(item.title)
                .font(.title2.bold())
              Text(timeRangeText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
          }

          Text(formatDuration(item.durationSeconds))
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
        }
        .padding(16)
        .healthCardSurface()

        LazyVGrid(columns: columns, spacing: 12) {
          ActivityDetailMetricTile(title: "Distance", value: distanceText, systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: tint)
          ActivityDetailMetricTile(title: "Avg HR", value: heartRateText(item.averageHeartRate), systemImage: "heart.fill", tint: .red)
          ActivityDetailMetricTile(title: "Max HR", value: heartRateText(item.maxHeartRate), systemImage: "waveform.path.ecg", tint: .red)
          ActivityDetailMetricTile(title: "Status", value: statusText, systemImage: "checkmark.seal", tint: .blue)
        }

        VStack(alignment: .leading, spacing: 12) {
          HealthSectionTitle("Heart Rate Zones")
          ForEach(HeartRateZone.zones.reversed()) { zone in
            ActivityZoneDurationRow(
              zone: zone,
              duration: item.zoneDurations[zone.id, default: 0],
              totalDuration: totalZoneDuration
            )
          }
        }
        .padding(16)
        .healthCardSurface()
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationTitle(item.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }

  private let columns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  private var totalZoneDuration: TimeInterval {
    max(item.zoneDurations.values.reduce(0, +), item.durationSeconds)
  }

  private var timeRangeText: String {
    let end = item.startedAt.addingTimeInterval(item.durationSeconds)
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return "\(formatter.string(from: item.startedAt)) - \(formatter.string(from: end))"
  }

  private var distanceText: String {
    guard let distanceMeters = item.distanceMeters, distanceMeters > 0 else {
      return "--"
    }
    let parts = fitnessDistanceParts(distanceMeters)
    return "\(parts.value) \(parts.unit.lowercased())"
  }

  private var statusText: String {
    item.syncStatus.isEmpty ? "Stored" : item.syncStatus.replacingOccurrences(of: "_", with: " ").capitalized
  }

  private var systemImage: String {
    switch item.activityType {
    case "walking", "hiking":
      return "figure.walk"
    case "running":
      return "figure.run"
    case "cycling", "spinning":
      return "bicycle"
    case "strength":
      return "dumbbell"
    default:
      return "figure.mixed.cardio"
    }
  }

  private var tint: Color {
    switch item.activityType {
    case "walking", "hiking":
      return .green
    case "running":
      return .orange
    case "cycling", "spinning":
      return .blue
    case "strength":
      return .red
    default:
      return .pink
    }
  }

  private func heartRateText(_ value: Int?) -> String {
    value.map { "\($0) bpm" } ?? "--"
  }
}

struct ActivityDetailMetricTile: View {
  let title: String
  let value: String
  let systemImage: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Image(systemName: systemImage)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(tint)
        .frame(width: 30, height: 30)
        .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      Text(value)
        .font(.title3.weight(.bold))
        .fontDesign(.rounded)
        .lineLimit(1)
        .minimumScaleFactor(0.70)
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
    .padding(14)
    .healthCardSurface()
  }
}

struct ActivityZoneDurationRow: View {
  let zone: HeartRateZone
  let duration: TimeInterval
  let totalDuration: TimeInterval

  var body: some View {
    HStack(spacing: 12) {
      Text("Z\(zone.id)")
        .font(.subheadline.weight(.bold))
        .foregroundStyle(zone.color)
        .frame(width: 34, alignment: .leading)
      GeometryReader { proxy in
        ZStack(alignment: .leading) {
          Capsule().fill(Color(.tertiarySystemFill))
          Capsule()
            .fill(zone.color)
            .frame(width: proxy.size.width * progress)
        }
      }
      .frame(height: 9)
      Text(formatDuration(duration))
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .frame(width: 58, alignment: .trailing)
    }
  }

  private var progress: CGFloat {
    CGFloat(min(max(duration / max(totalDuration, 1), 0), 1))
  }
}
