import AppKit
import Foundation
import os

/// Il registro degli errori che prima morivano dentro un `try?`. Si legge con:
/// `log show --last 10m --predicate 'subsystem == "app.limbo.mac"'`
/// Un componente che inghiotte i propri errori non è diagnosticabile
/// (pagato il 18/08: «non li mette e non li toglie», e nessuno sapeva dire
/// perché).
let registro = Logger(subsystem: "app.limbo.mac", category: "archivio")

/// Il disco: dove Limbo tiene le sue cose fra un avvio e l'altro.
///
/// Sta tutto in `~/Library/Application Support/Limbo/`, e un indice JSON
/// leggibile a occhio accanto ai file. Leggibile non è vezzo: il giorno che
/// qualcosa non torna, si apre l'indice con un editor invece di scrivere un
/// programma per interrogarlo.
struct Archivio {
    let cartella: String

    var radice: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Limbo", isDirectory: true)
            .appendingPathComponent(cartella, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private var indice: URL { radice.appendingPathComponent("indice.json") }

    // MARK: - Materializzare

    /// **La via veloce, e va preferita sempre quando i byte ci sono già.**
    /// (Il vecchio `materializza(NSImage)` è morto il 18/08 con l'ultimo
    /// chiamante: ricodificare una schermata costava 589 ms — 56 di TIFF,
    /// 533 di PNG — cioè 35 fotogrammi persi a immagine, misurati.)
    /// Una schermata negli appunti è già PNG: scriverla è mezzo millisecondo,
    /// mentre farla passare da `NSImage` e ricodificarla ne costa 589. Non
    /// ricodificare quello che è già nel formato giusto è il rimedio, spostare
    /// la codifica su un altro thread è solo il ripiego.
    nonisolated func scriviByte(_ dati: Data, estensione: String) -> URL? {
        let url = radice.appendingPathComponent("\(UUID().uuidString).\(estensione)")
        do {
            try dati.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// L'impronta di un contenuto, per dire se due copie sono la stessa cosa
    /// senza rileggere due file interi a ogni confronto. Lunghezza più i primi
    /// e gli ultimi mille byte: un campione che due immagini diverse non
    /// condividono mai, e che costa quanto una lettura di indice.
    nonisolated static func impronta(_ dati: Data) -> String {
        var accumulatore: UInt64 = 1469598103934665603
        func mescola(_ fetta: Data) {
            for byte in fetta {
                accumulatore = (accumulatore ^ UInt64(byte)) &* 1099511628211
            }
        }
        mescola(dati.prefix(1000))
        mescola(dati.suffix(1000))
        return "\(dati.count)-\(accumulatore)"
    }

    /// Copia un file dentro l'archivio tenendo il nome originale, e
    /// disambiguando se un file con quel nome c'è già.
    nonisolated func accogli(_ origine: URL) -> URL? {
        let destinazione = destinazioneLibera(per: origine.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: origine, to: destinazione)
            return destinazione
        } catch {
            return nil
        }
    }

    /// SPOSTA un file dentro l'archivio: rinomina sullo stesso volume, copia
    /// più eliminazione attraverso i volumi (lo fa `moveItem` da solo).
    ///
    /// È la regola del deposito dal 18/08 (sua parola: «se dal desktop lo
    /// metto nel deposito allora anche sul desktop non deve più esserci»), e
    /// ripara anche la classe del -43: indicare un file altrui voleva dire
    /// indicare anche le schermate nella cartella temporanea di macOS, che il
    /// sistema svuota da solo — la scheda restava e il file sotto moriva.
    ///
    /// Se lo spostamento non riesce (volume in sola lettura, permessi) si
    /// COPIA: la voce resta comunque nostra. Se nemmeno la copia riesce,
    /// `nil`: mai più una voce che indica un percorso fuori dall'archivio.
    nonisolated func sposta(_ origine: URL) -> URL? {
        let destinazione = destinazioneLibera(per: origine.lastPathComponent)
        let fm = FileManager.default
        do {
            try fm.moveItem(at: origine, to: destinazione)
            registro.info("spostato: \(origine.path, privacy: .public)")
            return destinazione
        } catch {
            registro.error("sposta fallito su \(origine.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        do {
            try fm.copyItem(at: origine, to: destinazione)
            registro.info("copiato (ripiego): \(origine.path, privacy: .public)")
            return destinazione
        } catch {
            registro.error("anche la copia fallita su \(origine.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Elimina i file dell'archivio che nessuna voce indica più, quando la
    /// loro ultima modifica (= l'ora dell'uscita, marcata da `togli`) è più
    /// vecchia dell'orizzonte. L'orizzonte protegge due corse: la copia
    /// asincrona del Finder dopo un atterraggio, e un file appena scritto la
    /// cui voce non è ancora nell'indice.
    nonisolated func eliminaOrfani(tranne vivi: Set<String>, orizzonte: TimeInterval) {
        let fm = FileManager.default
        guard let figli = try? fm.contentsOfDirectory(
            at: radice, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let limite = Date().addingTimeInterval(-orizzonte)
        for figlio in figli {
            guard figlio.lastPathComponent != "indice.json",
                  !vivi.contains(figlio.path) else { continue }
            let quando = (try? figlio.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if quando < limite {
                try? fm.removeItem(at: figlio)
                registro.info("orfano raccolto: \(figlio.lastPathComponent, privacy: .public)")
            }
        }
    }

    /// Il primo percorso libero nell'archivio per un file con quel nome.
    nonisolated private func destinazioneLibera(per nome: String) -> URL {
        let fm = FileManager.default
        var destinazione = radice.appendingPathComponent(nome)
        var contatore = 2
        let base = destinazione.deletingPathExtension().lastPathComponent
        let estensione = destinazione.pathExtension
        while fm.fileExists(atPath: destinazione.path) {
            let nuovo = estensione.isEmpty ? "\(base) \(contatore)" : "\(base) \(contatore).\(estensione)"
            destinazione = radice.appendingPathComponent(nuovo)
            contatore += 1
        }
        return destinazione
    }

    // MARK: - L'indice degli appunti

    private struct RigaAppunti: Codable, Sendable {
        var id: UUID
        var tipo: String        // "testo" | "immagine" | "file"
        var testo: String?
        var percorso: String?
        var percorsi: [String]?
        var app: String?
        var quando: Date
        /// Il testo LETTO dentro un'immagine, che è un'altra cosa dal `testo`
        /// qui sopra (quello è il contenuto di una copia di testo).
        var testoLetto: String?
    }

    func scriviAppunti(_ voci: [VoceAppunti]) {
        let righe: [RigaAppunti] = voci.map { voce in
            switch voce.contenuto {
            case .testo(let t):
                RigaAppunti(id: voce.id, tipo: "testo", testo: t, percorso: nil,
                            percorsi: nil, app: voce.app, quando: voce.quando,
                            testoLetto: nil)
            case .immagine(let url):
                RigaAppunti(id: voce.id, tipo: "immagine", testo: nil, percorso: url.path,
                            percorsi: nil, app: voce.app, quando: voce.quando,
                            testoLetto: voce.testoLetto)
            case .file(let urls):
                RigaAppunti(id: voce.id, tipo: "file", testo: nil, percorso: nil,
                            percorsi: urls.map(\.path), app: voce.app, quando: voce.quando,
                            testoLetto: nil)
            }
        }
        scrivi(righe, in: indice)
    }

    func rileggiAppunti() -> [VoceAppunti] {
        let righe: [RigaAppunti] = leggi(indice)
        return righe.compactMap { riga in
            let contenuto: VoceAppunti.Contenuto?
            switch riga.tipo {
            case "testo":
                contenuto = riga.testo.map { .testo($0) }
            case "immagine":
                // Un'immagine il cui file non c'è più non è una voce vuota: è
                // una voce che non esiste. Si scarta invece di mostrarne il
                // fantasma (appearance ≠ existence).
                contenuto = riga.percorso
                    .map { URL(fileURLWithPath: $0) }
                    .flatMap { FileManager.default.fileExists(atPath: $0.path) ? .immagine($0) : nil }
            case "file":
                // Anche qui: un percorso morto non si mostra. Dal 18/08 mandare
                // un file al deposito lo SPOSTA, quindi la voce degli appunti
                // che lo indicava resta indietro per costruzione — si scarta.
                let urls = (riga.percorsi ?? [])
                    .map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                contenuto = urls.isEmpty ? nil : .file(urls)
            default:
                contenuto = nil
            }
            guard let contenuto else { return nil }
            return VoceAppunti(id: riga.id, contenuto: contenuto, app: riga.app,
                               quando: riga.quando, testoLetto: riga.testoLetto)
        }
    }

    // MARK: - L'indice del deposito

    private struct RigaDeposito: Codable, Sendable {
        var id: UUID
        var percorso: String
        var nome: String
        var quando: Date
        var fissata: Bool
        var nostra: Bool
        // Campo nuovo (19/08): un indice vecchio non ce l'ha, e `Codable`
        // sugli opzionali decodifica «assente» come `nil` invece di
        // fallire — quindi gli indici già sul disco continuano a leggersi.
        var testoLetto: String?
    }

    func scriviDeposito(_ voci: [VoceDeposito]) {
        let righe = voci.map {
            RigaDeposito(id: $0.id, percorso: $0.url.path, nome: $0.nome,
                         quando: $0.quando, fissata: $0.fissata, nostra: $0.nostra,
                         testoLetto: $0.testoLetto)
        }
        scrivi(righe, in: indice)
    }

    func rileggiDeposito() -> [VoceDeposito] {
        let righe: [RigaDeposito] = leggi(indice)
        return righe.map {
            VoceDeposito(id: $0.id, url: URL(fileURLWithPath: $0.percorso), nome: $0.nome,
                         quando: $0.quando, fissata: $0.fissata, nostra: $0.nostra,
                         testoLetto: $0.testoLetto)
        }
    }

    // MARK: - Lettura e scrittura

    /// L'indice si scrive **fuori** dal thread principale. Da solo costa
    /// poco, ma parte a ogni copia e a ogni rilascio, cioè sempre insieme
    /// all'immagine: sommarlo lì era regalare altri millisecondi al momento
    /// peggiore. La coda è seriale, quindi due scritture non si accavallano e
    /// l'ultima vince, che è quello che vogliamo.
    private static let codaDisco = DispatchQueue(label: "app.limbo.disco", qos: .utility)

    private func scrivi<T: Encodable & Sendable>(_ valore: T, in url: URL) {
        Self.codaDisco.async {
            let codificatore = JSONEncoder()
            codificatore.outputFormatting = [.prettyPrinted, .sortedKeys]
            codificatore.dateEncodingStrategy = .iso8601
            guard let dati = try? codificatore.encode(valore) else { return }
            try? dati.write(to: url, options: .atomic)
        }
    }

    private func leggi<T: Decodable>(_ url: URL) -> [T] {
        guard let dati = try? Data(contentsOf: url) else { return [] }
        let decodificatore = JSONDecoder()
        decodificatore.dateDecodingStrategy = .iso8601
        return (try? decodificatore.decode([T].self, from: dati)) ?? []
    }
}
