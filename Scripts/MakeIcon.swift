#!/usr/bin/env swift
import AppKit

// L'icona di Limbo, disegnata in codice come nel resto della famiglia: carta
// di fondo, un notch d'inchiostro appeso in alto, e sotto la fila di cose in
// attesa. Nessun file binario da tenere in repo e da rifare a mano quando i
// colori cambiano.

let lato = 1024.0
let uscita = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

let carta = NSColor(red: 0.980, green: 0.968, blue: 0.941, alpha: 1)
let inchiostro = NSColor(red: 0.118, green: 0.169, blue: 0.227, alpha: 1)
let penna = NSColor(red: 0.184, green: 0.361, blue: 0.541, alpha: 1)

let immagine = NSImage(size: NSSize(width: lato, height: lato))
immagine.lockFocus()

// Fondo: il quadratone arrotondato di macOS, con il margine che Apple lascia.
let margine = lato * 0.09
let fondo = NSBezierPath(
    roundedRect: NSRect(x: margine, y: margine,
                        width: lato - margine * 2, height: lato - margine * 2),
    xRadius: lato * 0.22, yRadius: lato * 0.22)
carta.setFill()
fondo.fill()

// Il notch: un rettangolo d'inchiostro appeso al bordo alto, con i soli
// angoli bassi tondi. È la forma dell'app, quindi è l'icona.
let largoNotch = lato * 0.42
let altoNotch = lato * 0.15
let notch = NSBezierPath()
let sinistra = (lato - largoNotch) / 2
let alto = lato - margine
let basso = alto - altoNotch
let raggio = lato * 0.05
notch.move(to: NSPoint(x: sinistra, y: alto))
notch.line(to: NSPoint(x: sinistra, y: basso + raggio))
notch.appendArc(withCenter: NSPoint(x: sinistra + raggio, y: basso + raggio),
                radius: raggio, startAngle: 180, endAngle: 270)
notch.line(to: NSPoint(x: sinistra + largoNotch - raggio, y: basso))
notch.appendArc(withCenter: NSPoint(x: sinistra + largoNotch - raggio, y: basso + raggio),
                radius: raggio, startAngle: 270, endAngle: 360)
notch.line(to: NSPoint(x: sinistra + largoNotch, y: alto))
notch.close()
inchiostro.setFill()
notch.fill()

// Le tre cose in attesa sotto il notch: la fila di schede, che è la decisione
// forte dell'interfaccia (regola 7 del gusto) e quindi anche dell'icona.
let largoScheda = lato * 0.17
let altoScheda = lato * 0.21
let passo = largoScheda + lato * 0.035
let partenza = (lato - (passo * 3 - (passo - largoScheda))) / 2
let yScheda = lato * 0.30
for indice in 0..<3 {
    let x = partenza + Double(indice) * passo
    let scheda = NSBezierPath(
        roundedRect: NSRect(x: x, y: yScheda, width: largoScheda, height: altoScheda),
        xRadius: lato * 0.03, yRadius: lato * 0.03)
    // La scheda di mezzo è la penna: un accento solo, e marca una cosa sola.
    (indice == 1 ? penna : inchiostro.withAlphaComponent(0.22)).setFill()
    scheda.fill()
}

immagine.unlockFocus()

guard let tiff = immagine.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("non sono riuscito a disegnare l'icona\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: uscita))
print(uscita)
