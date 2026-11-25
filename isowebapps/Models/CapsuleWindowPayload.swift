//
//  CapsuleWindowPayload.swift
//  isowebapps
//
//  Description:
//  Codable window launch payload for macOS `capsuleWindow` scenes.
//

import Foundation
#if os(macOS)
import AppKit
#endif

#if os(macOS)
struct CapsuleWindowPayload: Codable, Hashable, Identifiable {
    var id: UUID { instanceId }
    let appId: UUID?
    let urlString: String?
    let name: String?
    let isSecondaryWindow: Bool
    let openAsTab: Bool
    let startInReaderMode: Bool
    let instanceId: UUID
    let sourceWindowNumber: Int?
    let sourceFrame: [Double]?
    
    enum CodingKeys: String, CodingKey {
        case appId
        case urlString
        case name
        case isSecondaryWindow
        case openAsTab
        case startInReaderMode
        case instanceId
        case sourceWindowNumber
        case sourceFrame
    }
    
    init(
        appId: UUID?,
        urlString: String?,
        name: String?,
        isSecondaryWindow: Bool = true,
        openAsTab: Bool = false,
        startInReaderMode: Bool = false,
        instanceId: UUID = UUID(),
        sourceWindowNumber: Int? = nil,
        sourceFrame: [Double]? = nil
    ) {
        self.appId = appId
        self.urlString = urlString
        self.name = name
        self.isSecondaryWindow = isSecondaryWindow
        self.openAsTab = openAsTab
        self.startInReaderMode = startInReaderMode
        self.instanceId = instanceId
        self.sourceWindowNumber = sourceWindowNumber
        self.sourceFrame = sourceFrame
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appId = try container.decodeIfPresent(UUID.self, forKey: .appId)
        self.urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.isSecondaryWindow = try container.decodeIfPresent(Bool.self, forKey: .isSecondaryWindow) ?? true
        self.openAsTab = try container.decodeIfPresent(Bool.self, forKey: .openAsTab) ?? false
        self.startInReaderMode = try container.decodeIfPresent(Bool.self, forKey: .startInReaderMode) ?? false
        self.instanceId = try container.decodeIfPresent(UUID.self, forKey: .instanceId) ?? UUID()
        self.sourceWindowNumber = try container.decodeIfPresent(Int.self, forKey: .sourceWindowNumber)
        self.sourceFrame = try container.decodeIfPresent([Double].self, forKey: .sourceFrame)
    }
    
    var sourceFrameRect: NSRect? {
        guard let sf = sourceFrame, sf.count == 4 else { return nil }
        return NSRect(x: sf[0], y: sf[1], width: sf[2], height: sf[3])
    }
    
    static var defaultNewTabPayload: CapsuleWindowPayload {
        let modeRaw = UserDefaults.standard.string(forKey: "windowPresentationMode") ?? "singleWindow"
        let mode = WindowPresentationMode(rawValue: modeRaw) ?? .singleWindow
        let rawEngine = UserDefaults.standard.string(forKey: SearchEngine.storageKey) ?? SearchEngine.duckDuckGo.rawValue
        let engine = SearchEngine(rawValue: rawEngine) ?? .duckDuckGo
        let customURL = UserDefaults.standard.string(forKey: SearchEngine.customURLStorageKey) ?? ""
        return CapsuleWindowPayload(
            appId: nil,
            urlString: engine.homeURLString(customTemplate: customURL),
            name: engine.displayName,
            isSecondaryWindow: true,
            openAsTab: (mode == .tabs)
        )
    }
}
#endif
