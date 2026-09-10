import AppKit
import ImageIO
import os

/// La sentinella delle schermate: guarda la cartella dove macOS scrive gli
/// screenshot e li fa entrare nel deposito da soli (C98-C101, 6/09).
///
/// **La cosa che NON facciamo, ed è il cuore del progetto.** Non tocchiamo
/// `com.apple.screencapture show-thumbnail`: la miniatura di Apple in basso a
/// destra resta accesa. Finché quella miniatura è lì il file **non esiste su
/// disco** — se lui la prende al volo e la trascina in un'app, non atterra da
/// nessuna parte e noi non vediamo niente. Solo quando la ignora macOS scrive
/// il file, e solo allora questa sentinella lo trova. Sua frase del 6/09: «se
/// riesco a prenderla subito non è un problema, se scompare va direttamente
/// nel deposito». La sequenza che vuole è quella nativa: bastava non romperla.
@MainActor
final class SentinellaSchermate: ObservableObject {
    private let registro = Logger(subsystem: "app.limbo.mac", category: "schermate")

    /// Chiamata dopo ogni assorbimento, con la voce entrata: la usa il braccio
    /// del notch per dire «Depositata · click = desktop».
    var nota: ((VoceDeposito) -> Void)?

    private weak var deposito: Deposito?
    private var sorgente: DispatchSourceFileSystemObject?
    private var lavoro: Task<Void, Never>?
    private var cartellaViva: URL?

    /// I file che c'erano GIÀ quando la sentinella si è accesa. Non si
    /// assorbono: la sua Scrivania ha cinque schermate vecchie, e assorbirle
    /// tutte al primo avvio sarebbe un gesto che non ha chiesto. Screenshoss
    /// fa esattamente questo e lo considero un difetto, non una funzione.
    ///
    /// **Per identità, non per percorso (10/09).** Fino a stamattina questa
    /// era una `Set<String>` di path, e bastava rinominare il file per farlo
    /// tornare sconosciuto: lui rinominava una schermata vecchia sulla
    /// Scrivania e se la vedeva sparire nel deposito tre secondi dopo.
    private var giaViste: Set<Identita> = []

    /// I file che abbiamo appena rimesso fuori con l'annulla. Senza questa
    /// lista l'annulla è un cappio: il file torna sulla Scrivania, la
    /// sorgente scatta, e la sentinella lo riassorbe un istante dopo.
    private var rimessiFuori: [Identita: Date] = [:]

    /// Quanto dura la finestra di grazia dell'annulla. **Non è `let` perché
    /// il banco la azzera**, come fa con `StatoNotch.scadenzaArrivo`: una
    /// grazia scaduta è lo stato che conta, cioè quello in cui il file deve
    /// restare fuori lo stesso.
    static var graziaAnnulla: TimeInterval = 120

    /// Respiro fra l'evento e la lettura: la stessa idea del watcher delle
    /// chat, e qui serve anche a lasciar finire la scrittura di macOS.
    private static let respiro: TimeInterval = 0.35

    init(deposito: Deposito) {
        self.deposito = deposito
    }

    // MARK: - Dove guardare (C101)

    /// La cartella di cattura è quella che dice il SISTEMA, non la Scrivania
    /// per fede. Chi sposta gli screenshot in `~/Immagini` con
    /// `defaults write com.apple.screencapture location` rende cieco chi dà
    /// per scontata la Scrivania — è il secondo limite di Screenshoss.
    nonisolated static func cartellaDiCattura() -> URL {
        let scrivania = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        guard let scelta = UserDefaults(suiteName: "com.apple.screencapture")?
            .string(forKey: "location")?
            .trimmingCharacters(in: .whitespaces), !scelta.isEmpty else { return scrivania }
        let espanso = (scelta as NSString).expandingTildeInPath
        var cartella: ObjCBool = false
        guard FileManager.default.fileExists(atPath: espanso, isDirectory: &cartella),
              cartella.boolValue else { return scrivania }
        return URL(fileURLWithPath: espanso)
    }

    // MARK: - Cos'è una schermata (C99)

    /// **L'attributo esteso, non il nome del file.** Screenshoss riconosce le
    /// schermate dal prefisso del nome (`screenshot `), che dipende dalla
    /// lingua del sistema. `screencapture` invece scrive sul file un attributo
    /// esteso `com.apple.metadata:kMDItemIsScreenCapture`, che contiene un
    /// plist binario con `true`.
    ///
    /// **Si legge l'attributo, non Spotlight**, e la differenza è misurata: il
    /// 6/09 lo stesso file copiato in `/var/folders` continuava ad avere
    /// l'attributo (`xattr -l` lo mostra) mentre `mdls` rispondeva `(null)`,
    /// perché quella cartella non è indicizzata. Passare da `MDItemCopyAttribute`
    /// vuol dire dipendere dall'indice di Spotlight; leggere l'attributo è
    /// immediato e non dipende da niente.
    nonisolated static func eSchermata(_ url: URL) -> Bool {
        if let dati = attributo("com.apple.metadata:kMDItemIsScreenCapture", di: url),
           let valore = try? PropertyListSerialization.propertyList(from: dati, format: nil) {
            if let numero = valore as? NSNumber { return numero.boolValue }
            if let booleano = valore as? Bool { return booleano }
        }
        // Ripiego: il nome, cioè il metodo di Screenshoss. Serve per i file
        // che perdono gli attributi passando da un volume che non li tiene
        // (una chiavetta FAT). Non è la strada principale apposta.
        return nomeDaSchermata(url)
    }

    /// Il ripiego dal nome, nelle due lingue che questa macchina può produrre.
    nonisolated static func nomeDaSchermata(_ url: URL) -> Bool {
        guard ["png", "jpg", "jpeg", "heic", "tiff"].contains(url.pathExtension.lowercased()) else {
            return false
        }
        let nome = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["screenshot ", "screen shot ", "schermata ", "screenshot-", "schermata-"]
            .contains { nome.hasPrefix($0) }
    }

    nonisolated private static func attributo(_ chiave: String, di url: URL) -> Data? {
        return url.withUnsafeFileSystemRepresentation { percorso -> Data? in
            guard let percorso else { return nil }
            let quanto = getxattr(percorso, chiave, nil, 0, 0, 0)
            guard quanto > 0 else { return nil }
            var dati = Data(count: quanto)
            let letti = dati.withUnsafeMutableBytes { grezzo -> Int in
                getxattr(percorso, chiave, grezzo.baseAddress, quanto, 0, 0)
            }
            guard letti == quanto else { return nil }
            return dati
        }
    }

    // MARK: - Chi è questo file (C110-C112, 10/09)

    /// L'identità di un file per il sistema: il numero che gli dà il volume,
    /// non il nome che gli dà lui.
    ///
    /// **Il perché sta in una misura:** rinominare e spostare dentro lo stesso
    /// volume sono la stessa chiamata, `rename(2)`, e lasciano intatti sia
    /// l'inode sia gli attributi estesi — cambia solo il percorso. Ricordare
    /// il percorso vuol dire quindi dimenticare il file al primo gesto suo,
    /// ed è esattamente il difetto del 10/09.
    ///
    /// `dev` sta accanto a `ino` perché un inode è unico dentro un volume e
    /// non fra volumi: senza, una schermata su una chiavetta potrebbe
    /// collidere con una della Scrivania e sparire dal giro senza motivo.
    struct Identita: Hashable {
        let dev: dev_t
        let ino: ino_t
    }

    nonisolated static func identita(_ url: URL) -> Identita? {
        var informazioni = stat()
        let letto = url.withUnsafeFileSystemRepresentation { percorso -> Bool in
            guard let percorso else { return false }
            return stat(percorso, &informazioni) == 0
        }
        guard letto else { return nil }
        return Identita(dev: informazioni.st_dev, ino: informazioni.st_ino)
    }

    /// Il marchio che scriviamo NOI sul file: «questa è già passata dal
    /// deposito, non riprenderla da sola».
    ///
    /// **Si scrive all'INGRESSO, non all'uscita, ed è la correzione del
    /// 10/09 sera (C114).** Marcarlo solo nell'annulla copriva una porta
    /// sola. L'altra è il trascinamento fuori dal deposito, che è un `.copy`
    /// (`Trascina.swift`): il Finder scrive sulla Scrivania una copia con gli
    /// attributi estesi dentro, quindi con `kMDItemIsScreenCapture` addosso,
    /// inode nuovo e — se avessimo marcato all'uscita — nessun marchio. La
    /// sentinella la vedrebbe come una schermata appena scattata e se la
    /// riprenderebbe. Marcando all'ingresso, **ogni copia che esce dal
    /// deposito porta il marchio con sé**, qualunque sia la porta.
    ///
    /// Serve anche perché la memoria della sentinella muore col processo — un
    /// riavvio di Limbo azzera qualunque `Set` in RAM — e perché un file può
    /// uscire dalla cartella di cattura e tornarci giorni dopo, quando la
    /// fotografia scattata da `attiva(cartella:)` non lo contiene più. La
    /// decisione deve sopravvivere al file, non alla sessione, e l'unico
    /// posto dove il file la porta con sé è il file stesso.
    ///
    /// **Quello che NON facciamo, ed è la scorciatoia che sembra ovvia:**
    /// togliere `com.apple.metadata:kMDItemIsScreenCapture`. Sarebbe il modo
    /// più corto per farla ignorare da questo giro, e romperebbe la cartella
    /// smart «Schermate» di Spotlight, che è roba sua. Si aggiunge un
    /// attributo nostro, non si toglie uno suo.
    nonisolated static let marchioDeposito = "app.limbo.mac.giaDepositata"

    nonisolated static func eGiaDepositata(_ url: URL) -> Bool {
        attributo(marchioDeposito, di: url) != nil
    }

    nonisolated static func marcaGiaDepositata(_ url: URL) {
        let dati = Data("1".utf8)
        url.withUnsafeFileSystemRepresentation { percorso in
            guard let percorso else { return }
            _ = dati.withUnsafeBytes { grezzo in
                setxattr(percorso, marchioDeposito, grezzo.baseAddress, dati.count, 0, 0)
            }
        }
    }

    // MARK: - Quando è finita di scrivere (C100)

    /// L'unico pezzo preso da Screenshoss, ed è quello che vale: un file si
    /// tocca solo quando ha smesso di crescere. Dimensione e data identiche a
    /// 150 ms di distanza **e** il decodificatore dice che l'immagine è
    /// completa. Senza il secondo controllo un PNG troncato passa, perché fra
    /// due letture ravvicinate può stare fermo per caso.
    nonisolated static func eFerma(_ url: URL, attesaMillisecondi: Int = 150) async -> Bool {
        guard let prima = firma(url), immagineCompleta(url) else { return false }
        if attesaMillisecondi > 0 {
            try? await Task.sleep(for: .milliseconds(attesaMillisecondi))
        }
        guard let dopo = firma(url), prima == dopo else { return false }
        return immagineCompleta(url)
    }

    private struct Firma: Equatable { let byte: Int; let quando: Date }

    nonisolated private static func firma(_ url: URL) -> Firma? {
        guard let attributi = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributi[.type] as? FileAttributeType == .typeRegular,
              let byte = attributi[.size] as? NSNumber,
              let quando = attributi[.modificationDate] as? Date else { return nil }
        return Firma(byte: byte.intValue, quando: quando)
    }

    /// **`CGImageSourceGetStatus` NON accorge una troncatura, e Screenshoss ci
    /// si appoggia.** Misurato il 6/09 su un PNG tagliato a metà: la sorgente
    /// nasce, lo stato risponde `.statusComplete` (0) esattamente come sul file
    /// intero, perché ImageIO ha letto l'intestazione e si ferma lì. L'unico
    /// controllo che distingue davvero è **decodificare**: sul mezzo file torna
    /// `nil`, sull'intero torna l'immagine.
    ///
    /// E costa meno del controllo che non funziona: 1,2 ms contro 4,5 ms sulla
    /// sua schermata da 3456×2234, perché ImageIO lavora pigro e la sorgente è
    /// già aperta. Il controllo giusto qui era anche il più economico.
    nonisolated private static func immagineCompleta(_ url: URL) -> Bool {
        guard let sorgente = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        return CGImageSourceCreateImageAtIndex(sorgente, 0, nil) != nil
    }

    // MARK: - Il ciclo di vita

    var viva: Bool { sorgente != nil }

    /// Si accende sulla cartella corrente e **segna come già viste** le
    /// schermate che ci sono adesso. Da qui in avanti entra solo quello che
    /// nasce.
    func attiva() { attiva(cartella: Self.cartellaDiCattura()) }

    /// La cucitura per il banco: la cartella si può dire, e allora la
    /// sentinella si accende su una cartella di sabbia invece che sulla sua
    /// Scrivania. `attiva()` resta la porta dell'app e passa di qui.
    func attiva(cartella: URL) {
        if let viva = cartellaViva, viva == cartella, sorgente != nil { return }
        ferma()
        giaViste = Set(Self.schermateNella(cartella).compactMap(Self.identita))
        let fd = open(cartella.path, O_EVTONLY)
        guard fd >= 0 else {
            registro.error("non riesco ad aprire \(cartella.path, privacy: .public)")
            return
        }
        let s = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.programmaGiro() }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        sorgente = s
        cartellaViva = cartella
    }

    func ferma() {
        sorgente?.cancel()
        sorgente = nil
        lavoro?.cancel()
        lavoro = nil
        cartellaViva = nil
    }

    private func programmaGiro() {
        lavoro?.cancel()
        lavoro = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.respiro))
            guard let self, !Task.isCancelled else { return }
            await self.giro()
        }
    }

    // MARK: - Il giro

    nonisolated private static func schermateNella(_ cartella: URL) -> [URL] {
        let file = (try? FileManager.default.contentsOfDirectory(
            at: cartella, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])) ?? []
        return file.filter(eSchermata)
    }

    /// Un giro: le schermate nuove, ferme, non appena rimesse fuori, entrano.
    func giro() async {
        guard let cartella = cartellaViva, let deposito else { return }
        potaGrazia()
        for url in Self.schermateNella(cartella) {
            guard let chi = Self.identita(url) else { continue }
            if giaViste.contains(chi) { continue }
            if rimessiFuori[chi] != nil { continue }
            // Il marchio è l'unica memoria che sopravvive al riavvio e al
            // viaggio fuori dalla cartella: si legge dal file, sempre.
            if Self.eGiaDepositata(url) { giaViste.insert(chi); continue }
            guard await Self.eFerma(url) else { continue }
            let nome = url.lastPathComponent
            giaViste.insert(chi)
            guard let voce = deposito.assorbi(schermata: url) else { continue }
            // Il marchio va sul file APPENA ENTRATO, non su quello che esce:
            // è l'unico punto attraversato da tutte le uscite del deposito —
            // l'annulla, il trascinamento nel Finder, «Condividi», AirDrop.
            Self.marcaGiaDepositata(voce.url)
            registro.info("assorbita: \(nome, privacy: .public)")
            nota?(voce)
        }
    }

    /// L'annulla del braccio: il file torna nella cartella di cattura col suo
    /// nome, e da lì in avanti è suo.
    ///
    /// **Tre memorie, non una, perché ognuna copre un buco delle altre**
    /// (10/09): la grazia a tempo ferma il rimbalzo immediato della sorgente,
    /// `giaViste` lo tiene fuori per tutta la sessione anche se lui lo
    /// rinomina o lo sposta, e il marchio sul file è l'unica che sopravvive
    /// al riavvio di Limbo e a un viaggio fuori dalla cartella e ritorno.
    @discardableResult
    func rimettiFuori(_ voce: VoceDeposito) -> URL? {
        guard let deposito else { return nil }
        let cartella = cartellaViva ?? Self.cartellaDiCattura()
        guard let tornato = deposito.rimettiFuori(voce, in: cartella) else { return nil }
        // Ridondante dopo la marcatura all'ingresso, e si tiene: è idempotente,
        // e copre una voce entrata nel deposito per un'altra strada.
        Self.marcaGiaDepositata(tornato)
        if let chi = Self.identita(tornato) {
            rimessiFuori[chi] = Date()
            giaViste.insert(chi)
        }
        return tornato
    }

    private func potaGrazia() {
        let limite = Date().addingTimeInterval(-Self.graziaAnnulla)
        rimessiFuori = rimessiFuori.filter { $0.value > limite }
    }
}
