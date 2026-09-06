import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers
import os.log

class ShareViewController: UIViewController {
    
    let logger = OSLog(subsystem: "com.trevalim.isowebapps.Open-in-a-capsule", category: "ShareExtension")

    override func viewDidLoad() {
        super.viewDidLoad()
        #if DEBUG
        os_log("ShareViewController viewDidLoad", log: self.logger, type: .debug)
        #endif
        
        view.backgroundColor = .clear // Prevent white flash if possible
        
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            #if DEBUG
            os_log("No attachments found", log: self.logger, type: .error)
            #endif
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        let urlType = UTType.url.identifier
        
        if itemProvider.hasItemConformingToTypeIdentifier(urlType) {
            #if DEBUG
            os_log("Found URL item provider", log: self.logger, type: .debug)
            #endif
            itemProvider.loadItem(forTypeIdentifier: urlType, options: nil) { (item, error) in
                if let error = error {
                    #if DEBUG
                    os_log("Error loading item: %{public}@", log: self.logger, type: .error, error.localizedDescription)
                    #endif
                }
                
                if let url = item as? URL {
                    self.openMainApp(with: url)
                } else if let urlString = item as? String, let url = URL(string: urlString) {
                    self.openMainApp(with: url)
                } else {
                    #if DEBUG
                    os_log("Item was not a URL or String", log: self.logger, type: .error)
                    #endif
                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            }
        } else {
            #if DEBUG
            os_log("No item conforming to URL type", log: self.logger, type: .error)
            #endif
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
    
    private func openMainApp(with sharedURL: URL) {
        #if DEBUG
        os_log("Preparing to open URL: %{public}@", log: self.logger, type: .debug, sharedURL.absoluteString)
        #endif
        
        var allowedQuery = CharacterSet.urlQueryAllowed
        allowedQuery.remove(charactersIn: "?&=")
        guard let encodedURL = sharedURL.absoluteString.addingPercentEncoding(withAllowedCharacters: allowedQuery),
              let appURL = URL(string: "capsulebrowser://open?url=\(encodedURL)") else {
            #if DEBUG
            os_log("Failed to construct capsulebrowser URL", log: self.logger, type: .error)
            #endif
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        #if DEBUG
        os_log("Final appURL: %{public}@", log: self.logger, type: .debug, appURL.absoluteString)
        #endif
        
        // Bypass App Extension restriction for UIApplication.shared
        let selector = NSSelectorFromString("sharedApplication")
        if UIApplication.responds(to: selector) {
            let sharedApp = UIApplication.perform(selector).takeUnretainedValue() as? UIApplication
            sharedApp?.open(appURL, options: [:]) { success in
                #if DEBUG
                os_log("UIApplication.open result: %d", log: self.logger, type: .debug, success)
                #endif
                self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            }
        } else {
            // Fallback
            #if DEBUG
            os_log("sharedApplication selector not found, falling back", log: self.logger, type: .debug)
            #endif
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
}
