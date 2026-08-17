import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Volun sovelluskuvake: kirjaintunnus V.
//
// Kuvake on läpinäkymätön ja täyttää koko neliön — iOS pyöristää kulmat itse,
// ja alfakanava tai valmiiksi pyöristetty kuva hylätään latauksessa.
//
// V piirretään täytettynä muotona eikä vedettynä viivana, jotta vedoille voi
// antaa eri paksuudet. Tasapaksu V on geometrinen mutta eloton; oikeissa
// kirjaintyypeissä vasen diagonaali on paksu varsi ja oikea ohut.

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        colorSpace: space,
        components: [
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255,
            1,
        ]
    )!
}

func render(name: String, top: UInt32, bottom: UInt32) {
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("konteksti") }

    // Liuku on jatkettava molempiin suuntiin: vinolla akselilla pelkkä jana
    // jättää vastakkaiset kulmat maalaamatta, ja ne jäävät mustiksi.
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [color(top), color(bottom)] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: size * 0.15, y: size),
        end: CGPoint(x: size * 0.85, y: 0),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Mitat. Yläpäät leikataan vaakasuoraan, mikä on kirjaintyypin tapa —
    // vinoon leikattu pää näyttää siltä että kirjain on piirretty tussilla.
    let centre = size / 2
    let topY = 700.0          // ylälaita
    let apexOuter = 300.0     // kärjen alalaita
    let apexInner = 470.0     // kärjen ylälaita (muodon sisäreuna)
    let leftOuter = 296.0
    let rightOuter = size - leftOuter
    let leftWidth = 178.0     // paksu varsi
    let rightWidth = 116.0    // ohut veto
    let apexFlat = 16.0       // kärjen tasaus: terävä piikki särkyy pienessä koossa

    let path = CGMutablePath()
    path.move(to: CGPoint(x: leftOuter, y: topY))
    path.addLine(to: CGPoint(x: centre - apexFlat, y: apexOuter))
    path.addLine(to: CGPoint(x: centre + apexFlat, y: apexOuter))
    path.addLine(to: CGPoint(x: rightOuter, y: topY))
    path.addLine(to: CGPoint(x: rightOuter - rightWidth, y: topY))
    path.addLine(to: CGPoint(x: centre, y: apexInner))
    path.addLine(to: CGPoint(x: leftOuter + leftWidth, y: topY))
    path.closeSubpath()

    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(path)
    ctx.fillPath()

    guard let image = ctx.makeImage() else { fatalError("kuva") }
    let url = URL(fileURLWithPath: name) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("kohde")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// Käytössä oleva kuvake. Aja repon juuresta:
//   swift Tools/make-app-icon.swift
// ja tulos menee suoraan resurssiin.
render(
    name: "Volu/Assets.xcassets/AppIcon.appiconset/icon-1024.png",
    top: 0x2B3138,
    bottom: 0x0E1013
)
print("ok")
