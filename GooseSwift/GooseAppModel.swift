import Foundation
import UIKit


@MainActor
final class HomeActivityTimelineStore: ObservableObject {
  @Published var items: [ActivityTimelineItem] = []
  @Published var status = "Activity timeline not loaded"
}

@MainActor
final class GooseAppModel: ObservableObject {
  @Published var onboardingComplete = false
  @Published var rustStatus = "Rust bridge not checked"
  @Published var helloSummary = "Client hello not prepared"
  @Published var packetImportRevision = 0
  @Published var packetImportStatus = "No packet import"
  @Published var activityPersistenceStatus = "No activity stored"
  var activityDetectionStatus = "Watching for movement packets" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var movementPacketValidationStatus = "Not run" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var movementPacketValidationIsRunning = false {
    didSet { syncHealthCaptureStatusStore() }
  }
  @Published var heartRateHourlyRanges: [HeartRateHourlyRange] = []
  @Published var heartRateStorageStatus = "No HR samples stored"
  var healthPacketCaptureSessionID: String? {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureStatus = "No health packet capture" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureStartedAt: Date? {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureFrameCount = 0 {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureTargetSummary = "No health packet capture" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureLastPacketSummary = "No packets captured" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var healthPacketCaptureFamilyRows: [HealthPacketCaptureFamily] = [] {
    didSet { syncHealthCaptureStatusStore() }
  }
  var respiratoryPacketWatchActive = false {
    didSet { syncHealthCaptureStatusStore() }
  }
  var respiratoryPacketWatchStatus = "Not watching K18 respiratory history" {
    didSet { syncHealthCaptureStatusStore() }
  }
  var overnightGuardActive = false {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardStatus = "Not started" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardReadinessStatus = "pending" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardReadinessSummary = "Not sleep-ready | connect WHOOP and start Overnight Guard" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardRawNotificationCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardRangePollCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardRangeTelemetryCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardSuccessfulRangePollCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardCommandWriteCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardEventLogCount = 0 {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardTargetSummary = OvernightGuardTargetCounts().summary {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardHistoricalOrderSummary = OvernightGuardHistoricalOrderEvidence().summary {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardLastPacketSummary = "No raw notifications" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardSpoolPath = "No overnight spool" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardSpoolSizeSummary = "No overnight spool size" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardSQLiteMirrorSummary = "SQLite mirror not started" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardPowerSummary = "Power not checked" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardWatchdogSummary = "Watchdog not checked" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardWarning = "Keep the official WHOOP app closed until Goose final sync/export finishes." {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardExportStatus = "No overnight export" {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardExportInProgress = false {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardExportURL: URL? {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardExportManifestURL: URL? {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardExportManifestError: String? {
    didSet { syncOvernightGuardStatusStore() }
  }
  var overnightGuardCanExportLastSession = false {
    didSet { syncOvernightGuardStatusStore() }
  }

  let ble: GooseBLEClient
  let homeActivityTimeline = HomeActivityTimelineStore()
  let packetMonitor = PacketMonitorModel()
  let healthCaptureStatus = GooseHealthCaptureStatusStore()
  let overnightGuardStatusStore = GooseOvernightGuardStatusStore()
  let activitySession = ActivitySessionModel()
  let activityLocationTracker = ActivityLocationTracker()
  let rust = GooseRustBridge()
  let notificationFrameParser = NotificationFrameParser()
  let notificationIngestQueue = DispatchQueue(label: "com.goose.swift.notification-ingest", qos: .utility)
  let notificationIngestStateLock = NSLock()
  let notificationParseQueue = DispatchQueue(label: "com.goose.swift.notification-parse", qos: .utility)
  let notificationParseStateLock = NSLock()
  let captureFrameRowBuildQueue = DispatchQueue(label: "com.goose.swift.capture-frame-row-build", qos: .utility)
  let rustStartupQueue = DispatchQueue(label: "com.goose.swift.rust-startup", qos: .utility)
  let activityTimelineRefreshQueue = DispatchQueue(label: "com.goose.swift.activity-timeline-refresh", qos: .utility)
  let captureStatusSnapshotWriteQueue = DispatchQueue(label: "com.goose.swift.capture-status-snapshot", qos: .utility)
  let heartRateSamplePipeline = HeartRateSamplePipeline(
    timelinePublishInterval: GooseAppModel.heartRateHourlyRangePublishInterval
  )
  let packetUIStateAggregator = PacketUIStateAggregator(
    publishInterval: GooseAppModel.packetUIStatePublishInterval,
    maximumPendingDeviceSignalPoints: GooseAppModel.maxRecentDeviceSignalPoints
  )
  let whoopDataSignalPipeline: WhoopDataSignalPipeline
  let healthPacketCaptureFamilyAggregator = HealthPacketCaptureFamilyAggregator(
    publishInterval: GooseAppModel.healthPacketCaptureUIUpdateInterval
  )
  let captureFrameWriteQueue = CaptureFrameWriteQueue(
    databasePath: HealthDataStore.defaultDatabasePath(),
    maxQueuedRows: GooseAppModel.captureFrameWriteQueueMaxRows,
    maxBatchRows: GooseAppModel.captureFrameWriteBatchMaxRows
  )
  let captureFrameEnqueueAggregator = CaptureFrameEnqueueAggregator(
    publishInterval: GooseAppModel.packetUIStatePublishInterval
  )
  let overnightSQLiteMirror = OvernightSQLiteMirrorQueue(databasePath: HealthDataStore.defaultDatabasePath())
  let passiveActivityDetectionPipeline = PassiveActivityDetectionPipeline()
  var activeActivityPersistence: ActiveActivityPersistence?
  var activeActivityOwnsCaptureSession = false
  var activityRequestedHighFrequencyHistorySync = false
  var activeHealthPacketCapture: ActiveHealthPacketCapture?
  let overnightRawSpool = OvernightRawNotificationSpool()
  var overnightGuardSession: OvernightGuardSession?
  var overnightGuardHeartbeatWorkItem: DispatchWorkItem?
  var overnightGuardRangePollWorkItem: DispatchWorkItem?
  var overnightGuardFinalSyncDrainWorkItem: DispatchWorkItem?
  var overnightGuardFinalSyncPending = false
  var overnightGuardCriticalBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
  var overnightGuardCriticalBackgroundTaskReason: String?
  var overnightGuardStartedHealthCapture = false
  var overnightGuardTargetCounts = OvernightGuardTargetCounts()
  var overnightGuardHistoricalOrder = OvernightGuardHistoricalOrderEvidence()
  var overnightGuardPowerWarning: String?
  var overnightGuardWatchdogWarning: String?
  var overnightGuardRawSpoolWarning: String?
  var overnightGuardBLELogWarning: String?
  var overnightGuardSQLiteMirrorWarning: String?
  var overnightGuardWroteInitialRawNotificationStatus = false
  var overnightGuardWroteInitialSQLiteMirrorStatus = false
  var overnightGuardLastRawStaleWarningAt = Date.distantPast
  var overnightGuardLastRangeSuccessWarningAt = Date.distantPast
  var overnightGuardLastTargetMissingWarningAt = Date.distantPast
  var activityDetectionIdleWorkItem: DispatchWorkItem?
  var movementPacketValidation = MovementPacketValidation()
  var movementPacketValidationTimeoutWorkItem: DispatchWorkItem?
  var packetImportRevisionWorkItem: DispatchWorkItem?
  var healthPacketCaptureTimeoutWorkItem: DispatchWorkItem?
  var healthPacketCaptureStreamRetryWorkItem: DispatchWorkItem?
  var healthPacketCaptureUIUpdateWorkItem: DispatchWorkItem?
  var respiratoryPacketWatchTimeoutWorkItem: DispatchWorkItem?
  var autoStartRespiratoryPacketWatchWorkItem: DispatchWorkItem?
  var temperatureHistorySyncWorkItem: DispatchWorkItem?
  var healthPacketCaptureStreamRetryAttempt = 0
  var autoStartHealthPacketCaptureWorkItem: DispatchWorkItem?
  var autoStartHealthPacketCaptureAttempt = 0
  var autoStartRespiratoryPacketWatchAttempt = 0
  var passiveActivityCaptureWorkItem: DispatchWorkItem?
  var healthPacketCaptureFamilyRowsByID: [String: HealthPacketCaptureFamily] = [:]
  var lastParsedFrameSummary: String { packetMonitor.lastParsedFrameSummary }
  var movementPacketStatus: String { packetMonitor.movementPacketStatus }
  var latestWhoopEventStatus: String { packetMonitor.latestWhoopEventStatus }
  var latestSkinTemperatureCandidateStatus: String { packetMonitor.latestSkinTemperatureCandidateStatus }
  var latestWhoopDataPacketStatus: String { packetMonitor.latestWhoopDataPacketStatus }
  var latestHistoryTemperatureCandidateStatus: String { packetMonitor.latestHistoryTemperatureCandidateStatus }
  var latestRespiratoryRateCandidateStatus: String { packetMonitor.latestRespiratoryRateCandidateStatus }
  var latestPulseInformationPacketStatus: String { packetMonitor.latestPulseInformationPacketStatus }
  var latestOpticalPacketStatus: String { packetMonitor.latestOpticalPacketStatus }
  var latestRawResearchPacketStatus: String { packetMonitor.latestRawResearchPacketStatus }
  var latestRealtimeStatusPacketStatus: String { packetMonitor.latestRealtimeStatusPacketStatus }
  var performancePipelineStatus: String { packetMonitor.performancePipelineStatus }
  var liveDeviceDataSummary: String { packetMonitor.liveDeviceDataSummary }
  var recentDeviceSignalPoints: [DeviceSignalPoint] { packetMonitor.recentDeviceSignalPoints }
  func syncHealthCaptureStatusStore() {
    healthCaptureStatus.apply(
      activityDetectionStatus: activityDetectionStatus,
      movementPacketValidationStatus: movementPacketValidationStatus,
      movementPacketValidationIsRunning: movementPacketValidationIsRunning,
      healthPacketCaptureSessionID: healthPacketCaptureSessionID,
      healthPacketCaptureStatus: healthPacketCaptureStatus,
      healthPacketCaptureStartedAt: healthPacketCaptureStartedAt,
      healthPacketCaptureFrameCount: healthPacketCaptureFrameCount,
      healthPacketCaptureTargetSummary: healthPacketCaptureTargetSummary,
      healthPacketCaptureLastPacketSummary: healthPacketCaptureLastPacketSummary,
      healthPacketCaptureFamilyRows: healthPacketCaptureFamilyRows,
      respiratoryPacketWatchActive: respiratoryPacketWatchActive,
      respiratoryPacketWatchStatus: respiratoryPacketWatchStatus
    )
  }
  func syncOvernightGuardStatusStore() {
    overnightGuardStatusStore.apply(
      active: overnightGuardActive,
      status: overnightGuardStatus,
      readinessStatus: overnightGuardReadinessStatus,
      readinessSummary: overnightGuardReadinessSummary,
      rawNotificationCount: overnightGuardRawNotificationCount,
      rangePollCount: overnightGuardRangePollCount,
      rangeTelemetryCount: overnightGuardRangeTelemetryCount,
      successfulRangePollCount: overnightGuardSuccessfulRangePollCount,
      commandWriteCount: overnightGuardCommandWriteCount,
      eventLogCount: overnightGuardEventLogCount,
      targetSummary: overnightGuardTargetSummary,
      historicalOrderSummary: overnightGuardHistoricalOrderSummary,
      lastPacketSummary: overnightGuardLastPacketSummary,
      spoolPath: overnightGuardSpoolPath,
      spoolSizeSummary: overnightGuardSpoolSizeSummary,
      sqliteMirrorSummary: overnightGuardSQLiteMirrorSummary,
      powerSummary: overnightGuardPowerSummary,
      watchdogSummary: overnightGuardWatchdogSummary,
      warning: overnightGuardWarning,
      exportStatus: overnightGuardExportStatus,
      exportInProgress: overnightGuardExportInProgress,
      exportURL: overnightGuardExportURL,
      exportManifestURL: overnightGuardExportManifestURL,
      exportManifestError: overnightGuardExportManifestError,
      canExportLastSession: overnightGuardCanExportLastSession
    )
  }
  var homeActivityTimelineItems: [ActivityTimelineItem] {
    get { homeActivityTimeline.items }
    set { homeActivityTimeline.items = newValue }
  }
  var homeActivityTimelineStatus: String {
    get { homeActivityTimeline.status }
    set { homeActivityTimeline.status = newValue }
  }
  var pendingHealthPacketCaptureLastPacketSummary: String?
  var pendingPacketImportStatus: String?
  var lastPacketImportRevisionPublishedAt = Date.distantPast
  var lastHealthPacketCaptureUIUpdatedAt = Date.distantPast
  var lastHealthPacketCaptureSummaryLoggedAt = Date.distantPast
  var lastParsedFrameSummaryUpdatedAt = Date.distantPast
  var lastRestingHeartRateFrameWriteAt = Date.distantPast
  var lastMovementPacketStatusUpdatedAt = Date.distantPast
  var lastMovementPacketLoggedAt = Date.distantPast
  var lastMovementPacketLoggedMoving: Bool?
  var passiveActivityPacketCount = 0
  var movementPacketLogCount = 0
  var deviceSignalCountsByFamily: [String: Int] = [:]
  var notificationIngestQueueDepth = 0
  var notificationIngestQueueHighWatermark = 0
  var notificationParseQueueDepth = 0
  var notificationParseQueueHighWatermark = 0
  let captureFrameRowBuildStateLock = NSLock()
  var captureFrameRowBuildQueueDepth = 0
  var captureFrameRowBuildQueueHighWatermark = 0
  let pipelinePerformanceLogLock = NSLock()
  var lastPipelinePerformanceStatusPublishedAt = Date.distantPast
  var lastPipelinePerformanceLoggedAt = Date.distantPast
  var respiratoryPacketWatchK18Count = 0
  var respiratoryPacketWatchK24Count = 0
  var respiratoryPacketWatchStartedAt: Date?
  var lastWhoopEventLoggedAt = Date.distantPast
  var lastWhoopEventStatusUpdatedAt = Date.distantPast
  var activityTimelineRefreshGeneration = 0
  var skippedNotificationDiagnostics = SkippedNotificationDiagnostics()
  var frameReassemblyBuffers: [String: Data] = [:]
  let autoStartHealthPacketCaptureOnReady: Bool = {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-start-health-packet-capture")
      || processInfo.environment["GOOSE_START_HEALTH_PACKET_CAPTURE"] == "1"
  }()
  let autoStartTemperaturePacketCaptureOnReady: Bool = {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-start-temperature-packet-capture")
      || processInfo.environment["GOOSE_START_TEMPERATURE_PACKET_CAPTURE"] == "1"
  }()
  let autoStartPhysiologyPacketCaptureOnReady: Bool = {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-start-physiology-packet-capture")
      || processInfo.environment["GOOSE_START_PHYSIOLOGY_PACKET_CAPTURE"] == "1"
  }()
  let autoStartRespiratoryPacketWatchOnReady: Bool = {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-start-respiratory-packet-watch")
      || processInfo.environment["GOOSE_START_RESPIRATORY_PACKET_WATCH"] == "1"
  }()
  let autoStartHealthPacketCaptureDuration: TimeInterval = {
    let processInfo = ProcessInfo.processInfo
    if let value = processInfo.environment["GOOSE_HEALTH_PACKET_CAPTURE_DURATION_SECONDS"],
       let seconds = Double(value),
       seconds > 0 {
      return seconds
    }
    let prefix = "--goose-health-packet-capture-duration="
    if let argument = processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
       let seconds = Double(argument.dropFirst(prefix.count)),
       seconds > 0 {
      return seconds
    }
    return 30 * 60
  }()
  let autoStartTemperaturePacketCaptureDuration: TimeInterval = {
    let processInfo = ProcessInfo.processInfo
    if let value = processInfo.environment["GOOSE_TEMPERATURE_PACKET_CAPTURE_DURATION_SECONDS"],
       let seconds = Double(value),
       seconds > 0 {
      return seconds
    }
    let prefix = "--goose-temperature-packet-capture-duration="
    if let argument = processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
       let seconds = Double(argument.dropFirst(prefix.count)),
       seconds > 0 {
      return seconds
    }
    return 10 * 60
  }()
  let autoStartPhysiologyPacketCaptureDuration: TimeInterval = {
    let processInfo = ProcessInfo.processInfo
    if let value = processInfo.environment["GOOSE_PHYSIOLOGY_PACKET_CAPTURE_DURATION_SECONDS"],
       let seconds = Double(value),
       seconds > 0 {
      return seconds
    }
    let prefix = "--goose-physiology-packet-capture-duration="
    if let argument = processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
       let seconds = Double(argument.dropFirst(prefix.count)),
       seconds > 0 {
      return seconds
    }
    return 30 * 60
  }()
  let autoStartRespiratoryPacketWatchDuration: TimeInterval = {
    let processInfo = ProcessInfo.processInfo
    if let value = processInfo.environment["GOOSE_RESPIRATORY_PACKET_WATCH_DURATION_SECONDS"],
       let seconds = Double(value),
       seconds > 0 {
      return seconds
    }
    let prefix = "--goose-respiratory-packet-watch-duration="
    if let argument = processInfo.arguments.first(where: { $0.hasPrefix(prefix) }),
       let seconds = Double(argument.dropFirst(prefix.count)),
       seconds > 0 {
      return seconds
    }
    return 10 * 60
  }()
  let autoSyncHistoryDuringPhysiologyCapture: Bool = {
    let processInfo = ProcessInfo.processInfo
    return processInfo.arguments.contains("--goose-sync-history-during-physiology-capture")
      || processInfo.environment["GOOSE_SYNC_HISTORY_DURING_PHYSIOLOGY_CAPTURE"] == "1"
  }()
  let captureStatusSnapshotURL: URL? = {
    let processInfo = ProcessInfo.processInfo
    let enabled = processInfo.arguments.contains("--goose-afc-capture-status")
      || processInfo.environment["GOOSE_AFC_CAPTURE_STATUS"] == "1"
    guard enabled else {
      return nil
    }
    guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return nil
    }
    let gooseDirectory = directory.appendingPathComponent("GooseSwift", isDirectory: true)
    try? FileManager.default.createDirectory(at: gooseDirectory, withIntermediateDirectories: true)
    return gooseDirectory.appendingPathComponent("capture-status.txt")
  }()
  static let captureTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
  static let maximumBufferedFrameBytes = 64 * 1024
  static let packetImportRevisionInterval: TimeInterval = 5
  static let healthPacketCaptureUIUpdateInterval: TimeInterval = 1
  static let healthPacketCaptureSummaryLogInterval: TimeInterval = 10
  static let parsedFrameSummaryUpdateInterval: TimeInterval = 1
  static let heartRateHourlyRangePublishInterval: TimeInterval = 10
  static let packetUIStatePublishInterval: TimeInterval = 0.2
  static let restingHeartRateFrameWriteInterval: TimeInterval = 0.1
  static let captureFrameWriteQueueMaxRows = 2048
  static let captureFrameWriteBatchMaxRows = 128
  static let passiveActivityCaptureDuration: TimeInterval = 12 * 60 * 60
  static let movementPacketStatusInterval: TimeInterval = 1
  static let movementPacketLogInterval: TimeInterval = 5
  static let whoopDataSignalLogInterval: TimeInterval = 10
  static let pipelinePerformanceStatusPublishInterval: TimeInterval = 1
  static let pipelinePerformanceLogInterval: TimeInterval = 5
  static let whoopEventStatusInterval: TimeInterval = 1
  static let whoopDataSignalStatusInterval: TimeInterval = 1
  static let whoopDataSignalPipelineMaxSamples = 256
  static let maxRecentDeviceSignalPoints = 32
  static let deviceSignalPointInterval: TimeInterval = 0.75
  static let overnightGuardDuration: TimeInterval = 12 * 60 * 60
  static let overnightGuardHeartbeatInterval: TimeInterval = 60
  static let overnightGuardRangePollInterval: TimeInterval = 15 * 60
  static let overnightGuardRangeBlockedRetryInterval: TimeInterval = 30
  static let overnightGuardRangeFailureRetryInterval: TimeInterval = 2 * 60
  static let overnightGuardFinalSyncDrainInterval: TimeInterval = 8
  static let overnightGuardRawStaleWarningInterval: TimeInterval = 5 * 60
  static let overnightGuardRangeSuccessWarningDelay: TimeInterval = 2 * 60
  static let overnightGuardTargetMissingWarningDelay: TimeInterval = 30 * 60
  static let overnightGuardWarningRepeatInterval: TimeInterval = 15 * 60

  init(startBLE: Bool = true) {
    ble = GooseBLEClient(startCentral: startBLE)
    whoopDataSignalPipeline = WhoopDataSignalPipeline(
      ble: ble,
      packetUIStateAggregator: packetUIStateAggregator,
      statusInterval: Self.whoopDataSignalStatusInterval,
      logInterval: Self.whoopDataSignalLogInterval,
      deviceSignalPointInterval: Self.deviceSignalPointInterval,
      maxQueuedSamples: Self.whoopDataSignalPipelineMaxSamples
    )
    let heartRateSamplePipeline = self.heartRateSamplePipeline
    heartRateSamplePipeline.onHeartRateTimelineSnapshot = { [weak self] snapshot in
      Task { @MainActor in
        self?.applyHeartRateTimelineSnapshot(snapshot)
      }
    }
    packetUIStateAggregator.onSnapshot = { [weak self] snapshot in
      Task { @MainActor in
        self?.applyPacketUIStateSnapshot(snapshot)
      }
    }
    whoopDataSignalPipeline.onStatus = { [weak self] status in
      Task { @MainActor in
        self?.publishPipelinePerformanceStatus(status)
      }
    }
    healthPacketCaptureFamilyAggregator.onSnapshot = { [weak self] snapshot in
      Task { @MainActor in
        self?.applyHealthPacketCaptureFamilySnapshot(snapshot)
      }
    }
    healthPacketCaptureFamilyAggregator.onStatus = { [weak self] status in
      Task { @MainActor in
        self?.publishPipelinePerformanceStatus(status)
      }
    }
    captureFrameEnqueueAggregator.onSnapshot = { [weak self] snapshot in
      Task { @MainActor in
        self?.applyCaptureFrameEnqueueSnapshot(snapshot)
      }
    }
    passiveActivityDetectionPipeline.onEvents = { [weak self] events in
      Task { @MainActor in
        self?.applyActivityDetectionEvents(events)
      }
    }
    passiveActivityDetectionPipeline.onStatus = { [weak self] status in
      Task { @MainActor in
        self?.publishPipelinePerformanceStatus(status)
      }
    }
    ble.onRawNotificationWithContext = { [weak self] event, context in
      self?.persistOvernightRawNotificationBeforeInterpretation(
        event,
        activeDeviceName: context.activeDeviceName,
        connectionState: context.connectionState
      )
    }
    ble.onCommandWrite = { [weak self, weak ble] event in
      self?.persistOvernightCommandWrite(
        event,
        activeDeviceName: ble?.activeDeviceName ?? "WHOOP",
        connectionState: ble?.connectionState ?? "unknown"
      )
    }
    ble.onNotification = { [weak self] event in
      self?.handleNotification(event)
    }
    ble.onLiveHeartRate = { bpm, source, capturedAt in
      heartRateSamplePipeline.recordHeartRateSample(bpm: bpm, source: source, capturedAt: capturedAt)
    }
    ble.onHRVSample = { rmssdMS, rrIntervalCount, source, capturedAt in
      heartRateSamplePipeline.recordHRVSample(
        rmssdMS: rmssdMS,
        rrIntervalCount: rrIntervalCount,
        source: source,
        capturedAt: capturedAt
      )
    }
    ble.onConnectionStateChange = { [weak self] state in
      Task { @MainActor in
        self?.handleBLEConnectionStateChange(state)
      }
    }
    ble.onHistoricalSyncProgress = { [weak self] progress in
      Task { @MainActor in
        self?.handleHistoricalSyncProgress(progress)
      }
    }
    ble.onHistoricalRangeTelemetry = { [weak self] telemetry in
      self?.persistOvernightHistoricalRangeTelemetry(telemetry)
    }
    ble.onMessage = { [weak self] message in
      self?.persistOvernightEventLog(message)
    }
    refreshHeartRateHourlyRanges()
    ble.record(source: "app", title: "model.init")
    prepareClientHello()
    cleanupOrphanedActivityCaptureSessions()
    refreshActivityTimeline()
    scheduleAutoStartHealthPacketCaptureIfNeeded()
    scheduleAutoStartRespiratoryPacketWatchIfNeeded()
    recoverUncleanOvernightGuardSessionIfNeeded()
  }

  deinit {
    activityDetectionIdleWorkItem?.cancel()
    movementPacketValidationTimeoutWorkItem?.cancel()
    packetImportRevisionWorkItem?.cancel()
    healthPacketCaptureTimeoutWorkItem?.cancel()
    healthPacketCaptureStreamRetryWorkItem?.cancel()
    healthPacketCaptureUIUpdateWorkItem?.cancel()
    respiratoryPacketWatchTimeoutWorkItem?.cancel()
    autoStartRespiratoryPacketWatchWorkItem?.cancel()
    temperatureHistorySyncWorkItem?.cancel()
    autoStartHealthPacketCaptureWorkItem?.cancel()
    passiveActivityCaptureWorkItem?.cancel()
    overnightGuardHeartbeatWorkItem?.cancel()
    overnightGuardRangePollWorkItem?.cancel()
    overnightGuardFinalSyncDrainWorkItem?.cancel()
    if overnightGuardCriticalBackgroundTaskID != .invalid {
      let backgroundTaskID = overnightGuardCriticalBackgroundTaskID
      Task { @MainActor in
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
      }
    }
    if overnightRawSpool.isActive {
      _ = overnightRawSpool.suspendActive(reason: "model_deinit")
    } else {
      _ = overnightRawSpool.finish(status: "model_deinit")
    }
  }

}
