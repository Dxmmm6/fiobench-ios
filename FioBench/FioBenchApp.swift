import SwiftUI
import UIKit

@main
struct FioBenchApp: App {
    @StateObject private var model = AppModel()

    init() {
        UITableView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
