import SwiftUI

struct HeartRateDetailView: View {
  @ObservedObject var store: HealthDataStore
  @ObservedObject var liveVitals: GooseLiveVitalsStore
  @State private var selectedRange: CoreMetricRange = .oneHour

  var body: some View {
    CoreMetricDetailSurface(
      title: "Heart Rate",
      systemImage: "heart.fill",
      tint: .red,
      value: currentValue,
      status: statusText,
      source: source,
      selectedRange: $selectedRange,
      points: heartRatePoints
    )
    .navigationTitle("Heart Rate")
    .task {
      store.refreshHeartRateTimeline()
    }
  }

  private var currentValue: String {
    if let bpm = liveVitals.liveHeartRateBPM {
      return "\(bpm) bpm"
    }
    guard let sample = HeartRateSeriesStore.shared.latestSample() else {
      return "--"
    }
    return "\(sample.bpm) bpm"
  }

  private var statusText: String {
    if liveVitals.liveHeartRateBPM != nil {
      return HealthDataStore.relativeText(for: liveVitals.liveHeartRateUpdatedAt) ?? "Live"
    }
    return store.heartRateTimelineStatus
  }

  private var source: HealthDataSource {
    liveVitals.liveHeartRateBPM == nil
      ? .unavailable("BLE heart-rate stream waiting")
      : .live(liveVitals.liveHeartRateSource)
  }

  private var heartRatePoints: [CoreMetricPoint] {
    let end = Date()
    let samples = HeartRateSeriesStore.shared.samples(from: selectedRange.startDate(endingAt: end), to: end)
    return CoreMetricPoint.bucketed(
      samples: samples,
      range: selectedRange,
      value: { Double($0.bpm) },
      date: \.capturedAt
    )
  }
}

struct StepsDetailView: View {
  @ObservedObject var store: HealthDataStore
  @State private var selectedRange: CoreMetricRange = .day

  var body: some View {
    CoreMetricDetailSurface(
      title: "Steps",
      systemImage: "shoeprints.fill",
      tint: .green,
      value: store.whoopStepsDisplayText(),
      status: store.whoopStepsStatusText(),
      source: store.whoopStepsSource(),
      selectedRange: $selectedRange,
      points: stepPoints
    )
    .navigationTitle("Steps")
    .task {
      store.refreshPacketInputsIfNeeded()
    }
  }

  private var stepPoints: [CoreMetricPoint] {
    switch selectedRange {
    case .oneHour, .sixHours, .day:
      return hourlyStepPoints()
    case .week:
      return dailyStepPoints()
    }
  }

  private func hourlyStepPoints() -> [CoreMetricPoint] {
    let cutoffMS = HealthDataStore.unixMilliseconds(selectedRange.startDate(endingAt: Date()))
    return store.hourlyActivityMetrics()
      .compactMap { metric -> CoreMetricPoint? in
        guard let startMS = HealthDataStore.int64Value(metric["start_time_unix_ms"]),
              startMS >= cutoffMS,
              let steps = HealthDataStore.doubleValue(metric["steps"]) else {
          return nil
        }
        let date = Date(timeIntervalSince1970: Double(startMS) / 1000)
        return CoreMetricPoint(date: date, label: date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted))), value: steps)
      }
      .sorted { $0.date < $1.date }
  }

  private func dailyStepPoints() -> [CoreMetricPoint] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    let cutoffMS = HealthDataStore.unixMilliseconds(cutoff)
    return store.dailyActivityMetrics()
      .compactMap { metric -> CoreMetricPoint? in
        guard let startMS = HealthDataStore.int64Value(metric["start_time_unix_ms"]),
              startMS >= cutoffMS,
              let steps = HealthDataStore.doubleValue(metric["steps"]) else {
          return nil
        }
        let date = Date(timeIntervalSince1970: Double(startMS) / 1000)
        return CoreMetricPoint(date: date, label: date.formatted(.dateTime.weekday(.abbreviated)), value: steps)
      }
      .sorted { $0.date < $1.date }
  }
}

struct CoreMetricDetailSurface: View {
  let title: String
  let systemImage: String
  let tint: Color
  let value: String
  let status: String
  let source: HealthDataSource
  @Binding var selectedRange: CoreMetricRange
  let points: [CoreMetricPoint]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 14) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
              .font(.system(size: 25, weight: .bold))
              .foregroundStyle(tint)
              .frame(width: 48, height: 48)
              .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
              Text(title)
                .font(.title2.bold())
              Text(status)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()
            HealthSourceBadge(source: source)
          }

          Text(value)
            .font(.system(size: 44, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
        .padding(16)
        .healthCardSurface()

        Picker("Range", selection: $selectedRange) {
          ForEach(CoreMetricRange.allCases) { range in
            Text(range.title).tag(range)
          }
        }
        .pickerStyle(.segmented)

        VStack(alignment: .leading, spacing: 12) {
          HStack {
            HealthSectionTitle("Trend")
            Spacer()
            Text(summaryText)
              .font(.caption.weight(.semibold))
              .foregroundStyle(.secondary)
          }

          CoreMetricLineChart(points: points, tint: tint, valueLabel: formatted)
            .frame(height: 214)
        }
        .padding(16)
        .healthCardSurface()
      }
      .padding(16)
    }
    .gooseScreenBackground()
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
  }

  private var summaryText: String {
    guard !points.isEmpty else {
      return "No data"
    }
    let values = points.map(\.value)
    let minValue = values.min() ?? 0
    let maxValue = values.max() ?? 0
    return "\(formatted(minValue)) - \(formatted(maxValue))"
  }

  private func formatted(_ value: Double) -> String {
    title == "Steps"
      ? HealthDataStore.groupedIntegerText(Int(value.rounded()))
      : "\(Int(value.rounded())) bpm"
  }
}

struct CoreMetricLineChart: View {
  let points: [CoreMetricPoint]
  let tint: Color
  let valueLabel: (Double) -> String
  @State private var selectedPointID: String?

  var body: some View {
    GeometryReader { proxy in
      if points.isEmpty {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color(.tertiarySystemFill))
          .overlay {
              ContentUnavailableView("No Data", systemImage: "chart.line.uptrend.xyaxis")
          }
      } else {
        let chartRect = chartRect(size: proxy.size)
        let valueBounds = valueBounds()
        let dateBounds = dateBounds()
        let cgPoints = points.map { chartPoint($0, chartRect: chartRect, valueBounds: valueBounds, dateBounds: dateBounds) }
        let selectedPoint = selectedPoint
        let selectedCGPoint = selectedPoint.map { chartPoint($0, chartRect: chartRect, valueBounds: valueBounds, dateBounds: dateBounds) }

        ZStack(alignment: .topLeading) {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground))

          ForEach(Array(axisValues(in: valueBounds).enumerated()), id: \.offset) { _, value in
            let y = yPosition(for: value, chartRect: chartRect, valueBounds: valueBounds)
            Path { path in
              path.move(to: CGPoint(x: chartRect.minX, y: y))
              path.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            }
            .stroke(Color.primary.opacity(0.08), lineWidth: 1)

            Text(axisLabel(value))
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .frame(width: 36, alignment: .trailing)
              .position(x: chartRect.minX - 23, y: y)
          }

          Path { path in
            path.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
            path.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
            path.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
          }
          .stroke(Color.primary.opacity(0.18), lineWidth: 1)

          if cgPoints.count == 1, let point = cgPoints.first {
            Circle()
              .fill(tint)
              .frame(width: 8, height: 8)
              .position(point)
          } else {
            smoothPath(points: cgPoints)
              .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
          }

          HStack(alignment: .top) {
            Text(points.first?.label ?? "")
            Spacer()
            Text(points[points.count / 2].label)
            Spacer()
            Text(points.last?.label ?? "")
          }
          .font(.caption2.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(width: chartRect.width)
          .position(x: chartRect.midX, y: chartRect.maxY + 18)

          if let selectedPoint, let selectedCGPoint {
            Path { path in
              path.move(to: CGPoint(x: selectedCGPoint.x, y: chartRect.minY))
              path.addLine(to: CGPoint(x: selectedCGPoint.x, y: chartRect.maxY))
            }
            .stroke(Color.primary.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

            Circle()
              .fill(tint)
              .frame(width: 12, height: 12)
              .position(selectedCGPoint)

            VStack(alignment: .leading, spacing: 2) {
              Text(valueLabel(selectedPoint.value))
                .font(.caption.weight(.bold))
                .monospacedDigit()
              Text(selectedPoint.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .position(
              x: min(max(selectedCGPoint.x + 42, chartRect.minX + 48), chartRect.maxX - 48),
              y: chartRect.minY + 24
            )
          }
        }
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              selectedPointID = nearestPoint(to: value.location, chartRect: chartRect, dateBounds: dateBounds)?.id
            }
        )
      }
    }
  }

  private var selectedPoint: CoreMetricPoint? {
    guard let selectedPointID else {
      return nil
    }
    return points.first { $0.id == selectedPointID }
  }

  private func chartRect(size: CGSize) -> CGRect {
    CGRect(
      x: 44,
      y: 18,
      width: max(size.width - 56, 1),
      height: max(size.height - 50, 1)
    )
  }

  private func valueBounds() -> ClosedRange<Double> {
    let values = points.map(\.value)
    let minimum = values.min() ?? 0
    let maximum = values.max() ?? 1
    let padding = max((maximum - minimum) * 0.12, 1)
    return (minimum - padding)...(maximum + padding)
  }

  private func dateBounds() -> ClosedRange<Date> {
    let start = points.first?.date ?? Date()
    let end = points.last?.date ?? start.addingTimeInterval(1)
    if start == end {
      return start...start.addingTimeInterval(1)
    }
    return start...end
  }

  private func axisValues(in bounds: ClosedRange<Double>) -> [Double] {
    [bounds.upperBound, (bounds.lowerBound + bounds.upperBound) / 2, bounds.lowerBound]
  }

  private func axisLabel(_ value: Double) -> String {
    valueLabel(value)
      .replacingOccurrences(of: " bpm", with: "")
      .replacingOccurrences(of: " cal", with: "")
  }

  private func chartPoint(
    _ point: CoreMetricPoint,
    chartRect: CGRect,
    valueBounds: ClosedRange<Double>,
    dateBounds: ClosedRange<Date>
  ) -> CGPoint {
    let valueSpan = max(valueBounds.upperBound - valueBounds.lowerBound, 1)
    let dateSpan = max(dateBounds.upperBound.timeIntervalSince1970 - dateBounds.lowerBound.timeIntervalSince1970, 1)
    let xProgress = (point.date.timeIntervalSince1970 - dateBounds.lowerBound.timeIntervalSince1970) / dateSpan
    let yProgress = (point.value - valueBounds.lowerBound) / valueSpan
    let x = chartRect.minX + chartRect.width * CGFloat(min(max(xProgress, 0), 1))
    let y = chartRect.maxY - chartRect.height * CGFloat(min(max(yProgress, 0), 1))
    return CGPoint(x: x, y: y)
  }

  private func yPosition(
    for value: Double,
    chartRect: CGRect,
    valueBounds: ClosedRange<Double>
  ) -> CGFloat {
    let valueSpan = max(valueBounds.upperBound - valueBounds.lowerBound, 1)
    let progress = (value - valueBounds.lowerBound) / valueSpan
    return chartRect.maxY - chartRect.height * CGFloat(min(max(progress, 0), 1))
  }

  private func nearestPoint(
    to location: CGPoint,
    chartRect: CGRect,
    dateBounds: ClosedRange<Date>
  ) -> CoreMetricPoint? {
    let clampedX = min(max(location.x, chartRect.minX), chartRect.maxX)
    let xProgress = Double((clampedX - chartRect.minX) / max(chartRect.width, 1))
    let dateSpan = dateBounds.upperBound.timeIntervalSince1970 - dateBounds.lowerBound.timeIntervalSince1970
    let target = dateBounds.lowerBound.timeIntervalSince1970 + dateSpan * xProgress
    return points.min {
      abs($0.date.timeIntervalSince1970 - target) < abs($1.date.timeIntervalSince1970 - target)
    }
  }

  private func smoothPath(points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else {
      return path
    }
    path.move(to: first)
    guard points.count > 1 else {
      return path
    }
    for index in 0..<(points.count - 1) {
      let previous = index > 0 ? points[index - 1] : points[index]
      let current = points[index]
      let next = points[index + 1]
      let following = index + 2 < points.count ? points[index + 2] : next
      let control1 = CGPoint(
        x: current.x + (next.x - previous.x) / 6,
        y: current.y + (next.y - previous.y) / 6
      )
      let control2 = CGPoint(
        x: next.x - (following.x - current.x) / 6,
        y: next.y - (following.y - current.y) / 6
      )
      path.addCurve(to: next, control1: control1, control2: control2)
    }
    return path
  }
}

enum CoreMetricRange: String, CaseIterable, Identifiable {
  case oneHour
  case sixHours
  case day
  case week

  var id: String { rawValue }

  var title: String {
    switch self {
    case .oneHour: "1H"
    case .sixHours: "6H"
    case .day: "1D"
    case .week: "7D"
    }
  }

  func startDate(endingAt end: Date) -> Date {
    switch self {
    case .oneHour:
      return end.addingTimeInterval(-60 * 60)
    case .sixHours:
      return end.addingTimeInterval(-6 * 60 * 60)
    case .day:
      return Calendar.current.startOfDay(for: end)
    case .week:
      return end.addingTimeInterval(-7 * 24 * 60 * 60)
    }
  }
}

struct CoreMetricPoint: Identifiable {
  let id: String
  let date: Date
  let label: String
  let value: Double

  init(date: Date, label: String, value: Double) {
    self.id = "\(Int64((date.timeIntervalSince1970 * 1000).rounded())).\(Int(value.rounded()))"
    self.date = date
    self.label = label
    self.value = value
  }

  static func bucketed<Sample>(
    samples: [Sample],
    range: CoreMetricRange,
    value: (Sample) -> Double,
    date: KeyPath<Sample, Date>
  ) -> [CoreMetricPoint] {
    guard !samples.isEmpty else {
      return []
    }
    let bucketSeconds: TimeInterval = switch range {
    case .oneHour: 60
    case .sixHours: 5 * 60
    case .day: 15 * 60
    case .week: 2 * 60 * 60
    }
    let calendar = Calendar.current
    let groups = Dictionary(grouping: samples) { sample in
      let timestamp = sample[keyPath: date].timeIntervalSince1970
      return Date(timeIntervalSince1970: floor(timestamp / bucketSeconds) * bucketSeconds)
    }
    return groups
      .map { bucketDate, bucketSamples in
        let average = bucketSamples.map(value).reduce(0, +) / Double(max(bucketSamples.count, 1))
        let label = range == .week
          ? bucketDate.formatted(.dateTime.weekday(.abbreviated))
          : bucketDate.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        return CoreMetricPoint(date: calendar.dateInterval(of: .minute, for: bucketDate)?.start ?? bucketDate, label: label, value: average)
      }
      .sorted { $0.date < $1.date }
  }
}
