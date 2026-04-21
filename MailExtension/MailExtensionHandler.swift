import MailKit

class MailExtensionHandler: NSObject, MEExtension {
    func handlerForContentBlocker() -> any MEContentBlocker {
        return ContentBlockerHandler()
    }

    func handlerForMessageSecurity() -> any MEMessageSecurityHandler {
        return MessageSecurityHandler()
    }
}
