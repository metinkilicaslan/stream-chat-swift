//
//  ComposerView.swift
//  StreamChat
//
//  Created by Alexey Bukhtin on 10/04/2019.
//  Copyright © 2019 Stream.io Inc. All rights reserved.
//

import UIKit
import StreamChatCore
import SnapKit
import RxSwift
import RxCocoa

/// A composer view.
public final class ComposerView: UIView {
    
    /// A composer view  style.
    public var style: ComposerViewStyle?
    
    private var styleStateStyle: ComposerViewStyle.Style? { style?.style(with: styleState) }
    
    /// An `UITextView`.
    /// You have to use the `text` property to change the value of the text view.
    public private(set) lazy var textView = setupTextView()
    var textViewTopConstraint: Constraint?
    
    /// A button to send a reply in the channel.
    public let alsoSendToChannelButton = UIButton(type: .custom)
    
    lazy var toolBar = UIToolbar(frame: .zero)
    
    /// An action for a plus button in the images attachments collection view.
    /// If it's nil, it will not be shown in the images collection view.
    public var imagesAddAction: AttachmentCollectionViewCell.TapAction?
    
    private var previousTextBeforeReset: NSAttributedString?
    private let disposeBag = DisposeBag()
    private(set) weak var heightConstraint: Constraint?
    
    var baseTextHeight = CGFloat.greatestFiniteMagnitude
    
    /// An images collection view.
    public private(set) lazy var imagesCollectionView = setupImagesCollectionView()
    /// A files stack view.
    public private(set) lazy var filesStackView = setupFilesStackView()
    
    /// Uploader for images and files.
    public var uploadManager: UploadManager?
    
    var isLanguageRightToLeft: Bool {
         if UIView.userInterfaceLayoutDirection(for: semanticContentAttribute) == .rightToLeft {
             return true
         }
         return false
     }
    
    var paragraphStyle: NSMutableParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = isLanguageRightToLeft ? .right : .left
        return paragraphStyle
    }
    
    /// A placeholder label.
    /// You have to use the `placeholderText` property to change the value of the placeholder label.
    public private(set) lazy var placeholderLabel: UILabel = {
        let label = UILabel(frame: .zero)
        addSubview(label)
        
        label.snp.makeConstraints { make in
            make.top.equalTo(textView.snp.top).offset(textView.textContainerInset.top)
            make.leading.equalTo(textView.snp.leading).offset(textView.textContainer.lineFragmentPadding)
            make.bottom.equalTo(textView.snp.bottom).offset(-textView.textContainerInset.bottom)
            make.trailing.equalTo(textView.snp.trailing).offset(-textView.textContainer.lineFragmentPadding)
        }
        
        return label
    }()
    
    /// A send button.
    public private(set) lazy var sendButton: UIButton = {
        let button = UIButton(frame: .zero)
        button.setImage(UIImage.Icons.send.uiLayoutDirectionAdjusted, for: .normal)
        button.backgroundColor = backgroundColor
        button.titleLabel?.font = .chatMediumBold
        
        button.snp.makeConstraints {
            sendButtonWidthConstraint = $0.width.equalTo(CGFloat.composerButtonWidth).priority(999).constraint
        }
        
        return button
    }()
    
    let sendButtonVisibilityBehaviorSubject = BehaviorSubject<(isHidden: Bool, isEnabled: Bool)>(value: (false, false))
    /// An observable sendButton visibility state.
    public private(set) lazy var sendButtonVisibility = sendButtonVisibilityBehaviorSubject
        .distinctUntilChanged { lhs, rhs -> Bool in lhs.0 == rhs.0 && lhs.1 == rhs.1 }
    
    private var sendButtonWidthConstraint: Constraint?
    private var sendButtonRightConstraint: Constraint?
    
    /// An attachment button.
    public private(set) lazy var attachmentButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage.Icons.plus, for: .normal)
        button.snp.makeConstraints { $0.width.equalTo(CGFloat.composerButtonWidth).priority(999) }
        button.backgroundColor = backgroundColor
        return button
    }()
    
    /// The text of the text view.
    public var text: String {
        get {
            textView.attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        set {
            textView.attributedText = attributedText(text: newValue)
            updatePlaceholder()
        }
    }
    
    /// The placeholder text.
    public var placeholderText: String {
        get { placeholderLabel.attributedText?.string ?? "" }
        set { placeholderLabel.attributedText = attributedText(text: newValue, textColor: styleStateStyle?.tintColor) }
    }
    
    func attributedText(text: String = "", textColor: UIColor? = nil) -> NSAttributedString {
        guard let style = style else {
            return NSAttributedString(string: text)
        }
        
        return NSAttributedString(string: text, attributes: [.foregroundColor: textColor ?? style.textColor,
                                                             .font: style.font,
                                                             .paragraphStyle: paragraphStyle])
    }
    
    /// A composer view style state and it will toggle `isUserInteractionEnabled` states for all child views.
    public var styleState: ComposerViewStyle.State = .normal {
        didSet {
            update(for: styleState)
            let isEnabled = styleState != .disabled
            
            if let style = style {
                sendButton.isEnabled = style.sendButtonVisibility == .whenActive ? isEnabled : false
                sendButtonVisibilityBehaviorSubject.onNext((sendButton.isHidden, sendButton.isEnabled))
            }
            
            attachmentButton.isEnabled = isEnabled
            imagesCollectionView.isUserInteractionEnabled = isEnabled
            imagesCollectionView.alpha = isEnabled ? 1 : 0.5
            textView.isEditable = isEnabled
        }
    }
}

// MARK: - Add to Superview

public extension ComposerView {
    /// Add the composer to a view.
    ///
    /// - Parameters:
    ///   - view: a superview.
    ///   - showAlsoSendToChannelButton: a flag to show a send reply to a channel button.
    func addToSuperview(_ view: UIView, showAlsoSendToChannelButton: Bool = false) {
        guard let style = style else {
            return
        }
        
        // Add to superview.
        view.addSubview(self)
        
        snp.makeConstraints { make in
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leadingMargin).offset(style.edgeInsets.left)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailingMargin).offset(-style.edgeInsets.right)
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottomMargin).offset(-style.edgeInsets.bottom)
            heightConstraint = make.height.equalTo(style.height).constraint
        }
        
        // Apply style.
        backgroundColor = style.backgroundColor
        clipsToBounds = true
        layer.cornerRadius = style.cornerRadius
        layer.borderWidth = styleStateStyle?.borderWidth ?? 0
        layer.borderColor = styleStateStyle?.tintColor.cgColor ?? nil
        
        // Add attachment button.
        addSubview(attachmentButton)
        
        attachmentButton.snp.makeConstraints { make in
            make.height.equalTo(style.height)
            make.leading.equalToSuperview()
            make.bottom.equalToSuperview()
        }
        
        // Add buttons.
        if style.sendButtonVisibility != .none {
            sendButton.isHidden = style.sendButtonVisibility == .whenActive
            sendButton.isEnabled = style.sendButtonVisibility == .whenActive
            sendButton.setTitleColor(style.style(with: .active).tintColor, for: .normal)
            sendButton.setTitleColor(style.style(with: .disabled).tintColor, for: .disabled)
            sendButtonVisibilityBehaviorSubject.onNext((sendButton.isHidden, sendButton.isEnabled))
            
            addSubview(sendButton)
            
            sendButton.snp.makeConstraints { make in
                make.height.equalTo(style.height)
                make.bottom.equalToSuperview()
                sendButtonRightConstraint = make.trailing.equalToSuperview().constraint
            }
        }
        
        // Images Collection View.
        addSubview(imagesCollectionView)
        
        imagesCollectionView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        // Files Stack View.
        addSubview(filesStackView)
        
        filesStackView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalToSuperview()
        }
        
        // Add text view.
        addSubview(textView)
        updateTextHeightIfNeeded()
        textView.keyboardAppearance = style.textColor.isDark ? .default : .dark
        textView.backgroundColor = backgroundColor
        
        textView.snp.makeConstraints { make in
            textViewTopConstraint = make.top.equalToSuperview().offset(textViewPadding).priority(990).constraint
            make.bottom.equalToSuperview().offset(-textViewPadding)
            
            if sendButton.superview == nil {
                make.trailing.equalToSuperview().offset(-textViewPadding)
            } else {
                make.trailing.equalTo(sendButton.snp.leading)
            }
            
            if attachmentButton.isHidden {
                make.leading.equalToSuperview().offset(textViewPadding)
            } else {
                var offset = textView.textContainer.lineFragmentPadding
                
                if let borderWidth = style.states[.active]?.borderWidth, borderWidth > 0 {
                    offset += borderWidth
                }
                
                make.leading.equalTo(attachmentButton.snp.trailing).offset(-offset)
            }
        }
        
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Blurred background.
        if style.backgroundColor == .clear {
            addBlurredBackground(blurEffectStyle: style.textColor.isDark ? .extraLight : .dark)
        }
        
        // Add placeholder.
        self.placeholderText = style.placeholderText
        placeholderLabel.textColor = style.placeholderTextColor
        
        // Send to the channel button.
        if showAlsoSendToChannelButton, let replyInChannelViewStyle = style.replyInChannelViewStyle {
            view.addSubview(alsoSendToChannelButton)
            alsoSendToChannelButton.isHidden = true
            alsoSendToChannelButton.isSelected = true
            alsoSendToChannelButton.backgroundColor = style.backgroundColor
            toggleAlsoSendToChannelButton()
            
            alsoSendToChannelButton.snp.makeConstraints { make in
                make.top.equalTo(snp.bottom).offset(replyInChannelViewStyle.edgeInsets.top)
                make.leading.equalTo(snp.leading).offset(replyInChannelViewStyle.edgeInsets.left)
                make.height.equalTo(replyInChannelViewStyle.height)
            }
            
            alsoSendToChannelButton.rx.tap
                .subscribe(onNext: { [weak self] in self?.toggleAlsoSendToChannelButton() })
                .disposed(by: disposeBag)
        }
        
        updateToolbarIfNeeded()
        styleState = .normal
    }
    
    /// Reset states of all child views and clear all added/generated data.
    func reset() {
        styleState = .normal
        previousTextBeforeReset = textView.attributedText
        textView.attributedText = attributedText()
        uploadManager?.reset()
        updatePlaceholder()
        filesStackView.isHidden = true
        filesStackView.removeAllArrangedSubviews()
        updateImagesCollectionView()
        styleState = textView.isFirstResponder ? .active : .normal
        
        if alsoSendToChannelButton.superview != nil {
            alsoSendToChannelButton.isHidden = true
            alsoSendToChannelButton.isSelected = true
            toggleAlsoSendToChannelButton()
        }
    }
    
    /// Update the placeholder and send button visibility.
    func updatePlaceholder() {
        placeholderLabel.isHidden = textView.attributedText.length != 0
        DispatchQueue.main.async { [weak self] in self?.updateSendButton() }
    }
    
    func updateSendButton() {
        guard let style = style else {
            return
        }
        
        let anyUploadedItem = uploadManager?.images.first(where: { $0.attachment != nil })
            ?? uploadManager?.files.first(where: { $0.attachment != nil })
        
        let isHidden = text.isEmpty && anyUploadedItem == nil
        
        if style.sendButtonVisibility == .whenActive {
            sendButton.isHidden = isHidden
        } else {
            sendButton.isEnabled = !isHidden
        }
        
        sendButtonVisibilityBehaviorSubject.onNext((sendButton.isHidden, sendButton.isEnabled))
    }
    
    internal func updateStyleState() {
        guard styleState != .disabled else {
            return
        }
        
        let styleState: ComposerViewStyle.State = !textView.isFirstResponder
            && (uploadManager?.images.isEmpty ?? true)
            && (uploadManager?.files.isEmpty ?? true)
            && text.isEmpty ? .normal : (self.styleState == .edit ? .edit : .active)
        
        if self.styleState != styleState {
            self.styleState = styleState
        }
    }
    
    private func update(for styleState: ComposerViewStyle.State) {
        guard let style = style else {
            return
        }
        
        let styleForCurrentState = style.style(with: styleState)
        layer.borderWidth = styleForCurrentState.borderWidth
        layer.borderColor = styleForCurrentState.tintColor.cgColor
        textView.tintColor = styleForCurrentState.tintColor
        sendButton.tintColor = styleForCurrentState.tintColor
        attachmentButton.tintColor = styleForCurrentState.tintColor
        
        if styleState == .edit {
            sendButton.setTitleColor(styleForCurrentState.tintColor, for: .normal)
        } else if styleState == .active {
            sendButton.setTitleColor(styleForCurrentState.tintColor, for: .normal)
        }
    }
    
    private func toggleAlsoSendToChannelButton() {
        guard let replyInChannelViewStyle = style?.replyInChannelViewStyle, !replyInChannelViewStyle.text.isEmpty else {
            return
        }
        
        alsoSendToChannelButton.isSelected.toggle()
        
        let checkmarkFont: UIFont = alsoSendToChannelButton.isSelected ? .systemFont(ofSize: 15) : .systemFont(ofSize: 16)
        
        let textColor = alsoSendToChannelButton.isSelected
            ? replyInChannelViewStyle.selectedColor
            : replyInChannelViewStyle.color
        
        let title = NSMutableAttributedString(string: alsoSendToChannelButton.isSelected ? "☑︎" : "☐",
                                              attributes: [.font: checkmarkFont, .foregroundColor: textColor])
        
        title.append(NSAttributedString(string: " " + replyInChannelViewStyle.text,
                                        attributes: [.font: replyInChannelViewStyle.font, .foregroundColor: textColor]))
        
        alsoSendToChannelButton.setAttributedTitle(title, for: .normal)
    }
}

// MARK: - Send Button Customization

extension ComposerView {
    
    /// Replace send button image with a new image.
    ///
    /// - Parameters:
    ///   - image: a new send button image.
    ///   - buttonWidth: update the button width (optional).
    public func setSendButtonImage(_ image: UIImage, buttonWidth: CGFloat? = nil) {
        sendButton.setImage(image, for: .normal)
        
        if let buttonWidth = buttonWidth {
            sendButtonWidthConstraint?.update(offset: max(buttonWidth, image.size.width))
        }
    }
    
    /// Replace send button image with a title.
    ///
    /// - Parameters:
    ///   - title: a send button title
    ///   - rightEdgeOffset: a right edge inset for the title (optional).
    public func setSendButtonTitle(_ title: String, rightEdgeOffset: CGFloat = .messageEdgePadding) {
        sendButton.setImage(nil, for: .normal)
        sendButton.setTitle(title, for: .normal)
        sendButtonWidthConstraint?.deactivate()
        sendButtonWidthConstraint = nil
        sendButtonRightConstraint?.update(offset: -rightEdgeOffset)
    }
}

// MARK: - Blurred Background

private extension ComposerView {
    func addBlurredBackground(blurEffectStyle: UIBlurEffect.Style) {
        let isDark = blurEffectStyle == .dark
        let blurEffect: UIBlurEffect
        
        if #available(iOS 13, *) {
            blurEffect = UIBlurEffect(style: .systemThinMaterial)
        } else {
            if UIAccessibility.isReduceTransparencyEnabled {
                backgroundColor = isDark ? .chatDarkGray : .chatComposer
                return
            }
            
            blurEffect = UIBlurEffect(style: blurEffectStyle)
        }
        
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.isUserInteractionEnabled = false
        insertSubview(blurView, at: 0)
        blurView.makeEdgesEqualToSuperview()
        
        // Adjust the blur effect for iOS 12 and below.
        if #available(iOS 13, *) {} else {
            let adjustingView = UIView(frame: .zero)
            adjustingView.isUserInteractionEnabled = false
            adjustingView.backgroundColor = .init(white: isDark ? 1 : 0, alpha: isDark ? 0.25 : 0.1)
            insertSubview(adjustingView, at: 0)
            adjustingView.makeEdgesEqualToSuperview()
        }
    }
}
