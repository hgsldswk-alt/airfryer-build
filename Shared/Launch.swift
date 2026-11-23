import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments
    static let isTesting = arguments.contains("-ui-testing")
    static let proID = "com.hgsldswk.airfryercheatsheet.pro"
    static let trialID = "com.hgsldswk.airfryercheatsheet.trial"

    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) })
    }

    static var isFree: Bool { isFree(arguments: arguments) }
}
