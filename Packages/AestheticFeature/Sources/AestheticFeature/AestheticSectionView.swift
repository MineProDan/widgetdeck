import AestheticFeatureWidgetKit
import CoreKit
import DesignSystem
import PhotosUI
import SwiftUI
import UIKit

/// Root view of the Aesthetic section: Theme Sync (A-02, ThemeSync artboard) and the Photo widget (A-01).
///
/// Both pickers use `PhotosPicker`, which runs out of process: no photo-library permission is asked.
public struct AestheticSectionView: View {
    @State private var store: AestheticStore
    @State private var isPickingWallpaper = false
    @State private var wallpaperItem: PhotosPickerItem?
    @State private var isPickingPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isPickingBoard = false
    @State private var boardItems: [PhotosPickerItem] = []
    @Environment(\.displayScale) private var displayScale

    public init(store: AestheticStore) {
        _store = State(initialValue: store)
    }

    /// Standalone use (previews, or before the app wires a store): no Core Data persistence.
    public init() {
        self.init(store: AestheticStore())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ThemeSyncPanel(store: store, pickWallpaper: { isPickingWallpaper = true })
            PhotoWidgetPanel(store: store, addPhotos: { isPickingPhotos = true })
                .padding(.top, 36)
            MoodBoardPanel(store: store, addPhotos: { isPickingBoard = true })
                .padding(.top, 36)
            WidgetStylePanel(store: store)
                .padding(.top, 36)
        }
        .task { await store.load() }
        .photosPicker(isPresented: $isPickingWallpaper, selection: $wallpaperItem, matching: .images,
                      preferredItemEncoding: .current)
        .photosPicker(isPresented: $isPickingPhotos, selection: $photoItems,
                      maxSelectionCount: max(1, PhotoLibrary.maxPhotos - store.photos.count),
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: wallpaperItem) { _, item in
            guard let item else { return }
            wallpaperItem = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    store.errorMessage = "That photo couldn't be opened. Try another one."
                    return
                }
                await store.pickWallpaper(data)
            }
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            let scale = displayScale
            let screen = Self.screenSize
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                if datas.count < items.count { store.errorMessage = "Some photos couldn't be opened." }
                await store.importPhotos(datas, screen: screen, scale: scale)
            }
        }
        .photosPicker(isPresented: $isPickingBoard, selection: $boardItems,
                      maxSelectionCount: max(1, MoodBoardLibrary.maxPhotos - store.moodBoard.count),
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .onChange(of: boardItems) { _, items in
            guard !items.isEmpty else { return }
            boardItems = []
            let scale = displayScale
            let screen = Self.screenSize
            Task {
                var datas: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
                }
                if datas.count < items.count { store.errorMessage = "Some photos couldn't be opened." }
                await store.importMoodBoardPhotos(datas, screen: screen, scale: scale)
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { store.errorMessage != nil },
                                                            set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    /// Portrait screen size in points (for exact widget pixel sizes).
    private static var screenSize: CGSize {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.screen.bounds.size ?? CGSize(width: 390, height: 844)
    }
}

// MARK: - Theme Sync

private struct ThemeSyncPanel: View {
    let store: AestheticStore
    let pickWallpaper: () -> Void

    var body: some View {
        if let palette = store.palette {
            synced(palette)
        } else {
            empty
        }
    }

    // Before a wallpaper is picked: explain why we need the photo (apps can't read the wallpaper).
    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Button(action: pickWallpaper) {
                    PaintChip(color: WXSection.aesthetic.color, field: .fixed(130), cornerRadius: WXRadius.card) {
                        if store.syncPhase == .extracting { ProgressView().tint(WXColor.ink) }
                    } label: {
                        ChipLabelBand(caption: "Wallpaper", value: "Pick", valueSize: 18)
                    }
                    .frame(width: 112, height: 206)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pick your wallpaper photo")

                VStack(alignment: .leading, spacing: 10) {
                    Text("Start with your wallpaper").wxGrotesk(22)
                    Text("Apps can't see your wallpaper. Pick the same photo from your library and Theme Sync reads its five colours.")
                        .wxBody(15)
                        .fixedSize(horizontal: false, vertical: true)
                    if case let .failed(message) = store.syncPhase {
                        Text(message).wxLabel(color: WXColor.clayLink)
                    }
                }
            }
            WXPrimaryButton(store.syncPhase == .extracting ? "Reading colours…" : "Pick my wallpaper", height: 52,
                            action: pickWallpaper)
                .disabled(store.syncPhase == .extracting)
                .padding(.top, 22)
        }
    }

    private func synced(_ palette: ExtractedPalette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Button(action: pickWallpaper) {
                    wallpaperThumbnail
                        .frame(width: 112, height: 206)
                        .wxRounded(WXRadius.card)
                        .wxShadow(.photo, cornerRadius: WXRadius.card)
                        .overlay {
                            if store.syncPhase == .extracting { ProgressView().tint(WXColor.labelIvory) }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Your wallpaper photo")
                .accessibilityHint("Pick a different photo")

                VStack(alignment: .leading) {
                    ForEach(Array(palette.rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Spacer(minLength: 6) }
                        SwatchRow(color: row.color.color.swiftUIColor, role: row.role, name: row.color.name)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)

            if case let .failed(message) = store.syncPhase {
                Text(message).wxLabel(color: WXColor.clayLink).padding(.top, 10)
            }

            WXSectionHeader("Before · after", accessory: "\(Int((store.comparePosition * 100).rounded()))% before",
                            accessoryColor: WXColor.inkSecondary)
                .monospacedDigit()
                .padding(.top, 20)

            CompareWell(palette: palette, before: store.comparePosition)
                .padding(.top, 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Drag to compare").wxLabel()
                WXSlider(value: Binding(get: { store.comparePosition }, set: { store.comparePosition = $0 }),
                         label: "Drag to compare")
            }
            .padding(.top, 10)

            HStack(spacing: 10) {
                WXPrimaryButton(applyTitle, height: 52) {
                    Task { await store.applyPalette() }
                }
                .disabled(!store.hasUnappliedPalette || store.isApplying)
                .opacity(store.hasUnappliedPalette ? 1 : 0.55)
                if palette.contrastChecked {
                    Text("Contrast checked · AA").wxLabel(color: WXColor.mossPositive).frame(width: 76, alignment: .leading)
                }
            }
            .padding(.top, 22)
        }
    }

    @ViewBuilder
    private var wallpaperThumbnail: some View {
        if let wallpaper = store.wallpaper {
            Image(uiImage: wallpaper).resizable().scaledToFill()
        } else {
            WXColor.beachSand
        }
    }

    private var applyTitle: String {
        if store.isApplying { return "Applying…" }
        if !store.hasUnappliedPalette { return "Applied" }
        if let count = store.installedWidgetCount, count > 0 {
            return count == 1 ? "Apply to 1 widget" : "Apply to \(count) widgets"
        }
        return "Apply to my widgets"
    }
}

/// Before/after well: the themed chips, with the generic un-themed look masked over the left
/// (ThemeSync artboard).
private struct CompareWell: View {
    let palette: ExtractedPalette
    let before: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                pair(themed: true, width: proxy.size.width)
                pair(themed: false, width: proxy.size.width)
                    .background(ThemeSyncPaint.beforeGround)
                    .frame(width: proxy.size.width * before, alignment: .leading)
                    .clipped()
                    .overlay(alignment: .trailing) { WXColor.ink.frame(width: 2) }
            }
        }
        .frame(height: 184)
        .background(WXColor.compareGround)
        .wxRounded(WXRadius.card)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of your widgets in \(palette.name)")
    }

    private func pair(themed: Bool, width: CGFloat) -> some View {
        let chipWidth = (width - 24 - 14) / 2
        return HStack(spacing: 14) {
            previewChip(themed: themed, color: palette.accent, before: "Next class", value: "BIO 201", width: chipWidth)
            previewChip(themed: themed, color: palette.primary, before: "Battery", value: "82%", width: chipWidth)
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func previewChip(themed: Bool, color: NamedColor, before: String, value: String, width: CGFloat) -> some View {
        if themed {
            PaintChip(color: color.color.swiftUIColor, field: .fixed(92), cornerRadius: 18, shadow: .preview) {
                ChipLabelBand(caption: color.name, value: value, captionSize: 10, valueSize: 18,
                              padding: EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12), alignment: .topLeading)
            }
            .frame(width: width, height: 160)
        } else {
            // The generic, un-themed widget look Theme Sync replaces (mockup "before" state).
            VStack(alignment: .leading, spacing: 0) {
                ThemeSyncPaint.beforeField.frame(height: 92)
                VStack(alignment: .leading, spacing: 4) {
                    Text(before.uppercased()).font(.system(size: 11)).foregroundStyle(ThemeSyncPaint.beforeCaption)
                    Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(ThemeSyncPaint.beforeValue)
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                Spacer(minLength: 0)
            }
            .frame(width: width, height: 160)
            .background(Color.white)
            .wxRounded(18)
        }
    }
}

// MARK: - Photo widget

private struct PhotoWidgetPanel: View {
    let store: AestheticStore
    let addPhotos: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 10)]

    var body: some View {
        // Empty sections already show an "Add photos" button, so the header link only appears once there are photos.
        let showsAddLink = !store.photos.isEmpty && store.photos.count < PhotoLibrary.maxPhotos
        return VStack(alignment: .leading, spacing: 14) {
            WXSectionHeader("Photo widget", accessory: showsAddLink ? "Add photos" : nil,
                            action: showsAddLink ? addPhotos : nil)

            if store.photos.isEmpty {
                Text("Pick up to \(PhotoLibrary.maxPhotos) photos. The widget shows one at a time and moves to the next each day or hour.")
                    .wxBody(15)
                    .fixedSize(horizontal: false, vertical: true)
                WXPillButton("Add photos", action: addPhotos)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(store.photos) { item in
                        thumbnail(item)
                    }
                }
                HStack {
                    Text("Changes").wxLabel()
                    Spacer()
                    WXSegmentedControl(selection: Binding(get: { store.rotation },
                                                          set: { (value: PhotoRotation) in Task { @MainActor in await store.setRotation(value) } }),
                                       options: PhotoRotation.allCases.map { ($0, $0.title) })
                        .frame(width: 200)
                }
                Text("\(store.photos.count) of \(PhotoLibrary.maxPhotos) · touch and hold a photo to remove it")
                    .wxLabel()
            }
            if store.isImporting {
                ProgressView("Adding photos…").font(WXFont.body(15)).tint(WXColor.ink)
            }
        }
    }

    private func thumbnail(_ item: PhotoItem) -> some View {
        let isCurrent = store.currentPhoto()?.id == item.id
        return Group {
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
        .overlay {
            RoundedRectangle(cornerRadius: WXRadius.swatch, style: .continuous)
                .strokeBorder(WXColor.ink, lineWidth: isCurrent ? 2 : 0)
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await store.removePhoto(item) }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isCurrent ? "Photo, on the widget now" : "Photo")
        .accessibilityAction(named: Text("Remove")) { Task { @MainActor in await store.removePhoto(item) } }
    }
}

#Preview {
    ScrollView {
        AestheticSectionView().padding(.horizontal, WXSpace.gutter)
    }
    .background(WXColor.paperIvory)
}
