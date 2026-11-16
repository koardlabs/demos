import SwiftUI

/// A quiet, solid register background that adapts to light and dark appearance.
struct KoardBackgroundView: View {
    var body: some View { POSDesign.background.ignoresSafeArea() }
}

extension Color {
    static var koardCardSurface: Color { POSDesign.surface }
    static var koardKeySurface: Color { POSDesign.surface }
    static var koardHairline: Color { POSDesign.line }
}
