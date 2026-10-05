import SwiftUI

/// Mockup colours for the Theme Sync artboard: the sample wallpaper and the plain "before" widget.
/// Public so the Aesthetic feature and the DEBUG Design Gallery draw the same values. Lives outside
/// the gallery file because that file is DEBUG-only and Release builds use these too.
public enum ThemeSyncPaint {
    public static let eveningSea = Color(wxHex: 0x5B6C8F)
    public static let wallpaperSand = Color(wxHex: 0xEAD7B7)
    public static let beforeGround = Color(wxHex: 0xECECEC)
    public static let beforeField = Color(wxHex: 0xC9CBD1)
    public static let beforeCaption = Color(wxHex: 0x5F616B)
    public static let beforeValue = Color(wxHex: 0x1C1C1E)
}
