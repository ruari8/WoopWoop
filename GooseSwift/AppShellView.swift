import SwiftUI

struct AppShellView: View {
  let model: GooseAppModel
  @EnvironmentObject private var router: AppRouter
  @StateObject private var healthStore = HealthDataStore()
  @State private var homePath: [HomeRoute] = []
  @State private var homeSelectedDate = Date()

  var body: some View {
    TabView(selection: tabSelection) {
      ForEach(GooseAppTab.allCases) { tab in
        tabNavigationStack(for: tab, isActive: router.selectedTab == tab)
        .tabItem {
          Label(tab.title, systemImage: tab.systemImage)
        }
        .tag(tab)
      }
    }
  }

  private var tabSelection: Binding<GooseAppTab> {
    Binding {
      router.selectedTab
    } set: { newTab in
      if newTab == router.selectedTab {
        router.reselect(newTab)
        return
      }
      router.selectedTab = newTab
      model.recordUIAction("tab.selected", detail: newTab.title)
    }
  }

  @ViewBuilder
  private func tabNavigationStack(for tab: GooseAppTab, isActive: Bool) -> some View {
    if tab == .home {
      NavigationStack(path: $homePath) {
        tabContent(for: tab, isActive: isActive)
          .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .health(let healthRoute):
              HealthRouteDestinationView(
                route: healthRoute,
                store: healthStore,
                ble: model.ble,
                liveVitals: model.ble.liveVitals,
                activitySession: model.activitySession,
                selectedDate: $homeSelectedDate,
                recordUIAction: model.recordUIAction
              )
            case .activity(let item):
              ActivityTimelineDetailView(item: item)
            }
          }
      }
    } else if tab == .health {
      NavigationStack(path: $router.healthPath) {
        tabContent(for: tab, isActive: isActive)
      }
    } else if tab == .more {
      NavigationStack(path: $router.morePath) {
        tabContent(for: tab, isActive: isActive)
      }
    } else {
      NavigationStack {
        tabContent(for: tab, isActive: isActive)
      }
    }
  }

  @ViewBuilder
  private func tabContent(for tab: GooseAppTab, isActive: Bool) -> some View {
    if isActive {
      switch tab {
      case .home:
        HomeDashboardView(
          model: model,
          connectionStatus: model.ble.connectionStatus,
          activityTimeline: model.homeActivityTimeline,
          healthStore: healthStore,
          selectedDate: $homeSelectedDate,
          openHealthRoute: openHomeHealthRoute,
          openActivity: openHomeActivity
        )
      case .health:
        HealthView(model: model, liveVitals: model.ble.liveVitals, store: healthStore)
      case .coach:
        CoachView(model: model, liveVitals: model.ble.liveVitals, healthStore: healthStore)
      case .more:
        MoreView(
          model: model,
          ble: model.ble,
          connectionStatus: model.ble.connectionStatus,
          healthStore: healthStore
        )
      }
    } else {
      Color.clear
    }
  }

  private func openHomeHealthRoute(_ route: HealthRoute) {
    homePath = [.health(route)]
  }

  private func openHomeActivity(_ item: ActivityTimelineItem) {
    homePath = [.activity(item)]
  }
}

enum HomeRoute: Hashable {
  case health(HealthRoute)
  case activity(ActivityTimelineItem)
}

enum GooseAppTab: String, CaseIterable, Identifiable {
  case home
  case health
  case coach
  case more

  var id: String { rawValue }

  var title: String {
    switch self {
    case .home: "Home"
    case .health: "Health"
    case .coach: "Coach"
    case .more: "More"
    }
  }

  var systemImage: String {
    switch self {
    case .home: "house"
    case .health: "heart.text.square"
    case .coach: "sparkles"
    case .more: "ellipsis.circle"
    }
  }

}
