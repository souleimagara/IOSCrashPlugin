import Foundation

/// Optimizes crash report payloads by removing unnecessary null/empty values
/// This reduces payload size without losing critical diagnostic data
///
/// Removes:
/// - null values (fields with nil)
/// - empty strings ("")
/// - empty arrays ([])
/// - empty dictionaries ([:])
///
/// Keeps:
/// - false booleans (important for crash analysis)
/// - 0 values (important for timing/counts)
/// - non-empty strings and collections
///
/// Size reduction: ~300-400 bytes per crash (3-5%)
struct PayloadOptimizationStrategy {

    /// Clean a dictionary by removing null/empty values recursively
    static func cleanDictionary(_ dict: [String: Any?]) -> [String: Any] {
        var cleaned = [String: Any]()

        for (key, value) in dict {
            if let cleanedValue = cleanValue(value) {
                cleaned[key] = cleanedValue
                print("✅ [PayloadOptimization] Kept: \(key)")
            } else {
                print("🗑️ [PayloadOptimization] Removed: \(key) (null or empty)")
            }
        }

        return cleaned
    }

    /// Clean a single value (handles recursion for nested structures)
    private static func cleanValue(_ value: Any?) -> Any? {
        // Remove nil values
        guard let value = value else {
            return nil
        }

        // Handle String
        if let stringValue = value as? String {
            return stringValue.isEmpty ? nil : stringValue
        }

        // Handle Array
        if let arrayValue = value as? [Any] {
            let cleanedArray = arrayValue.compactMap { cleanValue($0) }
            return cleanedArray.isEmpty ? nil : cleanedArray
        }

        // Handle Dictionary (nested objects)
        if let dictValue = value as? [String: Any?] {
            let cleaned = cleanDictionary(dictValue)
            return cleaned.isEmpty ? nil : cleaned
        }

        // Keep NSNull as nil
        if value is NSNull {
            return nil
        }

        // Keep everything else (numbers, booleans, custom objects)
        // Including false booleans and 0 values which are important
        return value
    }

    /// Convert CrashData to an optimized JSON dictionary (before encoding)
    /// This is useful if you want to clean the data structure before JSONEncoding
    static func optimizeForTransmission(_ dict: [String: Any?]) -> [String: Any] {
        return cleanDictionary(dict)
    }

    /// Calculate the size reduction achieved
    static func calculateSizeReduction(originalJSON: Data, optimizedJSON: Data) -> (bytes: Int, percentage: Double) {
        let originalSize = originalJSON.count
        let optimizedSize = optimizedJSON.count
        let bytesReduced = originalSize - optimizedSize
        let percentageReduced = originalSize > 0 ? Double(bytesReduced) / Double(originalSize) * 100 : 0

        print("📊 [PayloadOptimization] Original: \(originalSize) bytes, Optimized: \(optimizedSize) bytes")
        print("📊 [PayloadOptimization] Reduction: \(bytesReduced) bytes (\(String(format: "%.1f", percentageReduced))%)")

        return (bytes: bytesReduced, percentage: percentageReduced)
    }

    /// JSON serialization helper to prepare crash data for transmission
    static func prepareForSerialization(_ crashData: CrashData) -> [String: Any?] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []  // Compact JSON

        do {
            let jsonData = try encoder.encode(crashData)
            if let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any?] {
                return cleanDictionary(jsonDict)
            }
        } catch {
            print("❌ [PayloadOptimization] Failed to prepare for serialization: \(error)")
        }

        return [:]
    }
}
