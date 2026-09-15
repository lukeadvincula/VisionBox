//
//  VisionBoxApp.swift
//  VisionBox
//

import SwiftUI

@main
struct VisionBoxApp: App {
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ScanView(dependencies: dependencies)
            }
        }
    }
}
