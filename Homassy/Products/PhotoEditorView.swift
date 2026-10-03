import HomassyCore
import SwiftUI
import UIKit

/// Crops a product photo to a square and rotates it in quarter turns (user request, 2026-09-24).
/// Pinch to zoom, drag to move; the square is what gets stored, at most 800 px (`ImageProcessor.crop`).
struct PhotoEditorView: View {
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var source: Data?
    @State private var image: UIImage?
    @State private var quarterTurns = 0
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var failed = false
    private let original: Data

    init(data: Data, onDone: @escaping (Data) -> Void) {
        original = data
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height) - 32
                ZStack {
                    Color.black.ignoresSafeArea()
                    if let image {
                        // Both are pinned to the screen: the zoomed photo is larger than it and must not size the stack.
                        photo(image, side: side)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                        cropMask(side: side, in: proxy.size)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    } else if failed {
                        ContentUnavailableView("photoEditor.failed", systemImage: "photo.badge.exclamationmark")
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(gestures(side: side))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        SheetCancelButton { dismiss() }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button { rotateLeft() } label: { Label("photoEditor.rotate", systemImage: "rotate.left") }
                            .accessibilityIdentifier("photoEditor.rotate")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        SheetConfirmButton(title: "photoEditor.done") { finish(side: side) }
                            .disabled(image == nil)
                            .accessibilityIdentifier("photoEditor.done")
                    }
                }
            }
            .navigationTitle("photoEditor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
        }
        .task { await load() }
    }

    // MARK: Geometry

    /// The photo's size after the quarter turns, in pixels.
    private func rotatedSize(_ image: UIImage) -> CGSize {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return quarterTurns % 2 == 0 ? size : CGSize(width: size.height, height: size.width)
    }

    /// Points per pixel: the photo fills the square at zoom 1.
    private func scale(for image: UIImage, side: CGFloat) -> CGFloat {
        let size = rotatedSize(image)
        return side / min(size.width, size.height) * zoom
    }

    private func photo(_ image: UIImage, side: CGFloat) -> some View {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = scale(for: image, side: side)
        return Image(uiImage: image)
            .resizable()
            .frame(width: pixelSize.width * scale, height: pixelSize.height * scale)
            .rotationEffect(.degrees(-90 * Double(quarterTurns)))
            .offset(offset)
            .accessibilityHidden(true)
    }

    private func cropMask(side: CGFloat, in size: CGSize) -> some View {
        let square = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
        return ZStack {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(square)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: side, height: side)
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Text("photoEditor.cropArea"))
        .accessibilityIdentifier("photoEditor.crop")
    }

    private func gestures(side: CGFloat) -> some Gesture {
        let magnify = MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), 6)
                offset = clamped(offset, side: side)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
            }
        let drag = DragGesture()
            .onChanged { value in
                offset = clamped(CGSize(width: committedOffset.width + value.translation.width,
                                        height: committedOffset.height + value.translation.height), side: side)
            }
            .onEnded { _ in committedOffset = offset }
        return SimultaneousGesture(magnify, drag)
    }

    /// Keeps the square inside the photo.
    private func clamped(_ proposed: CGSize, side: CGFloat) -> CGSize {
        guard let image else { return .zero }
        let size = rotatedSize(image)
        let scale = scale(for: image, side: side)
        let maxX = max((size.width * scale - side) / 2, 0)
        let maxY = max((size.height * scale - side) / 2, 0)
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }

    // MARK: Actions

    private func rotateLeft() {
        quarterTurns = (quarterTurns + 1) % 4
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }

    /// The square in unit coordinates of the rotated photo.
    private func cropRect(side: CGFloat) -> CGRect? {
        guard let image else { return nil }
        let size = rotatedSize(image)
        let scale = scale(for: image, side: side)
        let displayed = CGSize(width: size.width * scale, height: size.height * scale)
        let minX = (displayed.width - side) / 2 - offset.width
        let minY = (displayed.height - side) / 2 - offset.height
        return CGRect(x: minX / displayed.width, y: minY / displayed.height,
                      width: side / displayed.width, height: side / displayed.height)
    }

    private func finish(side: CGFloat) {
        guard let source, let rect = cropRect(side: side) else { return }
        let turns = quarterTurns
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                try? ImageProcessor.crop(source, to: rect, quarterTurns: turns)
            }.value
            if let result {
                onDone(result)
                dismiss()
            } else {
                failed = true
            }
        }
    }

    private func load() async {
        let original = original
        let editable = await Task.detached(priority: .userInitiated) { try? ImageProcessor.editable(original) }.value
        guard let editable, let decoded = UIImage(data: editable) else {
            failed = true
            return
        }
        source = editable
        image = decoded
    }
}
