import SwiftUI

// SF Symbols are centralized here so icon geometry stays native and no view
// substitutes text, Unicode glyphs, or emoji for interface icons.
enum VLMSnapperIcon: String {
    case extract = "text.alignleft"
    case translate = "character.book.closed"
    case language = "globe"
    case provider = "cpu"
    case close = "xmark"
    case copy = "doc.on.doc"
    case retry = "arrow.clockwise"
    case capture = "viewfinder"
    case permission = "rectangle.inset.filled.and.person.filled"
    case complete = "checkmark.circle.fill"
    case warning = "exclamationmark.triangle.fill"
    case key = "key.fill"
    case model = "cpu.fill"
    case info = "info.circle"
    case history = "clock.arrow.circlepath"
    case settings = "gearshape"
    case update = "arrow.down.circle"
    case quit = "power"
    case folder = "folder"

    var image: Image {
        Image(systemName: rawValue)
    }
}
