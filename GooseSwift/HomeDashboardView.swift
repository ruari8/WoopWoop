import SwiftUI

struct HomeDashboardView: View {
  let model: GooseAppModel
  @ObservedObject var connectionStatus: GooseConnectionStatusStore
  @ObservedObject var activityTimeline: HomeActivityTimelineStore
  @ObservedObject var healthStore: HealthDataStore
  @Binding var selectedDate: Date
  let openHealthRoute: (HealthRoute) -> Void
  let openActivity: (ActivityTimelineItem) -> Void
  @State private var showingScoreDatePicker = false
  @State private var showingCardioLoadSheet = false
  @State private var selectedHealthMonitorTrend: HealthMetricSnapshot?

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HomeDailyScoreCard(
          scores: scoreSnapshots,
          openScore: openHealth
        )

        HomeCoreMetricsSection(
          heartRateValue: liveHeartRateValue,
          heartRateStatus: liveHeartRateStatus,
          heartRateSource: liveHeartRateSource,
          stepsValue: healthStore.whoopStepsDisplayText(for: selectedDate),
          stepsStatus: stepsStatusText,
          stepsSource: healthStore.whoopStepsSource(for: selectedDate),
          openHeartRate: { openHealth(.heartRate) },
          openSteps: { openHealth(.steps) }
        )

        HomeDataReadinessCard(message: dailyActionSummary) {
          openHealth(.packetInputs)
        }

        HomeCardioLoadWidget(
          snapshot: landingSnapshot(for: .cardioLoad),
          days: healthStore.cardioLoadWeeklyPoints()
        ) {
          showingCardioLoadSheet = true
          model.recordUIAction("health.sheet.opened", detail: "Cardio Load home widget")
        }

        HomeHealthMonitorSection(
          snapshots: healthStore.healthMonitorSnapshots(allowLiveFallbacks: false),
          openSnapshot: openHealthMonitorSnapshot
        )

        HomeTimelineSection(
          sleep: homeSnapshot(for: .sleep),
          recovery: homeSnapshot(for: .recovery),
          activities: activityTimeline.items,
          openSleep: { openHealth(.sleep) },
          openActivity: openActivity,
          openRecovery: { openHealth(.recovery) }
        )

      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .scrollClipDisabled()
    .gooseScreenBackground()
    .navigationTitle("Today")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .overlay(alignment: .top) {
      HomeTopScrollFade()
        .allowsHitTesting(false)
    }
    .safeAreaInset(edge: .bottom, alignment: .trailing) {
      HomeStartActivityFloatingButton(model: model, session: model.activitySession)
        .padding(.trailing, 18)
        .padding(.bottom, 10)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        ScoreDateTitleButton(
          title: homeTitle,
          subtitle: nil,
          action: { showingScoreDatePicker = true }
        )
      }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          DeviceView(model: model)
        } label: {
          Image(systemName: "applewatch")
            .font(.system(size: 17, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(deviceToolbarTint)
        }
        .accessibilityLabel("Device")
        .accessibilityValue(deviceToolbarAccessibilityValue)
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Home")
    }
    .task {
      healthStore.loadBridgeCatalogsIfNeeded()
      model.refreshActivityTimeline(for: selectedDate)
    }
    .onChange(of: selectedDate) { _, newValue in
      model.refreshActivityTimeline(for: newValue)
    }
    .sheet(isPresented: $showingScoreDatePicker) {
      ScoreDatePickerSheet(
        title: "Daily Scores",
        routes: [.sleep, .recovery, .strain],
        snapshots: scorePickerSnapshots,
        selectedDate: $selectedDate
      )
    }
    .sheet(isPresented: $showingCardioLoadSheet) {
      CardioLoadSheet(store: healthStore)
    }
    .sheet(item: $selectedHealthMonitorTrend) { snapshot in
      SleepV2BevelTrendSheet(snapshot: snapshot)
    }
  }

  private var scoreSnapshots: [HealthMetricSnapshot] {
    [
      datedHomeSnapshot(for: .sleep),
      datedHomeSnapshot(for: .recovery),
      datedHomeSnapshot(for: .strain),
    ]
  }

  private var scorePickerSnapshots: [HealthMetricSnapshot] {
    [
      homeSnapshot(for: .sleep),
      homeSnapshot(for: .recovery),
      homeSnapshot(for: .strain),
    ]
  }

  private var homeTitle: String {
    ScoreDateTimeline.dateLabel(for: selectedDate)
  }

  private var deviceToolbarTint: Color {
    deviceToolbarConnected ? .green : .red
  }

  private var deviceToolbarAccessibilityValue: String {
    deviceToolbarConnected ? "Connected" : "Disconnected"
  }

  private var deviceToolbarConnected: Bool {
    let state = connectionStatus.connectionState.lowercased()
    return state == "ready" || state == "connected"
  }

  private var dailyActionSummary: String {
    let inputAction = healthStore.metricInputReadinessNextActionSummary()
    if !inputAction.isEmpty {
      return inputAction
    }
    return healthStore.packetDerivedScoreNextActionSummary()
  }

  private var liveHeartRateValue: String {
    guard let bpm = model.ble.liveVitals.liveHeartRateBPM else {
      return "--"
    }
    return "\(bpm)"
  }

  private var liveHeartRateStatus: String {
    guard model.ble.liveVitals.liveHeartRateBPM != nil else {
      return healthStore.heartRateTimelineStatus
    }
    return HealthDataStore.relativeText(for: model.ble.liveVitals.liveHeartRateUpdatedAt) ?? "Live"
  }

  private var liveHeartRateSource: HealthDataSource {
    model.ble.liveVitals.liveHeartRateBPM == nil
      ? .unavailable("BLE heart-rate stream waiting")
      : .live(model.ble.liveVitals.liveHeartRateSource)
  }

  private var stepsStatusText: String {
    if Calendar.current.isDate(selectedDate, inSameDayAs: Date()) {
      return healthStore.whoopStepsStatusText()
    }
    return healthStore.whoopStepsSource(for: selectedDate).detail
  }

  private var landingSnapshots: [HealthMetricSnapshot] {
    healthStore.landingSnapshots(
      liveHeartRateBPM: nil,
      liveHeartRateSource: "home dashboard stable daily metrics",
      liveHeartRateUpdatedAt: nil,
      stableDailyMetrics: true
    )
  }

  private func landingSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    landingSnapshots.first { $0.route == route } ?? healthStore.snapshot(for: route)
  }

  private func homeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    let snapshot = landingSnapshot(for: route)
    guard route == .strain, snapshot.unit != "%" else {
      return snapshot
    }
    let rawValue = firstNumber(in: snapshot.displayValue) ?? firstNumber(in: snapshot.value) ?? 0
    let percent = min(max(Int((rawValue / 21 * 100).rounded()), 0), 100)
    return HealthMetricSnapshot(
      id: snapshot.id,
      route: snapshot.route,
      group: snapshot.group,
      title: snapshot.title,
      value: "\(percent)",
      unit: "%",
      status: snapshot.status,
      freshness: snapshot.freshness,
      provenance: snapshot.provenance,
      source: snapshot.source,
      systemImage: snapshot.systemImage,
      tint: snapshot.tint,
      trend: snapshot.trend
    )
  }

  private func datedHomeSnapshot(for route: HealthRoute) -> HealthMetricSnapshot {
    ScoreDateTimeline.datedSnapshot(from: homeSnapshot(for: route), date: selectedDate)
  }

  private func openHealth(_ route: HealthRoute) {
    openHealthRoute(route)
    model.recordUIAction("health.deep_link.opened", detail: route.title)
  }

  private func openHealthMonitorSnapshot(_ snapshot: HealthMetricSnapshot) {
    if snapshot.id == "resting-hr" {
      selectedHealthMonitorTrend = snapshot
    } else {
      openHealth(.healthMonitor)
    }
  }

}
