import Alamofire
import Foundation
import Swinject

final class NetworkAssembly: Assembly {
    func assemble(container: Container) {
        container.register(ReachabilityManager.self) { _ in
            NetworkReachabilityManager()!
        }.inObjectScope(.transient)

        container.register(NightscoutManager.self) { r in BaseNightscoutManager(resolver: r) }
    }
}
