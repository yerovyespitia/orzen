import SwiftUI

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        iPhoneRootShell()
        #else
        SidebarView { selectedItem in
            switch selectedItem?.title {
            case "Home":
                HomeView()
            case "Series":
                SeriesView()
            case "Movies":
                MoviesView()
            case "Collections":
                CollectionsView()
            case "Search":
                SearchView()
            case "Addons":
                AddonsView()
            case "Settings":
                SettingsView()
            default:
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack {
                        Text("Select an item from the sidebar")
                            .foregroundColor(.white)
                    }
                }
            }
        }
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 1280, height: 980)
    }
}
