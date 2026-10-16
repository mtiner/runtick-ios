import SwiftUI

// Native vector paths copied from runtick-app custom wordmark SVGs.
struct RTWordmark: Shape {
    var chinese = false
    func path(in rect: CGRect) -> Path {
        let points = chinese ? Self.zh : Self.en
        let width: CGFloat = chinese ? 429 : 936
        let height: CGFloat = chinese ? 181 : 205
        let scale = min(rect.width / width, rect.height / height)
        let x = (rect.width - width * scale) / 2, y = (rect.height - height * scale) / 2
        var path = Path()
        for polygon in points {
            for (index, point) in polygon.enumerated() {
                let p = CGPoint(x: x + point.x * scale, y: y + point.y * scale)
                if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
        }
        return path
    }
    private static let en: [[CGPoint]] = [
        [CGPoint(x: 49, y: 8), CGPoint(x: 216, y: 8), CGPoint(x: 190, y: 105), CGPoint(x: 153, y: 124), CGPoint(x: 201, y: 181), CGPoint(x: 157, y: 181), CGPoint(x: 101, y: 113), CGPoint(x: 163, y: 80), CGPoint(x: 173, y: 45), CGPoint(x: 38, y: 45)],
        [CGPoint(x: 496, y: 8), CGPoint(x: 640, y: 8), CGPoint(x: 622, y: 45), CGPoint(x: 576, y: 45), CGPoint(x: 541, y: 174), CGPoint(x: 500, y: 197), CGPoint(x: 546, y: 45), CGPoint(x: 478, y: 45)],
        [CGPoint(x: 830, y: 24), CGPoint(x: 859, y: 24), CGPoint(x: 831, y: 120), CGPoint(x: 883, y: 80), CGPoint(x: 928, y: 80), CGPoint(x: 869, y: 126), CGPoint(x: 910, y: 181), CGPoint(x: 869, y: 181), CGPoint(x: 828, y: 128), CGPoint(x: 815, y: 171), CGPoint(x: 773, y: 192)],
        [CGPoint(x: 646, y: 46), CGPoint(x: 675, y: 46), CGPoint(x: 668, y: 71), CGPoint(x: 633, y: 80)],
        [CGPoint(x: 91, y: 69), CGPoint(x: 56, y: 168), CGPoint(x: 8, y: 196), CGPoint(x: 51, y: 81)],
        [CGPoint(x: 388, y: 80), CGPoint(x: 498, y: 80), CGPoint(x: 469, y: 181), CGPoint(x: 435, y: 181), CGPoint(x: 457, y: 108), CGPoint(x: 406, y: 108), CGPoint(x: 383, y: 181), CGPoint(x: 349, y: 181), CGPoint(x: 381, y: 84)],
        [CGPoint(x: 230, y: 80), CGPoint(x: 262, y: 80), CGPoint(x: 240, y: 149), CGPoint(x: 300, y: 149), CGPoint(x: 322, y: 80), CGPoint(x: 357, y: 80), CGPoint(x: 326, y: 181), CGPoint(x: 230, y: 181), CGPoint(x: 206, y: 156)],
        [CGPoint(x: 696, y: 80), CGPoint(x: 787, y: 80), CGPoint(x: 779, y: 108), CGPoint(x: 714, y: 108), CGPoint(x: 700, y: 152), CGPoint(x: 765, y: 152), CGPoint(x: 756, y: 181), CGPoint(x: 658, y: 181), CGPoint(x: 689, y: 84)],
        [CGPoint(x: 663, y: 85), CGPoint(x: 633, y: 181), CGPoint(x: 597, y: 181), CGPoint(x: 625, y: 99)]
    ]
    private static let zh: [[CGPoint]] = [
        [CGPoint(x: 302, y: 8), CGPoint(x: 323, y: 8), CGPoint(x: 321, y: 20), CGPoint(x: 357, y: 20), CGPoint(x: 345, y: 42), CGPoint(x: 307, y: 42), CGPoint(x: 281, y: 68), CGPoint(x: 297, y: 68), CGPoint(x: 310, y: 55), CGPoint(x: 336, y: 55), CGPoint(x: 261, y: 126), CGPoint(x: 235, y: 126), CGPoint(x: 275, y: 87), CGPoint(x: 249, y: 87), CGPoint(x: 253, y: 71), CGPoint(x: 281, y: 42), CGPoint(x: 257, y: 42), CGPoint(x: 265, y: 20), CGPoint(x: 299, y: 20)],
        [CGPoint(x: 81, y: 12), CGPoint(x: 101, y: 12), CGPoint(x: 80, y: 83), CGPoint(x: 98, y: 44), CGPoint(x: 107, y: 38), CGPoint(x: 116, y: 38), CGPoint(x: 100, y: 75), CGPoint(x: 88, y: 85), CGPoint(x: 78, y: 88), CGPoint(x: 83, y: 143), CGPoint(x: 66, y: 163), CGPoint(x: 63, y: 119), CGPoint(x: 39, y: 159), CGPoint(x: 8, y: 173), CGPoint(x: 56, y: 95)],
        [CGPoint(x: 137, y: 12), CGPoint(x: 155, y: 12), CGPoint(x: 150, y: 26), CGPoint(x: 177, y: 26), CGPoint(x: 160, y: 74), CGPoint(x: 120, y: 126), CGPoint(x: 97, y: 126), CGPoint(x: 109, y: 108), CGPoint(x: 118, y: 101), CGPoint(x: 110, y: 100), CGPoint(x: 107, y: 78), CGPoint(x: 124, y: 75), CGPoint(x: 125, y: 88), CGPoint(x: 136, y: 77), CGPoint(x: 130, y: 64), CGPoint(x: 128, y: 64), CGPoint(x: 127, y: 68), CGPoint(x: 107, y: 68)],
        [CGPoint(x: 205, y: 12), CGPoint(x: 214, y: 12), CGPoint(x: 205, y: 48), CGPoint(x: 228, y: 48), CGPoint(x: 224, y: 65), CGPoint(x: 201, y: 65), CGPoint(x: 197, y: 73), CGPoint(x: 210, y: 76), CGPoint(x: 208, y: 126), CGPoint(x: 186, y: 126), CGPoint(x: 189, y: 88), CGPoint(x: 163, y: 126), CGPoint(x: 141, y: 126), CGPoint(x: 174, y: 77), CGPoint(x: 177, y: 65), CGPoint(x: 171, y: 67), CGPoint(x: 167, y: 64), CGPoint(x: 178, y: 48), CGPoint(x: 185, y: 47), CGPoint(x: 193, y: 17)],
        [CGPoint(x: 398, y: 12), CGPoint(x: 421, y: 12), CGPoint(x: 381, y: 157), CGPoint(x: 365, y: 170), CGPoint(x: 328, y: 170), CGPoint(x: 337, y: 142), CGPoint(x: 360, y: 142)],
        [CGPoint(x: 220, y: 17), CGPoint(x: 236, y: 17), CGPoint(x: 231, y: 42), CGPoint(x: 216, y: 42)],
        [CGPoint(x: 363, y: 24), CGPoint(x: 384, y: 24), CGPoint(x: 353, y: 128), CGPoint(x: 331, y: 128)],
        [CGPoint(x: 50, y: 40), CGPoint(x: 66, y: 40), CGPoint(x: 54, y: 83), CGPoint(x: 46, y: 89), CGPoint(x: 35, y: 89)],
        [CGPoint(x: 142, y: 42), CGPoint(x: 136, y: 52), CGPoint(x: 145, y: 62), CGPoint(x: 153, y: 42)],
        [CGPoint(x: 307, y: 91), CGPoint(x: 333, y: 91), CGPoint(x: 298, y: 125), CGPoint(x: 306, y: 127), CGPoint(x: 320, y: 170), CGPoint(x: 298, y: 170), CGPoint(x: 286, y: 137), CGPoint(x: 246, y: 170), CGPoint(x: 218, y: 170)],
        [CGPoint(x: 96, y: 139), CGPoint(x: 105, y: 134), CGPoint(x: 120, y: 134), CGPoint(x: 101, y: 170), CGPoint(x: 77, y: 170)],
        [CGPoint(x: 124, y: 134), CGPoint(x: 144, y: 134), CGPoint(x: 138, y: 170), CGPoint(x: 118, y: 170)],
        [CGPoint(x: 152, y: 134), CGPoint(x: 172, y: 134), CGPoint(x: 162, y: 170), CGPoint(x: 143, y: 170)],
        [CGPoint(x: 181, y: 134), CGPoint(x: 201, y: 134), CGPoint(x: 195, y: 170), CGPoint(x: 174, y: 170)]
    ]
}
