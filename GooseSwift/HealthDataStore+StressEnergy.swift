import Darwin
import Foundation
import SwiftUI
import UIKit

private struct StressHeartRateBucket {
  var totalBPM = 0
  var minBPM = Int.max
  var maxBPM = Int.min
  var sampleCount = 0

  mutating func append(_ bpm: Int) {
    totalBPM += bpm
    minBPM = min(minBPM, bpm)
    maxBPM = max(maxBPM, bpm)
    sampleCount += 1
  }
}

extension HealthDataStore {
  func stressAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> StressAlgorithmSummary {
    if allowLiveFallbacks,
       calendar.isDate(currentStressEnergySummaryDayStart, inSameDayAs: date) {
      return currentStressSummary
    }
    let samples = heartRateSeriesStore.samples(forDayContaining: date, calendar: calendar)
    return Self.computeStressAlgorithmSummary(
      samples: samples,
      date: date,
      calendar: calendar,
      previewMissingData: previewMissingData,
      heartRateTimelineStatus: heartRateTimelineStatus,
      allowLiveFallbacks: allowLiveFallbacks
    )
  }

  nonisolated static func computeStressAlgorithmSummary(
    samples: [HeartRateSamplePoint],
    date: Date = Date(),
    calendar: Calendar = .current,
    previewMissingData: Bool = false,
    heartRateTimelineStatus: String,
    allowLiveFallbacks: Bool = true
  ) -> StressAlgorithmSummary {
    guard !previewMissingData else {
      return emptyStressSummaryValue(
        status: "No data",
        freshness: "Missing",
        source: .unavailable("preview missing stress data")
      )
    }

    guard samples.count >= 6 else {
      return emptyStressSummaryValue(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress requires at least six heart-rate samples today")
      )
    }

    let dayStart = calendar.startOfDay(for: date)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(24 * 60 * 60)
    let restingHeartRate = Self.stressRestingHeartRateEstimate(
      samples: samples,
      date: date,
      calendar: calendar,
      allowLiveFallbacks: allowLiveFallbacks
    )
    let bucketSeconds: TimeInterval = 10 * 60
    let bucketCount = max(1, Int(ceil(dayEnd.timeIntervalSince(dayStart) / bucketSeconds)))
    var buckets = Array(repeating: StressHeartRateBucket(), count: bucketCount)
    for sample in samples {
      let bucket = Int(max(sample.capturedAt.timeIntervalSince(dayStart), 0) / bucketSeconds)
      guard buckets.indices.contains(bucket) else {
        continue
      }
      buckets[bucket].append(sample.bpm)
    }

    let windows = buckets.enumerated()
      .compactMap { bucket, bucketSamples -> StressWindowPoint? in
        guard bucketSamples.sampleCount > 0 else {
          return nil
        }
        let averageHeartRate = Double(bucketSamples.totalBPM) / Double(bucketSamples.sampleCount)
        let minHeartRate = Double(bucketSamples.minBPM)
        let maxHeartRate = Double(bucketSamples.maxBPM)
        let heartRatePressure = Self.clamp(
          (averageHeartRate - restingHeartRate) / max(32.0, restingHeartRate * 0.62),
          min: 0,
          max: 1
        )
        let volatilityPressure = Self.clamp(
          ((maxHeartRate - minHeartRate) / max(averageHeartRate, 1)) / 0.24,
          min: 0,
          max: 1
        )
        let start = dayStart.addingTimeInterval(TimeInterval(bucket) * bucketSeconds)
        let end = min(start.addingTimeInterval(bucketSeconds), dayEnd)
        let sleepWindow = Self.isLikelySleepWindow(start, calendar: calendar)
        var stress = (heartRatePressure * 0.88 + volatilityPressure * 0.12) * 100.0
        if sleepWindow {
          stress *= 0.62
        }
        if averageHeartRate <= restingHeartRate + 4 {
          stress *= 0.65
        }
        stress = Self.clamp(stress, min: 0, max: 100)

        return StressWindowPoint(
          id: "\(Int64((start.timeIntervalSince1970 * 1000).rounded()))",
          start: start,
          end: end,
          timeLabel: Self.timeLabel(start),
          stress: stress,
          averageHeartRate: averageHeartRate,
          sampleCount: bucketSamples.sampleCount,
          isSleepWindow: sleepWindow
        )
      }

    guard !windows.isEmpty else {
      return emptyStressSummaryValue(
        status: "No HR data",
        freshness: heartRateTimelineStatus,
        source: .unavailable("stress buckets could not be computed")
      )
    }

    let weightedSampleCount = max(windows.reduce(0) { $0 + $1.sampleCount }, 1)
    let score = windows.reduce(0.0) { $0 + $1.stress * Double($1.sampleCount) } / Double(weightedSampleCount)
    let averageHeartRate = windows.reduce(0.0) { $0 + $1.averageHeartRate * Double($1.sampleCount) } / Double(weightedSampleCount)
    let totalMinutes = max(windows.reduce(0.0) { $0 + $1.durationMinutes }, 1)
    let highMinutes = windows.filter { $0.stress >= 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let mediumMinutes = windows.filter { $0.stress >= 33 && $0.stress < 66 }.reduce(0.0) { $0 + $1.durationMinutes }
    let lowMinutes = max(totalMinutes - highMinutes - mediumMinutes, 0)
    let sampleConfidence = Self.clamp(Double(samples.count) / 120.0, min: 0, max: 1)
    let windowConfidence = Self.clamp(Double(windows.count) / 18.0, min: 0, max: 1)
    let stressConfidence = Self.clamp(0.32 + sampleConfidence * 0.42 + windowConfidence * 0.18, min: 0.32, max: 0.88)
    let inputSummary = [
      "hr_samples=\(samples.count)",
      "windows=\(windows.count)",
      "resting_hr=\(Self.numberText(restingHeartRate, fractionDigits: 0) ?? "--") bpm",
      "model=hr_elevation+hr_volatility",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(stressConfidence, fractionDigits: 2) ?? "0"

    return StressAlgorithmSummary(
      score: score,
      status: Self.stressStatusLabel(score: score),
      averageHeartRate: averageHeartRate,
      averageHRV: nil,
      windows: windows,
      high: StressZoneSummary(label: "High", percent: highMinutes / totalMinutes, durationMinutes: highMinutes),
      medium: StressZoneSummary(label: "Med", percent: mediumMinutes / totalMinutes, durationMinutes: mediumMinutes),
      low: StressZoneSummary(label: "Low", percent: lowMinutes / totalMinutes, durationMinutes: lowMinutes),
      sampleCount: samples.count,
      source: .localEstimate("goose.stress.hr_proxy.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: Self.relativeText(for: samples.last?.capturedAt) ?? "Today",
      confidence: stressConfidence,
      inputSummary: inputSummary
    )
  }

  func energyBankAlgorithmSummary(
    for date: Date = Date(),
    calendar: Calendar = .current,
    allowLiveFallbacks: Bool = true
  ) -> EnergyBankAlgorithmSummary {
    if allowLiveFallbacks,
       calendar.isDate(currentStressEnergySummaryDayStart, inSameDayAs: date) {
      return currentEnergyBankSummary
    }
    let stress = stressAlgorithmSummary(for: date, calendar: calendar, allowLiveFallbacks: allowLiveFallbacks)
    return Self.computeEnergyBankAlgorithmSummary(
      stress: stress,
      recoverySeed: recoveryScoreValue()
    )
  }

  nonisolated static func computeEnergyBankAlgorithmSummary(
    stress: StressAlgorithmSummary,
    recoverySeed: Double?
  ) -> EnergyBankAlgorithmSummary {
    guard stress.hasData else {
      return emptyEnergyBankSummaryValue(
        status: "No stress data",
        freshness: stress.freshness,
        source: stress.source
      )
    }

    var energy = Self.clamp(recoverySeed ?? 55, min: 5, max: 100)
    var points: [EnergyStressPoint] = []
    var totalCharged = 0.0
    var totalDrained = 0.0
    var sleepCharge = 0.0

    for window in stress.windows.sorted(by: { $0.start < $1.start }) {
      let hours = max(window.durationMinutes / 60.0, 1.0 / 6.0)
      let delta: Double
      if window.isSleepWindow {
        let lowStressBonus = max(0, 35 - window.stress) * 0.045
        delta = (3.3 + lowStressBonus) * hours
      } else {
        let stressDrain = (0.75 + window.stress / 20.0) * hours
        let quietCharge = window.stress < 22 ? 0.55 * hours : 0
        delta = quietCharge - stressDrain
      }

      energy = Self.clamp(energy + delta, min: 0, max: 100)
      if delta >= 0 {
        totalCharged += delta
        if window.isSleepWindow {
          sleepCharge += delta
        }
      } else {
        totalDrained += abs(delta)
      }

      points.append(
        EnergyStressPoint(
          id: window.id,
          timeLabel: window.timeLabel,
          energy: energy,
          stress: window.stress,
          usage: Self.clamp(abs(delta) * 12.0, min: 4, max: 100),
          isSleepWindow: window.isSleepWindow,
          isChargeEvent: delta > 0
        )
      )
    }

    let stressConfidence = stress.confidence ?? 0.35
    let energyConfidence = Self.clamp(stressConfidence * 0.86 + (recoverySeed == nil ? 0 : 0.10), min: 0.30, max: 0.90)
    let seedText = recoverySeed.flatMap { Self.numberText($0, fractionDigits: 0) }.map { "recovery_score=\($0)" } ?? "recovery_score=default_55"
    let inputSummary = [
      "stress_windows=\(stress.windows.count)",
      "stress_confidence=\(Self.numberText(stressConfidence, fractionDigits: 2) ?? "0")",
      seedText,
      "model=stress_charge_drain",
    ].joined(separator: " | ")
    let confidenceText = Self.numberText(energyConfidence, fractionDigits: 2) ?? "0"

    return EnergyBankAlgorithmSummary(
      percent: energy,
      status: Self.energyBankStatusLabel(percent: energy),
      points: points,
      totalCharged: totalCharged,
      totalDrained: totalDrained,
      primarySleepCharge: sleepCharge,
      source: .localEstimate("goose.energy_bank.v1 | confidence=\(confidenceText) | \(inputSummary)"),
      freshness: stress.freshness,
      confidence: energyConfidence,
      inputSummary: inputSummary
    )
  }

  func stressSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    let summary = stressAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks)
    guard let score = summary.score,
          let scoreText = Self.numberText(score, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: scoreText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: Self.stressTrendModel(base: snapshot.trend, summary: summary)
    )
  }

  func energyBankSnapshot(base snapshot: HealthMetricSnapshot, allowLiveFallbacks: Bool = true) -> HealthMetricSnapshot {
    let summary = energyBankAlgorithmSummary(allowLiveFallbacks: allowLiveFallbacks)
    guard let percent = summary.percent,
          let percentText = Self.numberText(percent, fractionDigits: 0) else {
      return replacingHealthMonitorSnapshot(
        snapshot,
        value: "--",
        unit: "%",
        status: summary.status,
        freshness: summary.freshness,
        provenance: summary.source.detail,
        source: summary.source,
        trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
      )
    }

    return replacingHealthMonitorSnapshot(
      snapshot,
      value: percentText,
      unit: "%",
      status: summary.status,
      freshness: summary.freshness,
      provenance: summary.source.detail,
      source: summary.source,
      trend: Self.energyBankTrendModel(base: snapshot.trend, summary: summary)
    )
  }

  func emptyStressSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> StressAlgorithmSummary {
    Self.emptyStressSummaryValue(status: status, freshness: freshness, source: source)
  }

  nonisolated static func emptyStressSummaryValue(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> StressAlgorithmSummary {
    StressAlgorithmSummary(
      score: nil,
      status: status,
      averageHeartRate: nil,
      averageHRV: nil,
      windows: [],
      high: StressZoneSummary(label: "High", percent: 0, durationMinutes: 0),
      medium: StressZoneSummary(label: "Med", percent: 0, durationMinutes: 0),
      low: StressZoneSummary(label: "Low", percent: 0, durationMinutes: 0),
      sampleCount: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  func emptyEnergyBankSummary(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> EnergyBankAlgorithmSummary {
    Self.emptyEnergyBankSummaryValue(status: status, freshness: freshness, source: source)
  }

  nonisolated static func emptyEnergyBankSummaryValue(
    status: String,
    freshness: String,
    source: HealthDataSource
  ) -> EnergyBankAlgorithmSummary {
    EnergyBankAlgorithmSummary(
      percent: nil,
      status: status,
      points: [],
      totalCharged: 0,
      totalDrained: 0,
      primarySleepCharge: 0,
      source: source,
      freshness: freshness,
      confidence: nil,
      inputSummary: source.detail
    )
  }

  nonisolated static func stressRestingHeartRateEstimate(
    samples: [HeartRateSamplePoint],
    date: Date,
    calendar: Calendar,
    allowLiveFallbacks: Bool = true
  ) -> Double {
    if samples.count < 12,
       allowLiveFallbacks,
       let liveEstimate = Self.liveHRDerivedRestingHeartRateSample()?.bpm {
      return liveEstimate
    }
    let values = samples.map(\.bpm).sorted()
    let lowCount = max(1, values.count / 4)
    return Double(values.prefix(lowCount).reduce(0, +)) / Double(lowCount)
  }

  func zeroStrainSnapshot(
    base snapshot: HealthMetricSnapshot,
    freshness: String,
    provenance: String,
    sourceDetail: String
  ) -> HealthMetricSnapshot {
    replacingHealthMonitorSnapshot(
      snapshot,
      value: "--",
      unit: "",
      status: "No strain data",
      freshness: freshness,
      provenance: provenance,
      source: .unavailable(sourceDetail),
      trend: Self.emptyTrend(from: snapshot.trend, packetCount: packetEvidenceFrameCount())
    )
  }

}
