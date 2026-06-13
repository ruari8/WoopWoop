import Darwin
import Foundation
import SwiftUI
import UIKit

@MainActor
final class HealthDataStore: ObservableObject {
  @Published var algorithmDefinitions: [HealthAlgorithmDefinition]
  @Published var referenceDefinitions: [HealthAlgorithmDefinition]
  @Published var selectedAlgorithmByFamily: [String: String]
  @Published var catalogStatus = "Metric catalog not loaded"
  @Published var catalogSource = HealthDataSource.unavailable("metric registry not loaded")
  @Published var packetInputStatus = "No run"
  @Published var packetInputIsRunning = false
  @Published var packetScoreStatus = "No run"
  @Published var packetScoreIsRunning = false
  @Published var bandSleepImportStatus = "No band sync yet"
  @Published var externalSleepImportStatus = "External sleep imports disabled"
  @Published var referenceRunStatusByFamily: [String: String] = [:]
  @Published var primarySleepDetail: PrimarySleepDetail?
  @Published var calibrationTargetFamily = "recovery"
  @Published var calibrationLabelsImported = false
  @Published var calibrationRunComplete = false
  @Published var heartRateHourlyRanges: [HeartRateHourlyRange] = []
  @Published var heartRateTimelineStatus = "No HR samples stored"
  @Published var currentStressSummary = HealthDataStore.emptyStressSummaryValue(
    status: "No HR data",
    freshness: "No HR samples stored",
    source: .unavailable("stress requires heart-rate samples")
  )
  @Published var currentEnergyBankSummary = HealthDataStore.emptyEnergyBankSummaryValue(
    status: "No stress data",
    freshness: "No HR samples stored",
    source: .unavailable("energy bank requires stress windows")
  )

  let bridge = GooseRustBridge()
  let heartRateSeriesStore = HeartRateSeriesStore.shared
  var attemptedCatalogLoad = false
  var previewMissingData = false
  var packetInputReports: [String: [String: Any]] = [:]
  var safePacketMetricRowsByReport: [String: [[String: Any]]] = [:]
  var preferredDailyRecoveryUnavailableMetricByCacheKey: [String: [String: Any]] = [:]
  var packetScoreReports: [String: [String: Any]] = [:]
  var referenceComparisonReports: [String: [String: Any]] = [:]
  var packetInputRefreshWorkItem: DispatchWorkItem?
  var packetInputRunID: UUID?
  var packetScoreRunID: UUID?
  var heartRateTimelineRefreshID: UUID?
  var currentStressEnergySummaryDayStart = Calendar.current.startOfDay(for: Date())
  var heartRateSeriesUpdateObserver: NSObjectProtocol?
  let packetInputQueue = DispatchQueue(label: "com.goose.swift.health.packet-inputs", qos: .utility)
  let packetScoreQueue = DispatchQueue(label: "com.goose.swift.health.packet-scores", qos: .utility)
  let heartRateTimelineQueue = DispatchQueue(label: "com.goose.swift.health.heart-rate-timeline", qos: .utility)
  let bridgeCatalogQueue = DispatchQueue(label: "com.goose.swift.health.bridge-catalogs", qos: .userInitiated)
  var catalogRefreshInFlight = false
  lazy var databasePath = HealthDataStore.defaultDatabasePath()

  nonisolated static let liveHRVRMSSDDefaultsKey = "goose.swift.liveHRVRMSSD"
  nonisolated static let liveHRVRRIntervalCountDefaultsKey = "goose.swift.liveHRVRRIntervalCount"
  nonisolated static let liveHRVRMSSDSampleCountDefaultsKey = "goose.swift.liveHRVRMSSDSampleCount"
  nonisolated static let liveHRVUpdatedAtDefaultsKey = "goose.swift.liveHRVUpdatedAt"
  nonisolated static let liveHRVSourceDefaultsKey = "goose.swift.liveHRVSource"
  nonisolated static let restingHeartRateEstimateBPMDefaultsKey = "goose.swift.restingHeartRateEstimateBPM"
  nonisolated static let restingHeartRateEstimateSampleCountDefaultsKey = "goose.swift.restingHeartRateEstimateSampleCount"
  nonisolated static let restingHeartRateEstimateUpdatedAtDefaultsKey = "goose.swift.restingHeartRateEstimateUpdatedAt"
  nonisolated static let restingHeartRateEstimateSourceDefaultsKey = "goose.swift.restingHeartRateEstimateSource"

  init() {
    algorithmDefinitions = []
    referenceDefinitions = []
    selectedAlgorithmByFamily = [:]
    primarySleepDetail = nil
    refreshHeartRateTimeline()
    heartRateSeriesUpdateObserver = NotificationCenter.default.addObserver(
      forName: HeartRateSeriesStore.didUpdateNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.refreshHeartRateTimeline()
      }
    }
  }

  deinit {
    if let heartRateSeriesUpdateObserver {
      NotificationCenter.default.removeObserver(heartRateSeriesUpdateObserver)
    }
  }

  static func defaultDatabasePath() -> String {
    let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    let directory = baseDirectory.appendingPathComponent("GooseSwift", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("goose.sqlite").path
  }

  var usesSampleData: Bool {
    false
  }

  var localDataSupportsExport: Bool {
    !packetInputReports.isEmpty || !packetScoreReports.isEmpty || !referenceComparisonReports.isEmpty
  }

  var localHealthExportText: String {
    [
      "Goose Health Export",
      "Catalog: \(catalogStatus)",
      "Band sleep import: \(bandSleepImportStatus)",
      "HealthKit metric import: disabled; profile weight only",
      "Packet inputs: \(packetInputStatus)",
      "Packet scores: \(packetScoreStatus)",
      "Readiness: \(metricInputReadinessSummary())",
      "Sleep: \(sleepFeatureScoreSummary())",
      "Recovery: \(recoveryFeatureScoreSummary())",
      "Strain: \(strainFeatureScoreSummary())",
      "Stress: \(stressFeatureScoreSummary())",
    ].joined(separator: "\n")
  }

  func loadBridgeCatalogsIfNeeded() {
    guard !attemptedCatalogLoad else {
      return
    }
    attemptedCatalogLoad = true
    refreshBridgeCatalogs()
  }

  /// Synchronously guarantees the metric catalogs are populated before returning. Used by
  /// explicit, user-initiated actions that immediately read `algorithmDefinitions` (not the
  /// render-path `onAppear` loaders, which use the async `refreshBridgeCatalogs`). After the
  /// persistent-connection change this is a cheap query rather than a full migrate.
  func ensureBridgeCatalogsLoaded() {
    guard algorithmDefinitions.isEmpty else {
      return
    }
    attemptedCatalogLoad = true
    applyBridgeCatalogResult(HealthDataStore.bridgeCatalogValues())
  }

  func refreshPacketInputsIfNeeded() {
    guard packetInputReports.isEmpty, packetInputStatus == "No run" else {
      return
    }
    runPacketInputs()
  }

  func refreshHeartRateTimeline(for date: Date = Date()) {
    let refreshID = UUID()
    heartRateTimelineRefreshID = refreshID
    let store = heartRateSeriesStore
    let previewMissingData = previewMissingData
    let recoverySeed = recoveryScoreValue()
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: date)
    heartRateTimelineQueue.async { [weak self] in
      let snapshot = store.timelineSnapshot(forDayContaining: date, calendar: calendar)
      let samples = store.samples(forDayContaining: date, calendar: calendar)
      let stressSummary = HealthDataStore.computeStressAlgorithmSummary(
        samples: samples,
        date: date,
        calendar: calendar,
        previewMissingData: previewMissingData,
        heartRateTimelineStatus: snapshot.status,
        allowLiveFallbacks: true
      )
      let energyBankSummary = HealthDataStore.computeEnergyBankAlgorithmSummary(
        stress: stressSummary,
        recoverySeed: recoverySeed
      )
      Task { @MainActor in
        guard let self,
              self.heartRateTimelineRefreshID == refreshID else {
          return
        }
        if self.heartRateHourlyRanges != snapshot.ranges {
          self.heartRateHourlyRanges = snapshot.ranges
        }
        if self.heartRateTimelineStatus != snapshot.status {
          self.heartRateTimelineStatus = snapshot.status
        }
        self.currentStressEnergySummaryDayStart = dayStart
        self.currentStressSummary = stressSummary
        self.currentEnergyBankSummary = energyBankSummary
      }
    }
  }

  func heartRateHourlyTimelineRows(maxRows: Int = 8) -> [HealthSummaryRow] {
    let ranges = Array(heartRateHourlyRanges.suffix(maxRows)).reversed()
    guard !ranges.isEmpty else {
      return []
    }

    return ranges.map { range in
      let hour = range.hourStart.formatted(.dateTime.hour(.twoDigits(amPM: .abbreviated)))
      return HealthSummaryRow(
        "HR \(hour)",
        value: "\(range.minBPM)-\(range.maxBPM) bpm | avg \(range.averageBPM) | \(range.sampleCount) samples",
        source: .live("BLE heart-rate sample store"),
        systemImage: "heart"
      )
    }
  }

  func refreshPacketInputsAfterCapture() {
    packetInputRefreshWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in
      self?.runPacketInputs()
    }
    packetInputRefreshWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
  }

  func refreshBridgeCatalogs() {
    // The three catalog calls cross the Rust FFI (SQLite open + query + JSON), which must
    // not run on the main thread. Do the FFI on a background queue, then hop back to the
    // main actor for the cheap parsing and @Published assignment.
    guard !catalogRefreshInFlight else {
      return
    }
    catalogRefreshInFlight = true

    bridgeCatalogQueue.async { [weak self] in
      let result = HealthDataStore.bridgeCatalogValues()
      DispatchQueue.main.async { [weak self] in
        guard let self else {
          return
        }
        self.catalogRefreshInFlight = false
        self.applyBridgeCatalogResult(result)
      }
    }
  }

  /// Runs the three metric-registry bridge calls off the main thread. Returns the raw
  /// decoded values; parsing into model types happens back on the main actor.
  nonisolated static func bridgeCatalogValues() -> Result<(algorithms: Any, references: Any, preferences: Any), Error> {
    let bridge = GooseRustBridge()
    do {
      let algorithmsValue = try bridge.requestValue(method: "metrics.built_in_definitions")
      let referencesValue = try bridge.requestValue(method: "metrics.reference_definitions")
      let preferencesValue = try bridge.requestValue(method: "metrics.default_preferences")
      return .success((algorithmsValue, referencesValue, preferencesValue))
    } catch {
      return .failure(error)
    }
  }

  private func applyBridgeCatalogResult(_ result: Result<(algorithms: Any, references: Any, preferences: Any), Error>) {
    switch result {
    case .success(let values):
      let parsedAlgorithms = Self.algorithmRows(from: values.algorithms)
        .map { HealthAlgorithmDefinition(row: $0, source: .bridge("metrics.built_in_definitions")) }
      let parsedReferences = Self.algorithmRows(from: values.references)
        .map { HealthAlgorithmDefinition(row: $0, source: .bridge("metrics.reference_definitions")) }
      let parsedPreferences = Self.preferenceRows(from: values.preferences)

      if !parsedAlgorithms.isEmpty {
        algorithmDefinitions = parsedAlgorithms
      }
      if !parsedReferences.isEmpty {
        referenceDefinitions = parsedReferences
      }
      if !parsedPreferences.isEmpty {
        selectedAlgorithmByFamily = parsedPreferences
      } else {
        selectedAlgorithmByFamily = Dictionary(
          uniqueKeysWithValues: algorithmDefinitions.map { ($0.family, $0.id) }
        )
      }
      catalogSource = .bridge("Rust metric registry")
      catalogStatus = "Bridge catalog loaded"
    case .failure(let error):
      algorithmDefinitions = []
      referenceDefinitions = []
      selectedAlgorithmByFamily = [:]
      catalogSource = .unavailable("Rust catalog unavailable")
      catalogStatus = "Metric catalog unavailable: \(Self.shortError(error))"
    }
  }

  func selectAlgorithm(_ algorithmID: String, for family: String) {
    selectedAlgorithmByFamily[family] = algorithmID
  }

  func runPacketInputs(completion: (() -> Void)? = nil) {
    guard !packetInputIsRunning else {
      packetInputStatus = "Packet-derived input extraction already running..."
      completion?()
      return
    }
    packetInputRefreshWorkItem?.cancel()
    let runID = UUID()
    packetInputRunID = runID
    packetInputIsRunning = true
    let databasePath = databasePath
    packetInputStatus = "Extracting packet-derived inputs..."

    packetInputQueue.async {
      let result: Result<(
        reports: [String: [String: Any]],
        safeMetricRowsByReport: [String: [[String: Any]]],
        preferredDailyRecoveryUnavailableMetricByCacheKey: [String: [String: Any]]
      ), Error>
      switch HealthDataStore.packetInputBridgeReports(databasePath: databasePath) {
      case .success(let reports):
        let safeMetricRowsByReport = HealthDataStore.safePacketMetricRowsByReport(from: reports)
        let unavailableMetricsByCacheKey = HealthDataStore
          .preferredDailyRecoveryUnavailableMetricByCacheKey(
            from: safeMetricRowsByReport["daily_recovery"] ?? []
          )
        result = .success((
          reports: reports,
          safeMetricRowsByReport: safeMetricRowsByReport,
          preferredDailyRecoveryUnavailableMetricByCacheKey: unavailableMetricsByCacheKey
        ))
      case .failure(let error):
        result = .failure(error)
      }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.packetInputRunID == runID else {
          return
        }
        self.packetInputIsRunning = false
        switch result {
        case .success(let values):
          self.applyPacketInputReports(
            values.reports,
            safeMetricRowsByReport: values.safeMetricRowsByReport,
            preferredDailyRecoveryUnavailableMetricByCacheKey: values
              .preferredDailyRecoveryUnavailableMetricByCacheKey
          )
          self.packetInputStatus = "Bridge packet-derived inputs extracted"
        case .failure(let error):
          self.packetInputStatus = "Bridge input extraction blocked: \(HealthDataStore.shortError(error))"
        }
        completion?()
      }
    }
  }

  func applyPacketInputReports(
    _ reports: [String: [String: Any]],
    safeMetricRowsByReport: [String: [[String: Any]]],
    preferredDailyRecoveryUnavailableMetricByCacheKey: [String: [String: Any]] = [:]
  ) {
    packetInputReports = reports
    self.safePacketMetricRowsByReport = safeMetricRowsByReport
    self.preferredDailyRecoveryUnavailableMetricByCacheKey =
      preferredDailyRecoveryUnavailableMetricByCacheKey
  }

  nonisolated static func safePacketMetricRowsByReport(
    from reports: [String: [String: Any]]
  ) -> [String: [[String: Any]]] {
    var rowsByReport: [String: [[String: Any]]] = [:]
    for reportKey in ["daily_recovery", "daily_activity", "hourly_activity"] {
      let rows = Self.array(reports[reportKey]?["metrics"])
        .filter { Self.localHealthMetricRowIsDisplaySafe($0) }
      if !rows.isEmpty {
        rowsByReport[reportKey] = rows
      }
    }
    return rowsByReport
  }

  func safePacketMetricRows(for reportKey: String) -> [[String: Any]] {
    safePacketMetricRowsByReport[reportKey] ?? []
  }

  nonisolated static var cachedDailyRecoveryUnavailableMetricIDs: [String] {
    [
      "respiratory_rate_rpm",
      "oxygen_saturation_percent",
      "skin_temperature_delta_c",
      "hrv_rmssd_ms",
    ]
  }

  nonisolated static func preferredDailyRecoveryUnavailableMetricByCacheKey(
    from dailyRecoveryMetrics: [[String: Any]]
  ) -> [String: [String: Any]] {
    var metricsByCacheKey: [String: [String: Any]] = [:]
    let metricIDs = cachedDailyRecoveryUnavailableMetricIDs
    for metric in dailyRecoveryMetrics {
      guard metric["source_kind"] as? String == "unavailable",
            Self.doubleValue(metric["confidence"]) != nil else {
        continue
      }
      for metricID in metricIDs where Self.dailyRecoveryUnavailableMetric(metric, matches: metricID) {
        cachePreferredDailyRecoveryUnavailableMetric(metric, metricID: metricID, in: &metricsByCacheKey)
        if let dateKey = metric["date_key"] as? String ?? metric["date"] as? String {
          cachePreferredDailyRecoveryUnavailableMetric(
            metric,
            metricID: metricID,
            dateKey: dateKey,
            in: &metricsByCacheKey
          )
        }
      }
    }
    return metricsByCacheKey
  }

  nonisolated static func dailyRecoveryUnavailableMetricCacheKey(
    metricID: String,
    dateKey: String?
  ) -> String {
    "\(metricID)|\(dateKey ?? "*")"
  }

  nonisolated private static func cachePreferredDailyRecoveryUnavailableMetric(
    _ metric: [String: Any],
    metricID: String,
    dateKey: String? = nil,
    in metricsByCacheKey: inout [String: [String: Any]]
  ) {
    let key = dailyRecoveryUnavailableMetricCacheKey(metricID: metricID, dateKey: dateKey)
    if let existing = metricsByCacheKey[key],
       !dailyRecoveryMetric(metric, isBetterThan: existing, valueKey: "confidence") {
      return
    }
    metricsByCacheKey[key] = metric
  }

  func markBandSleepSyncRequested(automatic: Bool, canSync: Bool, detail: String) {
    if canSync {
      bandSleepImportStatus = automatic ? "Auto-syncing band sleep packets..." : "Syncing band sleep packets..."
    } else {
      bandSleepImportStatus = "Band sync unavailable: \(detail)"
    }
  }

  func markBandSleepSyncFailed(_ detail: String) {
    bandSleepImportStatus = "Band sync failed: \(detail)"
  }

  func refreshSleepAfterBandSync(packetCount: Int) {
    bandSleepImportStatus = "Band sync captured \(packetCount) packets | extracting sleep inputs..."
    runPacketInputs { [weak self] in
      guard let self else {
        return
      }
      self.runSleepScore()
      self.bandSleepImportStatus = "Band sync captured \(packetCount) packets | \(self.packetScoreStatus)"
    }
  }
}
