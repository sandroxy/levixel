import Foundation

final class LevixelUniJSONEventRelay {
    typealias Handler = (String) -> Void

    private var handler: Handler?

    func replaceHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    func emit(_ eventJSON: String) {
        handler?(eventJSON)
    }
}
