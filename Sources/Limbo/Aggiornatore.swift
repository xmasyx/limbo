import AppKit
import Combine
import Foundation

/// La rete e i processi dell'aggiornamento stanno qui; ogni decisione viene da
/// `Aggiornamenti`, che è pura e si può interrogare da un banco.
///
/// Il tasto vive nelle Impostazioni e fa una cosa sola a seconda di come l'app
/// è arrivata sul Mac: se l'ha portata `brew`, lancia `brew upgrade` e riapre
/// Limbo; se è stata copiata a mano, apre la pagina della release, perché
/// sovrascriversi da soli un bundle scaricato a mano è il modo di lasciare
/// mezza app sul disco quando qualcosa va storto.
@MainActor
final class Aggiornatore: ObservableObject {
    enum Stato {
        case fermo
        case guardo
        case aggiornata(versione: String)
        case disponibile(versione: String, azione: Aggiornamenti.Azione)
        case scarico(riga: String)
        case fallito(String)
    }

    @Published var stato: Stato = .fermo

    private let preferenze = UserDefaults.standard
    private let ambiente = ProcessInfo.processInfo.environment
    private let banco = CommandLine.arguments.contains("--banco-aggiornamenti")
    private var paginaDellaRelease: URL?
    private var accettoLeRighe = false

    /// Il clic cambia stato subito; la rete prosegue senza fermare la finestra.
    func guardaAdesso() {
        guard !occupato else { return }
        stato = .guardo
        Task { await guarda() }
    }

    /// Il controllo all'apertura della pagina: una sola lettura, in silenzio, e
    /// non più di una all'ora. Se il Mac è fuori rete non compare nessun avviso.
    func guardaSeEOra(intervallo: TimeInterval = 3_600) {
        let ultimo = preferenze.object(forKey: Self.chiaveUltimoControllo) as? Date
        guard Aggiornamenti.eOra(ultimoControllo: ultimo, adesso: Date(), intervallo: intervallo)
        else { return }
        guardaAdesso()
    }

    func esegui(_ azione: Aggiornamenti.Azione) {
        switch azione {
        case .apriLaPagina(let url):
            apri(url)
        case .aggiornaERiapri(let argomenti):
            guard let brew = percorsoBrew() else {
                stato = .fallito(S.aggiornamentoSenzaBrew)
                registra(S.aggiornamentoSenzaBrew)
                stampaPerIlBanco()
                if let paginaDellaRelease { apri(paginaDellaRelease) }
                return
            }
            stato = .scarico(riga: S.aggiornamentoPreparo)
            stampaPerIlBanco()
            Task { await aggiorna(con: brew, argomenti: argomenti) }
        }
    }

    /// Il banco usa lo stesso controllo e la stessa azione, aspettando solo che
    /// il processo finisca. Uscite: 0 fatto, 2 occupato, 3 niente da aggiornare.
    func giraIlBanco() async -> Int32 {
        guard !occupato else { return 2 }
        stato = .guardo
        stampaPerIlBanco()
        await guarda()

        guard case .disponibile(_, let azione) = stato else {
            stampaPerIlBanco()
            return 3
        }
        esegui(azione)
        while case .scarico = stato {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return 0
    }

    static let chiaveUltimoControllo = "aggiornamenti.ultimoControllo"

    private var occupato: Bool {
        switch stato {
        case .guardo, .scarico: return true
        default: return false
        }
    }

    private var versioneInstallata: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    private func guarda() async {
        defer {
            if !banco { preferenze.set(Date(), forKey: Self.chiaveUltimoControllo) }
        }

        do {
            let dati = try await datiDellaRelease()
            guard let tag = Aggiornamenti.tagUltimaRelease(dalJSON: dati) else {
                throw ErroreAggiornamento.releaseSenzaTag
            }
            guard let versione = Aggiornamenti.versionePiuNuova(
                installata: versioneInstallata, tagRemoto: tag) else {
                stato = .aggiornata(versione: versioneInstallata)
                stampaPerIlBanco()
                return
            }

            let radici = ambiente["LIMBO_CASKROOM"].map { [$0] }
                ?? ["/opt/homebrew/Caskroom", "/usr/local/Caskroom"]
            // Il banco DICHIARA il luogo che sta simulando: un eseguibile nella
            // cartella di build non starebbe mai in /Applications, quindi senza
            // questa riga il polo Homebrew non sarebbe raggiungibile nemmeno
            // con un Caskroom vero accanto.
            let percorso = banco ? "/Applications/Limbo.app" : Bundle.main.bundlePath
            let provenienza = Aggiornamenti.provenienza(
                percorsoBundle: percorso,
                radiciCaskroom: radici,
                casa: NSHomeDirectory(),
                esiste: FileManager.default.fileExists(atPath:))
            if case .apriLaPagina(let url) = Aggiornamenti.azione(per: .aMano, versione: versione) {
                paginaDellaRelease = url
            }
            stato = .disponibile(versione: versione,
                                 azione: Aggiornamenti.azione(per: provenienza, versione: versione))
            stampaPerIlBanco()
        } catch {
            registra(error.localizedDescription)
            stato = .fermo
            stampaPerIlBanco()
        }
    }

    private func datiDellaRelease() async throws -> Data {
        let grezzo = ambiente["LIMBO_API_AGGIORNAMENTI"]
            ?? "https://api.github.com/repos/\(Aggiornamenti.repo)/releases/latest"
        guard let url = URL(string: grezzo) else { throw ErroreAggiornamento.indirizzoStorto }

        // `URLSession` non carica `file://`: questo ramo è il rubinetto locale
        // del banco, mentre ogni richiesta HTTP passa dalla stessa sessione con
        // scadenza e intestazioni dichiarate.
        if url.isFileURL {
            return try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value
        }

        var richiesta = URLRequest(url: url, timeoutInterval: 10)
        richiesta.httpMethod = "GET"
        richiesta.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        richiesta.setValue("Limbo/\(versioneInstallata)", forHTTPHeaderField: "User-Agent")
        let (dati, risposta) = try await URLSession.shared.data(for: richiesta)
        guard let http = risposta as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ErroreAggiornamento.rispostaStorta
        }
        return dati
    }

    private func percorsoBrew() -> URL? {
        let candidati = ambiente["LIMBO_BREW"].map { [$0] }
            ?? ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        guard let percorso = candidati.first(where: FileManager.default.isExecutableFile(atPath:))
        else { return nil }
        return URL(fileURLWithPath: percorso)
    }

    private func ambienteDelProcesso(conAutoUpdate: Bool) -> [String: String] {
        var risultato = ambiente
        risultato["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        risultato["HOME"] = NSHomeDirectory()
        risultato["HOMEBREW_NO_ENV_HINTS"] = "1"
        risultato["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        if conAutoUpdate {
            risultato.removeValue(forKey: "HOMEBREW_NO_AUTO_UPDATE")
        } else {
            risultato["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        }
        return risultato
    }

    private func aggiorna(con brew: URL, argomenti: [String]) async {
        let veloce = ambienteDelProcesso(conAutoUpdate: false)
        // Il tap si aggiorna da sé con un `git pull`, che costa un secondo:
        // `brew update` completo scarica l'intero indice di Homebrew e fa
        // aspettare chi voleva solo la versione nuova di un'app.
        let cartellaDelTap = await Processo.gira(eseguibile: brew,
                                                 argomenti: ["--repository", Aggiornamenti.tap],
                                                 ambiente: veloce)
        var tapAggiornato = false
        if cartellaDelTap.stato == 0, let percorso = cartellaDelTap.righe.last, !percorso.isEmpty {
            let pull = await Processo.gira(eseguibile: URL(fileURLWithPath: "/usr/bin/git"),
                                           argomenti: ["-C", percorso, "pull", "--ff-only", "-q"],
                                           ambiente: veloce)
            tapAggiornato = pull.stato == 0
        }

        accettoLeRighe = true
        let esito = await Processo.gira(
            eseguibile: brew,
            argomenti: argomenti,
            ambiente: ambienteDelProcesso(conAutoUpdate: !tapAggiornato)
        ) { [weak self] riga in
            Task { @MainActor in
                guard let self, self.accettoLeRighe else { return }
                self.stato = .scarico(riga: riga)
                self.stampaPerIlBanco()
            }
        }
        accettoLeRighe = false

        guard esito.stato == 0 else {
            let motivo = esito.righe.suffix(2).joined(separator: " · ")
            let messaggio = motivo.isEmpty ? S.aggiornamentoFallito : motivo
            registra(messaggio)
            stato = .fallito(messaggio)
            stampaPerIlBanco()
            return
        }

        // Un banco non deve riaprire se stesso all'infinito: lì l'uscita zero
        // del processo È il risultato osservato.
        guard !banco else {
            stato = .fermo
            stampaPerIlBanco()
            return
        }
        await togliLaQuarantena()
        riapriDopoLUscita()
        NSApp.terminate(nil)
    }

    /// Homebrew può lasciare `com.apple.quarantine` sull'app appena installata,
    /// e con quel contrassegno addosso un'app firmata in casa non si apre. Si
    /// tocca SOLO il proprio bundle, e solo dopo un `brew` uscito zero.
    private func togliLaQuarantena() async {
        let esito = await Processo.gira(
            eseguibile: URL(fileURLWithPath: "/usr/bin/xattr"),
            argomenti: ["-dr", "com.apple.quarantine", Bundle.main.bundlePath],
            ambiente: ambienteDelProcesso(conAutoUpdate: false))
        if esito.stato != 0 {
            registra("quarantena non tolta: \(esito.righe.last ?? "")")
        }
    }

    private func riapriDopoLUscita() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let percorso = Bundle.main.bundlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open -a \"\(percorso)\""
        let processo = Process()
        processo.executableURL = URL(fileURLWithPath: "/bin/sh")
        processo.arguments = ["-c", script]
        processo.standardInput = FileHandle.nullDevice
        processo.standardOutput = FileHandle.nullDevice
        processo.standardError = FileHandle.nullDevice
        try? processo.run()
    }

    private func apri(_ url: URL) {
        if banco {
            print("apriLaPagina \(url.absoluteString)")
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func registra(_ messaggio: String) {
        NSLog("Limbo: %@", messaggio)
    }

    private func stampaPerIlBanco() {
        guard banco else { return }
        switch stato {
        case .fermo: print("fermo")
        case .guardo: print("guardo")
        case .aggiornata(let versione): print("aggiornata \(versione)")
        case .disponibile(let versione, let azione):
            switch azione {
            case .aggiornaERiapri: print("disponibile \(versione) aggiornaERiapri")
            case .apriLaPagina(let url): print("disponibile \(versione) apriLaPagina \(url.absoluteString)")
            }
        case .scarico(let riga): print("scarico \(riga)")
        case .fallito(let motivo): print("fallito \(motivo)")
        }
        fflush(stdout)
    }
}

private enum ErroreAggiornamento: LocalizedError {
    case indirizzoStorto
    case rispostaStorta
    case releaseSenzaTag

    var errorDescription: String? {
        switch self {
        case .indirizzoStorto: return "l'indirizzo degli aggiornamenti non è valido"
        case .rispostaStorta: return "GitHub non ha risposto con l'ultima release"
        case .releaseSenzaTag: return "la release non porta un numero di versione"
        }
    }
}

/// Un processo esterno letto riga per riga, con l'uscita e le ultime due righe.
private enum Processo {
    struct Esito {
        let stato: Int32?
        let righe: [String]
    }

    static func gira(eseguibile: URL,
                     argomenti: [String],
                     ambiente: [String: String],
                     riga: ((String) -> Void)? = nil) async -> Esito {
        await withCheckedContinuation { continuazione in
            let processo = Process()
            let tubo = Pipe()
            let uscita = Uscita()
            processo.executableURL = eseguibile
            processo.arguments = argomenti
            processo.environment = ambiente
            processo.standardOutput = tubo
            processo.standardError = tubo

            tubo.fileHandleForReading.readabilityHandler = { maniglia in
                let dati = maniglia.availableData
                guard !dati.isEmpty else { return }
                uscita.aggiungi(dati).forEach { riga?($0) }
            }
            processo.terminationHandler = { finito in
                tubo.fileHandleForReading.readabilityHandler = nil
                uscita.aggiungi(tubo.fileHandleForReading.readDataToEndOfFile()).forEach { riga?($0) }
                continuazione.resume(returning: Esito(stato: finito.terminationStatus,
                                                      righe: uscita.chiudi()))
            }

            do {
                try processo.run()
                tubo.fileHandleForWriting.closeFile()
            } catch {
                tubo.fileHandleForReading.readabilityHandler = nil
                tubo.fileHandleForWriting.closeFile()
                continuazione.resume(returning: Esito(stato: nil,
                                                      righe: [error.localizedDescription]))
            }
        }
    }
}

/// `FileHandle` consegna i byte su code diverse: il lucchetto conserva righe e
/// ordine senza lasciare che un'uscita rumorosa cresca per tutto l'aggiornamento.
private final class Uscita: @unchecked Sendable {
    private let lucchetto = NSLock()
    private var inSospeso = Data()
    private var ultime: [String] = []

    func aggiungi(_ dati: Data) -> [String] {
        guard !dati.isEmpty else { return [] }
        lucchetto.lock()
        defer { lucchetto.unlock() }
        inSospeso.append(dati)
        var complete: [String] = []
        while let aCapo = inSospeso.firstIndex(of: 10) {
            let byte = inSospeso[..<aCapo]
            inSospeso.removeSubrange(...aCapo)
            let testo = String(decoding: byte, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !testo.isEmpty else { continue }
            complete.append(testo)
            ultime.append(testo)
            ultime = Array(ultime.suffix(2))
        }
        return complete
    }

    func chiudi() -> [String] {
        lucchetto.lock()
        defer { lucchetto.unlock() }
        let testo = String(decoding: inSospeso, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !testo.isEmpty {
            ultime.append(testo)
            ultime = Array(ultime.suffix(2))
        }
        inSospeso.removeAll()
        return ultime
    }
}
