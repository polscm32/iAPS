import Combine
import LocalAuthentication

protocol UnlockManager {
    func unlock(_ completion: @escaping (_ success: Bool) -> Void)
}

struct UnlockError: Error {
    let error: Error?
}

final class BaseUnlockManager: UnlockManager {
    func unlock(_ completion: @escaping (_ success: Bool) -> Void) {
        let context = LAContext()
        let reason = "We need to make sure you are the owner of the device."

        // Previous implementation had a check for if we can evaluate the policy,
        // we should probably keep that around
//        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
//        }

        context
            .evaluatePolicy(
                LAPolicy.deviceOwnerAuthentication,
                localizedReason: reason
            ) { success, _ in
                DispatchQueue.main.async {
                    if success {
                        completion(true)
                    } else {
                        completion(false)
                        print("Failed auth")
                        return
                    }
                }
            }
    }
}
