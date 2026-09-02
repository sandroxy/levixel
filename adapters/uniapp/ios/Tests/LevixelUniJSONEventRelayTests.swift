import Foundation

private final class LifetimeToken {}

private final class WeakBox<Value: AnyObject> {
    weak var value: Value?

    init(_ value: Value?) {
        self.value = value
    }
}

@main
private enum LevixelUniJSONEventRelayTests {
    static func main() {
        replacementReleasesAndStopsThePreviousHandler()
        sessionEventsDoNotAccumulateHandlers()
        replacementPreservesEventJSON()
    }

    private static func replacementReleasesAndStopsThePreviousHandler() {
        let relay = LevixelUniJSONEventRelay()
        var firstEvents: [String] = []
        var secondEvents: [String] = []
        var token: LifetimeToken? = LifetimeToken()
        let weakToken = WeakBox(token)

        relay.replaceHandler { [capturedToken = token!] eventJSON in
            _ = capturedToken
            firstEvents.append(eventJSON)
        }
        token = nil

        relay.replaceHandler { eventJSON in
            secondEvents.append(eventJSON)
        }

        precondition(weakToken.value == nil, "Replacing the handler must release the previous callback")
        relay.emit("{\"type\":\"dismiss\"}")
        precondition(firstEvents.isEmpty)
        precondition(secondEvents == ["{\"type\":\"dismiss\"}"])
    }

    private static func sessionEventsDoNotAccumulateHandlers() {
        let relay = LevixelUniJSONEventRelay()
        var firstSessionDeliveries: [String] = []
        var secondSessionDeliveries: [String] = []
        let firstSessionEvents = [
            "{\"type\":\"ready\",\"payload\":{},\"time\":1}",
            "{\"type\":\"dismiss\",\"payload\":{},\"time\":2}",
        ]
        let secondSessionEvents = [
            "{\"type\":\"ready\",\"payload\":{},\"time\":3}",
            "{\"type\":\"indexChange\",\"payload\":{\"currentIndex\":1,\"itemId\":\"video-1\"},\"time\":4}",
            "{\"type\":\"dismiss\",\"payload\":{},\"time\":5}",
        ]

        relay.replaceHandler { firstSessionDeliveries.append($0) }
        firstSessionEvents.forEach(relay.emit)
        relay.replaceHandler { secondSessionDeliveries.append($0) }
        secondSessionEvents.forEach(relay.emit)

        precondition(firstSessionDeliveries == firstSessionEvents)
        precondition(secondSessionDeliveries == secondSessionEvents)
    }

    private static func replacementPreservesEventJSON() {
        let relay = LevixelUniJSONEventRelay()
        var received = ""
        relay.replaceHandler { received = $0 }
        let eventJSON = "{\"type\":\"sourceVisibilityChange\",\"payload\":{\"hidden\":false,\"index\":0,\"itemId\":\"image-1\",\"galleryId\":\"gallery\"},\"time\":5}"

        relay.emit(eventJSON)

        precondition(received == eventJSON, "The relay must not decode or rewrite event JSON")
    }
}
