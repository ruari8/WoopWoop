import SwiftUI

struct ConnectionView: View {
  let ble: GooseBLEClient
  let rustStatus: String
  let helloSummary: String

  var body: some View {
    ConnectionContentView(
      ble: ble,
      connectionStatus: ble.connectionStatus,
      historicalSync: ble.historicalSyncStatusStore,
      liveVitals: ble.liveVitals,
      rustStatus: rustStatus,
      helloSummary: helloSummary
    )
  }
}

private struct ConnectionContentView: View {
  private static let maximumVisibleEventMessages = 80

  @EnvironmentObject private var messageStore: GooseMessageStore
  let ble: GooseBLEClient
  @ObservedObject var connectionStatus: GooseConnectionStatusStore
  @ObservedObject var historicalSync: GooseHistoricalSyncStatusStore
  @ObservedObject var liveVitals: GooseLiveVitalsStore
  let rustStatus: String
  let helloSummary: String

  var body: some View {
    List {
      Section("Status") {
        LabeledContent("Bluetooth", value: connectionStatus.bluetoothState)
        LabeledContent("Connection", value: connectionStatus.connectionState)
        LabeledContent("Reconnect", value: connectionStatus.reconnectState)
        LabeledContent("Historical", value: historicalSyncValue)
        LabeledContent("Remembered", value: connectionStatus.rememberedDeviceDescription)
        LabeledContent("Live HR", value: liveHeartRateValue)
        LabeledContent("Rust", value: rustStatus)
        LabeledContent("Hello", value: helloSummary)
      }

      Section("Actions") {
        Button("Request Bluetooth") {
          ble.requestBluetooth()
        }
        Button(connectionStatus.isScanning ? "Stop Scan" : "Scan") {
          connectionStatus.isScanning ? ble.stopScan() : ble.startScan()
        }
        .disabled(!connectionStatus.canScan)

        Button("Connect Selected") {
          ble.connectSelected()
        }
        .disabled(!connectionStatus.canConnect)

        Button("Reconnect Remembered") {
          ble.reconnectRemembered()
        }
        .disabled(!connectionStatus.canReconnectRemembered)

        Button("Send Client Hello") {
          ble.sendClientHello()
        }
        .disabled(!connectionStatus.canSendHello)

        Button(historicalSync.isSyncing ? "Syncing Historical Packets" : "Request Historical Packets") {
          ble.syncHistoricalPackets()
        }
        .disabled(!historicalSync.canSyncHistorical)

        Button("Forget Remembered Device", role: .destructive) {
          ble.forgetRememberedDevice()
        }
        .disabled(!connectionStatus.hasRememberedDevice)
      }

      Section("Discovered") {
        if connectionStatus.discoveredDevices.isEmpty {
          Text("No devices yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(connectionStatus.discoveredDevices) { device in
            Button {
              ble.select(device)
            } label: {
              HStack {
                VStack(alignment: .leading) {
                  Text(device.name)
                  Text(device.id.uuidString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(device.rssi)")
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      }

      Section("Client Hello") {
        Text(GooseHello.clientHelloFrameHex)
          .font(.system(.footnote, design: .monospaced))
          .textSelection(.enabled)
      }

      Section("Event Log") {
        ForEach(visibleMessages) { message in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(message.timestamp, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
              Text(message.level.rawValue.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.level == .error ? .red : .secondary)
              Text(message.source)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(message.title)
              .font(.subheadline.weight(.semibold))
            Text(message.body)
              .font(.system(.caption, design: .monospaced))
              .foregroundStyle(.secondary)
              .textSelection(.enabled)
          }
        }

        if messageStore.messages.count > Self.maximumVisibleEventMessages {
          Text("Showing latest \(Self.maximumVisibleEventMessages) of \(messageStore.messages.count) events")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .gooseListBackground()
    .navigationTitle("Connect")
  }

  private var visibleMessages: ArraySlice<GooseMessage> {
    messageStore.messages.prefix(Self.maximumVisibleEventMessages)
  }

  private var liveHeartRateValue: String {
    guard let bpm = liveVitals.liveHeartRateBPM else {
      return liveVitals.liveHeartRateSource
    }
    if let updatedAt = liveVitals.liveHeartRateUpdatedAt {
      return "\(bpm) bpm via \(liveVitals.liveHeartRateSource) @ \(updatedAt.formatted(date: .omitted, time: .standard))"
    }
    return "\(bpm) bpm via \(liveVitals.liveHeartRateSource)"
  }

  private var historicalSyncValue: String {
    let packetCount = historicalSync.packetCount
    let packets = "\(packetCount) \(packetCount == 1 ? "packet" : "packets")"
    if historicalSync.isSyncing {
      return "syncing | \(packets)"
    }
    if let completedAt = historicalSync.completedAt {
      return "\(historicalSync.status) | \(packets) @ \(completedAt.formatted(date: .omitted, time: .standard))"
    }
    return "\(historicalSync.status) | \(packets)"
  }
}
