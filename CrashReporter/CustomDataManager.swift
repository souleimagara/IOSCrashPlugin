import Foundation

class CustomDataManager {
    static let shared = CustomDataManager()
    
    private var customData: [String: String] = [:]
    private var environment: String = "production"
    private let queue = DispatchQueue(label: "com.crashreporter.customdata", attributes: .concurrent)
    
    private init() {}
    
    func setUserContext(userId: String?, email: String? = nil, username: String? = nil) {
        queue.async(flags: .barrier) {
            if let userId = userId {
                self.customData["userId"] = userId
            }
            if let email = email {
                self.customData["email"] = email
            }
            if let username = username {
                self.customData["username"] = username
            }
        }
    }
    
    func setTag(key: String, value: String) {
        queue.async(flags: .barrier) {
            self.customData[key] = value
        }
    }
    
    func removeTag(key: String) {
        queue.async(flags: .barrier) {
            self.customData.removeValue(forKey: key)
        }
    }
    
    func setEnvironment(env: String) {
        queue.async(flags: .barrier) {
            self.environment = env
        }
    }
    
    func getEnvironment() -> String {
        return queue.sync {
            return environment
        }
    }
    
    func getCustomData() -> [String: String] {
        return queue.sync {
            return customData
        }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.customData.removeAll()
        }
    }
}
