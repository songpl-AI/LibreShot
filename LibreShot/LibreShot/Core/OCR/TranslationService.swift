import Foundation
import NaturalLanguage
import Translation

enum TranslationServiceError: LocalizedError {
    case unsupportedLanguage
    case languageNotInstalled

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage:
            return "不支持该语言组合"
        case .languageNotInstalled:
            return "语言包尚未安装。请在系统设置 → 通用 → 语言与地区 → 翻译语言中下载所需语言后重试。"
        }
    }
}

/// 设备端离线翻译，基于系统 Translation 框架。
/// 当前 SDK 中 `TranslationSession` 的公开初始化器为
/// `init(installedSource:target:)`，仅 macOS 26.0+ 可用。
@available(macOS 26.0, *)
enum TranslationService {
    /// 翻译一段文本，自动检测源语言。
    static func translate(_ text: String, target: Locale.Language) async throws -> String {
        guard !text.isEmpty else { return "" }

        let source = detectLanguage(of: text)

        // 源语言与目标语言相同，无需翻译
        if source == target { return text }

        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)

        switch status {
        case .unsupported:
            throw TranslationServiceError.unsupportedLanguage
        case .supported:
            // Headless sessions cannot request downloads. Interactive callers must
            // use the session supplied by SwiftUI's translationTask instead.
            throw TranslationServiceError.languageNotInstalled
        case .installed:
            return try await translate(text, using: TranslationSession(installedSource: source, target: target))
        @unknown default:
            throw TranslationServiceError.unsupportedLanguage
        }
    }

    /// Keep the supplied session inside the lifetime of its translationTask.
    static func translate(_ text: String, using session: TranslationSession) async throws -> String {
        try Task.checkCancellation()
        // translate() presents the system download consent/progress UI if needed,
        // then continues translation. Installed languages skip that prompt.
        let response = try await session.translate(text)
        try Task.checkCancellation()
        return response.targetText
    }

    static func detectLanguage(of text: String) -> Locale.Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let dominant = recognizer.dominantLanguage {
            return Locale.Language(identifier: dominant.rawValue)
        }
        return Locale.Language(identifier: "en")
    }
}
