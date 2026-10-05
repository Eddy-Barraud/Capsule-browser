//
//  isowebappsApp.swift
//  isowebapps
//
//  Created by Eddy Barraud on 23/08/2026.
//
//  Description:
//  The main application entry point for both macOS and iOS platforms.
//  Initializes SwiftData with CloudKit synchronization for `WebAppItem` models,
//  and presents the root `ContentView`.
//

import SwiftUI
import SwiftData

@main
struct isowebappsApp: App {
    /// Shared SwiftData model container configured for multi-device sync
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WebAppItem.self,
            WebAppGroup.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 600)
        #endif
        .modelContainer(sharedModelContainer)
        
        #if os(macOS)
        WindowGroup(id: "capsuleWindow", for: CapsuleWindowPayload.self) { $payload in
            if let payload {
                CapsuleWindowHostView(payload: payload)
                    .frame(minWidth: 800, minHeight: 600)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .defaultSize(width: 800, height: 600)
        .modelContainer(sharedModelContainer)
        #endif
    }
}
