import Darwin
import Foundation
import SwiftUI
import UIKit

struct HealthView: View {
  let model: GooseAppModel
  let liveVitals: GooseLiveVitalsStore
  @ObservedObject var store: HealthDataStore

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 22) {
        HealthDashboardStatusHeader(
          catalogStatus: store.catalogStatus,
          usesSampleData: store.usesSampleData
        )

        HealthActivityOverviewContainer(store: store, liveVitals: liveVitals)

        HealthVitalsPreviewSection(snapshots: vitalSnapshots)

        HealthRouteShortcutSection(
          title: "Explore Health",
          snapshots: snapshots(for: [.sleep, .recovery, .strain, .stress, .cardioLoad, .energyBank])
        )

        HealthRouteShortcutSection(
          title: "Data & Algorithms",
          snapshots: snapshots(for: [.packetInputs, .algorithms, .calibration])
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 18)
    }
    .gooseScreenBackground()
    .navigationTitle("Health")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationDestination(for: HealthRoute.self) { route in
      HealthRouteContentView(
        route: route,
        store: store,
        ble: model.ble,
        liveVitals: liveVitals,
        activitySession: model.activitySession,
        recordUIAction: model.recordUIAction
      )
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          refreshDashboard()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .accessibilityLabel("Refresh Health")
      }
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "Health")
      store.loadBridgeCatalogsIfNeeded()
      store.refreshHeartRateTimeline()
    }
  }

  private var landingSnapshots: [HealthMetricSnapshot] {
    store
      .landingSnapshots(
        liveHeartRateBPM: nil,
        liveHeartRateSource: "health dashboard stable route snapshots",
        liveHeartRateUpdatedAt: nil
      )
  }

  private var vitalSnapshots: [HealthMetricSnapshot] {
    Array(store.healthMonitorSnapshots().prefix(4))
  }

  private func snapshots(for routes: [HealthRoute]) -> [HealthMetricSnapshot] {
    routes.compactMap { route in
      landingSnapshots.first { $0.route == route } ?? store.snapshot(for: route)
    }
  }

  @MainActor
  private func refreshDashboard() {
    store.refreshBridgeCatalogs()
    store.refreshHeartRateTimeline()
    store.refreshPacketInputsIfNeeded()
  }
}

private struct HealthActivityOverviewContainer: View {
  @ObservedObject var store: HealthDataStore
  @ObservedObject var liveVitals: GooseLiveVitalsStore

  var body: some View {
    HealthActivityOverviewSection(
      steps: store.whoopStepsDisplayText(),
      activeEnergy: store.whoopActiveCaloriesDisplayText(),
      stepsFreshness: store.whoopStepsStatusText(),
      stepsSource: store.whoopStepsSource(),
      activeEnergyFreshness: store.whoopActiveCaloriesStatusText(),
      activeEnergySource: store.whoopActiveCaloriesSource(),
      heartRateValue: liveHeartRateValue,
      heartRateStatus: liveHeartRateStatus,
      heartRateSource: liveHeartRateSource
    )
  }

  private var liveHeartRateValue: String {
    guard let bpm = liveVitals.liveHeartRateBPM else {
      return "--"
    }
    return "\(bpm) bpm"
  }

  private var liveHeartRateStatus: String {
    guard liveVitals.liveHeartRateBPM != nil else {
      return store.heartRateTimelineStatus
    }
    return HealthDataStore.relativeText(for: liveVitals.liveHeartRateUpdatedAt) ?? "Live"
  }

  private var liveHeartRateSource: HealthDataSource {
    liveVitals.liveHeartRateBPM == nil
      ? .unavailable("BLE heart-rate stream waiting")
      : .live(liveVitals.liveHeartRateSource)
  }
}
