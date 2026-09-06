import AppKit
import Foundation
import Vision

/// La lettura del testo dentro le immagini, con Vision di Apple: locale,
/// offline, senza permessi e senza account.
///
/// **Come si attiva, che è la domanda che ha fatto lui (19/08): da solo.**
/// Un comando «fai l'OCR adesso» costringerebbe a ricordarsi che esiste, e
/// una funzione che si deve ricordare non viene usata. Appena un'immagine
/// entra negli appunti o nel deposito, il testo si legge in sottofondo e
/// resta attaccato alla voce; sulla scheda compare un segno piccolo, e col
/// tasto destro c'è «Copia il testo». Zero gesti in più nel caso normale.
///
/// Si spegne dalle Impostazioni, e allora non gira proprio.
enum Ocr {
    static let chiavePreferenza = "leggiTesto"

    /// Acceso se non è stato spento a mano: il default è sì, perché il costo
    /// è una lettura sola per immagine e il ricavo è non ribattere a mano un
    /// IBAN da una schermata.
    static var attivo: Bool {
        UserDefaults.standard.object(forKey: chiavePreferenza) as? Bool ?? true
    }

    /// `true` se il file ha l'aria di un'immagine leggibile.
    static func leggibile(_ url: URL) -> Bool { Miniature.sembraImmagine(url) }

    /// Il testo dentro un'immagine, o `nil` se non c'è niente da leggere.
    /// **Non si chiama dal thread principale**: su una schermata piena costa
    /// centinaia di millisecondi.
    ///
    /// Italiano e inglese insieme, perché è quello che ha sullo schermo; la
    /// correzione linguistica è accesa, così «lVA» torna «IVA».
    nonisolated static func testo(in url: URL) -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let richiesta = VNRecognizeTextRequest()
        richiesta.recognitionLevel = .accurate
        richiesta.recognitionLanguages = ["it-IT", "en-US"]
        richiesta.usesLanguageCorrection = true

        let lettore = VNImageRequestHandler(url: url, options: [:])
        do {
            try lettore.perform([richiesta])
        } catch {
            registro.error("lettura del testo fallita: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let righe = (richiesta.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        let testo = righe.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return testo.isEmpty ? nil : testo
    }
}
