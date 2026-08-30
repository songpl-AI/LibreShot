import Foundation
import NaturalLanguage
import Translation

enum TranslationServiceError: LocalizedError {
    case unsupportedLanguage
    case languageNotInstalled
    case translationFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage:
            return "不支持该语言组合"
        case .languageNotInstalled:
            return "语言包未安装，首次使用需联网下载语言包后重试"
        case .translationFailed(let message):
            return "翻译失败：\(message)"
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

        let session = TranslationSession(installedSource: source, target: target)
        switch status {
        case .unsupported:
            throw TranslationServiceError.unsupportedLanguage
        case .supported:
            // 支持但未安装：先下载语言包
            do {
                try await session.prepareTranslation()
            } catch {
                throw TranslationServiceError.languageNotInstalled
            }
            return try await runTranslate(session, text)
        case .installed:
            return try await runTranslate(session, text)
        }
    }

    private static func runTranslate(_ session: TranslationSession, _ text: String) async throws -> String {
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch {
            throw TranslationServiceError.translationFailed(error.localizedDescription)
        }
    }

    private static func detectLanguage(of text: String) -> Locale.Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let dominant = recognizer.dominantLanguage {
            return Locale.Language(identifier: dominant.rawValue)
        }
        return Locale.Language(identifier: "en")
    }
}
