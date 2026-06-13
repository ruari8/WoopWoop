import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct LiveActivityView: View {
  let model: GooseAppModel

  var body: some View {
    LiveActivityContentView(
      model: model,
      liveVitals: model.ble.liveVitals,
      session: model.activitySession,
      locationTracker: model.activityLocationTracker
    )
  }
}
