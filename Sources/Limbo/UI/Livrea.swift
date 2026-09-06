import AppKit
import SwiftUI

// La livrea di famiglia (MacAppRules §0): carta, inchiostro, penna. Gli stessi
// tre colori delle app di casa, coi numeri copiati da quelle e non
// reinventati — un'app nuova parte da lì, non da una paletta inventata.
//
// Regola 15 del gusto: l'unica variazione ammessa fra giorno e notte è
// l'INVERSIONE fondo/segno. Colori dinamici (NSColor con provider), così
// seguono l'aspetto della finestra invece di essere decisi una volta all'avvio.
enum Livrea {
    static let nsCarta = NSColor(name: nil) { aspetto in
        scuro(aspetto)
            ? NSColor(red: 0.075, green: 0.102, blue: 0.137, alpha: 1) // notte
            : NSColor(red: 0.980, green: 0.968, blue: 0.941, alpha: 1) // carta
    }

    static let nsInchiostro = NSColor(name: nil) { aspetto in
        scuro(aspetto)
            ? NSColor(red: 0.949, green: 0.937, blue: 0.906, alpha: 1)
            : NSColor(red: 0.118, green: 0.169, blue: 0.227, alpha: 1)
    }

    /// La penna quando fa da SEGNO sopra la carta. Di notte si schiarisce, e
    /// il motivo è misurato in un'altra app di casa: il blu #2F5C8A rende 6,49:1 sulla carta
    /// chiara e crolla a 2,52:1 su quella scura, sotto il 3:1 che si chiede
    /// perfino a un titolone. La versione notturna torna a 5,92:1.
    static let nsPennaTesto = NSColor(name: nil) { aspetto in
        scuro(aspetto)
            ? NSColor(red: 0.42, green: 0.60, blue: 0.82, alpha: 1)
            : NSColor(red: 0.184, green: 0.361, blue: 0.541, alpha: 1)
    }

    static let carta = Color(nsColor: nsCarta)
    static let inchiostro = Color(nsColor: nsInchiostro)

    /// La penna come FONDO: sopra ci va testo bianco, quindi non si schiarisce
    /// mai. Capsule, pillola del selettore, contorno della zona di rilascio.
    static let penna = Color(red: 0.184, green: 0.361, blue: 0.541)
    static let pennaTesto = Color(nsColor: nsPennaTesto)

    /// Il guscio del notch è NERO PIENO, non carta: deve fondersi con la
    /// plastica dello schermo, e qualunque altro colore disegna un rettangolo
    /// visibile attorno all'hardware.
    static let guscio = Color.black

    /// Il segno DENTRO il guscio nero, dove la livrea chiaro/scuro non conta
    /// perché il fondo è nero in entrambi i mondi.
    static let sopraGuscio = Color(red: 0.949, green: 0.937, blue: 0.906)

    private static func scuro(_ aspetto: NSAppearance) -> Bool {
        aspetto.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// L'aspetto per il tema salvato: nil = segue il sistema.
    static func aspetto(perTema tema: String) -> NSAppearance? {
        switch tema {
        case "chiaro": NSAppearance(named: .aqua)
        case "scuro": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}


/// I simboli delle conferme, in un posto solo: un messaggio che dice «buttato»
/// e mostra una spunta è meno chiaro di uno che mostra un cestino.
enum Simboli {
    static let fatto = "checkmark"
    /// Non un cestino: il messaggio sotto DICE già «Nel Cestino», quindi
    /// l'icona può dire come ti senti invece di ripetere la meccanica. Il
    /// cestino pieno non gli piaceva (19/08) e le sei candidate stanno nella
    /// sonda `icone-cestino.png`, così la scelta si fa guardando.
    static let cestino = "sparkles"
}
