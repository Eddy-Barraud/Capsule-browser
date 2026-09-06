import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        let urlType = UTType.url.identifier
        
        if itemProvider.hasItemConformingToTypeIdentifier(urlType) {
            itemProvider.loadItem(forTypeIdentifier: urlType, options: nil) { (item, error) in
                if let url = item as? URL {
                    self.openMainApp(with: url)
                } else if let urlString = item as? String, let url = URL(string: urlString) {
                    self.openMainApp(with: url)
                } else {
                    self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            }
        } else {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
    
    private func openMainApp(with sharedURL: URL) {
        guard let encodedURL = sharedURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let appURL = URL(string: "capsulebrowser://open?url=\(encodedURL)") else {
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }
        
        // Use responder chain trick to call UIApplication.shared.openURL:
        var responder: UIResponder? = self
        while responder != nil {
            if responder?.responds(to: Selector("openURL:")) == true {
                responder?.perform(Selector("openURL:"), with: appURL)
                break
            }
            responder = responder?.next
        }
        
        self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
