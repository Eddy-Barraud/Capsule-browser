//
//  AISummarizer.swift
//  isowebapps
//
//  Created on 25/08/2026.
//
//  Description:
//  Provides on-device AI web page summarization using Apple Foundation Models.
//  Processes HTML-to-Markdown extracted web page content capped at 4,000 tokens
//  and streams or returns a concise summary limited to 4 sentences maximum.
//

import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Errors encountered during the web page Markdown capture and AI summarization pipeline.
public enum WebPageSummaryError: LocalizedError {
    case webViewUnavailable
    case emptyContent
    case modelUnavailable(String)
    case generationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .webViewUnavailable:
            return "The web page is not ready or unavailable."
        case .emptyContent:
            return "No readable content could be extracted from the web page."
        case .modelUnavailable(let reason):
            return "Apple Intelligence is unavailable: \(reason)"
        case .generationFailed(let reason):
            return "AI summary generation failed: \(reason)"
        }
    }
}

@MainActor
/// Orchestrates on-device Foundation Models for summarizing web pages.
public final class AISummarizer: ObservableObject {
    public static let shared = AISummarizer()
    public static let maxInputTokens: Int = 4000
    
    private init() {}
    
    /// Checks whether Apple Intelligence SystemLanguageModel is available on the current device and OS.
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability {
                return true
            }
        }
        #endif
        return false
    }
    
    /// Summarizes Markdown content extracted from a web page using Foundation Models.
    public func summarize(
        title: String,
        url: String,
        markdownContent: String,
        onPartialUpdate: ((String) -> Void)? = nil
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let trimmedContent = markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else {
                throw WebPageSummaryError.emptyContent
            }
            
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                break
            case .unavailable(let reason):
                let reasonStr: String
                switch reason {
                case .deviceNotEligible:
                    reasonStr = "Device is not eligible for Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    reasonStr = "Apple Intelligence is not enabled in System Settings."
                case .modelNotReady:
                    reasonStr = "Model is still downloading or preparing."
                @unknown default:
                    reasonStr = "Apple Intelligence is currently unavailable."
                }
                throw WebPageSummaryError.modelUnavailable(reasonStr)
            }
            
            let language = Self.resolvedLanguageCode()
            let instructions = Self.loadInstructions(for: language)
            
            // Cap Markdown input to 4,000 estimated tokens to preserve structure within context limits
            let truncatedContent = ReaderHTMLUtilities.truncateMarkdownToTokenLimit(
                trimmedContent,
                maxTokens: Self.maxInputTokens
            )
            let resolvedTitle = title.isEmpty ? Self.defaultWebPageTitle(for: language) : title
            let prompt = Self.loadUserPrompt(for: language, title: resolvedTitle, content: truncatedContent)
            
            do {
                let session = LanguageModelSession(instructions: instructions)
                let options = GenerationOptions(
                    temperature: 0.3,
                    maximumResponseTokens: 400
                )
                
                if let onPartialUpdate = onPartialUpdate {
                    var latestPartial = ""
                    let stream = session.streamResponse(to: prompt, options: options)
                    for try await snapshot in stream {
                        let partial = String(describing: snapshot.content).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !partial.isEmpty && partial != latestPartial {
                            latestPartial = partial
                            onPartialUpdate(partial)
                        }
                    }
                    if !latestPartial.isEmpty {
                        return latestPartial
                    }
                }
                
                let response = try await session.respond(to: prompt, options: options)
                let result = String(describing: response.content).trimmingCharacters(in: .whitespacesAndNewlines)
                return result
            } catch {
                throw WebPageSummaryError.generationFailed(error.localizedDescription)
            }
        } else {
            throw WebPageSummaryError.modelUnavailable("Apple Intelligence is not available on this version of iOS/macOS.")
        }
        #else
        throw WebPageSummaryError.modelUnavailable("FoundationModels is not supported on this platform.")
        #endif
    }
    
    // MARK: - Localization & Prompt Loading
    
    /// Supported prompt languages (`en`, `fr`, `es`), resolved from the user's preferred system languages.
    private static func resolvedLanguageCode() -> String {
        let supported: Set<String> = ["en", "fr", "es"]
        
        for identifier in Locale.preferredLanguages {
            let locale = Locale(identifier: identifier)
            if let code = locale.language.languageCode?.identifier.lowercased(),
               supported.contains(code) {
                return code
            }
            let prefix = String(identifier.prefix(2)).lowercased()
            if supported.contains(prefix) {
                return prefix
            }
        }
        
        if let currentCode = Locale.current.language.languageCode?.identifier.lowercased(),
           supported.contains(currentCode) {
            return currentCode
        }
        
        return "en"
    }
    
    private static func defaultWebPageTitle(for language: String) -> String {
        switch language {
        case "fr":
            return "Page Web"
        case "es":
            return "Página web"
        default:
            return "Web Page"
        }
    }
    
    /// Loads a prompt text file from the app bundle (`Prompts` subdirectory or bundle root).
    private static func loadPromptFile(named name: String) -> String? {
        let candidateURLs: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Prompts"),
            Bundle.main.url(forResource: name, withExtension: "txt"),
            Bundle.main.resourceURL?.appendingPathComponent("Prompts/\(name).txt"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).txt")
        ]
        
        for candidate in candidateURLs {
            if let url = candidate,
               FileManager.default.fileExists(atPath: url.path),
               let content = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty {
                return content
            }
        }
        return nil
    }
    
    private static func loadInstructions(for language: String) -> String {
        loadPromptFile(named: "instructions_\(language)")
            ?? loadPromptFile(named: "instructions_en")
            ?? ""
    }
    
    private static func loadUserPrompt(for language: String, title: String, content: String) -> String {
        let template = loadPromptFile(named: "prompt_\(language)")
            ?? loadPromptFile(named: "prompt_en")
            ?? "{{TITLE}}\n\n{{CONTENT}}"
        
        return template
            .replacingOccurrences(of: "{{TITLE}}", with: title)
            .replacingOccurrences(of: "{{CONTENT}}", with: content)
    }
}
