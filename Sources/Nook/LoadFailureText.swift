import Foundation
import NookSheet
import SwiftUI

/// Human-readable text for a failed load.
///
/// The system error deliberately does not travel here in full: the `NSError`
/// from `URLSession` prints the whole request address, sheet identifier and
/// all, and such text leaks into every screenshot. What is shown is the kind
/// of failure and what to do about it, without the address.
extension SheetLoadError {
    var message: Text {
        switch self {
        case .offline:
            return Text("No network — can’t reach the sheet")
        case .timedOut:
            return Text("The sheet didn’t answer in time")
        case let .network(code):
            return Text("Network error \(String(code))")
        case let .http(space, status):
            switch status {
            case 401, 403:
                return Text("The sheet is closed to reading — open access by link")
            case 404:
                return Text("Tab \(space) is not in the sheet — check the link in settings")
            default:
                return Text("The sheet answered with \(String(status))")
            }
        case let .notText(space):
            return Text("Tab \(space) came back not as a sheet — check the link in settings")
        case let .parse(space, reason):
            return Text("Tab \(space) is laid out unexpectedly: \(reason)")
        case let .datesDisagree(space):
            return Text("Tab \(space) has a different set of dates than the others")
        }
    }
}
