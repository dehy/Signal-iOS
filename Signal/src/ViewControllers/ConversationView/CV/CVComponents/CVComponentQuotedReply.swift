//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentQuotedReply: CVComponentBase, CVComponent {

    private let quotedReply: CVComponentState.QuotedReply
    private var quotedReplyModel: OWSQuotedReplyModel {
        quotedReply.quotedReplyModel
    }
    private var displayableQuotedText: DisplayableText? {
        quotedReply.displayableQuotedText
    }
    private let sharpCornersForQuotedMessage: OWSDirectionalRectCorner

    init(itemModel: CVItemModel,
         quotedReply: CVComponentState.QuotedReply,
         sharpCornersForQuotedMessage: OWSDirectionalRectCorner) {
        self.quotedReply = quotedReply
        self.sharpCornersForQuotedMessage = sharpCornersForQuotedMessage

        super.init(itemModel: itemModel)
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewQuotedReply()
    }

    public func configureForRendering(componentView componentViewParam: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentViewParam as? CVComponentViewQuotedReply else {
            owsFailDebug("Unexpected componentView.")
            componentViewParam.reset()
            return
        }

        let quotedMessageView = componentView.quotedMessageView
        let adapter = QuotedMessageViewAdapter(interactionUniqueId: interaction.uniqueId)
        quotedMessageView.configureForRendering(state: quotedReply.viewState,
                                                delegate: adapter,
                                                sharpCorners: sharpCornersForQuotedMessage,
                                                cellMeasurement: cellMeasurement)
    }

    private var stackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: 0,
                          layoutMargins: .zero)
    }

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        let size = QuotedMessageView.measure(state: quotedReply.viewState,
                                             maxWidth: maxWidth,
                                             measurementBuilder: measurementBuilder)
        return size
    }

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        componentDelegate.cvc_didTapQuotedReply(quotedReplyModel)
        return true
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewQuotedReply: NSObject, CVComponentView {

        fileprivate let quotedMessageView = QuotedMessageView(name: "quotedMessageView")

        public var isDedicatedCellView = false

        public var rootView: UIView {
            quotedMessageView
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            quotedMessageView.reset()
        }
    }
}

// MARK: -

private class QuotedMessageViewAdapter: QuotedMessageViewDelegate, Dependencies {

    private let interactionUniqueId: String

    init(interactionUniqueId: String) {
        self.interactionUniqueId = interactionUniqueId
    }

    func didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel,
                           failedThumbnailDownloadAttachmentPointer attachmentPointer: TSAttachmentPointer) {
        Self.attachmentDownloads.enqueueDownloadOfAttachments(forMessageId: interactionUniqueId,
                                                              attachmentGroup: .allAttachmentsOfAnyKind,
                                                              downloadBehavior: .default,
                                                              touchMessageImmediately: true,
                                                              success: { _ in
                                                                Logger.info("Success.")
                                                              },
                                                              failure: { error in
                                                                owsFailDebugUnlessNetworkFailure(error)
                                                              })
    }

    func didCancelQuotedReply() {
        owsFailDebug("Unexpected method invocation.")
    }
}
