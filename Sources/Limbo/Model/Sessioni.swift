import AppKit
import SwiftUI

/// Una chat Claude aperta nel terminale, come l'hook di LifeOS l'ha
/// depositata in `~/.claude/LIFEOS/MEMORY/STATE/notch-sessions/<id>.json`.
///
/// Limbo LEGGE e disegna, non deriva: stato, icona e colore arrivano già
/// risolti dalla tabella unica di LifeOS (`ascent.ts`). Due superfici che
/// calcolano lo stesso stato divergono; una che disegna quello scritto no.
struct SessioneChat: Identifiable, Equatable {
    enum Attivita: String {
        case lavora = "working"
        case aspetta = "waiting"
        case finita = "done"
    }

    let id: String
    let descrizione: String
    /// Due o tre parole per il braccio del notch, accanto al progetto: la
    /// scrive l'hook di LifeOS, qui non si riassume niente.
    let titolo: String?
    let attivita: Attivita
    /// Il motivo dell'attesa, quando c'è: la domanda, o cosa va approvato.
    let dettaglio: String?
    /// Icona/etichetta/colore dello stato di ascesa, MAI calcolati qui.
    let icona: String
    let etichetta: String
    let coloreEsadecimale: String
    /// Avanzamento delle claim (n/m), solo per i lavori tracciati.
    let fatte: Int?
    let totali: Int?
    let progetto: String
    /// Quale AI tiene aperta la chat: decide il segno nella pillola.
    let ai: SegnoAI
    /// `ITERM_SESSION_ID` della sessione: `w0t2p0:UUID`. Resta per i record
    /// scritti prima che l'hook dicesse anche CHI ospita la chat.
    let iterm: String?
    /// Il terminale che ospita la chat, come lo dichiara lui (`TERM_PROGRAM`).
    let ospite: String?
    /// Il tesserino della scheda dentro quel terminale: `ITERM_SESSION_ID` in
    /// iTerm, `T4A_SESSION_ID` in T4A.
    let tesserino: String?
    let aggiornata: Date

    /// Dove sta la chat e con quale porta ci si arriva. Un terminale che non
    /// sappiamo interrogare vale `nil`, mai «proviamo con iTerm»: un salto
    /// verso la scheda di qualcun altro è peggio di un salto che non parte.
    enum Terminale: Equatable {
        case iterm(String)
        case t4a(String)
    }

    var terminale: Terminale? {
        guard let grezzo = tesserino ?? iterm else { return nil }
        // iTerm impacchetta l'UUID in `w0t2p0:UUID`, T4A lo scrive nudo.
        let coda = grezzo.split(separator: ":").last.map(String.init) ?? grezzo
        // La stringa entra in uno script: si tiene solo l'alfabeto di un UUID.
        let uuid = coda.filter { $0.isHexDigit || $0 == "-" }
        guard !uuid.isEmpty else { return nil }
        let chi = ospite ?? ""
        if chi.localizedCaseInsensitiveContains("t4a") { return .t4a(uuid) }
        // Ospite taciuto: sono i record vecchi, che esistevano solo per iTerm.
        if chi.isEmpty || chi.localizedCaseInsensitiveContains("iterm") {
            return .iterm(uuid)
        }
        return nil
    }

    var avanzamento: String? {
        guard let fatte, let totali, totali > 0 else { return nil }
        return "\(fatte)/\(totali)"
    }

    /// Una chat che LAVORA ma è muta da troppo sta dormendo. Una che aspetta
    /// te resta «aspetta te» anche dopo un'ora: il bloccante sei tu, non lei.
    func inSonno(adesso: Date) -> Bool {
        attivita == .lavora && adesso.timeIntervalSince(aggiornata) > SessioniChat.sonnoDopo
    }

    var colore: Color {
        Self.colore(esadecimale: coloreEsadecimale) ?? Livrea.pennaTesto
    }

    /// L'età dell'ultimo movimento, corta come una didascalia.
    func eta(adesso: Date) -> String {
        let secondi = max(0, adesso.timeIntervalSince(aggiornata))
        if secondi < 60 { return S.adesso }
        if secondi < 3600 { return "\(Int(secondi / 60)) min" }
        return "\(Int(secondi / 3600)) h"
    }

    static func colore(esadecimale: String) -> Color? {
        var testo = esadecimale.trimmingCharacters(in: .whitespaces)
        if testo.hasPrefix("#") { testo.removeFirst() }
        guard testo.count == 6, let valore = UInt64(testo, radix: 16) else { return nil }
        return Color(red: Double((valore >> 16) & 0xFF) / 255,
                     green: Double((valore >> 8) & 0xFF) / 255,
                     blue: Double(valore & 0xFF) / 255)
    }
}

/// Lo store della scheda Chat: legge la cartella di stato, osserva i
/// cambiamenti, e AVVISA quando una chat passa ad «aspetta te» o «finita».
@MainActor
final class SessioniChat: ObservableObject {
    @Published private(set) var voci: [SessioneChat] = []

    /// Con l'avviso spento il rilevatore tace ma la scheda resta viva (C71).
    var avvisaAttivo = true
    /// Chiamato su una transizione degna di avviso. Lo cabla StatoNotch.
    var nota: ((SessioneChat) -> Void)?

    nonisolated static let sonnoDopo: TimeInterval = 10 * 60
    nonisolated static let scadenza: TimeInterval = 24 * 3600
    /// Il debounce del watcher: gli hook scrivono a raffica a fine turno.
    nonisolated static let respiroRicarica: TimeInterval = 0.2

    nonisolated static var cartellaDiSerie: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/LIFEOS/MEMORY/STATE/notch-sessions")
    }

    let cartella: URL
    private var sorgente: DispatchSourceFileSystemObject?
    private var lavoroRicarica: Task<Void, Never>?
    /// `nil` = mai caricato: il primo giro è la fotografia di partenza e non
    /// avvisa mai (C70: niente apertura alla prima lettura all'avvio).
    private var precedente: [String: SessioneChat.Attivita]?

    init(cartella: URL = SessioniChat.cartellaDiSerie) {
        self.cartella = cartella
    }

    // MARK: - Il ciclo di vita del watcher (C72)

    /// Il watcher vive quanto l'uso reale, non quanto il processo: sempre se
    /// l'avviso è acceso (l'uso È avvisare in qualunque momento), altrimenti
    /// solo mentre il pannello è aperto.
    static func deveVivere(avvisa: Bool, pannelloAperto: Bool) -> Bool {
        avvisa || pannelloAperto
    }

    var viva: Bool { sorgente != nil }

    /// **Il contratto con chi scrive, scoperto il 19/08 facendo fallire la mia
    /// stessa prova.** Questa sorgente guarda la CARTELLA, e `.write` su una
    /// cartella scatta quando cambia l'elenco delle voci — un file creato,
    /// tolto o rinominato. Riscrivere un file ESISTENTE sul posto non tocca
    /// l'elenco, quindi non sveglia nessuno: la mia prima prova dal vivo ha
    /// fatto proprio quello e la pillola non è mai comparsa, e per un minuto
    /// ho creduto che fosse rotta l'app.
    ///
    /// L'hook di LifeOS scrive un temporaneo e poi lo rinomina sul posto, che
    /// è una modifica dell'elenco a ogni giro: il contratto è rispettato per
    /// costruzione. Chi un domani scrivesse qui dentro deve fare lo stesso.
    func attiva() {
        guard sorgente == nil else { return }
        let fd = open(cartella.path, O_EVTONLY)
        guard fd >= 0 else { return } // la cartella nasce col primo hook: si riprova alla prossima apertura
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.programmaRicarica() }
        }
        s.setCancelHandler { close(fd) }
        s.resume()
        sorgente = s
        ricarica()
    }

    func ferma() {
        sorgente?.cancel()
        sorgente = nil
        lavoroRicarica?.cancel()
    }

    private func programmaRicarica() {
        lavoroRicarica?.cancel()
        lavoroRicarica = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.respiroRicarica))
            guard let self, !Task.isCancelled else { return }
            self.ricarica()
        }
    }

    // MARK: - La lettura

    func ricarica(adesso: Date = Date()) {
        let nuove = Self.carica(da: cartella, adesso: adesso)
        let fotografia = Dictionary(uniqueKeysWithValues: nuove.map { ($0.id, $0.attivita) })
        defer {
            precedente = fotografia
            if nuove != voci { voci = nuove }
        }
        guard avvisaAttivo, let prima = precedente else { return }
        // Un avviso per giro, e «aspetta te» vince su «finita»: il soffio è uno.
        let cambiate = nuove.filter { $0.attivita != .lavora && prima[$0.id] != $0.attivita }
        if let scelta = cambiate.first(where: { $0.attivita == .aspetta }) ?? cambiate.first {
            nota?(scelta)
        }
    }

    static func carica(da cartella: URL, adesso: Date) -> [SessioneChat] {
        let fm = FileManager.default
        guard let nomi = try? fm.contentsOfDirectory(atPath: cartella.path) else { return [] }
        return nomi
            .filter { $0.hasSuffix(".json") }
            .compactMap { nome -> SessioneChat? in
                guard let dati = try? Data(contentsOf: cartella.appendingPathComponent(nome)) else { return nil }
                return decodifica(dati, id: String(nome.dropLast(5)), adesso: adesso)
            }
            .sorted { $0.aggiornata > $1.aggiornata }
    }

    /// Un file rotto o scaduto non entra e non rompe niente (C68): si torna
    /// `nil` e si passa al prossimo. L'`id` è il session_id, cioè il nome
    /// del file: stabile fra le riletture, che è quello che serve al
    /// rilevatore di transizioni.
    static func decodifica(_ dati: Data, id: String, adesso: Date) -> SessioneChat? {
        guard let radice = (try? JSONSerialization.jsonObject(with: dati)) as? [String: Any],
              let descrizione = radice["description"] as? String,
              let attivita = SessioneChat.Attivita(rawValue: radice["activity"] as? String ?? ""),
              let ascent = radice["ascent"] as? [String: Any],
              let aggiornata = data(iso: radice["updatedAt"] as? String)
        else { return nil }
        guard adesso.timeIntervalSince(aggiornata) < scadenza else { return nil }

        let progresso = radice["progress"] as? [String: Any]
        let iterm = radice["iterm"] as? String
        return SessioneChat(
            id: id,
            descrizione: descrizione,
            titolo: (radice["label"] as? String)?.trimmingCharacters(in: .whitespaces),
            attivita: attivita,
            dettaglio: radice["detail"] as? String,
            icona: ascent["icon"] as? String ?? "",
            etichetta: ascent["label"] as? String ?? "",
            coloreEsadecimale: ascent["color"] as? String ?? "",
            fatte: progresso?["done"] as? Int,
            totali: progresso?["total"] as? Int,
            progetto: radice["project"] as? String ?? "",
            ai: SegnoAI(codice: radice["ai"] as? String),
            iterm: iterm,
            ospite: radice["host"] as? String,
            tesserino: radice["terminalSession"] as? String,
            aggiornata: aggiornata)
    }

    private static let conFrazioni: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let senzaFrazioni = ISO8601DateFormatter()

    private static func data(iso: String?) -> Date? {
        guard let iso else { return nil }
        return conFrazioni.date(from: iso) ?? senzaFrazioni.date(from: iso)
    }

    // MARK: - Il salto alla chat (C69)

    /// Porta davanti la chat, nel terminale che la ospita. Il primo uso su
    /// iTerm chiede il permesso Automazione: una volta sola. Su T4A non lo
    /// chiede affatto, perché lì si bussa a un indirizzo (`t4a://`) invece di
    /// pilotare l'app.
    func porta(inPrimoPiano sessione: SessioneChat) -> Bool {
        switch sessione.terminale {
        case .iterm(let uuid): return Self.portaITerm(uuid: uuid)
        case .t4a(let uuid): return Self.portaT4A(uuid: uuid)
        case nil: return false
        }
    }

    /// L'identificatore del bundle di T4A. Sta scritto qui una volta sola.
    static let bundleT4A = "dev.t4a.terminal"

    /// T4A pubblica il tesserino della scheda in `T4A_SESSION_ID` e ascolta
    /// su `t4a://focus?session=<uuid>`: è la stessa porta che usa il clic
    /// sulle sue notifiche, non una seconda strada.
    ///
    /// L'indirizzo va a OGNI istanza viva di T4A, una per una, e non a
    /// «quella che sceglie il sistema». Con due copie aperte — succede a ogni
    /// banco, cioè proprio mentre lui lavora su T4A — `NSWorkspace` ne
    /// prende una arbitraria: misurato il 25/08, il salto è finito
    /// nell'istanza sbagliata e non è successo niente. Una sola di quelle
    /// istanze possiede quella scheda, e le altre lasciano cadere
    /// l'indirizzo senza fare nulla, quindi mandarlo a tutte è esatto invece
    /// che approssimato.
    private static func portaT4A(uuid: String) -> Bool {
        var componenti = URLComponents()
        componenti.scheme = "t4a"
        componenti.host = "focus"
        componenti.queryItems = [URLQueryItem(name: "session", value: uuid)]
        guard let url = componenti.url?.absoluteString else { return false }
        let vive = NSRunningApplication.runningApplications(withBundleIdentifier: bundleT4A)
        guard !vive.isEmpty else { return false }
        for app in vive { apri(indirizzo: url, pid: app.processIdentifier) }
        return true
    }

    /// L'evento «apri questo indirizzo», recapitato a UN processo preciso.
    ///
    /// È la stessa cosa che fa `open`, ma senza passare da LaunchServices,
    /// che ragiona per applicazione e non per istanza. Senza risposta
    /// (`.noReply`): a noi non serve sapere cosa ne fa, e aspettarla
    /// bloccherebbe il clic.
    private static func apri(indirizzo: String, pid: pid_t) {
        let evento = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass),
            eventID: AEEventID(kAEGetURL),
            targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        evento.setParam(NSAppleEventDescriptor(string: indirizzo), forKeyword: keyDirectObject)
        _ = try? evento.sendEvent(options: [.noReply], timeout: 2)
    }

    private static func portaITerm(uuid: String) -> Bool {
        // `activate` sta DOPO la ricerca, di proposito: attivarlo prima
        // portava iTerm davanti anche quando la sessione non c'era più, cioè
        // ti mostrava una chat a caso e sembrava che il salto avesse mancato
        // il bersaglio.
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is "\(uuid)" then
                            select s
                            select t
                            select w
                            activate
                            return "trovata"
                        end if
                    end repeat
                end repeat
            end repeat
            return "sparita"
        end tell
        """
        var errore: NSDictionary?
        let esito = NSAppleScript(source: script)?.executeAndReturnError(&errore)
        return errore == nil && esito?.stringValue == "trovata"
    }
}
