//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import QuickLook
import SignalServiceKit
import SignalMessaging

protocol MessageDetailViewDelegate: AnyObject {
    func detailViewMessageWasDeleted(_ messageDetailViewController: MessageDetailViewController)
}

class MessageDetailViewController: OWSTableViewController2 {

    private enum DetailViewError: Error {
        case messageWasDeleted
    }

    weak var detailDelegate: MessageDetailViewDelegate?

    // MARK: Properties

    weak var pushPercentDrivenTransition: UIPercentDrivenInteractiveTransition?
    private var popPercentDrivenTransition: UIPercentDrivenInteractiveTransition?

    private var renderItem: CVRenderItem?
    private var thread: TSThread? { renderItem?.itemModel.thread }

    private(set) var message: TSMessage
    private var wasDeleted: Bool = false
    private var isIncoming: Bool { message as? TSIncomingMessage != nil }

    private struct MessageRecipientModel {
        let address: SignalServiceAddress
        let accessoryText: String
        let displayUDIndicator: Bool
    }
    private let messageRecipients = AtomicOptional<[MessageReceiptStatus: [MessageRecipientModel]]>(nil)

    private let cellView = CVCellView()

    private var attachments: [TSAttachment]?
    private var attachmentStreams: [TSAttachmentStream]? {
        return attachments?.compactMap { $0 as? TSAttachmentStream }
    }
    var hasMediaAttachment: Bool {
        guard let attachmentStreams = self.attachmentStreams, !attachmentStreams.isEmpty else {
            return false
        }
        return true
    }

    private let byteCountFormatter: ByteCountFormatter = ByteCountFormatter()

    private lazy var shouldShowUD: Bool = {
        return self.preferences.shouldShowUnidentifiedDeliveryIndicators()
    }()

    private lazy var contactShareViewHelper: ContactShareViewHelper = {
        let contactShareViewHelper = ContactShareViewHelper()
        contactShareViewHelper.delegate = self
        return contactShareViewHelper
    }()

    private var databaseUpdateTimer: Timer?

    // MARK: Initializers

    required init(
        message: TSMessage,
        thread: TSThread
    ) {
        self.message = message
        super.init()
    }

    // MARK: View Lifecycle

    override func themeDidChange() {
        super.themeDidChange()

        refreshContent()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "MESSAGE_METADATA_VIEW_TITLE",
            comment: "Title for the 'message metadata' view."
        )

        databaseStorage.appendUIDatabaseSnapshotDelegate(self)

        // Use our own swipe back animation, since the message
        // details are presented as a "drawer" type view.
        let panGesture = DirectionalPanGestureRecognizer(direction: .horizontal, target: self, action: #selector(handlePan))

        // Allow panning with trackpad
        if #available(iOS 13.4, *) { panGesture.allowedScrollTypesMask = .continuous }

        view.addGestureRecognizer(panGesture)

        if let interactivePopGestureRecognizer = navigationController?.interactivePopGestureRecognizer {
            interactivePopGestureRecognizer.require(toFail: panGesture)
        }

        refreshContent()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.refreshContent()
        }
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        contents.addSection(buildMessageSection())

        if isIncoming {
            contents.addSection(buildSenderSection())
        } else {
            buildStatusSections().forEach { contents.addSection($0) }
        }

        self.contents = contents
    }

    public func buildRenderItem(interactionId: String) -> CVRenderItem? {
        databaseStorage.uiRead { transaction in
            guard let interaction = TSInteraction.anyFetch(
                uniqueId: interactionId,
                transaction: transaction
            ) else {
                owsFailDebug("Missing interaction.")
                return nil
            }
            guard let thread = TSThread.anyFetch(
                uniqueId: interaction.uniqueThreadId,
                transaction: transaction
            ) else {
                owsFailDebug("Missing thread.")
                return nil
            }

            let conversationStyle = ConversationStyle(
                type: .messageDetails,
                thread: thread,
                viewWidth: view.width - (cellOuterInsets.totalWidth + (Self.cellHInnerMargin * 2)),
                hasWallpaper: false
            )

            return CVLoader.buildStandaloneRenderItem(
                interaction: interaction,
                thread: thread,
                conversationStyle: conversationStyle,
                transaction: transaction
            )
        }
    }

    private func buildMessageSection() -> OWSTableSection {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return OWSTableSection()
        }

        let messageStack = UIStackView()
        messageStack.axis = .vertical

        cellView.reset()

        cellView.configure(renderItem: renderItem, componentDelegate: self)
        cellView.isCellVisible = true
        cellView.autoSetDimension(.height, toSize: renderItem.cellSize.height)

        let cellContainer = UIView()
        cellContainer.layoutMargins = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        cellContainer.addSubview(cellView)
        cellView.autoPinHeightToSuperviewMargins()

        cellView.autoPinEdge(toSuperviewEdge: .leading)
        cellView.autoPinEdge(toSuperviewEdge: .trailing)

        messageStack.addArrangedSubview(cellContainer)

        // Sent time

        let sentTimeLabel = buildValueLabel(
            name: NSLocalizedString("MESSAGE_METADATA_VIEW_SENT_DATE_TIME",
                                    comment: "Label for the 'sent date & time' field of the 'message metadata' view."),
            value: DateUtil.formatPastTimestampRelativeToNow(message.timestamp)
        )
        messageStack.addArrangedSubview(sentTimeLabel)
        sentTimeLabel.isUserInteractionEnabled = true
        sentTimeLabel.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(didLongPressSent)))

        if isIncoming {
            // Received time
            messageStack.addArrangedSubview(buildValueLabel(
                name: NSLocalizedString("MESSAGE_METADATA_VIEW_RECEIVED_DATE_TIME",
                                        comment: "Label for the 'received date & time' field of the 'message metadata' view."),
                value: DateUtil.formatPastTimestampRelativeToNow(message.receivedAtTimestamp)
            ))
        }

        if hasMediaAttachment, attachments?.count == 1, let attachment = attachments?.first {
            if let sourceFilename = attachment.sourceFilename {
                messageStack.addArrangedSubview(buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_SOURCE_FILENAME",
                                            comment: "Label for the original filename of any attachment in the 'message metadata' view."),
                    value: sourceFilename
                ))
            }

            if let formattedByteCount = byteCountFormatter.string(for: attachment.byteCount) {
                messageStack.addArrangedSubview(buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_FILE_SIZE",
                                            comment: "Label for file size of attachments in the 'message metadata' view."),
                    value: formattedByteCount
                ))
            } else {
                owsFailDebug("formattedByteCount was unexpectedly nil")
            }

            if DebugFlags.messageDetailsExtraInfo {
                let contentType = attachment.contentType
                messageStack.addArrangedSubview(buildValueLabel(
                    name: NSLocalizedString("MESSAGE_METADATA_VIEW_ATTACHMENT_MIME_TYPE",
                                            comment: "Label for the MIME type of attachments in the 'message metadata' view."),
                    value: contentType
                ))
            }
        }

        let section = OWSTableSection()
        section.add(.init(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.selectionStyle = .none
                cell.contentView.addSubview(messageStack)
                messageStack.autoPinWidthToSuperviewMargins()
                messageStack.autoPinHeightToSuperview(withMargin: 20)
                return cell
            }, actionBlock: {

            }
        ))

        return section
    }

    private func buildSenderSection() -> OWSTableSection {
        guard let incomingMessage = message as? TSIncomingMessage else {
            owsFailDebug("Unexpected message type")
            return OWSTableSection()
        }

        let section = OWSTableSection()
        section.headerTitle = NSLocalizedString(
            "MESSAGE_DETAILS_VIEW_SENT_FROM_TITLE",
            comment: "Title for the 'sent from' section on the 'message details' view."
        )
        section.add(contactItem(
            for: incomingMessage.authorAddress,
            accessoryText: DateUtil.formatPastTimestampRelativeToNow(incomingMessage.timestamp),
            displayUDIndicator: incomingMessage.wasReceivedByUD
        ))
        return section
    }

    private func buildStatusSections() -> [OWSTableSection] {
        guard let outgoingMessage = message as? TSOutgoingMessage else {
            owsFailDebug("Unexpected message type")
            return []
        }

        var sections = [OWSTableSection]()

        let orderedStatusGroups: [MessageReceiptStatus] = [
            .read,
            .delivered,
            .sent,
            .uploading,
            .sending,
            .failed,
            .skipped
        ]

        guard let messageRecipients = messageRecipients.get() else { return [] }

        for statusGroup in orderedStatusGroups {
            guard let recipients = messageRecipients[statusGroup], !recipients.isEmpty else { continue }

            let section = OWSTableSection()
            sections.append(section)

            let sectionTitle = self.sectionTitle(for: statusGroup)
            if let iconName = sectionIconName(for: statusGroup) {
                let headerView = UIView()
                headerView.layoutMargins = cellOuterInsetsWithMargin(
                    top: (defaultSpacingBetweenSections ?? 0) + 12,
                    left: Self.cellHInnerMargin * 0.5,
                    bottom: 10,
                    right: Self.cellHInnerMargin * 0.5
                )

                let label = UILabel()
                label.textColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
                label.font = UIFont.ows_dynamicTypeBodyClamped.ows_semibold
                label.text = sectionTitle

                headerView.addSubview(label)
                label.autoPinHeightToSuperviewMargins()
                label.autoPinEdge(toSuperviewMargin: .leading)

                let iconView = UIImageView()
                iconView.contentMode = .scaleAspectFit
                iconView.setTemplateImageName(
                    iconName,
                    tintColor: Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
                )
                headerView.addSubview(iconView)
                iconView.autoAlignAxis(.horizontal, toSameAxisOf: label)
                iconView.autoPinEdge(.leading, to: .trailing, of: label)
                iconView.autoPinEdge(toSuperviewMargin: .trailing)
                iconView.autoSetDimension(.height, toSize: 12)

                section.customHeaderView = headerView
            } else {
                section.headerTitle = sectionTitle
            }

            section.separatorInsetLeading = NSNumber(value: Float(Self.cellHInnerMargin + CGFloat(kSmallAvatarSize) + kContactCellAvatarTextMargin))

            for recipient in recipients {
                section.add(contactItem(
                    for: recipient.address,
                    accessoryText: recipient.accessoryText,
                    displayUDIndicator: recipient.displayUDIndicator
                ))
            }
        }

        return sections
    }

    private func contactItem(for address: SignalServiceAddress, accessoryText: String, displayUDIndicator: Bool) -> OWSTableItem {
        return .init(
            customCellBlock: { [weak self] in
                let cell = ContactTableViewCell()
                guard let self = self else { return cell }
                cell.configureWithSneakyTransaction(recipientAddress: address,
                                                    localUserAvatarMode: .asUser)
                cell.ows_setAccessoryView(self.buildAccessoryView(text: accessoryText, displayUDIndicator: displayUDIndicator))
                return cell
            },
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let actionSheet = MemberActionSheet(address: address, groupViewHelper: nil)
                actionSheet.present(from: self)
            }
        )
    }

    private func buildAccessoryView(text: String, displayUDIndicator: Bool) -> UIView {
        let label = UILabel()
        label.textColor = Theme.ternaryTextColor
        label.text = text
        label.textAlignment = .right
        label.font = .ows_dynamicTypeFootnoteClamped

        guard displayUDIndicator && shouldShowUD else { return label }

        let imageView = UIImageView()
        imageView.setTemplateImageName(Theme.iconName(.sealedSenderIndicator), tintColor: Theme.ternaryTextColor)

        let hStack = UIStackView(arrangedSubviews: [imageView, label])
        hStack.axis = .horizontal
        hStack.spacing = 8

        return hStack
    }

    private func buildValueLabel(name: String, value: String) -> UILabel {
        let label = UILabel()
        label.textColor = Theme.primaryTextColor
        label.font = .ows_dynamicTypeFootnoteClamped
        label.attributedText = .composed(of: [
            name.styled(with: .font(UIFont.ows_dynamicTypeFootnoteClamped.ows_semibold)),
            " ",
            value
        ])
        return label
    }

    // MARK: - Actions

    private func sectionIconName(for messageReceiptStatus: MessageReceiptStatus) -> String? {
        switch messageReceiptStatus {
        case .uploading, .sending:
            return "message_status_sending"
        case .sent:
            return "message_status_sent"
        case .delivered:
            return "message_status_delivered"
        case .read:
            return "message_status_read"
        case .failed, .skipped:
            return nil
        }
    }

    private func sectionTitle(for messageReceiptStatus: MessageReceiptStatus) -> String {
        switch messageReceiptStatus {
        case .uploading:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_UPLOADING",
                              comment: "Status label for messages which are uploading.")
        case .sending:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENDING",
                              comment: "Status label for messages which are sending.")
        case .sent:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SENT",
                              comment: "Status label for messages which are sent.")
        case .delivered:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_DELIVERED",
                              comment: "Status label for messages which are delivered.")
        case .read:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_READ",
                              comment: "Status label for messages which are read.")
        case .failed:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_FAILED",
                                     comment: "Status label for messages which are failed.")
        case .skipped:
            return NSLocalizedString("MESSAGE_METADATA_VIEW_MESSAGE_STATUS_SKIPPED",
                                     comment: "Status label for messages which were skipped.")
        }
    }

    private var isPanning = false

    @objc
    func handlePan(_ sender: UIPanGestureRecognizer) {
        var xOffset = sender.translation(in: view).x
        var xVelocity = sender.velocity(in: view).x

        if CurrentAppContext().isRTL {
            xOffset = -xOffset
            xVelocity = -xVelocity
        }

        if xOffset < 0 { xOffset = 0 }

        let percentage = xOffset / view.width

        switch sender.state {
        case .began:
            popPercentDrivenTransition = UIPercentDrivenInteractiveTransition()
            navigationController?.popViewController(animated: true)
        case .changed:
            popPercentDrivenTransition?.update(percentage)
        case .ended:
            let percentageThreshold: CGFloat = 0.5
            let velocityThreshold: CGFloat = 500

            let shouldFinish = (percentage >= percentageThreshold && xVelocity >= 0) || (xVelocity >= velocityThreshold)
            if shouldFinish {
                popPercentDrivenTransition?.finish()
            } else {
                popPercentDrivenTransition?.cancel()
            }
        case .cancelled, .failed:
            popPercentDrivenTransition?.cancel()
            popPercentDrivenTransition = nil
        case .possible:
            break
        @unknown default:
            break
        }
    }
}

// MARK: -

extension MessageDetailViewController {
    @objc
    func didLongPressSent(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let messageTimestamp = "\(message.timestamp)"
        UIPasteboard.general.string = messageTimestamp

        let toast = ToastController(text: NSLocalizedString(
            "MESSAGE_DETAIL_VIEW_DID_COPY_SENT_TIMESTAMP",
            comment: "Toast indicating that the user has copied the sent timestamp."
        ))
        toast.presentToastView(fromBottomOfView: view, inset: bottomLayoutGuide.length + 8)
    }
}

// MARK: -

extension MessageDetailViewController: MediaGalleryDelegate {

    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.info("")

        guard items.contains(where: { $0.message == self.message }) else {
            Logger.info("ignoring deletion of unrelated media")
            return
        }

        self.wasDeleted = true
    }

    func mediaGallery(_ mediaGallery: MediaGallery, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        guard self.wasDeleted else {
            return
        }
        self.dismiss(animated: true) {
            self.navigationController?.popViewController(animated: true)
        }
    }

    func mediaGallery(_ mediaGallery: MediaGallery, didReloadItemsInSections sections: IndexSet) {
        // No action needed
    }
}

// MARK: -

extension MessageDetailViewController: ContactShareViewHelperDelegate {
    public func didCreateOrEditContact() {
        updateTableContents()
        self.dismiss(animated: true)
    }
}

extension MessageDetailViewController: LongTextViewDelegate {
    public func longTextViewMessageWasDeleted(_ longTextViewController: LongTextViewController) {
        self.detailDelegate?.detailViewMessageWasDeleted(self)
    }
}

extension MessageDetailViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard case let .gallery(galleryItem) = item else {
            owsFailDebug("Unexpected media type")
            return nil
        }

        guard let mediaView = cellView.albumItemView(forAttachment: galleryItem.attachmentStream) else {
            owsFailDebug("itemView was unexpectedly nil")
            return nil
        }

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)

        // TODO better corner rounding.
        return MediaPresentationContext(mediaView: mediaView,
                                        presentationFrame: presentationFrame,
                                        cornerRadius: kOWSMessageCellCornerRadius_Small * 2)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }

    func mediaWillDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        for mediaOverlayView in mediaOverlayViews {
            mediaOverlayView.alpha = 0
        }
    }

    func mediaDidDismiss(toContext: MediaPresentationContext) {
        // To avoid flicker when transition view is animated over the message bubble,
        // we initially hide the overlaying elements and fade them in.
        let mediaOverlayViews = toContext.mediaOverlayViews
        let duration: TimeInterval = kIsDebuggingMediaPresentationAnimations ? 1.5 : 0.2
        UIView.animate(
            withDuration: duration,
            animations: {
                for mediaOverlayView in mediaOverlayViews {
                    mediaOverlayView.alpha = 1
                }
            })
    }
}

// MARK: -

extension MediaPresentationContext {
    var mediaOverlayViews: [UIView] {
        guard let bodyMediaPresentationContext = mediaView.firstAncestor(ofType: BodyMediaPresentationContext.self) else {
            owsFailDebug("unexpected mediaView: \(mediaView)")
            return []
        }
        return bodyMediaPresentationContext.mediaOverlayViews
    }
}

// MARK: -

extension MessageDetailViewController: UIDatabaseSnapshotDelegate {

    public func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    public func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        AssertIsOnMainThread()

        guard databaseChanges.didUpdate(interaction: self.message) else {
            return
        }

        refreshContentForDatabaseUpdate()
    }

    public func uiDatabaseSnapshotDidUpdateExternally() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    public func uiDatabaseSnapshotDidReset() {
        AssertIsOnMainThread()

        refreshContentForDatabaseUpdate()
    }

    private func refreshContentForDatabaseUpdate() {
        guard databaseUpdateTimer == nil else { return }
        // Updating this view is slightly expensive and there will be tons of relevant
        // database updates when sending to a large group. Update latency isn't that
        // imporant, so we de-bounce to never update this view more than once every N seconds.
        self.databaseUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0,
            repeats: false
        ) { [weak self] _ in
            guard let self = self else {
                return
            }
            assert(self.databaseUpdateTimer != nil)
            self.databaseUpdateTimer?.invalidate()
            self.databaseUpdateTimer = nil
            self.refreshContent()
        }
    }

    private func refreshContent() {
        AssertIsOnMainThread()

        guard !wasDeleted else {
            // Item was deleted in the tile view gallery.
            // Don't bother re-rendering, it will fail and we'll soon be dismissed.
            return
        }

        do {
            try databaseStorage.uiReadThrows { transaction in
                let uniqueId = self.message.uniqueId
                guard let newMessage = TSInteraction.anyFetch(uniqueId: uniqueId,
                                                              transaction: transaction) as? TSMessage else {
                    Logger.error("Message was deleted")
                    throw DetailViewError.messageWasDeleted
                }
                self.message = newMessage
                self.attachments = newMessage.mediaAttachments(with: transaction.unwrapGrdbRead)
            }

            guard let renderItem = buildRenderItem(interactionId: message.uniqueId) else {
                owsFailDebug("Could not build renderItem.")
                throw DetailViewError.messageWasDeleted
            }
            self.renderItem = renderItem

            if isIncoming {
                updateTableContents()
            } else {
                refreshMessageRecipientsAsync()
            }
        } catch DetailViewError.messageWasDeleted {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.detailDelegate?.detailViewMessageWasDeleted(self)
            }
        } catch {
            owsFailDebug("unexpected error: \(error)")
        }
    }

    private func refreshMessageRecipientsAsync() {
        guard let outgoingMessage = message as? TSOutgoingMessage else {
            return owsFailDebug("Unexpected message type")
        }

        DispatchQueue.sharedUserInitiated.async { [weak self] in
            guard let self = self else { return }

            let messageRecipientAddressesUnsorted = outgoingMessage.recipientAddresses()
            let messageRecipientAddressesSorted = self.databaseStorage.read { transaction in
                self.contactsManagerImpl.sortSignalServiceAddresses(
                    messageRecipientAddressesUnsorted,
                    transaction: transaction
                )
            }
            let messageRecipientAddressesGrouped = messageRecipientAddressesSorted.reduce(
                into: [MessageReceiptStatus: [MessageRecipientModel]]()
            ) { result, address in
                guard let recipientState = outgoingMessage.recipientState(for: address) else {
                    return owsFailDebug("no message status for recipient: \(address).")
                }

                let (status, statusMessage, _) = MessageRecipientStatusUtils.recipientStatusAndStatusMessage(
                    outgoingMessage: outgoingMessage,
                    recipientState: recipientState
                )
                var bucket = result[status] ?? []

                switch status {
                case .delivered, .read, .sent:
                    bucket.append(MessageRecipientModel(
                        address: address,
                        accessoryText: statusMessage,
                        displayUDIndicator: recipientState.wasSentByUD
                    ))
                case .sending, .failed, .skipped, .uploading:
                    bucket.append(MessageRecipientModel(
                        address: address,
                        accessoryText: "",
                        displayUDIndicator: false
                    ))
                }

                result[status] = bucket
            }

            self.messageRecipients.set(messageRecipientAddressesGrouped)
            DispatchQueue.main.async { self.updateTableContents() }
        }
    }
}

// MARK: -

extension MessageDetailViewController: CVComponentDelegate {

    // MARK: - Long Press

    // TODO:
    func cvc_didLongPressTextViewItem(_ cell: CVCell,
                                      itemViewModel: CVItemViewModelImpl,
                                      shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressMediaViewItem(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl,
                                       shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressQuote(_ cell: CVCell,
                               itemViewModel: CVItemViewModelImpl,
                               shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didLongPressSystemMessage(_ cell: CVCell,
                                       itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didLongPressSticker(_ cell: CVCell,
                                 itemViewModel: CVItemViewModelImpl,
                                 shouldAllowReply: Bool) {}

    // TODO:
    func cvc_didChangeLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didEndLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didCancelLongpress(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: -

    // TODO:
    func cvc_didTapReplyToItem(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didTapSenderAvatar(_ interaction: TSInteraction) {}

    // TODO:
    func cvc_shouldAllowReplyForItem(_ itemViewModel: CVItemViewModelImpl) -> Bool { false }

    // TODO:
    func cvc_didTapReactions(reactionState: InteractionReactionState,
                             message: TSMessage) {}

    func cvc_didTapTruncatedTextMessage(_ itemViewModel: CVItemViewModelImpl) {
        AssertIsOnMainThread()

        let viewController = LongTextViewController(itemViewModel: itemViewModel)
        viewController.delegate = self
        navigationController?.pushViewController(viewController, animated: true)
    }

    // TODO:
    var cvc_hasPendingMessageRequest: Bool { false }

    func cvc_didTapFailedOrPendingDownloads(_ message: TSMessage) {}

    // MARK: - Messages

    func cvc_didTapBodyMedia(itemViewModel: CVItemViewModelImpl,
                         attachmentStream: TSAttachmentStream,
                         imageView: UIView) {
        guard let thread = thread else {
            owsFailDebug("Missing thread.")
            return
        }
        let mediaPageVC = MediaPageViewController(
            initialMediaAttachment: attachmentStream,
            thread: thread,
            showingSingleMessage: true
        )
        mediaPageVC.mediaGallery.addDelegate(self)
        present(mediaPageVC, animated: true)
    }

    func cvc_didTapGenericAttachment(_ attachment: CVComponentGenericAttachment) -> CVAttachmentTapAction {
        if attachment.canQuickLook {
            let previewController = QLPreviewController()
            previewController.dataSource = attachment
            present(previewController, animated: true)
            return .handledByDelegate
        } else {
            return .default
        }
    }

    func cvc_didTapQuotedReply(_ quotedReply: OWSQuotedReplyModel) {}

    func cvc_didTapLinkPreview(_ linkPreview: OWSLinkPreview) {
        guard let urlString = linkPreview.urlString else {
            owsFailDebug("Missing url.")
            return
        }
        guard let url = URL(string: urlString) else {
            owsFailDebug("Invalid url: \(urlString).")
            return
        }
        UIApplication.shared.open(url, options: [:])
    }

    func cvc_didTapContactShare(_ contactShare: ContactShareViewModel) {
        let contactViewController = ContactViewController(contactShare: contactShare)
        self.navigationController?.pushViewController(contactViewController, animated: true)
    }

    func cvc_didTapSendMessage(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.sendMessage(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapSendInvite(toContactShare contactShare: ContactShareViewModel) {
        contactShareViewHelper.showInviteContact(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapAddToContacts(contactShare: ContactShareViewModel) {
        contactShareViewHelper.showAddToContacts(contactShare: contactShare, fromViewController: self)
    }

    func cvc_didTapStickerPack(_ stickerPackInfo: StickerPackInfo) {
        let packView = StickerPackViewController(stickerPackInfo: stickerPackInfo)
        packView.present(from: self, animated: true)
    }

    func cvc_didTapGroupInviteLink(url: URL) {
        GroupInviteLinksUI.openGroupInviteLink(url, fromViewController: self)
    }

    func cvc_didTapMention(_ mention: Mention) {}

    func cvc_didTapShowMessageDetail(_ itemViewModel: CVItemViewModelImpl) {}

    func cvc_prepareMessageDetailForInteractivePresentation(_ itemViewModel: CVItemViewModelImpl) {}

    var isConversationPreview: Bool { true }

    var wallpaperBlurProvider: WallpaperBlurProvider? { nil }

    // MARK: - Selection

    // TODO:
    var isShowingSelectionUI: Bool { false }

    // TODO:
    func cvc_isMessageSelected(_ interaction: TSInteraction) -> Bool { false }

    // TODO:
    func cvc_didSelectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    // TODO:
    func cvc_didDeselectViewItem(_ itemViewModel: CVItemViewModelImpl) {}

    // MARK: - System Cell

    // TODO:
    func cvc_didTapPreviouslyVerifiedIdentityChange(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapUnverifiedIdentityChange(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapInvalidIdentityKeyErrorMessage(_ message: TSInvalidIdentityKeyErrorMessage) {}

    // TODO:
    func cvc_didTapCorruptedMessage(_ message: TSErrorMessage) {}

    // TODO:
    func cvc_didTapSessionRefreshMessage(_ message: TSErrorMessage) {}

    // See: resendGroupUpdate
    // TODO:
    func cvc_didTapResendGroupUpdateForErrorMessage(_ errorMessage: TSErrorMessage) {}

    // TODO:
    func cvc_didTapShowFingerprint(_ address: SignalServiceAddress) {}

    // TODO:
    func cvc_didTapIndividualCall(_ call: TSCall) {}

    // TODO:
    func cvc_didTapGroupCall() {}

    // TODO:
    func cvc_didTapFailedOutgoingMessage(_ message: TSOutgoingMessage) {}

    // TODO:
    func cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: TSInfoMessage,
                                                          oldGroupModel: TSGroupModel,
                                                          newGroupModel: TSGroupModel) {}

    func cvc_didTapGroupInviteLinkPromotion(groupModel: TSGroupModel) {}

    // TODO:
    func cvc_didTapShowConversationSettings() {}

    // TODO:
    func cvc_didTapShowConversationSettingsAndShowMemberRequests() {}

    // TODO:
    func cvc_didTapShowUpgradeAppUI() {}

    // TODO:
    func cvc_didTapUpdateSystemContact(_ address: SignalServiceAddress,
                                       newNameComponents: PersonNameComponents) {}

    func cvc_didTapViewOnceAttachment(_ interaction: TSInteraction) {
        guard let renderItem = renderItem else {
            owsFailDebug("Missing renderItem.")
            return
        }
        let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
        ViewOnceMessageViewController.tryToPresent(interaction: itemViewModel.interaction,
                                                   from: self)
    }

    // TODO:
    func cvc_didTapViewOnceExpired(_ interaction: TSInteraction) {}

    // TODO:
    func cvc_didTapUnknownThreadWarningGroup() {}
    // TODO:
    func cvc_didTapUnknownThreadWarningContact() {}
}

extension MessageDetailViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        return (animationController as? AnimationController)?.percentDrivenTransition
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let animationController = AnimationController(operation: operation)
        if operation == .push { animationController.percentDrivenTransition = pushPercentDrivenTransition }
        if operation == .pop { animationController.percentDrivenTransition = popPercentDrivenTransition }
        return animationController
    }
}

private class AnimationController: NSObject, UIViewControllerAnimatedTransitioning {
    weak var percentDrivenTransition: UIPercentDrivenInteractiveTransition?

    let operation: UINavigationController.Operation
    required init(operation: UINavigationController.Operation) {
        self.operation = operation
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            owsFailDebug("Missing view controllers.")
            return transitionContext.completeTransition(false)
        }

        let containerView = transitionContext.containerView
        let directionMultiplier: CGFloat = CurrentAppContext().isRTL ? -1 : 1

        let bottomViewHiddenTransform = CGAffineTransform(translationX: (fromView.width / 3) * directionMultiplier, y: 0)
        let topViewHiddenTransform = CGAffineTransform(translationX: -fromView.width * directionMultiplier, y: 0)

        let bottomViewOverlay = UIView()
        bottomViewOverlay.backgroundColor = .ows_blackAlpha10

        let topView: UIView
        let bottomView: UIView

        let isPushing = operation == .push
        let isInteractive = percentDrivenTransition != nil

        if isPushing {
            topView = fromView
            bottomView = toView
            bottomView.transform = bottomViewHiddenTransform
            bottomViewOverlay.alpha = 1
        } else {
            topView = toView
            bottomView = fromView
            topView.transform = topViewHiddenTransform
            bottomViewOverlay.alpha = 0
        }

        containerView.addSubview(bottomView)
        containerView.addSubview(topView)

        bottomView.addSubview(bottomViewOverlay)
        bottomViewOverlay.frame = bottomView.bounds

        let animationOptions: UIView.AnimationOptions
        if percentDrivenTransition != nil {
            animationOptions = .curveLinear
        } else {
            animationOptions = .curveEaseInOut
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0, options: animationOptions) {
            if isPushing {
                topView.transform = topViewHiddenTransform
                bottomView.transform = .identity
                bottomViewOverlay.alpha = 0
            } else {
                topView.transform = .identity
                bottomView.transform = bottomViewHiddenTransform
                bottomViewOverlay.alpha = 1
            }
        } completion: { _ in
            bottomView.transform = .identity
            topView.transform = .identity
            bottomViewOverlay.removeFromSuperview()

            if transitionContext.transitionWasCancelled {
                toView.removeFromSuperview()
            } else {
                fromView.removeFromSuperview()

                // When completing the transition, the first responder chain gets
                // messed with. We don't want the keyboard to present when returning
                // from message details, so we dismiss it when we leave the view.
                if let fromViewController = transitionContext.viewController(forKey: .from) as? ConversationViewController {
                    fromViewController.dismissKeyBoard()
                }
            }

            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
