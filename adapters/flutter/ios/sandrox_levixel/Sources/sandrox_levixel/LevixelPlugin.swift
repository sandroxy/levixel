import Flutter
import ImageIO
import Levixel
import UIKit

public final class LevixelPlugin: NSObject, FlutterPlugin {
    private weak var registrar: FlutterPluginRegistrar?
    private let channel: FlutterMethodChannel
    private let engineScope = UUID().uuidString
    private var session: ViewerSession?

    private init(registrar: FlutterPluginRegistrar, channel: FlutterMethodChannel) {
        self.registrar = registrar
        self.channel = channel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "com.sandrox.levixel/flutter", binaryMessenger: registrar.messenger())
        let plugin = LevixelPlugin(registrar: registrar, channel: channel)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.publish(plugin)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        session?.viewer?.close(animated: false)
        session?.removeSources()
        session = nil
        channel.setMethodCallHandler(nil)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let args = try object(call.arguments)
            let request = try text(args, "requestId")
            if call.method == "prepare" {
                guard session == nil else { throw BridgeError("Close the previous viewer before preparing another") }
                guard let presenter = registrar?.viewController, presenter.viewIfLoaded?.window != nil else {
                    throw BridgeError("The attached Flutter view is unavailable")
                }
                let next = try ViewerSession(args, scope: engineScope, presenter: presenter, channel: channel)
                do { try next.updateSources(array(args, "sources")) }
                catch { next.removeSources(); throw error }
                session = next
                if let sourceId = next.sourceId { next.sources[sourceId]?.showPreview(true) }
                result(nil)
                return
            }
            guard let current = session, current.id == request else {
                if call.method == "open" { result(FlutterError(code: "OPEN_CANCELLED", message: "This request is no longer active", details: nil)) }
                else { result(call.method == "retry" ? false : nil) }
                return
            }
            switch call.method {
            case "open": try current.open(); result(nil)
            case "updateSources":
                if !current.closing { try current.updateSources(array(args, "sources")) }
                result(nil)
            case "retry": result(current.viewer?.retry() ?? false)
            case "close":
                current.closing = true
                if let viewer = current.viewer { viewer.close { result(nil) } }
                else { result(nil) }
            case "finish":
                guard current.viewer == nil else { throw BridgeError("Dismiss the viewer before finishing") }
                current.removeSources(); session = nil; result(nil)
            default: result(FlutterMethodNotImplemented)
            }
        } catch {
            result(FlutterError(code: "INVALID_ARGUMENT", message: String(describing: error), details: nil))
        }
    }
}

private final class ViewerSession {
    let id: String
    let gallery: String
    let scopedGallery: String
    let sourceId: String?
    let index: Int
    let media: [LevixelMediaItem]
    let itemIds: [String]
    let channel: FlutterMethodChannel
    weak var presenter: UIViewController?
    var configuration: LevixelViewerConfiguration
    var viewer: LevixelViewerSession?
    var sources: [String: SourceAnchor] = [:]
    var closing = false

    init(_ args: [String: Any], scope: String, presenter: UIViewController, channel: FlutterMethodChannel) throws {
        id = try text(args, "requestId")
        gallery = try text(args, "galleryId")
        scopedGallery = "\(scope):\(id)"
        sourceId = try optionalText(args, "sourceId")
        self.presenter = presenter
        self.channel = channel
        var media: [LevixelMediaItem] = []
        var identifiers: [String] = []
        var seen = Set<String>()
        for value in try array(args, "items") {
            let item = try object(value)
            let identifier = try text(item, "id")
            guard seen.insert(identifier).inserted else { throw BridgeError("Media IDs must be unique") }
            let source = try location(text(item, "url"))
            let thumbnail = try optionalText(item, "thumbnailUrl").map(location)
            switch try text(item, "type") {
            case "image": media.append(.imageURL(source, thumbnailURL: thumbnail, placeholder: nil))
            case "video": media.append(.video(url: source, poster: try optionalText(item, "posterUrl").map(location) ?? thumbnail))
            default: throw BridgeError("Unknown media type")
            }
            identifiers.append(identifier)
        }
        let position = try number(args["index"])
        guard position.rounded(.towardZero) == position, position >= 0, position < CGFloat(media.count) else { throw BridgeError("Invalid media index") }
        index = Int(position)
        self.media = media; itemIds = identifiers
        let theme = try text(args, "theme")
        guard theme == "light" || theme == "dark" else { throw BridgeError("Invalid theme") }
        guard let layout = LevixelActionLayout(rawValue: try text(args, "actionLayout")) else { throw BridgeError("Invalid action layout") }
        var actions: [LevixelAction] = []
        seen.removeAll()
        for value in try array(args, "actions") {
            let action = try object(value)
            let identifier = try text(action, "id")
            guard seen.insert(identifier).inserted else { throw BridgeError("Action IDs must be unique") }
            let icon = try optionalText(action, "icon").map(location)
            guard layout != .grid || icon != nil else { throw BridgeError("Grid actions require icons") }
            actions.append(LevixelAction(id: identifier, label: try text(action, "label"), icon: icon,
                group: try optionalText(action, "group"), disabled: try boolean(action, "disabled"), destructive: try boolean(action, "destructive")))
        }
        configuration = LevixelViewerConfiguration(theme: theme == "light" ? .light : .dark,
            actions: actions, actionLayout: layout, actionListIcons: try boolean(args, "actionListIcons"))
        configuration.onEvent = { [weak self] event in
            guard let self else { return }
            var value = event.dictionary
            var payload = value["payload"] as? [String: Any] ?? [:]
            payload["galleryId"] = self.gallery
            value["payload"] = payload; value["requestId"] = self.id
            if event.type == "dismiss" { self.viewer = nil; self.closing = true }
            self.channel.invokeMethod("event", arguments: value)
        }
    }

    func open() throws {
        guard !closing, viewer == nil, let presenter, presenter.viewIfLoaded?.window != nil else { throw BridgeError("The viewer cannot be opened") }
        viewer = LevixelViewerSession.present(dataSource: LevixelArrayDataSource(items: media, itemIdentifiers: itemIds),
            initialIndex: index, configuration: configuration, from: presenter, galleryId: scopedGallery, sourceIdentifier: sourceId)
        guard viewer != nil else { throw BridgeError("No presenter is available") }
    }

    func updateSources(_ values: [Any]) throws {
        guard let host = presenter?.view, host.window != nil else { removeSources(); return }
        var retained = Set<String>()
        for value in values {
            let args = try object(value)
            let sourceId = try text(args, "sourceId"), itemId = try text(args, "itemId")
            guard itemIds.contains(itemId), retained.insert(sourceId).inserted else { throw BridgeError("Invalid source identity") }
            if let old = sources[sourceId], old.itemId != itemId { old.remove(); sources[sourceId] = nil }
            let source = sources[sourceId] ?? SourceAnchor(session: self, sourceId: sourceId, itemId: itemId)
            if source.superview == nil { host.addSubview(source) }
            sources[sourceId] = source
            try source.update(args, host: host)
        }
        for id in Array(sources.keys) where !retained.contains(id) { sources.removeValue(forKey: id)?.remove() }
    }

    func removeSources() { for source in sources.values { source.remove() }; sources.removeAll() }
}

private final class SourceAnchor: UIView {
    weak var session: ViewerSession?
    let sourceId: String
    let itemId: String
    let image = UIImageView()
    private var registration: LevixelSourceRegistration?
    private var visibilitySequence = 0
    private var displayLink: CADisplayLink?
    private var remainingFrames = 0

    init(session: ViewerSession, sourceId: String, itemId: String) {
        self.session = session; self.sourceId = sourceId; self.itemId = itemId
        super.init(frame: .zero)
        clipsToBounds = true; isUserInteractionEnabled = false; accessibilityElementsHidden = true
        image.alpha = 0
        addSubview(image)
        registration = LevixelSourceRegistration(view: self, sourceIdentifier: sourceId, imageViewProvider: { ($0 as? SourceAnchor)?.image })
    }

    required init?(coder: NSCoder) { nil }

    func update(_ args: [String: Any], host: UIView) throws {
        guard let session, let screen = host.window?.screen else { return }
        let scale = try number(args["pixelRatio"]) / screen.scale
        guard scale > 0 else { throw BridgeError("Invalid pixel ratio") }
        let sourceFrame = try rect(args["frame"], scale: scale), clip = try rect(args["clip"], scale: scale)
        let radius = try number(args["cornerRadius"]) * scale
        guard radius >= 0 else { throw BridgeError("Invalid corner radius") }
        frame = clip
        layer.cornerRadius = clip == sourceFrame ? radius : 0
        image.frame = sourceFrame.offsetBy(dx: -clip.minX, dy: -clip.minY)
        switch try text(args, "fit") {
        case "cover": image.contentMode = .scaleAspectFill
        case "contain": image.contentMode = .scaleAspectFit
        case "fill": image.contentMode = .scaleToFill
        default: throw BridgeError("Invalid source fit")
        }
        if let data = args["png"], !(data is NSNull) {
            guard let bytes = data as? FlutterStandardTypedData,
                  let source = CGImageSourceCreateWithData(bytes.data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= 1024, height <= 1024,
                  let bitmap = UIImage(data: bytes.data) else { throw BridgeError("Invalid source image") }
            image.image = bitmap
        }
        registration?.register(galleryId: session.scopedGallery, itemIdentifier: itemId, cornerRadius: radius)
    }

    func showPreview(_ show: Bool) { image.alpha = show ? 1 : 0 }

    override var alpha: CGFloat {
        didSet {
            guard alpha != oldValue, let session else { return }
            displayLink?.invalidate(); displayLink = nil
            let hidden = alpha == 0
            showPreview(!hidden)
            visibilitySequence += 1
            let sequence = visibilitySequence
            session.channel.invokeMethod("visibility", arguments: ["requestId": session.id, "sourceId": sourceId, "hidden": hidden]) { [weak self] _ in
                guard let self, self.visibilitySequence == sequence, !hidden, self.superview != nil else { return }
                self.remainingFrames = 2
                let link = CADisplayLink(target: self, selector: #selector(self.finishHandoff))
                self.displayLink = link; link.add(to: .main, forMode: .common)
            }
        }
    }

    @objc private func finishHandoff() {
        remainingFrames -= 1
        guard remainingFrames <= 0 else { return }
        displayLink?.invalidate(); displayLink = nil; showPreview(false)
    }

    func remove() {
        registration?.unregister()
        displayLink?.invalidate(); displayLink = nil
        removeFromSuperview(); image.image = nil
    }
}

private struct BridgeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private func object(_ value: Any?) throws -> [String: Any] {
    guard let value = value as? [String: Any] else { throw BridgeError("Expected an object") }; return value
}
private func array(_ value: [String: Any], _ key: String) throws -> [Any] {
    guard let result = value[key] as? [Any] else { throw BridgeError("Expected \(key)") }; return result
}
private func text(_ value: [String: Any], _ key: String) throws -> String {
    guard let result = value[key] as? String, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BridgeError("Invalid \(key)") }; return result
}
private func optionalText(_ value: [String: Any], _ key: String) throws -> String? {
    if value[key] == nil || value[key] is NSNull { return nil }; return try text(value, key)
}
private func boolean(_ value: [String: Any], _ key: String) throws -> Bool {
    guard let result = value[key] as? NSNumber, CFGetTypeID(result) == CFBooleanGetTypeID() else { throw BridgeError("Invalid \(key)") }; return result.boolValue
}
private func number(_ value: Any?) throws -> CGFloat {
    guard let result = value as? NSNumber, CFGetTypeID(result) != CFBooleanGetTypeID(), result.doubleValue.isFinite else { throw BridgeError("Expected a finite number") }; return CGFloat(result.doubleValue)
}
private func rect(_ value: Any?, scale: CGFloat) throws -> CGRect {
    guard let value = value as? [Any], value.count == 4 else { throw BridgeError("Invalid source rectangle") }
    let values = try value.map { try number($0) * scale }
    guard values[2] > 0, values[3] > 0 else { throw BridgeError("Empty source rectangle") }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}
private func location(_ value: String) throws -> URL {
    if let url = URL(string: value), url.scheme != nil { return url }
    guard !value.isEmpty else { throw BridgeError("Empty media location") }; return URL(fileURLWithPath: value)
}
