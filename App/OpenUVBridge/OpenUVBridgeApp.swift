// Copyright 2026 Josh Howard
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

@main
struct OpenUVBridgeApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
        }
    }
}
