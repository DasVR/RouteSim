import SwiftUI

struct RootView: View {
    @StateObject private var tunnelManager = TunnelManager.shared
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            mainTabs
        } else {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                SimulateView()
            }
            .tabItem {
                Label("Simulate", systemImage: "location.fill")
            }

            NavigationStack {
                LibraryView()
            }
            .tabItem {
                Label("Library", systemImage: "map")
            }

            NavigationStack {
                RouteSimSettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
    }
}
