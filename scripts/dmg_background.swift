import AppKit
import CoreGraphics
import Foundation

let outputPrefix = CommandLine.arguments.dropFirst().first ?? "/tmp/torec_dmg_bg"

func render(scale: Int) -> NSBitmapImageRep {
    let logicalWidth: CGFloat = 660
    let logicalHeight: CGFloat = 520
    let scaleFactor = CGFloat(scale)
    let physicalWidth = Int(logicalWidth * scaleFactor)
    let physicalHeight = Int(logicalHeight * scaleFactor)

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: physicalWidth,
        pixelsHigh: physicalHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let context = NSGraphicsContext.current!.cgContext
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    context.scaleBy(x: scaleFactor, y: scaleFactor)

    let background = CGGradient(
        colorSpace: colorSpace,
        colorComponents: [
            0.945, 0.945, 0.952, 1.0,
            0.912, 0.912, 0.924, 1.0
        ],
        locations: [0, 1],
        count: 2
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: logicalWidth / 2, y: logicalHeight),
        end: CGPoint(x: logicalWidth / 2, y: 0),
        options: []
    )

    let vignette = CGGradient(
        colorSpace: colorSpace,
        colorComponents: [
            0, 0, 0, 0.0,
            0, 0, 0, 0.045
        ],
        locations: [0, 1],
        count: 2
    )!
    context.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: logicalWidth / 2, y: logicalHeight / 2),
        startRadius: 0,
        endCenter: CGPoint(x: logicalWidth / 2, y: logicalHeight / 2),
        endRadius: logicalWidth * 0.8,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    let blueColor = CGColor(red: 0.20, green: 0.47, blue: 1.00, alpha: 1.0)
    let blueText = NSColor(red: 0.18, green: 0.44, blue: 1.00, alpha: 1.0)

    func dark(_ alpha: CGFloat) -> NSColor {
        NSColor(white: 0, alpha: alpha)
    }

    func paragraph() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = .left
        return style
    }

    func badge(_ number: String, centerX: CGFloat, centerY: CGFloat) {
        let radius: CGFloat = 14
        context.setFillColor(blueColor)
        context.fillEllipse(in: CGRect(x: centerX - radius, y: centerY - radius, width: radius * 2, height: radius * 2))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        NSAttributedString(
            string: number,
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style
            ]
        ).draw(in: CGRect(x: centerX - radius, y: centerY - 10, width: radius * 2, height: 20))
    }

    func divider(y: CGFloat) {
        context.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.10))
        context.setLineWidth(1 / scaleFactor)
        context.move(to: CGPoint(x: 32, y: y))
        context.addLine(to: CGPoint(x: logicalWidth - 32, y: y))
        context.strokePath()
    }

    badge("1", centerX: 46, centerY: 498)
    NSAttributedString(
        string: "Drag ToRec to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: dark(0.82),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 490, width: 460, height: 18))
    NSAttributedString(
        string: "Перетащи ToRec в Программы",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: dark(0.55),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 473, width: 460, height: 16))

    do {
        let arrowY: CGFloat = 412
        let startX: CGFloat = 248
        let endX: CGFloat = 412
        let headWidth: CGFloat = 18
        let headHeight: CGFloat = 22
        let shaftHalfHeight: CGFloat = 4.5
        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: arrowY + shaftHalfHeight))
        path.addLine(to: CGPoint(x: endX - headWidth, y: arrowY + shaftHalfHeight))
        path.addLine(to: CGPoint(x: endX - headWidth, y: arrowY + headHeight / 2))
        path.addLine(to: CGPoint(x: endX, y: arrowY))
        path.addLine(to: CGPoint(x: endX - headWidth, y: arrowY - headHeight / 2))
        path.addLine(to: CGPoint(x: endX - headWidth, y: arrowY - shaftHalfHeight))
        path.addLine(to: CGPoint(x: startX, y: arrowY - shaftHalfHeight))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(CGColor(red: 0.55, green: 0.55, blue: 0.60, alpha: 0.12))
        context.setStrokeColor(CGColor(red: 0.48, green: 0.48, blue: 0.54, alpha: 0.55))
        context.setLineWidth(1.5 / scaleFactor)
        context.setLineDash(phase: 0, lengths: [6, 3])
        context.drawPath(using: .fillStroke)
        context.setLineDash(phase: 0, lengths: [])
    }

    divider(y: 300)

    badge("2", centerX: 46, centerY: 272)
    NSAttributedString(
        string: "First launch: Finder -> Applications -> right-click ToRec -> Open",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: dark(0.82),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 264, width: 560, height: 18))
    NSAttributedString(
        string: "Первый запуск: Finder -> Программы -> правый клик ToRec -> Открыть",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: dark(0.55),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 247, width: 560, height: 16))

    divider(y: 214)

    badge("3", centerX: 46, centerY: 186)
    NSAttributedString(
        string: "If macOS blocks launch, click \"Done\"",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: dark(0.82),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 178, width: 540, height: 18))
    NSAttributedString(
        string: "Если macOS заблокирует запуск, нажми «Готово»",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: dark(0.55),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 161, width: 540, height: 16))

    divider(y: 128)

    badge("4", centerX: 46, centerY: 100)
    let englishStep4 = NSMutableAttributedString(
        string: "Scroll to Security -> click ",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: dark(0.82),
            .paragraphStyle: paragraph()
        ]
    )
    englishStep4.append(NSAttributedString(
        string: "\"Open Anyway\"",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: blueText,
            .paragraphStyle: paragraph()
        ]
    ))
    englishStep4.draw(in: CGRect(x: 70, y: 92, width: 540, height: 18))

    let russianStep4 = NSMutableAttributedString(
        string: "Прокрути до «Безопасность» -> нажми ",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: dark(0.55),
            .paragraphStyle: paragraph()
        ]
    )
    russianStep4.append(NSAttributedString(
        string: "«Все равно открыть»",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(red: 0.18, green: 0.44, blue: 1.0, alpha: 0.80),
            .paragraphStyle: paragraph()
        ]
    ))
    russianStep4.draw(in: CGRect(x: 70, y: 75, width: 540, height: 16))

    NSAttributedString(
        string: "One-time Gatekeeper step for the free unsigned test build  ·  Только один раз",
        attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: dark(0.25),
            .paragraphStyle: paragraph()
        ]
    ).draw(in: CGRect(x: 70, y: 46, width: 420, height: 12))

    return bitmap
}

let oneX = render(scale: 1)
let twoX = render(scale: 2)

let oneXURL = URL(fileURLWithPath: "\(outputPrefix)_1x.png")
let twoXURL = URL(fileURLWithPath: "\(outputPrefix)_2x.png")
try oneX.representation(using: .png, properties: [:])!.write(to: oneXURL)
try twoX.representation(using: .png, properties: [:])!.write(to: twoXURL)

print(oneXURL.path)
print(twoXURL.path)
