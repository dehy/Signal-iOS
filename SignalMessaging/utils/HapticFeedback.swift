//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@available(iOSApplicationExtension 10.0, *)
public class SelectionHapticFeedback {
    let selectionFeedbackGenerator: UISelectionFeedbackGenerator

    public init() {
        AssertIsOnMainThread()

        selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        selectionFeedbackGenerator.prepare()
    }

    public func selectionChanged() {
        DispatchQueue.main.async {
            self.selectionFeedbackGenerator.selectionChanged()
            self.selectionFeedbackGenerator.prepare()
        }
    }
}

@available(iOSApplicationExtension 10.0, *)
@objc
public class NotificationHapticFeedback: NSObject {
    let feedbackGenerator = UINotificationFeedbackGenerator()

    public override init() {
        AssertIsOnMainThread()

        feedbackGenerator.prepare()
    }

    @objc
    public func notificationOccurred(_ notificationType: UINotificationFeedbackGenerator.FeedbackType) {
        DispatchQueue.main.async {
            self.feedbackGenerator.notificationOccurred(notificationType)
            self.feedbackGenerator.prepare()
        }
    }
}

@available(iOSApplicationExtension 10.0, *)
@objc
public class ImpactHapticFeedback: NSObject {
    @objc
    public class func impactOccured(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }
}
