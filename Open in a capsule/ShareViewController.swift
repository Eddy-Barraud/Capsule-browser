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
            itemProvider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] (item, error) in
                if let error = error {
                    #if DEBUG
                    if let self = self {
                        os_log("Error loading item: %{public}@", log: self.logger, type: .error, error.localizedDescription)
                    }
                    #endif
                }
                
                DispatchQueue.main.async {
                    guard let self = self else { return }
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
        
        // Security: Strictly enforce http/https web schemes to prevent local file disclosure (file://)
        // or script execution vectors from being routed to the container app.
        guard let scheme = sharedURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            #if DEBUG
            os_log("Rejected shared URL with unsupported or non-web scheme: %{public}@", log: self.logger, type: .error, sharedURL.absoluteString)
            #endif
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
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
        
        // Safely traverse the UIResponder chain to invoke open(_:options:completionHandler:) on the application,
        // which complies with App Extension review guidelines without calling prohibited sharedApplication directly.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(appURL, options: [:]) { [weak self] _ in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
                #if DEBUG
                os_log("Successfully requested URL open via UIResponder chain", log: self.logger, type: .debug)
                #endif
                return
            }
            responder = current.next ?? (current as? UIViewController)?.view.window
        }
        
        #if DEBUG
        os_log("UIResponder chain did not respond to openURL:, completing request", log: self.logger, type: .error)
        #endif
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
