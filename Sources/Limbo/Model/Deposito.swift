import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Una cosa messa da parte.
struct VoceDeposito: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let nome: String
    let quando: Date
    /// Fissata: non esce quando svuoti, non scade.
    var fissata: Bool
    /// `true` se il file l'abbiamo scritto noi (una schermata, del testo
    /// trascinato) e quindi è nostro da cancellare; `false` se è un file suo
    /// che stiamo solo indicando. La differenza decide chi può cancellare che
    /// cosa, ed è il motivo per cui questo campo esiste.
    let nostra: Bool
    /// Il testo letto dentro l'immagine, quando ce n'è (vedi `Ocr`).
    var testoLetto: String? = nil

    var esiste: Bool { FileManager.default.fileExists(atPath: url.path) }

    var icona: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// Il deposito: quello che hai trascinato nel notch e che sta lì finché serve.
///
/// La regola che decide tutto, ROVESCIATA il 18/08 pomeriggio (sua parola:
/// «quando metto nel deposito deve essere spostato dalla posizione
/// d'origine»): **quello che entra nel deposito viene SPOSTATO da noi, e da
/// quel momento è nostro**. La regola precedente («un file suo si indica, non
/// si tocca») sembrava rispettosa ed era il difetto: una schermata trascinata
/// dall'anteprima di macOS vive in una cartella temporanea che il sistema
/// svuota da solo, la scheda restava e il file sotto moriva — errore -43 nel
/// Finder al trascinamento successivo. Possedere ripara la classe intera.
///
/// La contropartita di possedere: un'uscita di mano («Togli», «Svuota») non
/// elimina mai — passa dal Cestino, perché adesso la nostra è spesso l'unica
/// copia. L'eliminazione vera esiste solo quando un trascinamento è appena
/// atterrato, cioè quando a destinazione la copia c'è già.
@MainActor
final class Deposito: ObservableObject {
    @Published private(set) var voci: [VoceDeposito] = []

    /// Quando è ENTRATA l'ultima cosa. Decide su quale scheda si apre il
    /// pannello (sua regola del 19/08): appunti di norma, deposito se ci hai
    /// appena messo qualcosa. Solo in memoria: a ogni avvio si riparte da
    /// appunti, che è il caso di ogni giorno.
    private(set) var ultimoIngresso: Date?

    private let archivio: Archivio

    /// L'archivio si inietta per i banchi, che non devono toccare il deposito
    /// vero di nessuno.
    init(archivio: Archivio = Archivio(cartella: "deposito")) {
        self.archivio = archivio
        voci = archivio.rileggiDeposito()
        potaSpariti()
    }

    /// Il seme della sonda visiva: voci decise dal banco, indice mai riscritto
    /// (la sonda non invoca nessuna azione che scriva).
    /// **In un archivio di sabbia, MAI in quello vero.** Fino al 6/09 questa
    /// init usava l'archivio vero, e da quando aprire il pannello pota e
    /// raccoglie gli orfani (C6, C97) ogni banco che simulava un'apertura su
    /// un deposito «per sonda» vuoto **cancellava dal disco tutti i file
    /// dell'archivio più vecchi di dieci minuti e riscriveva l'indice vuoto**.
    /// Succedeva a ogni `build-app.sh`, in silenzio, e stanotte ha svuotato il
    /// suo deposito due volte prima che lo trovassi. Una sonda non tocca il
    /// disco di nessuno: se un giorno le servirà l'archivio vero, lo dirà
    /// per nome con `init(archivio:)`.
    init(perSonda voci: [VoceDeposito]) {
        self.archivio = Archivio(cartella: "sonda-\(UUID().uuidString)")
        self.voci = voci
    }

    // MARK: - Far entrare roba

    /// I file sul pasteboard del TRASCINAMENTO. I fornitori che SwiftUI
    /// consegna a `onDrop` sono lossy: misurato col log il 18/08, un `.txt`
    /// trascinato dal Finder arrivava come solo `public.plain-text` — il
    /// percorso non c'era proprio, il file entrava come testo ricopiato e il
    /// Desktop restava pieno. Il pasteboard di trascinamento i percorsi li
    /// porta sempre. Si legge SOLO dentro il gestore di un rilascio: fuori da
    /// lì contiene l'ultimo trascinamento di chiunque.
    static func percorsiTrascinati() -> [URL] {
        NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    /// Accoglie un RILASCIO: prima i percorsi veri dal pasteboard del
    /// trascinamento, poi i fornitori per ciò che arriva solo come byte
    /// (un'immagine da una pagina, un pezzo di testo selezionato).
    func accogliRilascio(_ fornitori: [NSItemProvider]) async -> Int {
        let percorsi = Self.percorsiTrascinati()
        if !percorsi.isEmpty {
            var entrate = 0
            for url in percorsi {
                if await spostaDentro(url) { entrate += 1 }
            }
            return entrate
        }
        return await accogli(fornitori)
    }

    /// Prende quello che il sistema offre a un rilascio. Torna quante voci
    /// sono davvero entrate, che è il numero da mostrare, non quante gliene
    /// hanno passate.
    func accogli(_ fornitori: [NSItemProvider]) async -> Int {
        var entrate = 0
        for fornitore in fornitori {
            if await accogliUno(fornitore) { entrate += 1 }
        }
        return entrate
    }

    /// Il gesto fondamentale del deposito: il file si SPOSTA da noi e diventa
    /// nostro (sua regola del 18/08).
    private func spostaDentro(_ url: URL) async -> Bool {
        let archivio = self.archivio
        let nome = url.lastPathComponent
        guard let dentro = await Task.detached(priority: .userInitiated, operation: {
            archivio.sposta(url)
        }).value else { return false }
        aggiungi(url: dentro, nome: nome, nostra: true)
        return true
    }

    private func accogliUno(_ fornitore: NSItemProvider) async -> Bool {
        registro.info("rilascio: tipi offerti = \(fornitore.registeredTypeIdentifiers.joined(separator: ", "), privacy: .public)")
        // 1. Un file vero: si SPOSTA da noi e diventa nostro.
        if let url = await caricaURL(fornitore), url.isFileURL {
            return await spostaDentro(url)
        }
        registro.info("rilascio: nessun percorso leggibile, provo i byte")
        // 2. Un'immagine come byte: senza di noi si perde, quindi si scrive.
        //    I BYTE, non un `NSImage`: ricodificare una schermata costa 589 ms
        //    sul thread che disegna (misurato il 18/08), ed era metà
        //    dell'impasto che si vedeva rilasciando qualcosa nel notch.
        if let dati = await caricaDatiImmagine(fornitore) {
            let archivio = self.archivio
            let url = await Task.detached(priority: .userInitiated) {
                dati.giaPng
                    ? archivio.scriviByte(dati.byte, estensione: "png")
                    : NSBitmapImageRep(data: dati.byte)?
                        .representation(using: .png, properties: [:])
                        .flatMap { archivio.scriviByte($0, estensione: "png") }
            }.value
            guard let url else { return false }
            aggiungi(url: url, nome: nomeSchermata(), nostra: true)
            return true
        }
        // 3. Del testo: stessa cosa, diventa un .txt.
        if let testo = await caricaTesto(fornitore), !testo.isEmpty {
            let archivio = self.archivio
            let url = await Task.detached(priority: .userInitiated) {
                Data(testo.utf8).isEmpty ? nil : archivio.scriviByte(Data(testo.utf8), estensione: "txt")
            }.value
            guard let url else { return false }
            aggiungi(url: url, nome: primaRiga(testo) + ".txt", nostra: true)
            return true
        }
        return false
    }

    /// Fa entrare la COPIA di un file che deve restare anche all'origine: le
    /// voci degli appunti. Gli appunti tengono la loro copia, e due indici che
    /// puntassero allo stesso file se lo cancellerebbero a vicenda. Byte
    /// copiati così come sono: niente `NSImage`, niente ricodifica (589 ms).
    func accogli(copiaDi url: URL) {
        let archivio = self.archivio
        let nome = url.pathExtension.lowercased() == "png" ? nomeSchermata() : url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            guard let dentro = archivio.accogli(url) else { return }
            await MainActor.run { self.aggiungi(url: dentro, nome: nome, nostra: true) }
        }
    }

    /// Fa entrare un file per percorso (il menu «Deposito» su una voce di tipo
    /// file degli appunti). Stessa regola del rilascio: si sposta.
    func accogli(fileEsistente url: URL) {
        let archivio = self.archivio
        let nome = url.lastPathComponent
        Task.detached(priority: .userInitiated) {
            guard let dentro = archivio.sposta(url) else { return }
            await MainActor.run { self.aggiungi(url: dentro, nome: nome, nostra: true) }
        }
    }

    // MARK: - Le schermate (C98, 6/09)

    /// Fa entrare una schermata trovata dalla sentinella. **Sincrona apposta:**
    /// chi chiama deve sapere SUBITO quale voce è nata, perché il braccio del
    /// notch offre l'annulla su quella voce e un `Task.detached` renderebbe la
    /// risposta più lenta dell'avviso che la annuncia. Lo spostamento è una
    /// rinomina sullo stesso volume (cartella di cattura e archivio stanno
    /// entrambi nella home), quindi non c'è niente da mandare in sottofondo.
    @discardableResult
    func assorbi(schermata url: URL) -> VoceDeposito? {
        let nome = url.lastPathComponent
        guard let dentro = archivio.sposta(url) else { return nil }
        aggiungi(url: dentro, nome: nome, nostra: true)
        // `aggiungi` inserisce in testa, sia per una voce nuova sia per una
        // che risale: la prima è sempre quella appena entrata.
        return voci.first
    }

    /// L'annulla: il file torna nella cartella da cui è arrivato e la voce
    /// sparisce. **Non passa dal Cestino** perché il file non muore, torna a
    /// casa — è l'unica uscita del deposito che può permetterselo, e vale solo
    /// perché la destinazione la conosciamo.
    func rimettiFuori(_ voce: VoceDeposito, in cartella: URL) -> URL? {
        let fm = FileManager.default
        var destinazione = cartella.appendingPathComponent(voce.nome)
        var contatore = 1
        let base = (voce.nome as NSString).deletingPathExtension
        let coda = (voce.nome as NSString).pathExtension
        while fm.fileExists(atPath: destinazione.path) {
            let nome = coda.isEmpty ? "\(base) (\(contatore))" : "\(base) (\(contatore)).\(coda)"
            destinazione = cartella.appendingPathComponent(nome)
            contatore += 1
        }
        do {
            try fm.moveItem(at: voce.url, to: destinazione)
        } catch {
            return nil
        }
        voci.removeAll { $0.id == voce.id }
        archivio.scriviDeposito(voci)
        return destinazione
    }

    /// Interna e non privata: il banco del deposito costruisce voci da qui.
    func aggiungi(url: URL, nome: String, nostra: Bool) {
        ultimoIngresso = Date()
        // Lo stesso file due volte non è due voci. Torna in cima e basta.
        if let indice = voci.firstIndex(where: { $0.url == url }) {
            let v = voci.remove(at: indice)
            voci.insert(v, at: 0)
            archivio.scriviDeposito(voci)
            return
        }
        let voce = VoceDeposito(id: UUID(), url: url, nome: nome,
                                quando: Date(), fissata: false, nostra: nostra)
        voci.insert(voce, at: 0)
        archivio.scriviDeposito(voci)
        leggiIlTesto(di: voce)
    }

    /// Legge il testo dell'immagine in sottofondo e lo attacca alla voce.
    /// Nessun gesto da parte sua: è il senso di come l'OCR si «attiva».
    private func leggiIlTesto(di voce: VoceDeposito) {
        guard Ocr.attivo, Ocr.leggibile(voce.url) else { return }
        let url = voce.url
        let id = voce.id
        Task.detached(priority: .utility) {
            guard let testo = Ocr.testo(in: url) else { return }
            await MainActor.run { self.annota(id: id, testo: testo) }
        }
    }

    private func annota(id: UUID, testo: String) {
        guard let indice = voci.firstIndex(where: { $0.id == id }) else { return }
        voci[indice].testoLetto = testo
        archivio.scriviDeposito(voci)
    }

    /// Il file dietro a un fornitore, **senza** metterlo nel deposito. Serve
    /// ad AirDrop, che vuole un percorso: un file suo si manda dov'è, mentre
    /// un'immagine che arriva come byte va scritta da qualche parte prima, o
    /// non c'è niente da mandare.
    func urlPerCondivisione(_ fornitore: NSItemProvider) async -> URL? {
        if let url = await caricaURL(fornitore), url.isFileURL { return url }
        if let dati = await caricaDatiImmagine(fornitore) {
            let archivio = self.archivio
            return await Task.detached(priority: .userInitiated) {
                dati.giaPng
                    ? archivio.scriviByte(dati.byte, estensione: "png")
                    : NSBitmapImageRep(data: dati.byte)?
                        .representation(using: .png, properties: [:])
                        .flatMap { archivio.scriviByte($0, estensione: "png") }
            }.value
        }
        if let testo = await caricaTesto(fornitore), !testo.isEmpty {
            let archivio = self.archivio
            return await Task.detached(priority: .userInitiated) {
                archivio.scriviByte(Data(testo.utf8), estensione: "txt")
            }.value
        }
        return nil
    }

    // MARK: - Far uscire roba

    /// `atterrata: true` solo quando la voce esce perché un trascinamento è
    /// appena atterrato. Lì il file NON si tocca: `endedAt` arriva quando la
    /// destinazione ACCETTA, non quando ha finito di copiare — il Finder
    /// copia in modo ASINCRONO, e cancellare qui è cancellargli la sorgente
    /// sotto le mani. Misurato il 18/08 col banco a mano: 50 byte, scheda
    /// uscita, nella cartella non atterrava MAI niente, e il suo errore -43
    /// era esattamente questo. La copia orfana la raccoglie `raccogliOrfani`
    /// dopo un orizzonte largo; qui si marca solo l'ora dell'uscita (mtime),
    /// che è l'ora da cui l'orizzonte conta.
    ///
    /// Ogni altra uscita è una scelta di mano, e una scelta di mano passa dal
    /// CESTINO (anti-claim A2): da quando entrare nel deposito sposta, la
    /// nostra copia è spesso l'unica. Le voci legacy non nostre si
    /// de-indicizzano e il loro file resta dov'è.
    func togli(_ voce: VoceDeposito, atterrata: Bool = false) {
        voci.removeAll { $0.id == voce.id }
        if voce.nostra {
            if atterrata {
                try? FileManager.default.setAttributes(
                    [.modificationDate: Date()], ofItemAtPath: voce.url.path)
            } else {
                try? FileManager.default.trashItem(at: voce.url, resultingItemURL: nil)
            }
        }
        archivio.scriviDeposito(voci)
    }

    /// Elimina i file nostri rimasti senza voce (usciti per atterraggio),
    /// solo quando la loro uscita è più vecchia dell'orizzonte: a quel punto
    /// qualunque copia asincrona della destinazione ha finito da un pezzo.
    /// Gira all'avvio e a ogni apertura del pannello.
    func raccogliOrfani(orizzonte: TimeInterval = 600) {
        let vivi = Set(voci.map(\.url.path))
        let archivio = self.archivio
        Task.detached(priority: .utility) {
            archivio.eliminaOrfani(tranne: vivi, orizzonte: orizzonte)
        }
    }

    func fissa(_ voce: VoceDeposito) {
        guard let indice = voci.firstIndex(where: { $0.id == voce.id }) else { return }
        voci[indice].fissata.toggle()
        archivio.scriviDeposito(voci)
    }

    /// Svuota tutto tranne quello che hai fissato: il fissaggio è la promessa
    /// che questo comando non lo tocca. Nel Cestino, mai eliminazione secca:
    /// «Svuota» è un gesto di mano, e i file nostri sono spesso l'unica copia.
    func svuota() {
        for voce in voci where !voce.fissata && voce.nostra {
            try? FileManager.default.trashItem(at: voce.url, resultingItemURL: nil)
        }
        voci = voci.filter(\.fissata)
        archivio.scriviDeposito(voci)
    }

    // MARK: - Scadenza

    /// Quanti giorni una voce non fissata resta nel deposito. `0` = mai, cioè
    /// il comportamento di prima del 20/08.
    ///
    /// Sua richiesta di quel giorno: una schermata messa da parte e mandata
    /// via era temporanea quando la incollava in chat, e qui invece restava
    /// per sempre. Solo il trascinamento ATTERRATO toglie la voce; AirDrop e
    /// «Condividi» la lasciano dov'è, e nessuno la toglieva mai più.
    static let chiaveScadenza = "giorniScadenzaDeposito"
    static let giorniScadenzaDefault = 7

    /// `object(forKey:)` e non `integer(forKey:)`: il secondo risponde `0` sia
    /// per «mai scelto» sia per «scelto: mai», e qui le due cose sono opposte.
    /// Un default che assorbe l'assenza restituisce un risultato plausibile e
    /// sbagliato — e questo, sbagliando, non scaderebbe niente per sempre.
    static var giorniScadenza: Int {
        UserDefaults.standard.object(forKey: chiaveScadenza) as? Int ?? giorniScadenzaDefault
    }

    /// Manda nel Cestino le voci non fissate più vecchie dell'orizzonte, e
    /// torna quante ne ha tolte. Gira all'avvio e a ogni apertura del pannello.
    ///
    /// Nel CESTINO, mai eliminazione secca, per la stessa ragione di «Svuota»:
    /// entrare nel deposito SPOSTA, quindi la nostra è spesso l'unica copia, e
    /// una scadenza che cancella davvero cancellerebbe l'originale senza che
    /// nessuno l'abbia chiesto. Il fissaggio è la promessa che questo comando
    /// non lo tocca. Una voce legacy non nostra si de-indicizza e basta.
    ///
    /// `orizzonte` esplicito serve solo ai banchi (il polo si prova con `-1`):
    /// in produzione lo decide la preferenza.
    @discardableResult
    func potaScadute(orizzonte: TimeInterval? = nil) -> Int {
        let finestra: TimeInterval
        if let orizzonte {
            finestra = orizzonte
        } else {
            let giorni = Self.giorniScadenza
            guard giorni > 0 else { return 0 }
            finestra = TimeInterval(giorni) * 86_400
        }
        let limite = Date().addingTimeInterval(-finestra)
        let scadute = voci.filter { !$0.fissata && $0.quando < limite }
        guard !scadute.isEmpty else { return 0 }
        for voce in scadute where voce.nostra {
            try? FileManager.default.trashItem(at: voce.url, resultingItemURL: nil)
            registro.info("scaduta: \(voce.nome, privacy: .public)")
        }
        let morte = Set(scadute.map(\.id))
        voci.removeAll { morte.contains($0.id) }
        archivio.scriviDeposito(voci)
        return scadute.count
    }

    /// Toglie le voci il cui file non c'è più. Gira all'avvio: un deposito che
    /// mostra file spariti è peggio di uno vuoto, perché ci conti sopra.
    func potaSpariti() {
        let vivi = voci.filter(\.esiste)
        guard vivi.count != voci.count else { return }
        voci = vivi
        archivio.scriviDeposito(voci)
    }

    // MARK: - Leggere quello che arriva

    private func caricaURL(_ fornitore: NSItemProvider) async -> URL? {
        guard fornitore.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { return nil }
        return await withCheckedContinuation { ripresa in
            _ = fornitore.loadObject(ofClass: URL.self) { url, _ in
                ripresa.resume(returning: url)
            }
        }
    }

    /// I byte di un'immagine, col suo formato. Si chiedono il PNG e il TIFF
    /// direttamente, così quando l'immagine è già PNG (quasi sempre: le
    /// schermate lo sono) non si ricodifica niente.
    private func caricaDatiImmagine(_ fornitore: NSItemProvider) async -> (byte: Data, giaPng: Bool)? {
        for (tipo, giaPng) in [(UTType.png, true), (UTType.tiff, false)] {
            guard fornitore.hasItemConformingToTypeIdentifier(tipo.identifier) else { continue }
            let byte: Data? = await withCheckedContinuation { ripresa in
                fornitore.loadDataRepresentation(forTypeIdentifier: tipo.identifier) { dati, _ in
                    ripresa.resume(returning: dati)
                }
            }
            if let byte, !byte.isEmpty { return (byte, giaPng) }
        }
        return nil
    }

    private func caricaTesto(_ fornitore: NSItemProvider) async -> String? {
        guard fornitore.canLoadObject(ofClass: NSString.self) else { return nil }
        return await withCheckedContinuation { ripresa in
            _ = fornitore.loadObject(ofClass: NSString.self) { oggetto, _ in
                ripresa.resume(returning: (oggetto as? NSString) as String?)
            }
        }
    }

    // MARK: - Nomi

    /// Il nome di una schermata materializzata. Data e ora, come le fa macOS:
    /// un nome che dice quando serve più di un nome che dice cosa.
    private func nomeSchermata() -> String {
        let formato = DateFormatter()
        formato.dateFormat = "yyyy-MM-dd 'alle' HH.mm.ss"
        return "Immagine \(formato.string(from: Date())).png"
    }

    /// La prima riga di un testo, tagliata a 40 caratteri e ripulita dai
    /// caratteri che il filesystem non accetta.
    private func primaRiga(_ testo: String) -> String {
        let riga = testo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n").first.map(String.init) ?? "Testo"
        let pulita = riga
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return String(pulita.prefix(40))
    }
}
