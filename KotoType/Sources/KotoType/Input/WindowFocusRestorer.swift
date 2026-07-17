import AppKit
@preconcurrency import ApplicationServices

@MainActor
struct WindowFocusIdentity: Equatable {
    let identifier: String?
    let title: String?
    let role: String?
    let subrole: String?
    let document: String?
    let position: CGPoint?
    let size: CGSize?

    func matches(_ other: WindowFocusIdentity) -> Bool {
        if let identifier, !identifier.isEmpty,
           let otherIdentifier = other.identifier, !otherIdentifier.isEmpty {
            return identifier == otherIdentifier
        }

        guard role == other.role, subrole == other.subrole else {
            return false
        }

        if let document, !document.isEmpty,
           let otherDocument = other.document, !otherDocument.isEmpty {
            return document == otherDocument && title == other.title
        }

        guard let title, title == other.title,
              let position, position == other.position,
              let size, size == other.size else {
            return false
        }
        return true
    }
}

@MainActor
struct WindowFocusTarget {
    let processIdentifier: pid_t
    let window: AXUIElement
    let identity: WindowFocusIdentity

    func matches(_ other: WindowFocusTarget) -> Bool {
        processIdentifier == other.processIdentifier && identity.matches(other.identity)
    }
}

@MainActor
enum WindowFocusRestorer {
    enum Result: Equatable {
        case unchanged
        case restored
        case unavailable

        var logDescription: String {
            switch self {
            case .unchanged:
                return "unchanged"
            case .restored:
                return "restored"
            case .unavailable:
                return "unavailable"
            }
        }
    }

    struct Runtime {
        var currentTarget: () -> WindowFocusTarget?
        var activateApplication: (pid_t) -> Bool
        var raiseWindow: (AXUIElement) -> AXError
    }

    static func capture() -> WindowFocusTarget? {
        let systemWideElement = AXUIElementCreateSystemWide()
        guard let focusedApplication = copyAXElement(
            from: copyAttributeValue(
                from: systemWideElement,
                attribute: kAXFocusedApplicationAttribute
            )
        ),
              let focusedWindow = copyAXElement(
                  from: copyAttributeValue(
                      from: focusedApplication,
                      attribute: kAXFocusedWindowAttribute
                  )
              ) else {
            return nil
        }

        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(focusedApplication, &processIdentifier) == .success,
              let identity = identity(of: focusedWindow),
              identity.role == "AXWindow" else {
            return nil
        }

        return WindowFocusTarget(
            processIdentifier: processIdentifier,
            window: focusedWindow,
            identity: identity
        )
    }

    static func restoreIfNeeded(
        _ target: WindowFocusTarget,
        runtime: Runtime? = nil
    ) -> Result {
        let runtime = runtime ?? liveRuntime()
        let currentTarget = runtime.currentTarget()
        if let currentTarget, target.matches(currentTarget) {
            return .unchanged
        }

        if currentTarget?.processIdentifier != target.processIdentifier {
            guard runtime.activateApplication(target.processIdentifier) else {
                return .unavailable
            }
        }
        guard runtime.raiseWindow(target.window) == .success else {
            return .unavailable
        }
        return .restored
    }

    private static func liveRuntime() -> Runtime {
        Runtime(
            currentTarget: capture,
            activateApplication: { processIdentifier in
                guard let application = NSRunningApplication(processIdentifier: processIdentifier) else {
                    return false
                }
                return application.activate(options: [])
            },
            raiseWindow: { window in
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            }
        )
    }

    private static func copyAttributeValue(
        from element: AXUIElement,
        attribute: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private static func copyAXElement(from value: CFTypeRef?) -> AXUIElement? {
        guard let value else {
            return nil
        }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func identity(of window: AXUIElement) -> WindowFocusIdentity? {
        WindowFocusIdentity(
            identifier: stringAttribute(of: window, attribute: kAXIdentifierAttribute),
            title: stringAttribute(of: window, attribute: kAXTitleAttribute),
            role: stringAttribute(of: window, attribute: kAXRoleAttribute),
            subrole: stringAttribute(of: window, attribute: kAXSubroleAttribute),
            document: stringAttribute(of: window, attribute: kAXDocumentAttribute),
            position: cgPointAttribute(of: window, attribute: kAXPositionAttribute),
            size: cgSizeAttribute(of: window, attribute: kAXSizeAttribute)
        )
    }

    private static func stringAttribute(
        of element: AXUIElement,
        attribute: String
    ) -> String? {
        guard let value = copyAttributeValue(from: element, attribute: attribute) else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return nil
    }

    private static func cgPointAttribute(
        of element: AXUIElement,
        attribute: String
    ) -> CGPoint? {
        guard let value = copyAttributeValue(from: element, attribute: attribute) else {
            return nil
        }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private static func cgSizeAttribute(
        of element: AXUIElement,
        attribute: String
    ) -> CGSize? {
        guard let value = copyAttributeValue(from: element, attribute: attribute) else {
            return nil
        }
        let axValue = value as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }
        return size
    }
}
