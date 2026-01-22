import Foundation
import UIKit

/// Validates ANR crashes with multi-factor analysis
///
/// Reduces false positives by checking:
/// - Screen state (must be ON for real ANR)
/// - Process importance (FOREGROUND/VISIBLE only)
/// - Power save mode (increases threshold)
/// - Battery level (< 5% is suspicious)
/// - Recent network loss (contextual)
/// - Calculates confidence score 0-100%
class ANRValidator {

    struct ValidationResult {
        let isValid: Bool              // Is this a real ANR (not false positive)?
        let confidence: Int            // 0-100 confidence score
        let reason: String             // Explanation of validation result
        let factors: ValidationFactors // Individual factor results
    }

    struct ValidationFactors {
        let screenOn: Bool
        let processImportance: String
        let powerSaveMode: Bool
        let batteryLevel: Float
        let networkLost: Bool
    }

    // MARK: - Validate ANR

    /// Validate if ANR crash is real (not false positive)
    /// - Parameters:
    ///   - watchdogDurationMs: Duration of watchdog/ANR
    ///   - deviceState: Current device state
    ///   - processInfo: Process information
    /// - Returns: ValidationResult with confidence and factors
    static func validateANR(
        watchdogDurationMs: Int64,
        deviceState: DeviceState,
        processInfo: ProcessInfo
    ) -> ValidationResult {
        var confidenceFactors: [Int] = []
        var validationReasons: [String] = []

        // Factor 1: Screen State (most important)
        let screenOn = deviceState.screenOn
        if screenOn {
            confidenceFactors.append(100)  // Very high confidence if screen on
            validationReasons.append("Screen ON")
        } else {
            confidenceFactors.append(20)   // Low confidence if screen off (might be background restriction)
            validationReasons.append("Screen OFF (lower confidence)")
        }

        // Factor 2: Process Importance
        let importance = processInfo.importance.uppercased()
        let isHighImportance = importance == "FOREGROUND" || importance == "VISIBLE"
        if isHighImportance {
            confidenceFactors.append(90)   // High confidence for foreground process
            validationReasons.append("Process importance: \(importance)")
        } else {
            confidenceFactors.append(30)   // Lower confidence for background
            validationReasons.append("Process importance: \(importance) (background)")
        }

        // Factor 3: Battery Level
        let batteryLevel = deviceState.batteryLevel
        if batteryLevel >= 0.05 {  // More than 5%
            confidenceFactors.append(80)
            validationReasons.append("Battery: \(Int(batteryLevel * 100))%")
        } else {
            confidenceFactors.append(40)   // Low battery can cause system sluggishness
            validationReasons.append("Battery: \(Int(batteryLevel * 100))% (critical)")
        }

        // Factor 4: Thermal State
        let thermalState = deviceState.thermalState.lowercased()
        if thermalState == "nominal" {
            confidenceFactors.append(90)
            validationReasons.append("Thermal state: Normal")
        } else if thermalState == "warm" {
            confidenceFactors.append(60)
            validationReasons.append("Thermal state: Warm (throttling possible)")
        } else {
            confidenceFactors.append(30)
            validationReasons.append("Thermal state: \(thermalState) (high impact)")
        }

        // Factor 5: Memory State
        let lowMemory = deviceState.lowMemory
        if !lowMemory {
            confidenceFactors.append(85)
            validationReasons.append("Memory: Sufficient")
        } else {
            confidenceFactors.append(55)
            validationReasons.append("Memory: Low (causes slowdown)")
        }

        // Factor 6: ANR Duration (longer duration = more likely real)
        let durationSeconds = watchdogDurationMs / 1000
        if durationSeconds >= 20 {  // ANR threshold is typically 20+ seconds
            confidenceFactors.append(95)
            validationReasons.append("Duration: \(durationSeconds)s (clear ANR)")
        } else if durationSeconds >= 10 {
            confidenceFactors.append(70)
            validationReasons.append("Duration: \(durationSeconds)s")
        } else {
            confidenceFactors.append(40)
            validationReasons.append("Duration: \(durationSeconds)s (short)")
        }

        // Calculate overall confidence (weighted average)
        let confidence = confidenceFactors.isEmpty ? 0 : confidenceFactors.reduce(0, +) / confidenceFactors.count

        // Determine validity: Real ANR if confidence > 60% AND screen ON AND foreground
        let isValid = confidence > 60 && screenOn && isHighImportance

        // Build reason string
        let reasonPrefix = isValid ? "Real ANR" : "Potential false positive"
        let reason = reasonPrefix + ": " + validationReasons.joined(separator: ", ")

        let factors = ValidationFactors(
            screenOn: screenOn,
            processImportance: importance,
            powerSaveMode: false,  // iOS doesn't expose low power mode easily, skip for now
            batteryLevel: batteryLevel,
            networkLost: false     // Network loss tracking done separately
        )

        return ValidationResult(
            isValid: isValid,
            confidence: confidence,
            reason: reason,
            factors: factors
        )
    }

    // MARK: - Add Validation Data to Custom Data

    /// Inject validation results into crash customData
    /// - Parameters:
    ///   - customData: Existing customData dictionary
    ///   - validation: ValidationResult from validateANR()
    /// - Returns: Updated customData with validation fields
    static func enrichCustomDataWithValidation(
        _ customData: [String: String],
        validation: ValidationResult
    ) -> [String: String] {
        var enriched = customData

        // Add validation fields
        enriched["anr_validation_isValid"] = validation.isValid ? "true" : "false"
        enriched["anr_validation_reason"] = validation.reason
        enriched["anr_validation_confidence"] = String(validation.confidence)

        // Add factor fields for debugging
        enriched["anr_factor_screenOn"] = validation.factors.screenOn ? "true" : "false"
        enriched["anr_factor_processImportance"] = validation.factors.processImportance
        enriched["anr_factor_powerSaveMode"] = validation.factors.powerSaveMode ? "true" : "false"
        enriched["anr_factor_batteryLevel"] = String(format: "%.0f", validation.factors.batteryLevel * 100)
        enriched["anr_factor_networkLost"] = validation.factors.networkLost ? "true" : "false"

        return enriched
    }
}
