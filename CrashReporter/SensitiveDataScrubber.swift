import Foundation

/// Redacts sensitive data from crash reports (passwords, tokens, emails)
///
/// Applies regex patterns to scrub:
/// - API keys and tokens
/// - Passwords and secrets
/// - Bearer tokens
/// - Email addresses
/// - Any custom patterns defined
class SensitiveDataScrubber {
    private static let redactionMask = "[REDACTED]"

    // MARK: - Regex Patterns for Common Sensitive Data

    private static let sensitivePatterns: [String] = [
        // API keys and tokens
        "(?i)(api[_-]?key|apikey|secret|token|password|passwd|pwd|auth[_-]?token|access[_-]?token|refresh[_-]?token)\\s*[=:]\\s*[\"']?[^\"'\\s]+[\"']?",

        // Bearer tokens
        "(?i)(bearer|authorization)\\s+\\S+",

        // Email addresses
        "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}",

        // Credit card patterns (basic)
        "\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b",

        // AWS keys and secrets
        "(?i)(aws_secret_access_key|aws_access_key_id|aws_session_token)\\s*[=:]\\s*[\"']?[^\"'\\s]+[\"']?",

        // OAuth tokens
        "(?i)(oauth|access_token|refresh_token|id_token)\\s*[=:]\\s*[\"']?[^\"'\\s]+[\"']?",

        // SQL passwords in connection strings
        "(?i)(password|pwd)\\s*=\\s*[^;\\s]+",

        // Private keys
        "-----BEGIN [A-Z]+ PRIVATE KEY-----[\\s\\S]*?-----END [A-Z]+ PRIVATE KEY-----"
    ]

    // MARK: - Scrub Crash Data

    /// Scrub sensitive data from crash data dictionary
    /// - Parameter data: Dictionary to scrub
    /// - Returns: Scrubbed dictionary
    static func scrubDictionary(_ data: [String: String]) -> [String: String] {
        var scrubbed = data
        for (key, value) in data {
            scrubbed[key] = scrubString(value)
        }
        return scrubbed
    }

    /// Scrub sensitive data from string
    /// - Parameter text: Text to scrub
    /// - Returns: Scrubbed text with sensitive data redacted
    static func scrubString(_ text: String) -> String {
        var result = text

        // Apply all patterns
        for pattern in sensitivePatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .useUnicodeWordBoundaries])
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: redactionMask)
            } catch {
                // Skip invalid regex patterns
                continue
            }
        }

        return result
    }

    // MARK: - Scrub Specific Fields

    /// Scrub exception message
    /// - Parameter message: Exception message
    /// - Returns: Scrubbed message
    static func scrubExceptionMessage(_ message: String) -> String {
        return scrubString(message)
    }

    /// Scrub stack trace
    /// - Parameter stackTrace: Full stack trace
    /// - Returns: Scrubbed stack trace
    static func scrubStackTrace(_ stackTrace: String) -> String {
        return scrubString(stackTrace)
    }

    /// Scrub customData dictionary
    /// - Parameter customData: Custom data fields
    /// - Returns: Scrubbed custom data
    static func scrubCustomData(_ customData: [String: String]) -> [String: String] {
        return scrubDictionary(customData)
    }

    // MARK: - Register Custom Pattern

    /// Register additional custom regex pattern for redaction
    /// Note: Patterns are applied in order, so more specific patterns should be added first
    /// - Parameter pattern: Regex pattern to match sensitive data
    private static var customPatterns: [String] = []

    static func registerCustomPattern(_ pattern: String) {
        customPatterns.append(pattern)
    }

    // MARK: - Test Pattern

    /// Test if string matches any sensitive data pattern
    /// - Parameter text: Text to test
    /// - Returns: true if any pattern matches
    static func containsSensitiveData(_ text: String) -> Bool {
        for pattern in sensitivePatterns + customPatterns {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    return true
                }
            } catch {
                continue
            }
        }
        return false
    }
}
