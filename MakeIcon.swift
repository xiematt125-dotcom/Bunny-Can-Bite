import AppKit

let destination = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
func render(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 215, yRadius: 215)
    NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
    tile.fill()
    NSGradient(starting: NSColor(calibratedWhite: 1, alpha: 1), ending: NSColor(calibratedRed: 0.86, green: 0.91, blue: 0.96, alpha: 1))!.draw(in: tile, angle: -90)
    let outer = NSBezierPath(ovalIn: NSRect(x: 213, y: 213, width: 598, height: 598))
    outer.lineWidth = 69
    NSColor(calibratedRed: 0.78, green: 0.85, blue: 0.92, alpha: 1).setStroke()
    outer.stroke()
    let ring = NSBezierPath()
    ring.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 299, startAngle: 90, endAngle: -185, clockwise: true)
    ring.lineWidth = 69
    ring.lineCapStyle = .round
    NSColor(calibratedRed: 0.08, green: 0.47, blue: 0.94, alpha: 1).setStroke()
    ring.stroke()
    let chip = NSBezierPath(roundedRect: NSRect(x: 375, y: 397, width: 274, height: 230), xRadius: 47, yRadius: 47)
    NSColor(calibratedRed: 0.14, green: 0.22, blue: 0.31, alpha: 1).setFill()
    chip.fill()
    NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.9, alpha: 1).setStroke()
    for offset in stride(from: CGFloat(425), through: CGFloat(605), by: 60) {
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x: offset, y: 364)); pin.line(to: NSPoint(x: offset, y: 390))
        pin.move(to: NSPoint(x: offset, y: 634)); pin.line(to: NSPoint(x: offset, y: 660))
        pin.lineWidth = 17; pin.lineCapStyle = .round; pin.stroke()
    }
    for offset in [CGFloat(447), CGFloat(512), CGFloat(577)] {
        let pin = NSBezierPath()
        pin.move(to: NSPoint(x: 342, y: offset)); pin.line(to: NSPoint(x: 368, y: offset))
        pin.move(to: NSPoint(x: 656, y: offset)); pin.line(to: NSPoint(x: 682, y: offset))
        pin.lineWidth = 17; pin.lineCapStyle = .round; pin.stroke()
    }
    let center = NSBezierPath(roundedRect: NSRect(x: 438, y: 460, width: 148, height: 104), xRadius: 16, yRadius: 16)
    NSColor(calibratedRed: 0.45, green: 0.72, blue: 1, alpha: 1).setFill()
    center.fill()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}
for dimension in [16,32,128,256,512] {
    try render(size: dimension).write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(dimension)x\(dimension).png"))
    try render(size: dimension * 2).write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(dimension)x\(dimension)@2x.png"))
}
