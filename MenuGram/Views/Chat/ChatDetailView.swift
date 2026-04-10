import SwiftUI
import UniformTypeIdentifiers
import TDLibKit

struct ChatDetailView: View {
    @Environment(TelegramService.self) private var telegram
    @State private var isDropTargeted = false
    @State private var isPinned = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if telegram.isLoadingOlderMessages {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }

                    ForEach(telegram.currentChatMessages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .onAppear {
                                if message.id == telegram.currentChatMessages.first?.id,
                                   telegram.didInitialLoad,
                                   telegram.hasOlderMessages,
                                   !telegram.isLoadingOlderMessages {
                                    Task { await telegram.loadOlderMessages() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .background(ScrollViewConfigurator())
            .defaultScrollAnchor(.bottom)
            .onChange(of: telegram.currentChatMessages.last?.id) { oldId, newId in
                if let id = newId, newId != oldId {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }
        }
        .safeAreaBar(edge: .top) {
            header
                .glassEffect(in: .rect(cornerRadii: .init(topLeading: 16, bottomLeading: 0, bottomTrailing: 0, topTrailing: 16)))
        }
        .safeAreaBar(edge: .bottom) {
            chatInputView
                .glassEffect(in: .rect(cornerRadii: .init(topLeading: 0, bottomLeading: 16, bottomTrailing: 16, topTrailing: 0)))
        }
        .overlay {
            if telegram.isLoadingMessages {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(RoundedRectangle(cornerRadius: 12).fill(.blue.opacity(0.08)))
                    .padding(8)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.arrow.down")
                                .font(.largeTitle)
                                .foregroundStyle(.blue)
                            Text("Drop image to send")
                                .font(.headline)
                                .foregroundStyle(.blue)
                        }
                    }
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            ImageDropTarget(isTargeted: $isDropTargeted) { urls in
                handleDroppedFiles(urls)
            }
        }
        .background(PanelPinner(isPinned: isPinned))
    }
    
    private var header: some View {
        HStack {
            if let photoPath = currentChat?.photoLocalPath,
               let nsImage = NSImage(contentsOfFile: photoPath) {
                ZStack {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .blur(radius: 5)
                        .opacity(0.3)
                        .offset(y: 4)
                    
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                }
            } else {
                Circle()
                    .fill(.blue.gradient)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Text(String(currentChatTitle.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(currentChatTitle)
                    .font(.headline)

                if let actionText = chatActionText {
                    ShimmerText(actionText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer()

            Button {
                isPinned.toggle()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isPinned ? .blue : .secondary)
                    .rotationEffect(.degrees(isPinned ? 0 : 45))
                    .animation(.snappy, value: isPinned)
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "Unpin window" : "Pin window on top")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
    
    private var chatInputView: some View {
        MessageInputView()
            .padding(8)
    }

    private func handleDroppedFiles(_ urls: [URL]) {
        guard let chatId = telegram.currentChatId else { return }
        for url in urls {
            Task {
                await telegram.sendPhoto(chatId: chatId, filePath: url.path)
            }
        }
    }

    private var currentChat: ChatItem? {
        guard let chatId = telegram.currentChatId else { return nil }
        return telegram.chats.first(where: { $0.id == chatId })
    }

    private var currentChatTitle: String {
        currentChat?.title ?? "Chat"
    }

    private var chatActionText: String? {
        guard let action = telegram.currentChatAction else { return nil }
        switch action {
        case .chatActionTyping:
            return "typing..."
        case .chatActionRecordingVoiceNote:
            return "recording voice..."
        case .chatActionUploadingVoiceNote:
            return "sending voice..."
        case .chatActionRecordingVideo:
            return "recording video..."
        case .chatActionUploadingVideo:
            return "sending video..."
        case .chatActionUploadingPhoto:
            return "sending photo..."
        case .chatActionUploadingDocument:
            return "sending file..."
        case .chatActionChoosingSticker:
            return "choosing sticker..."
        case .chatActionRecordingVideoNote:
            return "recording video message..."
        case .chatActionUploadingVideoNote:
            return "sending video message..."
        case .chatActionChoosingLocation:
            return "choosing location..."
        case .chatActionChoosingContact:
            return "choosing contact..."
        default:
            return nil
        }
    }
}
// MARK: - Shimmer Text
public struct ShimmerText: View {
    let text: String
    var color: Color = .blue
    var font: Font = .caption
    var duration: Double = 1.5
    var shimmerWidth: CGFloat = 0.5

    @State private var offset: CGFloat = -1

    public init(
        _ text: String,
        color: Color = .blue,
        font: Font = .caption,
        duration: Double = 1.5,
        shimmerWidth: CGFloat = 0.5
    ) {
        self.text = text
        self.color = color
        self.font = font
        self.duration = duration
        self.shimmerWidth = shimmerWidth
    }

    public var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color.opacity(0.4))
            .overlay {
                GeometryReader { geo in
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .mask {
                            LinearGradient(
                                colors: [.clear, .white, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: geo.size.width * shimmerWidth)
                            .offset(x: offset * geo.size.width)
                        }
                }
            }
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    offset = 1.5
                }
            }
    }

    public func shimmerColor(_ color: Color) -> ShimmerText {
        var copy = self
        copy.color = color
        return copy
    }

    public func shimmerFont(_ font: Font) -> ShimmerText {
        var copy = self
        copy.font = font
        return copy
    }

    public func shimmerDuration(_ duration: Double) -> ShimmerText {
        var copy = self
        copy.duration = duration
        return copy
    }

    public func shimmerWidth(_ fraction: CGFloat) -> ShimmerText {
        var copy = self
        copy.shimmerWidth = fraction
        return copy
    }
}

// MARK: - ScrollView Configurator
/// Forces the backing NSScrollView to hide its scrollers at the AppKit level.
/// Needed because `.scrollIndicators(.hidden)` doesn't reliably suppress
/// macOS overlay scrollers.
private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
          DispatchQueue.main.async {
            guard let scrollView = view.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - AppKit Drop Target
/// AppKit-level drag-and-drop handler that works reliably on MenuBarExtra panels.
private struct ImageDropTarget: NSViewRepresentable {
    @Binding var isTargeted: Bool
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropReceivingView {
        let view = DropReceivingView()
        view.onTargetChanged = { targeted in
            DispatchQueue.main.async { isTargeted = targeted }
        }
        view.onDrop = { urls in
            DispatchQueue.main.async {
                isTargeted = false
                onDrop(urls)
            }
        }
        return view
    }

    func updateNSView(_ nsView: DropReceivingView, context: Context) {}
}

/// NSView subclass that registers as a dragging destination for image file types.
final class DropReceivingView: NSView {
    var onTargetChanged: ((Bool) -> Void)?
    var onDrop: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Return nil so clicks and scrolls pass through to the SwiftUI views underneath.
    /// Drag operations bypass hitTest and still reach this view via registerForDraggedTypes.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasImageURLs(sender) else { return [] }
        onTargetChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard hasImageURLs(sender) else { return [] }
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onTargetChanged?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let urls = imageURLs(from: sender), !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    private func hasImageURLs(_ info: NSDraggingInfo) -> Bool {
        guard let urls = imageURLs(from: info) else { return false }
        return !urls.isEmpty
    }

    private func imageURLs(from info: NSDraggingInfo) -> [URL]? {
        let validExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"]
        let pasteboard = info.draggingPasteboard
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return nil }
        return urls.filter { validExtensions.contains($0.pathExtension.lowercased()) }
    }
}

// MARK: - Panel Pin Flag

private nonisolated(unsafe) var pinnedFlagKey: UInt8 = 0

private extension NSPanel {
    /// Per-instance flag read by the swizzled `orderOut:` to decide whether to block the hide.
    var isPinnedByMenuGram: Bool {
        get { objc_getAssociatedObject(self, &pinnedFlagKey) as? Bool ?? false }
        set { objc_setAssociatedObject(self, &pinnedFlagKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

// MARK: - Panel Pinner
/// Keeps the MenuBarExtra panel visible when pinned.
///
/// Strategy: swizzle `NSPanel.orderOut(_:)` so it becomes a no-op when
/// `isPinnedByMenuGram` is true. Because the original `orderOut:` never
/// executes, MenuBarExtra's internal toggle state stays perfectly in sync
/// — it still considers the panel "visible", so every subsequent menu-bar
/// click works correctly.
///
/// On unpin the flag is cleared and defaults restored. The panel stays
/// visible (user just clicked unpin, so the app is active). The next
/// click elsewhere triggers a normal hide through MenuBarExtra's own
/// code path, keeping everything consistent.
private struct PanelPinner: NSViewRepresentable {
    let isPinned: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let panel = nsView.window as? NSPanel else { return }
            context.coordinator.update(panel: panel, isPinned: isPinned)
        }
    }

    class Coordinator {
        private weak var panel: NSPanel?
        private var originalLevel: NSWindow.Level?

        func update(panel: NSPanel, isPinned: Bool) {
            if self.panel !== panel {
                self.panel = panel
                self.originalLevel = panel.level
            }

            OrderOutSwizzle.swizzleOnce()

            panel.isPinnedByMenuGram = isPinned
            panel.level = isPinned ? .floating : (originalLevel ?? panel.level)

            // Only ever turn hidesOnDeactivate OFF (safe).
            // Never turn it ON — doing so while the app isn't fully active
            // causes AppKit to immediately hide the panel.
            // The swizzle handles all hide/show logic for both states.
            if isPinned {
                panel.hidesOnDeactivate = false
            }
        }
    }
}

// MARK: - orderOut: Swizzle
/// One-time swizzle of `NSPanel.orderOut(_:)`.
/// When a panel's `isPinnedByMenuGram` flag is true the call is silently skipped.
/// All other panels (and our panel when unpinned) call the original implementation.
private enum OrderOutSwizzle {
    nonisolated(unsafe) static var done = false

    static func swizzleOnce() {
        guard !done else { return }
        done = true

        let sel = #selector(NSPanel.orderOut(_:))
        guard let method = class_getInstanceMethod(NSPanel.self, sel) else { return }

        typealias OrigFn = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
        let origIMP = method_getImplementation(method)
        let orig = unsafeBitCast(origIMP, to: OrigFn.self)

        let block: @convention(block) (AnyObject, AnyObject?) -> Void = { obj, sender in
            if let panel = obj as? NSPanel, panel.isPinnedByMenuGram { return }
            orig(obj, sel, sender)
        }

        method_setImplementation(method, imp_implementationWithBlock(block))
    }
}

#Preview {
    ChatDetailView()
}
