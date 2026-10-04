import SwiftUI

/// A letter strip on the trailing edge: touch or drag over it to jump between sections (user request, 2026-09-24).
/// VoiceOver sees one adjustable element: swipe up or down to move between letters.
struct SectionIndexBar: View {
    let letters: [String]
    let identifier: String
    let onSelect: (String) -> Void

    @State private var current: String?
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ForEach(letters, id: \.self) { letter in
                    Text(letter)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(letter == current && isDragging ? Palette.mochaButtonForeground : Palette.accent)
                        .frame(width: 20, height: rowHeight(in: proxy.size.height))
                        .background {
                            if letter == current && isDragging {
                                Circle().fill(Palette.mochaButtonBackground)
                            }
                        }
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in select(at: value.location.y, height: proxy.size.height) }
            )
        }
        .frame(width: 22)
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityElement()
        .accessibilityLabel(Text("sectionIndex.label"))
        .accessibilityValue(Text(current ?? letters.first ?? ""))
        .accessibilityAdjustableAction { direction in
            let index = current.flatMap(letters.firstIndex(of:)) ?? 0
            let next = direction == .increment ? min(index + 1, letters.count - 1) : max(index - 1, 0)
            jump(to: letters[next])
        }
        .accessibilityIdentifier(identifier)
    }

    /// Letters sit in the middle of the available height, at most 18 points apart.
    private func rowHeight(in height: CGFloat) -> CGFloat {
        guard !letters.isEmpty else { return 0 }
        return min(18, height / CGFloat(letters.count))
    }

    private func select(at y: CGFloat, height: CGFloat) {
        guard !letters.isEmpty else { return }
        let row = rowHeight(in: height)
        let top = (height - row * CGFloat(letters.count)) / 2
        let index = Int(((y - top) / row).rounded(.down))
        jump(to: letters[min(max(index, 0), letters.count - 1)])
    }

    private func jump(to letter: String) {
        guard letter != current else { return }
        current = letter
        onSelect(letter)
    }
}
