//
//  AddWebAppSheet.swift
//  isowebapps
//
//  Created on 23/08/2026.
//
//  Description:
//  Modal presentation form for adding a new web application to the Home Screen.
//  Collects the app's name and URL, fetches its high-resolution favicon once,
//  and inserts the new `WebAppItem` into the SwiftData model context.
//

import SwiftUI
import SwiftData

struct AddWebAppSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String = ""
    @State private var urlString: String = "https://"
    @State private var isFetching: Bool = false
    @State private var fetchedIconData: Data? = nil
    @State private var errorMessage: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Web App Details")) {
                    TextField("App Name (e.g. GitHub, Twitter)", text: $name)
                    
                    TextField("Website URL", text: $urlString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }
                
                if let iconData = fetchedIconData,
                   let platformImage = PlatformImage(data: iconData) {
                    Section(header: Text("Retrieved Icon")) {
                        HStack {
                            Spacer()
                            Image(platformImage: platformImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .liquidGlassCard(cornerRadius: 14)
                            Spacer()
                        }
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Add Web App")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        saveWebApp()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || urlString.trimmingCharacters(in: .whitespaces).isEmpty || isFetching)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }
    
    /// Normalizes URL, fetches favicon metadata asynchronously, and inserts `WebAppItem`
    private func saveWebApp() {
        var formattedURL = urlString.trimmingCharacters(in: .whitespaces)
        if !formattedURL.lowercased().hasPrefix("http://") && !formattedURL.lowercased().hasPrefix("https://") {
            formattedURL = "https://" + formattedURL
        }
        
        guard let url = URL(string: formattedURL) else {
            errorMessage = "Please enter a valid URL."
            return
        }
        
        isFetching = true
        errorMessage = nil
        
        Task {
            // Fetch web app icon once upon creation
            let iconData = await FaviconFetcher.fetchIcon(for: url)
            
            await MainActor.run {
                let newApp = WebAppItem(
                    name: name.trimmingCharacters(in: .whitespaces),
                    urlString: formattedURL,
                    iconData: iconData
                )
                modelContext.insert(newApp)
                try? modelContext.save()
                isFetching = false
                dismiss()
            }
        }
    }
}
                let newApp = WebAppItem(
                    name: name.trimmingCharacters(in: .whitespaces),
                    urlString: formattedURL,
                    iconData: iconData
                )
                modelContext.insert(newApp)
                try? modelContext.save()
                isFetching = false
                dismiss()
            }
        }
    }
}
