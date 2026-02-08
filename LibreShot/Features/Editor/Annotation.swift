import SwiftUI

enum AnnotationType: String, CaseIterable, Identifiable {
    case pen
    case rectangle
    case arrow
    case mosaic
    case blur
    
    var id: String { self.rawValue }
    
    var iconName: String {
        switch self {
        case .pen: return "pencil"
        case .rectangle: return "square"
        case .arrow: return "arrow.up.right"
        case .mosaic: return "square.grid.3x3"
        case .blur: return "drop"
        }
    }
}

struct Annotation: Identifiable {
    let id = UUID()
    var type: AnnotationType
    var color: Color
    var points: [CGPoint] = [] // For pen
    var startPoint: CGPoint = .zero // For shapes
    var endPoint: CGPoint = .zero // For shapes
    var lineWidth: CGFloat = 3.0
}
