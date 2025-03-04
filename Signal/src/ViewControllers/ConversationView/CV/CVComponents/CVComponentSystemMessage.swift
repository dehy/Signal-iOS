//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class CVComponentSystemMessage: CVComponentBase, CVRootComponent {

    public var cellReuseIdentifier: CVCellReuseIdentifier {
        CVCellReuseIdentifier.systemMessage
    }

    public let isDedicatedCell = true

    private let systemMessage: CVComponentState.SystemMessage

    typealias Action = CVMessageAction
    fileprivate var action: Action? { systemMessage.action }

    required init(itemModel: CVItemModel, systemMessage: CVComponentState.SystemMessage) {
        self.systemMessage = systemMessage

        super.init(itemModel: itemModel)
    }

    public func configureCellRootComponent(cellView: UIView,
                                           cellMeasurement: CVCellMeasurement,
                                           componentDelegate: CVComponentDelegate,
                                           cellSelection: CVCellSelection,
                                           messageSwipeActionState: CVMessageSwipeActionState,
                                           componentView: CVComponentView) {
        Self.configureCellRootComponent(rootComponent: self,
                                        cellView: cellView,
                                        cellMeasurement: cellMeasurement,
                                        componentDelegate: componentDelegate,
                                        componentView: componentView)
    }

    private var bubbleBackgroundColor: UIColor {
        Theme.backgroundColor
    }

    private var outerHStackConfig: CVStackViewConfig {
        let cellLayoutMargins = UIEdgeInsets(top: 0,
                                             leading: conversationStyle.fullWidthGutterLeading,
                                             bottom: 0,
                                             trailing: conversationStyle.fullWidthGutterTrailing)
        return CVStackViewConfig(axis: .horizontal,
                                 alignment: .fill,
                                 spacing: ConversationStyle.messageStackSpacing,
                                 layoutMargins: cellLayoutMargins)
    }

    private var innerVStackConfig: CVStackViewConfig {
        let layoutMargins = UIEdgeInsets(hMargin: 10, vMargin: 8)
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .center,
                                 spacing: 12,
                                 layoutMargins: layoutMargins)
    }

    private var outerVStackConfig: CVStackViewConfig {
        return CVStackViewConfig(axis: .vertical,
                                 alignment: .center,
                                 spacing: 0,
                                 layoutMargins: .zero)
    }

    public override func wallpaperBlurView(componentView: CVComponentView) -> CVWallpaperBlurView? {
        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return nil
        }
        return componentView.wallpaperBlurView
    }

    public func buildComponentView(componentDelegate: CVComponentDelegate) -> CVComponentView {
        CVComponentViewSystemMessage()
    }

    public func configureForRendering(componentView: CVComponentView,
                                      cellMeasurement: CVCellMeasurement,
                                      componentDelegate: CVComponentDelegate) {
        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return
        }

        let themeHasChanged = conversationStyle.isDarkThemeEnabled != componentView.isDarkThemeEnabled
        componentView.isDarkThemeEnabled = conversationStyle.isDarkThemeEnabled

        let hasWallpaper = conversationStyle.hasWallpaper
        let wallpaperModeHasChanged = hasWallpaper != componentView.hasWallpaper
        componentView.hasWallpaper = hasWallpaper

        let isFirstInCluster = itemModel.itemViewState.isFirstInCluster
        let isLastInCluster = itemModel.itemViewState.isLastInCluster
        let hasClusteringChanges = (componentView.isFirstInCluster != isFirstInCluster ||
                                        componentView.isLastInCluster != isLastInCluster)
        componentView.isFirstInCluster = isFirstInCluster
        componentView.isLastInCluster = isLastInCluster

        let outerHStack = componentView.outerHStack
        let innerVStack = componentView.innerVStack
        let outerVStack = componentView.outerVStack
        let selectionView = componentView.selectionView
        let titleLabel = componentView.titleLabel

        titleLabelConfig.applyForRendering(label: titleLabel)
        titleLabel.accessibilityLabel = titleLabelConfig.stringValue

        var hasActionButton = false
        if nil != action,
           !itemViewState.shouldCollapseSystemMessageAction,
           nil != cellMeasurement.size(key: Self.measurementKey_buttonSize) {
            hasActionButton = true
        }

        let isReusing = (componentView.rootView.superview != nil &&
                            !themeHasChanged &&
                            !wallpaperModeHasChanged &&
                            !hasClusteringChanges &&
                            componentView.isShowingSelectionUI == isShowingSelectionUI &&
                            !componentView.hasActionButton &&
                            !hasActionButton)
        if isReusing {
            innerVStack.configureForReuse(config: innerVStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_innerVStack)
            outerVStack.configureForReuse(config: outerVStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_outerVStack)
            outerHStack.configureForReuse(config: outerHStackConfig,
                                          cellMeasurement: cellMeasurement,
                                          measurementKey: Self.measurementKey_outerHStack)
        } else {
            var innerVStackViews: [UIView] = [
                titleLabel
            ]
            let outerVStackViews = [
                innerVStack
            ]
            var outerHStackViews = [UIView]()
            if isShowingSelectionUI {
                selectionView.isSelected = componentDelegate.cvc_isMessageSelected(interaction)
                outerHStackViews.append(selectionView)
            }
            outerHStackViews.append(contentsOf: [
                UIView.transparentSpacer(),
                outerVStack,
                UIView.transparentSpacer()
            ])

            if let action = action,
               !itemViewState.shouldCollapseSystemMessageAction,
               let actionButtonSize = cellMeasurement.size(key: Self.measurementKey_buttonSize) {

                let buttonLabelConfig = self.buttonLabelConfig(action: action)
                let button = OWSButton(title: action.title) {}
                componentView.button = button
                button.accessibilityIdentifier = action.accessibilityIdentifier
                button.titleLabel?.textAlignment = .center
                button.titleLabel?.font = buttonLabelConfig.font
                button.setTitleColor(buttonLabelConfig.textColor, for: .normal)
                if nil == interaction as? OWSGroupCallMessage {
                    if isDarkThemeEnabled && hasWallpaper {
                        button.backgroundColor = .ows_gray65
                    } else {
                        button.backgroundColor = Theme.conversationButtonBackgroundColor
                    }
                }
                button.contentEdgeInsets = buttonContentEdgeInsets
                button.layer.cornerRadius = actionButtonSize.height / 2
                button.isUserInteractionEnabled = false
                innerVStackViews.append(button)
            }

            outerHStack.reset()
            innerVStack.reset()
            outerVStack.reset()

            innerVStack.configure(config: innerVStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: Self.measurementKey_innerVStack,
                                  subviews: innerVStackViews)
            outerVStack.configure(config: outerVStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: Self.measurementKey_outerVStack,
                                  subviews: outerVStackViews)
            outerHStack.configure(config: outerHStackConfig,
                                  cellMeasurement: cellMeasurement,
                                  measurementKey: Self.measurementKey_outerHStack,
                                  subviews: outerHStackViews)

            componentView.wallpaperBlurView?.removeFromSuperview()
            componentView.wallpaperBlurView = nil

            componentView.backgroundView?.removeFromSuperview()
            componentView.backgroundView = nil

            let bubbleView: UIView

            if hasWallpaper {
                let wallpaperBlurView = componentView.ensureWallpaperBlurView()
                configureWallpaperBlurView(wallpaperBlurView: wallpaperBlurView,
                                           maskCornerRadius: 0,
                                           componentDelegate: componentDelegate)
                bubbleView = wallpaperBlurView
            } else {
                let backgroundView = UIView()
                backgroundView.backgroundColor = Theme.backgroundColor
                componentView.backgroundView = backgroundView
                bubbleView = backgroundView
            }

            if isFirstInCluster && isLastInCluster {
                innerVStack.addSubviewToFillSuperviewEdges(bubbleView)
                innerVStack.sendSubviewToBack(bubbleView)

                bubbleView.layer.cornerRadius = 8
                bubbleView.layer.maskedCorners = .all
                bubbleView.clipsToBounds = true
            } else {
                outerVStack.addSubviewToFillSuperviewEdges(bubbleView)
                outerVStack.sendSubviewToBack(bubbleView)

                if isFirstInCluster {
                    bubbleView.layer.cornerRadius = 12
                    bubbleView.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
                    bubbleView.clipsToBounds = true
                } else if isLastInCluster {
                    bubbleView.layer.cornerRadius = 12
                    bubbleView.layer.maskedCorners = [.layerMaxXMaxYCorner, .layerMinXMaxYCorner]
                    bubbleView.clipsToBounds = true
                }
            }
        }
        componentView.isShowingSelectionUI = isShowingSelectionUI
        componentView.hasActionButton = hasActionButton
    }

    private var titleLabelConfig: CVLabelConfig {
        CVLabelConfig(attributedText: systemMessage.title,
                      font: Self.titleLabelFont,
                      textColor: systemMessage.titleColor,
                      numberOfLines: 0,
                      lineBreakMode: .byWordWrapping,
                      textAlignment: .center)
    }

    private func buttonLabelConfig(action: Action) -> CVLabelConfig {
        let textColor: UIColor
        if nil != interaction as? OWSGroupCallMessage {
            textColor = Theme.isDarkThemeEnabled ? .ows_whiteAlpha90 : .white
        } else {
            textColor = Theme.conversationButtonTextColor
        }
        return CVLabelConfig(text: action.title,
                             font: UIFont.ows_dynamicTypeFootnote.ows_semibold,
                             textColor: textColor,
                             textAlignment: .center)
    }

    private var buttonContentEdgeInsets: UIEdgeInsets {
        UIEdgeInsets(hMargin: 12, vMargin: 6)
    }

    private static var titleLabelFont: UIFont {
        UIFont.ows_dynamicTypeFootnote
    }

    private static let measurementKey_outerHStack = "CVComponentSystemMessage.measurementKey_outerHStack"
    private static let measurementKey_innerVStack = "CVComponentSystemMessage.measurementKey_innerVStack"
    private static let measurementKey_outerVStack = "CVComponentSystemMessage.measurementKey_outerVStack"
    private static let measurementKey_buttonSize = "CVComponentSystemMessage.measurementKey_buttonSize"

    public func measure(maxWidth: CGFloat, measurementBuilder: CVCellMeasurement.Builder) -> CGSize {
        owsAssertDebug(maxWidth > 0)

        var maxContentWidth = (maxWidth -
                                (outerHStackConfig.layoutMargins.totalWidth +
                                    outerVStackConfig.layoutMargins.totalWidth +
                                    innerVStackConfig.layoutMargins.totalWidth))

        let selectionViewSize = CGSize(width: ConversationStyle.selectionViewWidth, height: 0)
        if isShowingSelectionUI {
            // Account for selection UI when doing measurement.
            maxContentWidth -= selectionViewSize.width + outerHStackConfig.spacing
        }

        // Padding around the outerVStack (leading and trailing side)
        maxContentWidth -= (outerHStackConfig.spacing + minBubbleHMargin) * 2

        maxContentWidth = max(0, maxContentWidth)

        let titleSize = CVText.measureLabel(config: titleLabelConfig,
                                            maxWidth: maxContentWidth)

        var innerVStackSubviewInfos = [ManualStackSubviewInfo]()
        innerVStackSubviewInfos.append(titleSize.asManualSubviewInfo)
        if let action = action, !itemViewState.shouldCollapseSystemMessageAction {
            let buttonLabelConfig = self.buttonLabelConfig(action: action)
            let actionButtonSize = (CVText.measureLabel(config: buttonLabelConfig,
                                                       maxWidth: maxContentWidth) +
                                        buttonContentEdgeInsets.asSize)
            measurementBuilder.setSize(key: Self.measurementKey_buttonSize, size: actionButtonSize)
            innerVStackSubviewInfos.append(actionButtonSize.asManualSubviewInfo(hasFixedSize: true))
        }
        let innerVStackMeasurement = ManualStackView.measure(config: innerVStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_innerVStack,
                                                             subviewInfos: innerVStackSubviewInfos)

        let outerVStackSubviewInfos: [ManualStackSubviewInfo] = [
            innerVStackMeasurement.measuredSize.asManualSubviewInfo
        ]
        let outerVStackMeasurement = ManualStackView.measure(config: outerVStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_outerVStack,
                                                             subviewInfos: outerVStackSubviewInfos)

        var outerHStackSubviewInfos = [ManualStackSubviewInfo]()
        if isShowingSelectionUI {
            outerHStackSubviewInfos.append(selectionViewSize.asManualSubviewInfo(hasFixedWidth: true))
        }
        outerHStackSubviewInfos.append(contentsOf: [
            CGSize(width: minBubbleHMargin, height: 0).asManualSubviewInfo(hasFixedWidth: true),
            outerVStackMeasurement.measuredSize.asManualSubviewInfo,
            CGSize(width: minBubbleHMargin, height: 0).asManualSubviewInfo(hasFixedWidth: true)
        ])
        let outerHStackMeasurement = ManualStackView.measure(config: outerHStackConfig,
                                                             measurementBuilder: measurementBuilder,
                                                             measurementKey: Self.measurementKey_outerHStack,
                                                             subviewInfos: outerHStackSubviewInfos,
                                                             maxWidth: maxWidth)
        return outerHStackMeasurement.measuredSize
    }

    private let minBubbleHMargin: CGFloat = 4

    // MARK: - Events

    public override func handleTap(sender: UITapGestureRecognizer,
                                   componentDelegate: CVComponentDelegate,
                                   componentView: CVComponentView,
                                   renderItem: CVRenderItem) -> Bool {

        guard let componentView = componentView as? CVComponentViewSystemMessage else {
            owsFailDebug("Unexpected componentView.")
            return false
        }

        if isShowingSelectionUI {
            let selectionView = componentView.selectionView
            let itemViewModel = CVItemViewModelImpl(renderItem: renderItem)
            if componentDelegate.cvc_isMessageSelected(interaction) {
                selectionView.isSelected = false
                componentDelegate.cvc_didDeselectViewItem(itemViewModel)
            } else {
                selectionView.isSelected = true
                componentDelegate.cvc_didSelectViewItem(itemViewModel)
            }
            // Suppress other tap handling during selection mode.
            return true
        }

        if let action = systemMessage.action {
            let rootView = componentView.rootView
            if rootView.containsGestureLocation(sender) {
                action.action.perform(delegate: componentDelegate)
                return true
            }
        }

        return false
    }

    public override func findLongPressHandler(sender: UILongPressGestureRecognizer,
                                              componentDelegate: CVComponentDelegate,
                                              componentView: CVComponentView,
                                              renderItem: CVRenderItem) -> CVLongPressHandler? {
        return CVLongPressHandler(delegate: componentDelegate,
                                  renderItem: renderItem,
                                  gestureLocation: .systemMessage)
    }

    // MARK: -

    // Used for rendering some portion of an Conversation View item.
    // It could be the entire item or some part thereof.
    @objc
    public class CVComponentViewSystemMessage: NSObject, CVComponentView {

        fileprivate let outerHStack = ManualStackView(name: "systemMessage.outerHStack")
        fileprivate let innerVStack = ManualStackView(name: "systemMessage.innerVStack")
        fileprivate let outerVStack = ManualStackView(name: "systemMessage.outerVStack")
        fileprivate let titleLabel = CVLabel()
        fileprivate let selectionView = MessageSelectionView()

        fileprivate var wallpaperBlurView: CVWallpaperBlurView?
        fileprivate func ensureWallpaperBlurView() -> CVWallpaperBlurView {
            if let wallpaperBlurView = self.wallpaperBlurView {
                return wallpaperBlurView
            }
            let wallpaperBlurView = CVWallpaperBlurView()
            self.wallpaperBlurView = wallpaperBlurView
            return wallpaperBlurView
        }

        fileprivate var backgroundView: UIView?

        fileprivate var button: OWSButton?

        fileprivate var hasWallpaper = false
        fileprivate var isDarkThemeEnabled = false
        fileprivate var isFirstInCluster = false
        fileprivate var isLastInCluster = false

        public var isDedicatedCellView = false

        public var isShowingSelectionUI = false
        public var hasActionButton = false

        public var rootView: UIView {
            outerHStack
        }

        // MARK: -

        override required init() {
            super.init()

            titleLabel.textAlignment = .center
        }

        public func setIsCellVisible(_ isCellVisible: Bool) {}

        public func reset() {
            owsAssertDebug(isDedicatedCellView)

            if !isDedicatedCellView {
                outerHStack.reset()
                innerVStack.reset()
                outerVStack.reset()

                wallpaperBlurView?.removeFromSuperview()
                wallpaperBlurView?.resetContentAndConfiguration()

                backgroundView?.removeFromSuperview()
                backgroundView = nil

                hasWallpaper = false
                isDarkThemeEnabled = false
                isFirstInCluster = false
                isLastInCluster = false
                isShowingSelectionUI = false
                hasActionButton = false
            }

            titleLabel.text = nil

            button?.removeFromSuperview()
            button = nil
        }
    }
}

// MARK: -

extension CVComponentSystemMessage {

    static func buildComponentState(interaction: TSInteraction,
                                    threadViewModel: ThreadViewModel,
                                    currentCallThreadId: String?,
                                    transaction: SDSAnyReadTransaction) -> CVComponentState.SystemMessage {

        let title = Self.title(forInteraction: interaction, transaction: transaction)
        let titleColor = Self.textColor(forInteraction: interaction)
        let action = Self.action(forInteraction: interaction,
                                 threadViewModel: threadViewModel,
                                 currentCallThreadId: currentCallThreadId,
                                 transaction: transaction)

        return CVComponentState.SystemMessage(title: title, titleColor: titleColor, action: action)
    }

    private static func title(forInteraction interaction: TSInteraction,
                              transaction: SDSAnyReadTransaction) -> NSAttributedString {

        let font = Self.titleLabelFont
        let labelText = NSMutableAttributedString()

        if let infoMessage = interaction as? TSInfoMessage,
           infoMessage.messageType == .typeGroupUpdate,
           let groupUpdates = infoMessage.groupUpdateItems(transaction: transaction),
           !groupUpdates.isEmpty {

            for (index, update) in groupUpdates.enumerated() {
                let iconName = Self.iconName(forGroupUpdateType: update.type)
                labelText.appendTemplatedImage(named: iconName,
                                               font: font,
                                               heightReference: ImageAttachmentHeightReference.lineHeight)
                labelText.append("  ", attributes: [:])
                labelText.append(update.text, attributes: [:])

                let isLast = index == groupUpdates.count - 1
                if !isLast {
                    labelText.append("\n", attributes: [:])
                }
            }

            if groupUpdates.count > 1 {
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.paragraphSpacing = 12
                paragraphStyle.alignment = .center
                labelText.addAttributeToEntireString(.paragraphStyle, value: paragraphStyle)
            }

            return labelText
        }

        if let icon = icon(forInteraction: interaction) {
            labelText.appendImage(icon.withRenderingMode(.alwaysTemplate),
                                  font: font,
                                  heightReference: ImageAttachmentHeightReference.lineHeight)
            labelText.append("  ", attributes: [:])
        }

        let systemMessageText = Self.systemMessageText(forInteraction: interaction,
                                                       transaction: transaction)
        owsAssertDebug(!systemMessageText.isEmpty)
        labelText.append(systemMessageText)

        let shouldShowTimestamp = interaction.interactionType() == .call
        if shouldShowTimestamp {
            labelText.append(LocalizationNotNeeded(" · "))
            labelText.append(DateUtil.formatTimestamp(asDate: interaction.timestamp))
            labelText.append(LocalizationNotNeeded(" "))
            labelText.append(DateUtil.formatTimestamp(asTime: interaction.timestamp))
        }

        return labelText
    }

    private static func systemMessageText(forInteraction interaction: TSInteraction,
                                          transaction: SDSAnyReadTransaction) -> String {

        if let errorMessage = interaction as? TSErrorMessage {
            return errorMessage.previewText(transaction: transaction)
        } else if let verificationMessage = interaction as? OWSVerificationStateChangeMessage {
            let isVerified = verificationMessage.verificationState == .verified
            let displayName = contactsManager.displayName(for: verificationMessage.recipientAddress, transaction: transaction)
            let format = (isVerified
                            ? (verificationMessage.isLocalChange
                                ? NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_LOCAL",
                                                    comment: "Format for info message indicating that the verification state was verified on this device. Embeds {{user's name or phone number}}.")
                                : NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_VERIFIED_OTHER_DEVICE",
                                                    comment: "Format for info message indicating that the verification state was verified on another device. Embeds {{user's name or phone number}}."))
                            : (verificationMessage.isLocalChange
                                ? NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_LOCAL",
                                                    comment: "Format for info message indicating that the verification state was unverified on this device. Embeds {{user's name or phone number}}.")
                                : NSLocalizedString("VERIFICATION_STATE_CHANGE_FORMAT_NOT_VERIFIED_OTHER_DEVICE",
                                                    comment: "Format for info message indicating that the verification state was unverified on another device. Embeds {{user's name or phone number}}.")))
            return String(format: format, displayName)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return infoMessage.systemMessageText(with: transaction)
        } else if let call = interaction as? TSCall {
            return call.previewText(transaction: transaction)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return groupCall.systemText(with: transaction)
        } else {
            owsFailDebug("Not a system message.")
            return ""
        }
    }

    private static func textColor(forInteraction interaction: TSInteraction) -> UIColor {
        if let call = interaction as? TSCall {
            switch call.callType {
            case .incomingMissed,
                 .incomingMissedBecauseOfChangedIdentity,
                 .incomingBusyElsewhere,
                 .incomingDeclined,
                 .incomingDeclinedElsewhere:
                // We use a custom red here, as we consider changing
                // our red everywhere for better accessibility
                return UIColor(rgbHex: 0xE51D0E)
            default:
                return Theme.secondaryTextAndIconColor
            }
        } else {
            return Theme.secondaryTextAndIconColor
        }
    }

    private static func icon(forInteraction interaction: TSInteraction) -> UIImage? {
        if let errorMessage = interaction as? TSErrorMessage {
            switch errorMessage.errorType {
            case .nonBlockingIdentityChange,
                 .wrongTrustedIdentityKey:
                return Theme.iconImage(.safetyNumber16)
            case .sessionRefresh:
                return Theme.iconImage(.refresh16)
            case .invalidKeyException,
                 .missingKeyId,
                 .noSession,
                 .invalidMessage,
                 .duplicateMessage,
                 .invalidVersion,
                 .unknownContactBlockOffer,
                 .groupCreationFailed:
                return nil
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }
        } else if let infoMessage = interaction as? TSInfoMessage {
            switch infoMessage.messageType {
            case .userNotRegistered,
                 .typeSessionDidEnd,
                 .typeUnsupportedMessage,
                 .addToContactsOffer,
                 .addUserToProfileWhitelistOffer,
                 .addGroupToProfileWhitelistOffer:
                return nil
            case .typeGroupUpdate,
                 .typeGroupQuit:
                return Theme.iconImage(.group16)
            case .unknownProtocolVersion:
                guard let message = interaction as? OWSUnknownProtocolVersionMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                return Theme.iconImage(message.isProtocolVersionUnknown ? .error16 : .check16)
            case .typeDisappearingMessagesUpdate:
                guard let message = interaction as? OWSDisappearingConfigurationUpdateInfoMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                let areDisappearingMessagesEnabled = message.configurationIsEnabled
                return Theme.iconImage(areDisappearingMessagesEnabled ? .timer16 : .timerDisabled16)
            case .verificationStateChange:
                guard let message = interaction as? OWSVerificationStateChangeMessage else {
                    owsFailDebug("Invalid interaction.")
                    return nil
                }
                guard message.verificationState == .verified else {
                    return nil
                }
                return Theme.iconImage(.check16)
            case .userJoinedSignal:
                return Theme.iconImage(.heart16)
            case .syncedThread:
                return Theme.iconImage(.info16)
            case .profileUpdate:
                return Theme.iconImage(.profile16)
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }
        } else if let call = interaction as? TSCall {

            let offerTypeString: String
            switch call.offerType {
            case .audio:
                offerTypeString = "phone"
            case .video:
                offerTypeString = "video"
            }

            let directionString: String
            switch call.callType {
            case .incomingMissed,
                 .incomingMissedBecauseOfChangedIdentity,
                 .incomingBusyElsewhere,
                 .incomingDeclined,
                 .incomingDeclinedElsewhere:
                directionString = "x"
            case .incoming,
                 .incomingIncomplete,
                 .incomingAnsweredElsewhere:
                directionString = "incoming"
            case .outgoing,
                 .outgoingIncomplete,
                 .outgoingMissed:
                directionString = "outgoing"
            @unknown default:
                owsFailDebug("Unknown value.")
                return nil
            }

            let themeString = Theme.isDarkThemeEnabled ? "solid" : "outline"

            let imageName = "\(offerTypeString)-\(directionString)-\(themeString)-16"
            return UIImage(named: imageName)
        } else if nil != interaction as? OWSGroupCallMessage {
            let imageName = Theme.isDarkThemeEnabled ? "video-solid-16" : "video-outline-16"
            return UIImage(named: imageName)
        } else {
            owsFailDebug("Unknown interaction type: \(type(of: interaction))")
            return nil
        }
    }

    private static func iconName(forGroupUpdateType groupUpdateType: GroupUpdateType) -> String {
        switch groupUpdateType {
        case .userMembershipState_left:
            return Theme.iconName(.leave16)
        case .userMembershipState_removed:
            return Theme.iconName(.memberRemove16)
        case .userMembershipState_invited,
             .userMembershipState_added,
             .userMembershipState_invitesNew:
            return Theme.iconName(.memberAdded16)
        case .groupCreated,
             .generic,
             .debug,
             .userMembershipState,
             .userMembershipState_invalidInvitesRemoved,
             .userMembershipState_invalidInvitesAdded,
             .groupInviteLink,
             .groupGroupLinkPromotion:
            return Theme.iconName(.group16)
        case .userMembershipState_invitesDeclined,
             .userMembershipState_invitesRevoked:
            return Theme.iconName(.memberDeclined16)
        case .accessAttributes,
             .accessMembers,
             .userRole:
            return Theme.iconName(.megaphone16)
        case .groupName:
            return Theme.iconName(.compose16)
        case .groupAvatar:
            return Theme.iconName(.photo16)
        case .disappearingMessagesState,
             .disappearingMessagesState_enabled:
            return Theme.iconName(.timer16)
        case .disappearingMessagesState_disabled:
            return Theme.iconName(.timerDisabled16)
        case .groupMigrated:
            return Theme.iconName(.megaphone16)
        case .groupMigrated_usersInvited:
            return Theme.iconName(.memberAdded16)
        case .groupMigrated_usersDropped:
            return Theme.iconName(.group16)
        }
    }

    // MARK: - Unknown Thread Warning

    static func buildUnknownThreadWarningState(interaction: TSInteraction,
                                               threadViewModel: ThreadViewModel,
                                               transaction: SDSAnyReadTransaction) -> CVComponentState.SystemMessage {

        let titleColor = Theme.secondaryTextAndIconColor
        if threadViewModel.isGroupThread {
            let title = NSLocalizedString("SYSTEM_MESSAGE_UNKNOWN_THREAD_WARNING_GROUP",
                                          comment: "Indicator warning about an unknown group thread.")

            let labelText = NSMutableAttributedString()
            labelText.appendTemplatedImage(named: Theme.iconName(.info16),
                                           font: Self.titleLabelFont,
                                           heightReference: ImageAttachmentHeightReference.lineHeight)
            labelText.append("  ", attributes: [:])
            labelText.append(title, attributes: [:])

            let action = Action(title: CommonStrings.learnMore,
                                accessibilityIdentifier: "unknown_thread_warning",
                                action: .cvc_didTapUnknownThreadWarningGroup)
            return CVComponentState.SystemMessage(title: labelText,
                                                  titleColor: titleColor,
                                                  action: action)
        } else {
            let title = NSLocalizedString("SYSTEM_MESSAGE_UNKNOWN_THREAD_WARNING_CONTACT",
                                          comment: "Indicator warning about an unknown contact thread.")
            let action = Action(title: CommonStrings.learnMore,
                                accessibilityIdentifier: "unknown_thread_warning",
                                action: .cvc_didTapUnknownThreadWarningContact)
            return CVComponentState.SystemMessage(title: title.attributedString(),
                                                  titleColor: titleColor,
                                                  action: action)
        }
    }

    // MARK: - Actions

    static func action(forInteraction interaction: TSInteraction,
                       threadViewModel: ThreadViewModel,
                       currentCallThreadId: String?,
                       transaction: SDSAnyReadTransaction) -> Action? {

        let thread = threadViewModel.threadRecord

        if let errorMessage = interaction as? TSErrorMessage {
            return action(forErrorMessage: errorMessage)
        } else if let infoMessage = interaction as? TSInfoMessage {
            return action(forInfoMessage: infoMessage, transaction: transaction)
        } else if let call = interaction as? TSCall {
            return action(forCall: call, thread: thread, transaction: transaction)
        } else if let groupCall = interaction as? OWSGroupCallMessage {
            return action(forGroupCall: groupCall,
                          threadViewModel: threadViewModel,
                          currentCallThreadId: currentCallThreadId)
        } else {
            owsFailDebug("Invalid interaction.")
            return nil
        }
    }

    private static func action(forErrorMessage message: TSErrorMessage) -> Action? {
        switch message.errorType {
        case .nonBlockingIdentityChange:
            guard let address = message.recipientAddress else {
                owsFailDebug("Missing address.")
                return nil
            }

            if message.wasIdentityVerified {
                return Action(title: NSLocalizedString("SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                                       comment: "Label for button to verify a user's safety number."),
                              accessibilityIdentifier: "verify_safety_number",
                              action: .cvc_didTapPreviouslyVerifiedIdentityChange(address: address))
            } else {
                return Action(title: CommonStrings.learnMore,
                              accessibilityIdentifier: "learn_more",
                              action: .cvc_didTapUnverifiedIdentityChange(address: address))
            }
        case .wrongTrustedIdentityKey:
            guard let message = message as? TSInvalidIdentityKeyErrorMessage else {
                owsFailDebug("Invalid interaction.")
                return nil
            }
            return Action(title: NSLocalizedString("SYSTEM_MESSAGE_ACTION_VERIFY_SAFETY_NUMBER",
                                                   comment: "Label for button to verify a user's safety number."),
                          accessibilityIdentifier: "verify_safety_number",
                          action: .cvc_didTapInvalidIdentityKeyErrorMessage(errorMessage: message))
        case .invalidKeyException,
             .missingKeyId,
             .noSession,
             .invalidMessage:
            return Action(title: NSLocalizedString("FINGERPRINT_SHRED_KEYMATERIAL_BUTTON",
                                                   comment: "Label for button to reset a session."),
                          accessibilityIdentifier: "reset_session",
                          action: .cvc_didTapCorruptedMessage(errorMessage: message))
        case .sessionRefresh:
            return Action(title: CommonStrings.learnMore,
                          accessibilityIdentifier: "learn_more",
                          action: .cvc_didTapSessionRefreshMessage(errorMessage: message))
        case .duplicateMessage,
             .invalidVersion:
            return nil
        case .unknownContactBlockOffer:
            owsFailDebug("TSErrorMessageUnknownContactBlockOffer")
            return nil
        case .groupCreationFailed:
            return Action(title: CommonStrings.retryButton,
                          accessibilityIdentifier: "retry_send_group",
                          action: .cvc_didTapResendGroupUpdate(errorMessage: message))
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forInfoMessage infoMessage: TSInfoMessage,
                               transaction: SDSAnyReadTransaction) -> Action? {

        switch infoMessage.messageType {
        case .userNotRegistered,
             .typeSessionDidEnd:
            return nil
        case .typeUnsupportedMessage:
            // Unused.
            return nil
        case .addToContactsOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddToContactsOffer")
            return nil
        case .addUserToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddUserToProfileWhitelistOffer")
            return nil
        case .addGroupToProfileWhitelistOffer:
            // Unused.
            owsFailDebug("TSInfoMessageAddGroupToProfileWhitelistOffer")
            return nil
        case .typeGroupUpdate:
            guard let newGroupModel = infoMessage.newGroupModel else {
                return nil
            }
            if newGroupModel.wasJustCreatedByLocalUserV2 {
                return Action(title: NSLocalizedString("GROUPS_INVITE_FRIENDS_BUTTON",
                                                       comment: "Label for 'invite friends to group' button."),
                              accessibilityIdentifier: "group_invite_friends",
                              action: .cvc_didTapGroupInviteLinkPromotion(groupModel: newGroupModel))
            }
            guard let oldGroupModel = infoMessage.oldGroupModel else {
                return nil
            }

            guard let groupUpdates = infoMessage.groupUpdateItems(transaction: transaction),
                  !groupUpdates.isEmpty else {
                return nil
            }

            for groupUpdate in groupUpdates {
                if groupUpdate.type == .groupMigrated {
                    return Action(title: CommonStrings.learnMore,
                                  accessibilityIdentifier: "group_migration_learn_more",
                                  action: .cvc_didTapShowGroupMigrationLearnMoreActionSheet(infoMessage: infoMessage,
                                                                                            oldGroupModel: oldGroupModel,
                                                                                            newGroupModel: newGroupModel))
                }
            }

            var newlyRequestingMembers = Set<SignalServiceAddress>()
            newlyRequestingMembers.formUnion(newGroupModel.groupMembership.requestingMembers)
            newlyRequestingMembers.subtract(oldGroupModel.groupMembership.requestingMembers)

            guard !newlyRequestingMembers.isEmpty else {
                return nil
            }
            let title = (newlyRequestingMembers.count > 1
                            ? NSLocalizedString("GROUPS_VIEW_REQUESTS_BUTTON",
                                                comment: "Label for button that lets the user view the requests to join the group.")
                            : NSLocalizedString("GROUPS_VIEW_REQUEST_BUTTON",
                                                comment: "Label for button that lets the user view the request to join the group."))
            return Action(title: title,
                          accessibilityIdentifier: "show_group_requests_button",
                          action: .cvc_didTapShowConversationSettingsAndShowMemberRequests)
        case .typeGroupQuit:
            return nil
        case .unknownProtocolVersion:
            guard let message = infoMessage as? OWSUnknownProtocolVersionMessage else {
                owsFailDebug("Unexpected message type.")
                return nil
            }
            guard message.isProtocolVersionUnknown else {
                return nil
            }
            return Action(title: NSLocalizedString("UNKNOWN_PROTOCOL_VERSION_UPGRADE_BUTTON",
                                                   comment: "Label for button that lets users upgrade the app."),
                          accessibilityIdentifier: "show_upgrade_app_ui",
                          action: .cvc_didTapShowUpgradeAppUI)
        case .typeDisappearingMessagesUpdate,
             .verificationStateChange,
             .userJoinedSignal,
             .syncedThread:
            return nil
        case .profileUpdate:
            guard let profileChangeAddress = infoMessage.profileChangeAddress else {
                owsFailDebug("Missing profileChangeAddress.")
                return nil
            }
            guard let profileChangeNewNameComponents = infoMessage.profileChangeNewNameComponents else {
                return nil
            }
            guard Self.contactsManager.isSystemContact(address: profileChangeAddress) else {
                return nil
            }
            let systemContactName = Self.contactsManagerImpl.nameFromSystemContacts(for: profileChangeAddress,
                                                                                    transaction: transaction)
            let newProfileName = PersonNameComponentsFormatter.localizedString(from: profileChangeNewNameComponents,
                                                                               style: .`default`,
                                                                               options: [])
            let currentProfileName = Self.profileManager.fullName(for: profileChangeAddress,
                                                                  transaction: transaction)

            // Don't show the update contact button if the system contact name
            // is already equivalent to the new profile name.
            guard systemContactName != newProfileName else {
                return nil
            }

            // If the new profile name is not the current profile name, it's no
            // longer relevant to ask you to update your contact.
            guard currentProfileName != newProfileName else {
                return nil
            }

            return Action(title: NSLocalizedString("UPDATE_CONTACT_ACTION", comment: "Action sheet item"),
                          accessibilityIdentifier: "update_contact",
                          action: .cvc_didTapUpdateSystemContact(address: profileChangeAddress,
                                                                 newNameComponents: profileChangeNewNameComponents))
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forCall call: TSCall,
                               thread: TSThread,
                               transaction: SDSAnyReadTransaction) -> Action? {

        // TODO: Respect -canCall from ConversationViewController

        let hasPendingMessageRequest = {
            thread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead)
        }

        switch call.callType {
        case .incoming,
             .incomingMissed,
             .incomingMissedBecauseOfChangedIdentity,
             .incomingDeclined,
             .incomingAnsweredElsewhere,
             .incomingDeclinedElsewhere,
             .incomingBusyElsewhere:
            guard !hasPendingMessageRequest() else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(title: NSLocalizedString("CALLBACK_BUTTON_TITLE", comment: "notification action"),
                          accessibilityIdentifier: "call_back",
                          action: .cvc_didTapIndividualCall(call: call))
        case .outgoing,
             .outgoingMissed:
            guard !hasPendingMessageRequest() else {
                return nil
            }
            // TODO: cvc_didTapGroupCall?
            return Action(title: NSLocalizedString("CALL_AGAIN_BUTTON_TITLE",
                                                   comment: "Label for button that lets users call a contact again."),
                          accessibilityIdentifier: "call_again",
                          action: .cvc_didTapIndividualCall(call: call))
        case .outgoingIncomplete,
             .incomingIncomplete:
            return nil
        @unknown default:
            owsFailDebug("Unknown value.")
            return nil
        }
    }

    private static func action(forGroupCall groupCallMessage: OWSGroupCallMessage,
                               threadViewModel: ThreadViewModel,
                               currentCallThreadId: String?) -> Action? {

        let thread = threadViewModel.threadRecord
        // Assume the current thread supports calling if we have no delegate. This ensures we always
        // overestimate cell measurement in cases where the current thread doesn't support calling.
        let isCallingSupported = ConversationViewController.canCall(threadViewModel: threadViewModel)
        let isCallActive = (!groupCallMessage.hasEnded && !groupCallMessage.joinedMemberAddresses.isEmpty)

        guard isCallingSupported, isCallActive else {
            return nil
        }

        // TODO: We need to touch thread whenever current call changes.
        let isCurrentCallForThread = currentCallThreadId == thread.uniqueId

        let joinTitle = NSLocalizedString("GROUP_CALL_JOIN_BUTTON", comment: "Button to join an ongoing group call")
        let returnTitle = NSLocalizedString("CALL_RETURN_BUTTON", comment: "Button to return to the current call")
        let title = isCurrentCallForThread ? returnTitle : joinTitle

        return Action(title: title,
                      accessibilityIdentifier: "group_call_button",
                      action: .cvc_didTapGroupCall)
    }
}
