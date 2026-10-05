import AestheticFeatureWidgetKit
import CoreKit
import DesignSystem
import SwiftUI
import UIKit

// MARK: - Mood board (A-06)

/// Pick, reorder and remove the mood board's photos, with a live preview of the medium widget.
struct MoodBoardPanel: View {
    let store: AestheticStore
    let addPhotos: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    private var canAdd: Bool { !store.moodBoard.isEmpty && store.moodBoard.count < MoodBoardLibrary.maxPhotos }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WXSectionHeader("Mood board", accessory: canAdd ? "Add photos" : nil, action: canAdd ? addPhotos : nil)

            if store.moodBoard.isEmpty {
                Text("Pick up to \(MoodBoardLibrary.maxPhotos) photos. The medium widget shows four in a grid, the large one six or eight.")
                    .wxBody(15)
                    .fixedSize(horizontal: false, vertical: true)
                WXPillButton("Add photos", action: addPhotos)
            } else {
                preview
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Array(store.moodBoard.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, index: index)
                    }
                }
                HStack {
                    Text("Shuffle daily").wxLabel()
                    Spacer()
                    WXSegmentedControl(selection: Binding(get: { store.shuffleDaily },
                                                          set: { (value: Bool) in Task { @MainActor in await store.setShuffleDaily(value) } }),
                                       options: [(false, "Off"), (true, "On")])
                        .frame(width: 160)
                }
                Text("\(store.moodBoard.count) of \(MoodBoardLibrary.maxPhotos) · touch and hold a photo to move or remove it")
                    .wxLabel()
            }
        }
    }

    /// The medium widget's 2 × 2 grid as it looks today.
    private var preview: some View {
        let today = store.moodBoardToday()
        let layout = MoodBoardLayout.medium
        return GeometryReader { proxy in
            let frames = layout.tileFrames(in: proxy.size)
            ZStack(alignment: .topLeading) {
                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    Group {
                        if index < today.count, let image = store.thumbnail(for: today[index]) {
                            Color.clear.overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                        } else {
                            WXColor.rule
                        }
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipShape(RoundedRectangle(cornerRadius: store.styles.moodBoard.corners.radius, style: .continuous))
                    .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .aspectRatio(364.0 / 170.0, contentMode: .fit)
        .background(WXColor.labelIvory)
        .wxRounded(WXRadius.widget)
        .wxShadow(.preview, cornerRadius: WXRadius.widget)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the medium Mood board widget")
    }

    private func thumbnail(_ item: MoodBoardItem, index: Int) -> some View {
        Group {
            if let image = store.thumbnail(for: item) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                WXColor.rule
            }
        }
        .frame(minWidth: 72, maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .wxRounded(WXRadius.swatch)
        .contextMenu {
            if index > 0 {
                Button { Task { await store.moveMoodBoardPhoto(item, by: -1) } } label: { Label("Move earlier", systemImage: "arrow.left") }
            }
            if index < store.moodBoard.count - 1 {
                Button { Task { await store.moveMoodBoardPhoto(item, by: 1) } } label: { Label("Move later", systemImage: "arrow.right") }
            }
            Button(role: .destructive) { Task { await store.removeMoodBoardPhoto(item) } } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityElement()
        .accessibilityLabel("Mood board photo \(index + 1) of \(store.moodBoard.count)")
        .accessibilityAction(named: Text("Move earlier")) { Task { @MainActor in await store.moveMoodBoardPhoto(item, by: -1) } }
        .accessibilityAction(named: Text("Move later")) { Task { @MainActor in await store.moveMoodBoardPhoto(item, by: 1) } }
        .accessibilityAction(named: Text("Remove")) { Task { @MainActor in await store.removeMoodBoardPhoto(item) } }
    }
}

// MARK: - Borders and effects (A-07)

/// Per-widget border, corner and dim options. Flat paint only (no gradients, glass or blur).
struct WidgetStylePanel: View {
    let store: AestheticStore
    @State private var target: AestheticStyleTarget = .photo

    private var style: WidgetStyle { store.styles[target] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WXSectionHeader("Borders and effects")
            WXSegmentedControl(selection: $target, options: AestheticStyleTarget.allCases.map { ($0, $0.title) })

            row("Border") {
                WXSegmentedControl(selection: binding(\.border), options: [(false, "Off"), (true, "On")])
                    .frame(width: 160)
            }
            if style.border {
                Text("Border colour").wxLabel()
                colourRow
                row("Width") {
                    WXSegmentedControl(selection: binding(\.borderWidth),
                                       options: WidgetBorderWidth.allCases.map { ($0, $0.title) })
                        .frame(width: 240)
                }
            }
            if target != .palette {
                row("Corners") {
                    WXSegmentedControl(selection: binding(\.corners),
                                       options: WidgetCornerStyle.allCases.map { ($0, $0.title) })
                        .frame(width: 200)
                }
            }
            if target.supportsDim {
                row("Dim photos") {
                    WXSegmentedControl(selection: binding(\.dim), options: WidgetDim.allCases.map { ($0, $0.title) })
                        .frame(width: 240)
                }
            }
        }
    }

    private var colourRow: some View {
        let theme = ActiveThemeStore().read()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(WidgetBorderColor.allCases, id: \.self) { colour in
                    let selected = style.borderColor == colour
                    Button {
                        update { $0.borderColor = colour }
                    } label: {
                        RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                            .fill(colour.color(theme: theme))
                            .frame(width: 40, height: 40)
                            .overlay {
                                RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                                    .strokeBorder(selected ? WXColor.ink : WXColor.rule, lineWidth: selected ? 2.5 : 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(colour.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Text(title).wxLabel()
            Spacer()
            control()
        }
    }

    private func binding<Value: Hashable>(_ keyPath: WritableKeyPath<WidgetStyle, Value>) -> Binding<Value> {
        Binding(get: { style[keyPath: keyPath] }, set: { value in update { $0[keyPath: keyPath] = value } })
    }

    private func update(_ change: (inout WidgetStyle) -> Void) {
        var next = style
        change(&next)
        let target = target
        Task { @MainActor in await store.setStyle(next, for: target) }
    }
}
