import CoreBluetooth
import Foundation
import OSLog

enum GooseLogLevel: String {
  case debug
  case info
  case warn
  case error
}

struct GooseDiscoveredDevice: Identifiable, Equatable {
  let id: UUID
  let name: String
  let rssi: Int
}

struct GooseMessage: Identifiable {
  let id = UUID()
  let timestamp: Date
  let level: GooseLogLevel
  let source: String
  let title: String
  let body: String
}

struct GooseNotificationEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let value: Data
  let capturedAt: Date

  var rustDeviceType: String {
    characteristicUUID.lowercased().hasPrefix("610800") ? "GEN4" : "GOOSE"
  }
}

struct GooseBLENotificationContext {
  let activeDeviceName: String
  let connectionState: String
}

struct GooseCommandWriteEvent {
  let deviceID: UUID
  let serviceUUID: String
  let characteristicUUID: String
  let commandName: String
  let commandNumber: UInt8?
  let sequence: UInt8?
  let payload: Data
  let frame: Data
  let writeType: String
  let source: String
  let capturedAt: Date
}

enum GooseSyncToastPhase: String {
  case syncing
  case synced
  case failed
}

struct GooseSyncToast: Identifiable, Equatable {
  let id = UUID()
  let phase: GooseSyncToastPhase
  let title: String
  let detail: String
}

struct GooseHistoricalSyncProgress {
  let status: String
  let detail: String
  let packetCount: Int
  let isTerminal: Bool
  let failed: Bool
  let capturedAt: Date
}

struct GooseHistoricalRangeTelemetry {
  let capturedAt: Date
  let status: String
  let commandSequence: UInt8
  let resultCode: UInt8
  let resultName: String
  let payloadHex: String
  let bodyHex: String
  let revisionOrStatus: UInt8?
  let wordsFromOffset1: [UInt32]
  let pageCurrent: UInt32?
  let pageOldest: UInt32?
  let pageEnd: UInt32?
  let pagesBehind: Int64?
  let pendingResponseCount: Int
  let retryCount: Int
  let notes: String
}

struct GooseSyncFailure: Identifiable, Equatable {
  let id = UUID()
  let title: String
  let message: String
  let occurredAt: Date
}

final class GooseSyncStatusStore: ObservableObject {
  @Published var syncToast: GooseSyncToast?
  @Published var lastSyncFailure: GooseSyncFailure?
  @Published var syncFailureSheet: GooseSyncFailure?
}

final class GooseConnectionStatusStore: ObservableObject {
  var bluetoothState = "not requested"
  var connectionState = "disconnected"
  var reconnectState = "idle"
  var rememberedDeviceDescription = "none"
  var discoveredDevices: [GooseDiscoveredDevice] = []
  var selectedDeviceID: UUID?
  var isScanning = false
  var canScan = false
  var canConnect = false
  var canReconnectRemembered = false
  var canSendHello = false
  var hasRememberedDevice = false

  func apply(
    bluetoothState nextBluetoothState: String,
    connectionState nextConnectionState: String,
    reconnectState nextReconnectState: String,
    rememberedDeviceDescription nextRememberedDeviceDescription: String,
    discoveredDevices nextDiscoveredDevices: [GooseDiscoveredDevice],
    selectedDeviceID nextSelectedDeviceID: UUID?,
    isScanning nextIsScanning: Bool,
    canScan nextCanScan: Bool,
    canConnect nextCanConnect: Bool,
    canReconnectRemembered nextCanReconnectRemembered: Bool,
    canSendHello nextCanSendHello: Bool,
    hasRememberedDevice nextHasRememberedDevice: Bool
  ) {
    guard nextBluetoothState != bluetoothState
      || nextConnectionState != connectionState
      || nextReconnectState != reconnectState
      || nextRememberedDeviceDescription != rememberedDeviceDescription
      || nextDiscoveredDevices != discoveredDevices
      || nextSelectedDeviceID != selectedDeviceID
      || nextIsScanning != isScanning
      || nextCanScan != canScan
      || nextCanConnect != canConnect
      || nextCanReconnectRemembered != canReconnectRemembered
      || nextCanSendHello != canSendHello
      || nextHasRememberedDevice != hasRememberedDevice
    else {
      return
    }

    objectWillChange.send()
    bluetoothState = nextBluetoothState
    connectionState = nextConnectionState
    reconnectState = nextReconnectState
    rememberedDeviceDescription = nextRememberedDeviceDescription
    discoveredDevices = nextDiscoveredDevices
    selectedDeviceID = nextSelectedDeviceID
    isScanning = nextIsScanning
    canScan = nextCanScan
    canConnect = nextCanConnect
    canReconnectRemembered = nextCanReconnectRemembered
    canSendHello = nextCanSendHello
    hasRememberedDevice = nextHasRememberedDevice
  }
}

final class GooseDeviceStatusStore: ObservableObject {
  var activeDeviceName = "WHOOP"
  var connectionState = "disconnected"
  var isScanning = false
  var lastSyncAt: Date?
  var batteryLevelPercent: Int?
  var batteryUpdatedAt: Date?
  var batteryIsCharging: Bool?
  var batteryPowerStatus = "Unknown"

  func apply(
    activeDeviceName nextActiveDeviceName: String,
    connectionState nextConnectionState: String,
    isScanning nextIsScanning: Bool,
    lastSyncAt nextLastSyncAt: Date?,
    batteryLevelPercent nextBatteryLevelPercent: Int?,
    batteryUpdatedAt nextBatteryUpdatedAt: Date?,
    batteryIsCharging nextBatteryIsCharging: Bool?,
    batteryPowerStatus nextBatteryPowerStatus: String
  ) {
    guard nextActiveDeviceName != activeDeviceName
      || nextConnectionState != connectionState
      || nextIsScanning != isScanning
      || nextLastSyncAt != lastSyncAt
      || nextBatteryLevelPercent != batteryLevelPercent
      || nextBatteryUpdatedAt != batteryUpdatedAt
      || nextBatteryIsCharging != batteryIsCharging
      || nextBatteryPowerStatus != batteryPowerStatus
    else {
      return
    }

    objectWillChange.send()
    activeDeviceName = nextActiveDeviceName
    connectionState = nextConnectionState
    isScanning = nextIsScanning
    lastSyncAt = nextLastSyncAt
    batteryLevelPercent = nextBatteryLevelPercent
    batteryUpdatedAt = nextBatteryUpdatedAt
    batteryIsCharging = nextBatteryIsCharging
    batteryPowerStatus = nextBatteryPowerStatus
  }
}

final class GooseDeviceAdvancedStatusStore: ObservableObject {
  var firmwareSummary = "Unknown"
  var modelSummary = "WHOOP"
  var batteryChargeDisplayStatus = "Unknown"
  var highFrequencyHistorySyncDisplaySummary = "Off"
  var highFrequencyHistorySyncActive = false
  var canWriteHighFrequencyHistorySync = false
  var canSyncClock = false
  var strapClockOffsetSeconds: TimeInterval?
  var strapClockUpdatedAt: Date?
  var strapClockStatus = "Not read"
  var canWriteAlarm = false
  var alarmWriteSupportSummary = "Connect WHOOP first"
  var alarmDisplaySummary = "No alarm command sent"
  var lastAlarmResponseSummary = "No alarm response yet"
  var lastAlarmEventSummary = "No alarm event yet"
  var lastAlarmCommandFrameHex = ""
  var lastAlarmResponsePayloadHex = ""
  var lastAlarmEventPayloadHex = ""
  var lastAlarmScheduledAt: Date?

  func apply(
    firmwareSummary nextFirmwareSummary: String,
    modelSummary nextModelSummary: String,
    batteryChargeDisplayStatus nextBatteryChargeDisplayStatus: String,
    highFrequencyHistorySyncDisplaySummary nextHighFrequencyHistorySyncDisplaySummary: String,
    highFrequencyHistorySyncActive nextHighFrequencyHistorySyncActive: Bool,
    canWriteHighFrequencyHistorySync nextCanWriteHighFrequencyHistorySync: Bool,
    canSyncClock nextCanSyncClock: Bool,
    strapClockOffsetSeconds nextStrapClockOffsetSeconds: TimeInterval?,
    strapClockUpdatedAt nextStrapClockUpdatedAt: Date?,
    strapClockStatus nextStrapClockStatus: String,
    canWriteAlarm nextCanWriteAlarm: Bool,
    alarmWriteSupportSummary nextAlarmWriteSupportSummary: String,
    alarmDisplaySummary nextAlarmDisplaySummary: String,
    lastAlarmResponseSummary nextLastAlarmResponseSummary: String,
    lastAlarmEventSummary nextLastAlarmEventSummary: String,
    lastAlarmCommandFrameHex nextLastAlarmCommandFrameHex: String,
    lastAlarmResponsePayloadHex nextLastAlarmResponsePayloadHex: String,
    lastAlarmEventPayloadHex nextLastAlarmEventPayloadHex: String,
    lastAlarmScheduledAt nextLastAlarmScheduledAt: Date?
  ) {
    guard nextFirmwareSummary != firmwareSummary
      || nextModelSummary != modelSummary
      || nextBatteryChargeDisplayStatus != batteryChargeDisplayStatus
      || nextHighFrequencyHistorySyncDisplaySummary != highFrequencyHistorySyncDisplaySummary
      || nextHighFrequencyHistorySyncActive != highFrequencyHistorySyncActive
      || nextCanWriteHighFrequencyHistorySync != canWriteHighFrequencyHistorySync
      || nextCanSyncClock != canSyncClock
      || nextStrapClockOffsetSeconds != strapClockOffsetSeconds
      || nextStrapClockUpdatedAt != strapClockUpdatedAt
      || nextStrapClockStatus != strapClockStatus
      || nextCanWriteAlarm != canWriteAlarm
      || nextAlarmWriteSupportSummary != alarmWriteSupportSummary
      || nextAlarmDisplaySummary != alarmDisplaySummary
      || nextLastAlarmResponseSummary != lastAlarmResponseSummary
      || nextLastAlarmEventSummary != lastAlarmEventSummary
      || nextLastAlarmCommandFrameHex != lastAlarmCommandFrameHex
      || nextLastAlarmResponsePayloadHex != lastAlarmResponsePayloadHex
      || nextLastAlarmEventPayloadHex != lastAlarmEventPayloadHex
      || nextLastAlarmScheduledAt != lastAlarmScheduledAt
    else {
      return
    }

    objectWillChange.send()
    firmwareSummary = nextFirmwareSummary
    modelSummary = nextModelSummary
    batteryChargeDisplayStatus = nextBatteryChargeDisplayStatus
    highFrequencyHistorySyncDisplaySummary = nextHighFrequencyHistorySyncDisplaySummary
    highFrequencyHistorySyncActive = nextHighFrequencyHistorySyncActive
    canWriteHighFrequencyHistorySync = nextCanWriteHighFrequencyHistorySync
    canSyncClock = nextCanSyncClock
    strapClockOffsetSeconds = nextStrapClockOffsetSeconds
    strapClockUpdatedAt = nextStrapClockUpdatedAt
    strapClockStatus = nextStrapClockStatus
    canWriteAlarm = nextCanWriteAlarm
    alarmWriteSupportSummary = nextAlarmWriteSupportSummary
    alarmDisplaySummary = nextAlarmDisplaySummary
    lastAlarmResponseSummary = nextLastAlarmResponseSummary
    lastAlarmEventSummary = nextLastAlarmEventSummary
    lastAlarmCommandFrameHex = nextLastAlarmCommandFrameHex
    lastAlarmResponsePayloadHex = nextLastAlarmResponsePayloadHex
    lastAlarmEventPayloadHex = nextLastAlarmEventPayloadHex
    lastAlarmScheduledAt = nextLastAlarmScheduledAt
  }
}

final class GooseHealthCaptureStatusStore: ObservableObject {
  var activityDetectionStatus = "Watching for movement packets"
  var movementPacketValidationStatus = "Not run"
  var movementPacketValidationIsRunning = false
  var healthPacketCaptureSessionID: String?
  var healthPacketCaptureStatus = "No health packet capture"
  var healthPacketCaptureStartedAt: Date?
  var healthPacketCaptureFrameCount = 0
  var healthPacketCaptureTargetSummary = "No health packet capture"
  var healthPacketCaptureLastPacketSummary = "No packets captured"
  var healthPacketCaptureFamilyRows: [HealthPacketCaptureFamily] = []
  var respiratoryPacketWatchActive = false
  var respiratoryPacketWatchStatus = "Not watching K18 respiratory history"

  func apply(
    activityDetectionStatus nextActivityDetectionStatus: String,
    movementPacketValidationStatus nextMovementPacketValidationStatus: String,
    movementPacketValidationIsRunning nextMovementPacketValidationIsRunning: Bool,
    healthPacketCaptureSessionID nextHealthPacketCaptureSessionID: String?,
    healthPacketCaptureStatus nextHealthPacketCaptureStatus: String,
    healthPacketCaptureStartedAt nextHealthPacketCaptureStartedAt: Date?,
    healthPacketCaptureFrameCount nextHealthPacketCaptureFrameCount: Int,
    healthPacketCaptureTargetSummary nextHealthPacketCaptureTargetSummary: String,
    healthPacketCaptureLastPacketSummary nextHealthPacketCaptureLastPacketSummary: String,
    healthPacketCaptureFamilyRows nextHealthPacketCaptureFamilyRows: [HealthPacketCaptureFamily],
    respiratoryPacketWatchActive nextRespiratoryPacketWatchActive: Bool,
    respiratoryPacketWatchStatus nextRespiratoryPacketWatchStatus: String
  ) {
    guard nextActivityDetectionStatus != activityDetectionStatus
      || nextMovementPacketValidationStatus != movementPacketValidationStatus
      || nextMovementPacketValidationIsRunning != movementPacketValidationIsRunning
      || nextHealthPacketCaptureSessionID != healthPacketCaptureSessionID
      || nextHealthPacketCaptureStatus != healthPacketCaptureStatus
      || nextHealthPacketCaptureStartedAt != healthPacketCaptureStartedAt
      || nextHealthPacketCaptureFrameCount != healthPacketCaptureFrameCount
      || nextHealthPacketCaptureTargetSummary != healthPacketCaptureTargetSummary
      || nextHealthPacketCaptureLastPacketSummary != healthPacketCaptureLastPacketSummary
      || nextHealthPacketCaptureFamilyRows != healthPacketCaptureFamilyRows
      || nextRespiratoryPacketWatchActive != respiratoryPacketWatchActive
      || nextRespiratoryPacketWatchStatus != respiratoryPacketWatchStatus
    else {
      return
    }

    objectWillChange.send()
    activityDetectionStatus = nextActivityDetectionStatus
    movementPacketValidationStatus = nextMovementPacketValidationStatus
    movementPacketValidationIsRunning = nextMovementPacketValidationIsRunning
    healthPacketCaptureSessionID = nextHealthPacketCaptureSessionID
    healthPacketCaptureStatus = nextHealthPacketCaptureStatus
    healthPacketCaptureStartedAt = nextHealthPacketCaptureStartedAt
    healthPacketCaptureFrameCount = nextHealthPacketCaptureFrameCount
    healthPacketCaptureTargetSummary = nextHealthPacketCaptureTargetSummary
    healthPacketCaptureLastPacketSummary = nextHealthPacketCaptureLastPacketSummary
    healthPacketCaptureFamilyRows = nextHealthPacketCaptureFamilyRows
    respiratoryPacketWatchActive = nextRespiratoryPacketWatchActive
    respiratoryPacketWatchStatus = nextRespiratoryPacketWatchStatus
  }
}

final class GooseOvernightGuardStatusStore: ObservableObject {
  var active = false
  var status = "Not started"
  var readinessStatus = "pending"
  var readinessSummary = "Not sleep-ready | connect WHOOP and start Overnight Guard"
  var rawNotificationCount = 0
  var rangePollCount = 0
  var rangeTelemetryCount = 0
  var successfulRangePollCount = 0
  var commandWriteCount = 0
  var eventLogCount = 0
  var targetSummary = OvernightGuardTargetCounts().summary
  var historicalOrderSummary = OvernightGuardHistoricalOrderEvidence().summary
  var lastPacketSummary = "No raw notifications"
  var spoolPath = "No overnight spool"
  var spoolSizeSummary = "No overnight spool size"
  var sqliteMirrorSummary = "SQLite mirror not started"
  var powerSummary = "Power not checked"
  var watchdogSummary = "Watchdog not checked"
  var warning = "Keep the official WHOOP app closed until Goose final sync/export finishes."
  var exportStatus = "No overnight export"
  var exportInProgress = false
  var exportURL: URL?
  var exportManifestURL: URL?
  var exportManifestError: String?
  var canExportLastSession = false

  func apply(
    active nextActive: Bool,
    status nextStatus: String,
    readinessStatus nextReadinessStatus: String,
    readinessSummary nextReadinessSummary: String,
    rawNotificationCount nextRawNotificationCount: Int,
    rangePollCount nextRangePollCount: Int,
    rangeTelemetryCount nextRangeTelemetryCount: Int,
    successfulRangePollCount nextSuccessfulRangePollCount: Int,
    commandWriteCount nextCommandWriteCount: Int,
    eventLogCount nextEventLogCount: Int,
    targetSummary nextTargetSummary: String,
    historicalOrderSummary nextHistoricalOrderSummary: String,
    lastPacketSummary nextLastPacketSummary: String,
    spoolPath nextSpoolPath: String,
    spoolSizeSummary nextSpoolSizeSummary: String,
    sqliteMirrorSummary nextSQLiteMirrorSummary: String,
    powerSummary nextPowerSummary: String,
    watchdogSummary nextWatchdogSummary: String,
    warning nextWarning: String,
    exportStatus nextExportStatus: String,
    exportInProgress nextExportInProgress: Bool,
    exportURL nextExportURL: URL?,
    exportManifestURL nextExportManifestURL: URL?,
    exportManifestError nextExportManifestError: String?,
    canExportLastSession nextCanExportLastSession: Bool
  ) {
    guard nextActive != active
      || nextStatus != status
      || nextReadinessStatus != readinessStatus
      || nextReadinessSummary != readinessSummary
      || nextRawNotificationCount != rawNotificationCount
      || nextRangePollCount != rangePollCount
      || nextRangeTelemetryCount != rangeTelemetryCount
      || nextSuccessfulRangePollCount != successfulRangePollCount
      || nextCommandWriteCount != commandWriteCount
      || nextEventLogCount != eventLogCount
      || nextTargetSummary != targetSummary
      || nextHistoricalOrderSummary != historicalOrderSummary
      || nextLastPacketSummary != lastPacketSummary
      || nextSpoolPath != spoolPath
      || nextSpoolSizeSummary != spoolSizeSummary
      || nextSQLiteMirrorSummary != sqliteMirrorSummary
      || nextPowerSummary != powerSummary
      || nextWatchdogSummary != watchdogSummary
      || nextWarning != warning
      || nextExportStatus != exportStatus
      || nextExportInProgress != exportInProgress
      || nextExportURL != exportURL
      || nextExportManifestURL != exportManifestURL
      || nextExportManifestError != exportManifestError
      || nextCanExportLastSession != canExportLastSession
    else {
      return
    }

    objectWillChange.send()
    active = nextActive
    status = nextStatus
    readinessStatus = nextReadinessStatus
    readinessSummary = nextReadinessSummary
    rawNotificationCount = nextRawNotificationCount
    rangePollCount = nextRangePollCount
    rangeTelemetryCount = nextRangeTelemetryCount
    successfulRangePollCount = nextSuccessfulRangePollCount
    commandWriteCount = nextCommandWriteCount
    eventLogCount = nextEventLogCount
    targetSummary = nextTargetSummary
    historicalOrderSummary = nextHistoricalOrderSummary
    lastPacketSummary = nextLastPacketSummary
    spoolPath = nextSpoolPath
    spoolSizeSummary = nextSpoolSizeSummary
    sqliteMirrorSummary = nextSQLiteMirrorSummary
    powerSummary = nextPowerSummary
    watchdogSummary = nextWatchdogSummary
    warning = nextWarning
    exportStatus = nextExportStatus
    exportInProgress = nextExportInProgress
    exportURL = nextExportURL
    exportManifestURL = nextExportManifestURL
    exportManifestError = nextExportManifestError
    canExportLastSession = nextCanExportLastSession
  }
}

final class GooseHistoricalSyncStatusStore: ObservableObject {
  var status = "idle"
  var packetCount = 0
  var isSyncing = false
  var canSyncHistorical = false
  var completedAt: Date?
  var lastRangeCommandStatus = "No GET_DATA_RANGE response"

  func apply(
    status nextStatus: String,
    packetCount nextPacketCount: Int,
    isSyncing nextIsSyncing: Bool,
    canSyncHistorical nextCanSyncHistorical: Bool,
    completedAt nextCompletedAt: Date?,
    lastRangeCommandStatus nextLastRangeCommandStatus: String
  ) {
    guard nextStatus != status
      || nextPacketCount != packetCount
      || nextIsSyncing != isSyncing
      || nextCanSyncHistorical != canSyncHistorical
      || nextCompletedAt != completedAt
      || nextLastRangeCommandStatus != lastRangeCommandStatus
    else {
      return
    }

    objectWillChange.send()
    status = nextStatus
    packetCount = nextPacketCount
    isSyncing = nextIsSyncing
    canSyncHistorical = nextCanSyncHistorical
    completedAt = nextCompletedAt
    lastRangeCommandStatus = nextLastRangeCommandStatus
  }

  var packetText: String {
    packetCount == 1 ? "1 packet" : "\(packetCount) packets"
  }
}

final class GooseLiveVitalsStore: ObservableObject {
  var liveHeartRateBPM: Int?
  var liveHeartRateSource = "waiting"
  var liveHeartRateUpdatedAt: Date?
  var restingHeartRateEstimateBPM: Double?
  var restingHeartRateEstimateSampleCount = 0
  var restingHeartRateEstimateSource = "waiting"
  var restingHeartRateEstimateUpdatedAt: Date?
  var liveHRVRMSSD: Double?
  var liveHRVRRIntervalCount = 0
  var liveHRVSource = "waiting"
  var liveHRVUpdatedAt: Date?
  var liveHRVRMSSDSampleCount = 0

  func apply(
    liveHeartRateBPM nextLiveHeartRateBPM: Int?,
    liveHeartRateSource nextLiveHeartRateSource: String,
    liveHeartRateUpdatedAt nextLiveHeartRateUpdatedAt: Date?,
    restingHeartRateEstimateBPM nextRestingHeartRateEstimateBPM: Double?,
    restingHeartRateEstimateSampleCount nextRestingHeartRateEstimateSampleCount: Int,
    restingHeartRateEstimateSource nextRestingHeartRateEstimateSource: String,
    restingHeartRateEstimateUpdatedAt nextRestingHeartRateEstimateUpdatedAt: Date?,
    liveHRVRMSSD nextLiveHRVRMSSD: Double?,
    liveHRVRRIntervalCount nextLiveHRVRRIntervalCount: Int,
    liveHRVRMSSDSampleCount nextLiveHRVRMSSDSampleCount: Int,
    liveHRVSource nextLiveHRVSource: String,
    liveHRVUpdatedAt nextLiveHRVUpdatedAt: Date?
  ) {
    guard nextLiveHeartRateBPM != liveHeartRateBPM
      || nextLiveHeartRateSource != liveHeartRateSource
      || nextLiveHeartRateUpdatedAt != liveHeartRateUpdatedAt
      || nextRestingHeartRateEstimateBPM != restingHeartRateEstimateBPM
      || nextRestingHeartRateEstimateSampleCount != restingHeartRateEstimateSampleCount
      || nextRestingHeartRateEstimateSource != restingHeartRateEstimateSource
      || nextRestingHeartRateEstimateUpdatedAt != restingHeartRateEstimateUpdatedAt
      || nextLiveHRVRMSSD != liveHRVRMSSD
      || nextLiveHRVRRIntervalCount != liveHRVRRIntervalCount
      || nextLiveHRVRMSSDSampleCount != liveHRVRMSSDSampleCount
      || nextLiveHRVSource != liveHRVSource
      || nextLiveHRVUpdatedAt != liveHRVUpdatedAt
    else {
      return
    }

    objectWillChange.send()
    liveHeartRateBPM = nextLiveHeartRateBPM
    liveHeartRateSource = nextLiveHeartRateSource
    liveHeartRateUpdatedAt = nextLiveHeartRateUpdatedAt
    restingHeartRateEstimateBPM = nextRestingHeartRateEstimateBPM
    restingHeartRateEstimateSampleCount = nextRestingHeartRateEstimateSampleCount
    restingHeartRateEstimateSource = nextRestingHeartRateEstimateSource
    restingHeartRateEstimateUpdatedAt = nextRestingHeartRateEstimateUpdatedAt
    liveHRVRMSSD = nextLiveHRVRMSSD
    liveHRVRRIntervalCount = nextLiveHRVRRIntervalCount
    liveHRVRMSSDSampleCount = nextLiveHRVRMSSDSampleCount
    liveHRVSource = nextLiveHRVSource
    liveHRVUpdatedAt = nextLiveHRVUpdatedAt
  }
}

struct GooseDebugCommandDefinition: Identifiable, Equatable {
  let id: String
  let title: String
  let commandNumber: UInt8
  let family: String
  let risk: String
  let detail: String
  let defaultPayloadHex: String?
  let requiresPayloadHex: Bool
  let payloadHint: String

  var canSendFromButton: Bool {
    defaultPayloadHex != nil || !requiresPayloadHex
  }

  var remoteURLExample: String {
    if requiresPayloadHex {
      return "gooseswift://debug-command/\(id)?payload=<hex>"
    }
    return "gooseswift://debug-command/\(id)"
  }
}

struct GooseDebugCommandResponse: Identifiable, Equatable {
  let id: UUID
  let commandID: String
  let title: String
  let commandNumber: UInt8
  let sequence: UInt8
  let requestedAt: Date
  let completedAt: Date?
  let status: String
  let result: String
  let requestPayloadHex: String
  let requestFrameHex: String
  let responsePayloadHex: String
  let responseBodyHex: String
  let source: String

  var summary: String {
    let time = completedAt ?? requestedAt
    let body = responseBodyHex.isEmpty ? "no body" : "body \(responseBodyHex)"
    return "\(status) | \(result) | seq \(sequence) | \(body) | \(time.formatted(date: .omitted, time: .standard))"
  }
}
