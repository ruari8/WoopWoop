import Foundation
import CryptoKit
import SwiftUI
import UIKit

#if canImport(HealthKit)
import HealthKit
#endif

struct MoreView: View {
  let model: GooseAppModel
  let ble: GooseBLEClient
  @ObservedObject var connectionStatus: GooseConnectionStatusStore
  @EnvironmentObject private var router: AppRouter
  @ObservedObject private var healthStore: HealthDataStore
  @StateObject private var store: MoreDataStore
  @AppStorage(OnboardingStorage.firstName) private var profileFirstName = ""
  @AppStorage(OnboardingStorage.unitSystem) private var profileUnitSystemRaw = "imperial"
  @AppStorage(OnboardingStorage.heightMm) private var profileHeightMm = 0
  @AppStorage(OnboardingStorage.weightGrams) private var profileWeightGrams = 0

  @MainActor
  init(
    model: GooseAppModel,
    ble: GooseBLEClient,
    connectionStatus: GooseConnectionStatusStore,
    healthStore: HealthDataStore
  ) {
    self.model = model
    self.ble = ble
    self.connectionStatus = connectionStatus
    self.healthStore = healthStore
    _store = StateObject(wrappedValue: MoreDataStore())
  }

  @MainActor
  init(
    model: GooseAppModel,
    ble: GooseBLEClient,
    connectionStatus: GooseConnectionStatusStore,
    healthStore: HealthDataStore,
    store: MoreDataStore
  ) {
    self.model = model
    self.ble = ble
    self.connectionStatus = connectionStatus
    self.healthStore = healthStore
    _store = StateObject(wrappedValue: store)
  }

  var body: some View {
    let status = routeStatus
    List {
      Section {
        NavigationLink(value: MoreRoute.profile) {
          MoreGreetingHeader(
            firstName: profileFirstName,
            profileSummary: profileSummary
          )
        }
        .accessibilityLabel("Update profile")
      }

      Section("Device") {
        routeRows(MoreRoute.deviceRoutes, routeStatus: status)
      }

      Section("App") {
        routeRows(MoreRoute.appRoutes, routeStatus: status)
      }

      Section("Settings") {
        routeRows(MoreRoute.settingsRoutes, routeStatus: status)
      }

      Section("Support") {
        routeRows(MoreRoute.supportRoutes, routeStatus: status)
      }

      Section("Developer") {
        routeRows(MoreRoute.developerRoutes, routeStatus: status)
      }
    }
    .listStyle(.insetGrouped)
    .gooseListBackground()
    .navigationTitle("More")
    .navigationBarTitleDisplayMode(.inline)
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationDestination(for: MoreRoute.self) { route in
      destination(for: route)
    }
    .onAppear {
      model.recordUIAction("page.opened", detail: "More")
      store.refreshBridgeStatus(model: model)
      store.refreshRecentCaptureSessions()
    }
  }

  private var routeStatus: MoreRouteStatus {
    store.routeStatus(connectionState: connectionStatus.connectionState, model: model)
  }

  @ViewBuilder
  private func routeRows(_ routes: [MoreRoute], routeStatus: MoreRouteStatus) -> some View {
    ForEach(routes) { route in
      NavigationLink(value: route) {
        MoreRouteRow(route: route, status: routeStatus[keyPath: route.statusKeyPath])
      }
      .accessibilityLabel(route.title)
    }
  }

  @ViewBuilder
  private func destination(for route: MoreRoute) -> some View {
    switch route {
    case .device:
      DeviceView(model: model)
    case .profile:
      MoreProfileView(model: model)
    case .connectionLab:
      ConnectionView(
        ble: ble,
        rustStatus: model.rustStatus,
        helloSummary: model.helloSummary
      )
    case .capture:
      MoreCaptureView(
        model: model,
        ble: ble,
        connectionStatus: ble.connectionStatus,
        deviceStatus: ble.deviceStatus,
        historicalSync: ble.historicalSyncStatusStore,
        overnightGuard: model.overnightGuardStatusStore,
        store: store
      )
    case .localStore:
      MoreLocalStoreView(store: store)
    case .healthSync:
      MoreHealthSyncView(store: store)
    case .rawExport:
      MoreRawExportView(store: store)
    case .algorithms:
      MoreAlgorithmsView(store: store, healthStore: healthStore) {
        router.openHealth(.algorithms)
      }
    case .debug:
      MoreDebugView(
        model: model,
        ble: ble,
        packetMonitor: model.packetMonitor,
        healthCapture: model.healthCaptureStatus,
        connectionStatus: ble.connectionStatus,
        deviceStatus: ble.deviceStatus,
        historicalSync: ble.historicalSyncStatusStore,
        store: store
      )
    case .privacy:
      MorePrivacyView(store: store)
    case .support:
      MoreSupportView(store: store)
    case .about:
      MoreAboutView(
        model: model,
        deviceStatus: ble.deviceStatus,
        store: store
      )
    case .developer:
      MoreDeveloperView(routes: MoreRoute.developerToolRoutes, routeStatus: routeStatus)
    }
  }

  private var profileSummary: String {
    let height = MoreProfileFormatting.heightText(millimeters: profileHeightMm, unitSystemRaw: profileUnitSystemRaw)
    let weight = MoreProfileFormatting.weightText(grams: profileWeightGrams, unitSystemRaw: profileUnitSystemRaw)
    let parts = [height, weight].filter { !$0.isEmpty }
    return parts.isEmpty ? "Update profile" : parts.joined(separator: " | ")
  }
}
