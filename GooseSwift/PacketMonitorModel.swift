import Foundation

@MainActor
final class PacketMonitorModel: ObservableObject {
  var lastParsedFrameSummary = "No notification frames parsed"
  var movementPacketStatus = "No movement packets"
  var latestWhoopEventStatus = "No WHOOP events"
  var latestSkinTemperatureCandidateStatus = "No skin temperature events"
  var latestWhoopDataPacketStatus = "No WHOOP data packets"
  var latestHistoryTemperatureCandidateStatus = "No history temperature packets"
  var latestRespiratoryRateCandidateStatus = "No respiratory rate candidates"
  var latestPulseInformationPacketStatus = "No pulse information packets"
  var latestOpticalPacketStatus = "No optical packets"
  var latestRawResearchPacketStatus = "No raw/research packets"
  var latestRealtimeStatusPacketStatus = "No realtime status packets"
  var performancePipelineStatus = "No pipeline samples"
  var liveDeviceDataSummary = "No live WHOOP data points"
  var recentDeviceSignalPoints: [DeviceSignalPoint] = []

  func apply(
    _ snapshot: PacketUIStateSnapshot,
    maxRecentDeviceSignalPoints: Int,
    publishInterval: TimeInterval
  ) {
    var nextLastParsedFrameSummary = lastParsedFrameSummary
    var nextMovementPacketStatus = movementPacketStatus
    var nextLatestWhoopEventStatus = latestWhoopEventStatus
    var nextLatestSkinTemperatureCandidateStatus = latestSkinTemperatureCandidateStatus
    var nextLatestWhoopDataPacketStatus = latestWhoopDataPacketStatus
    var nextLatestHistoryTemperatureCandidateStatus = latestHistoryTemperatureCandidateStatus
    var nextLatestRespiratoryRateCandidateStatus = latestRespiratoryRateCandidateStatus
    var nextLatestPulseInformationPacketStatus = latestPulseInformationPacketStatus
    var nextLatestOpticalPacketStatus = latestOpticalPacketStatus
    var nextLatestRawResearchPacketStatus = latestRawResearchPacketStatus
    var nextLatestRealtimeStatusPacketStatus = latestRealtimeStatusPacketStatus
    var nextPerformancePipelineStatus = performancePipelineStatus
    var nextLiveDeviceDataSummary = liveDeviceDataSummary
    var nextRecentDeviceSignalPoints = recentDeviceSignalPoints

    if let status = snapshot.lastParsedFrameSummary {
      nextLastParsedFrameSummary = status
    }
    if let status = snapshot.movementPacketStatus {
      nextMovementPacketStatus = status
    }
    if let status = snapshot.whoopEventStatus {
      nextLatestWhoopEventStatus = status
    }
    if let status = snapshot.skinTemperatureCandidateStatus {
      nextLatestSkinTemperatureCandidateStatus = status
    }
    if let status = snapshot.whoopDataPacketStatus {
      nextLatestWhoopDataPacketStatus = status
    }
    if let status = snapshot.historyTemperatureCandidateStatus {
      nextLatestHistoryTemperatureCandidateStatus = status
    }
    if let status = snapshot.respiratoryRateCandidateStatus {
      nextLatestRespiratoryRateCandidateStatus = status
    }
    if let status = snapshot.pulseInformationPacketStatus {
      nextLatestPulseInformationPacketStatus = status
    }
    if let status = snapshot.opticalPacketStatus {
      nextLatestOpticalPacketStatus = status
    }
    if let status = snapshot.rawResearchPacketStatus {
      nextLatestRawResearchPacketStatus = status
    }
    if let status = snapshot.realtimeStatusPacketStatus {
      nextLatestRealtimeStatusPacketStatus = status
    }
    if let status = snapshot.performancePipelineStatus {
      nextPerformancePipelineStatus = status
    }
    if !snapshot.deviceSignalPoints.isEmpty {
      for point in snapshot.deviceSignalPoints {
        nextRecentDeviceSignalPoints.insert(point, at: 0)
      }
      if nextRecentDeviceSignalPoints.count > maxRecentDeviceSignalPoints {
        nextRecentDeviceSignalPoints.removeLast(nextRecentDeviceSignalPoints.count - maxRecentDeviceSignalPoints)
      }
    }
    if let summary = snapshot.liveDeviceDataSummary {
      nextLiveDeviceDataSummary = summary
    }
    if snapshot.coalescedStatusUpdateCount > 0 {
      let summary = snapshot.coalescedStatusUpdateSummary ?? "unknown"
      nextPerformancePipelineStatus = "ui coalesced \(snapshot.coalescedStatusUpdateCount) status update(s) before publish (\(summary); reason=publish_interval_\(publishInterval)s) | \(nextPerformancePipelineStatus)"
    }
    if snapshot.droppedDeviceSignalPointCount > 0 {
      nextPerformancePipelineStatus = "ui signal preview dropped \(snapshot.droppedDeviceSignalPointCount) stale point(s) | \(nextPerformancePipelineStatus)"
    }

    guard nextLastParsedFrameSummary != lastParsedFrameSummary
      || nextMovementPacketStatus != movementPacketStatus
      || nextLatestWhoopEventStatus != latestWhoopEventStatus
      || nextLatestSkinTemperatureCandidateStatus != latestSkinTemperatureCandidateStatus
      || nextLatestWhoopDataPacketStatus != latestWhoopDataPacketStatus
      || nextLatestHistoryTemperatureCandidateStatus != latestHistoryTemperatureCandidateStatus
      || nextLatestRespiratoryRateCandidateStatus != latestRespiratoryRateCandidateStatus
      || nextLatestPulseInformationPacketStatus != latestPulseInformationPacketStatus
      || nextLatestOpticalPacketStatus != latestOpticalPacketStatus
      || nextLatestRawResearchPacketStatus != latestRawResearchPacketStatus
      || nextLatestRealtimeStatusPacketStatus != latestRealtimeStatusPacketStatus
      || nextPerformancePipelineStatus != performancePipelineStatus
      || nextLiveDeviceDataSummary != liveDeviceDataSummary
      || nextRecentDeviceSignalPoints != recentDeviceSignalPoints
    else {
      return
    }

    objectWillChange.send()
    lastParsedFrameSummary = nextLastParsedFrameSummary
    movementPacketStatus = nextMovementPacketStatus
    latestWhoopEventStatus = nextLatestWhoopEventStatus
    latestSkinTemperatureCandidateStatus = nextLatestSkinTemperatureCandidateStatus
    latestWhoopDataPacketStatus = nextLatestWhoopDataPacketStatus
    latestHistoryTemperatureCandidateStatus = nextLatestHistoryTemperatureCandidateStatus
    latestRespiratoryRateCandidateStatus = nextLatestRespiratoryRateCandidateStatus
    latestPulseInformationPacketStatus = nextLatestPulseInformationPacketStatus
    latestOpticalPacketStatus = nextLatestOpticalPacketStatus
    latestRawResearchPacketStatus = nextLatestRawResearchPacketStatus
    latestRealtimeStatusPacketStatus = nextLatestRealtimeStatusPacketStatus
    performancePipelineStatus = nextPerformancePipelineStatus
    liveDeviceDataSummary = nextLiveDeviceDataSummary
    recentDeviceSignalPoints = nextRecentDeviceSignalPoints
  }
}
