import AppKit
import Foundation
import ImageIO
import AVFoundation
import PDFKit

/// I banchi headless, quelli che `build-app.sh` esegue prima di assemblare il
/// bundle.
///
/// **Ogni banco ha due poli.** Non basta che il codice buono risulti verde:
/// deve risultare ROSSO il codice rotto, altrimenti il verde non sta dicendo
/// niente (regola del test negativo, pagata più volte). Qui il polo negativo è
/// esplicito: si costruisce apposta il caso sbagliato e si pretende che la
/// stessa funzione lo bocci.
enum SelfTests {

    /// Aspetta un lavoro asincrono con un TETTO di tempo. Serve perché il
    /// difetto che questi banchi devono prendere è uno STALLO: senza tetto il
    /// banco si pianterebbe insieme al codice che sta misurando, e un banco
    /// piantato non dice niente a nessuno.
    private static func attendi<T: Sendable>(secondi: Double,
                                             _ lavoro: @escaping @Sendable () async -> T?) -> T? {
        let semaforo = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var risultato: T?
        Task.detached {
            risultato = await lavoro()
            semaforo.signal()
        }
        return semaforo.wait(timeout: .now() + secondi) == .success ? risultato : nil
    }

    /// La misura che si VEDE: i pixel passati per la rotazione dichiarata.
    /// È l'unica che conta per dire se un video è uscito storpiato.
    private static func misuraVista(_ url: URL) -> CGSize {
        let filmato = AVURLAsset(url: url)
        guard let traccia = attendi(secondi: 10, {
            (try? await filmato.loadTracks(withMediaType: .video))?.first
        }) else { return .zero }
        let naturale = attendi(secondi: 10, { try? await traccia.load(.naturalSize) }) ?? .zero
        let matrice = attendi(secondi: 10, { try? await traccia.load(.preferredTransform) }) ?? .identity
        let vista = naturale.applying(matrice)
        return CGSize(width: abs(vista.width), height: abs(vista.height))
    }

    private static func esito(_ nome: String, _ prove: [(String, Bool)]) -> Int32 {
        var rotte = 0
        for (che, passata) in prove {
            print(passata ? "  ✓ \(che)" : "  ✗ \(che)")
            if !passata { rotte += 1 }
        }
        print(rotte == 0 ? "✓ \(nome)" : "✗ \(nome): \(rotte) su \(prove.count)")
        return rotte == 0 ? 0 : 1
    }

    // MARK: - Le stringhe

    /// Il testo che si legge: niente vuoto, niente inglese rimasto in mezzo.
    ///
    /// L'inglese si cerca su PAROLE INTERE, non su sottostringhe: cercare
    /// "file" dentro una frase italiana trova "file" che in italiano è una
    /// parola («una fila di file»), e un metro che risponde sempre sì non
    /// misura niente. E accanto al verdetto si stampa **la parola trovata**,
    /// perché un conteggio senza il testo non è controllabile da un umano.
    static func stringhe() -> Int32 {
        let testi: [(String, String)] = [
            // Le tre del 6/09. Stanno QUI perché il banco misura solo quello
            // che gli si dà: prima di aggiungerle il cancello diceva verde su
            // 56 stringhe mentre la 57ª, in inglese, non l'aveva mai vista.
            ("braccioSchermata", S.braccioSchermata),
            ("assorbiSchermate", S.assorbiSchermate),
            ("notaAssorbiSchermate", S.notaAssorbiSchermate),
            ("impostazioni", S.impostazioni), ("esci", S.esci),
            ("svuotaDeposito", S.svuotaDeposito), ("convertitore", S.convertitore),
            ("trascinaDaConvertire", S.trascinaDaConvertire),
            ("notaConversione", S.notaConversione),
            ("comprimoVideo", S.comprimoVideo), ("convertoImmagine", S.convertoImmagine),
            ("immagini", S.immagini), ("video", S.video), ("documenti", S.documenti),
            ("inPdf", S.inPdf), ("convertito", S.convertito),
            ("leggero", S.leggero), ("fedele", S.fedele),
            ("nonSoConvertire", S.nonSoConvertire),
            ("copiaIlTesto", S.copiaIlTesto), ("leggiTesto", S.leggiTesto),
            ("alleggerisci", S.alleggerisci), ("notaAlleggerisci", S.notaAlleggerisci),
            ("notaLeggiTesto", S.notaLeggiTesto),
            ("titoloImpostazioni", S.titoloImpostazioni),
            ("appunti", S.appunti), ("deposito", S.deposito),
            ("trascinaQui", S.trascinaQui), ("lascialoAndare", S.lascialoAndare),
            ("tienilodaParte", S.tienilodaParte), ("mandaloVia", S.mandaloVia),
            ("depositoVuoto", S.depositoVuoto), ("appuntiVuoti", S.appuntiVuoti),
            ("copia", S.copia), ("apri", S.apri), ("mostraNelFinder", S.mostraNelFinder),
            ("condividi", S.condividi), ("airdrop", S.airdrop), ("converti", S.converti),
            ("fissa", S.fissa), ("libera", S.libera),
            ("togliDalDeposito", S.togliDalDeposito),
            ("anteprima", S.anteprima), ("copiato", S.copiato),
            ("svuota", S.svuota), ("nelCestino", S.nelCestino),
            ("svuotaAppunti", S.svuotaAppunti), ("svuotati", S.svuotati),
            ("fileSparito", S.fileSparito), ("nonPreso", S.nonPreso),
            ("nienteDaCondividere", S.nienteDaCondividere),
            ("quanteVoci", S.quanteVoci), ("notaQuanteVoci", S.notaQuanteVoci),
            ("apriConIlPuntatore", S.apriConIlPuntatore),
            ("notaApriConIlPuntatore", S.notaApriConIlPuntatore),
            ("avvioAlLogin", S.avvioAlLogin), ("notaAvvioAlLogin", S.notaAvvioAlLogin),
            ("acceso", S.acceso), ("spento", S.spento),
            // Le sei dell'aggiornamento (6/09): stessa lezione di stamattina,
            // una stringa che il banco non ha in lista non è controllata.
            ("aggiornamenti", S.aggiornamenti),
            ("notaAggiornamenti", S.notaAggiornamenti),
            ("verificaAggiornamenti", S.verificaAggiornamenti),
            ("aggiornamentoUltima", S.aggiornamentoUltima),
            ("aggiornamentoSenzaBrew", S.aggiornamentoSenzaBrew),
            ("aggiornamentoFallito", S.aggiornamentoFallito),
        ]

        var prove: [(String, Bool)] = []
        let vuote = testi.filter { $0.1.trimmingCharacters(in: .whitespaces).isEmpty }
        prove.append(("nessuna stringa vuota (\(testi.count) controllate)", vuote.isEmpty))

        var trovate: [String] = []
        for (nome, testo) in testi {
            for parola in inglesi(in: testo) {
                trovate.append("\(nome): «\(parola)»")
            }
        }
        // AirDrop è un nome proprio del sistema, non traduttese: si scrive così
        // anche in italiano, e tradurlo sarebbe l'errore opposto.
        //
        // `braccioSchermata` è l'UNICA deroga motivata: sua decisione esplicita
        // del 6/09 dopo che le due forme italiane sfondavano i 210 punti del
        // braccio (233 e 218 contro 210). La deroga è nominale — vale per
        // QUELLA stringa, non per le parole: «click» e «desktop» restano
        // vietate ovunque altro, e infatti il 6/09 sono state aggiunte
        // all'elenco. Una deroga sulle parole avrebbe spento il cancello.
        let vere = trovate.filter { !$0.contains("airdrop") && !$0.hasPrefix("braccioSchermata:") }
        prove.append(("niente inglese nel testo\(vere.isEmpty ? "" : " → " + vere.joined(separator: ", "))",
                      vere.isEmpty))

        // La deroga nominale deve DAVVERO derogare: se questa riga diventa
        // verde perché la stringa è tornata italiana, la deroga è morta e va
        // tolta, non lasciata lì a coprire niente.
        prove.append(("il braccio delle schermate è inglese, e la deroga esiste per quello",
                      !inglesi(in: S.braccioSchermata).isEmpty))

        // La larghezza del braccio (C102). **Il primo polo che ho scritto qui
        // era vacuo e l'ha smascherato una fotografia:** misurava
        // `larghezzaAvviso`, che applica `min(tetto, ...)` e quindi non può
        // superare il tetto per costruzione — rispondeva «210 <= 210, verde»
        // mentre a schermo si leggeva «Depositata · click = desk…». Si misura
        // il FABBISOGNO, non il risultato già tosato.
        let fabbisogno = ceil((S.braccioSchermata as NSString)
            .size(withAttributes: [.font: NotchPanel.carattereAvviso]).width)
            + NotchPanel.cromaturaAvviso
        prove.append((String(format: "il braccio delle schermate non va troncato (serve %.0f, ce ne sono %.0f)",
                             fabbisogno, NotchPanel.avvisoLargo),
                      fabbisogno <= NotchPanel.avvisoLargo))
        // Polo negativo: una frase lunga DEVE risultare troncata, altrimenti
        // il metro qui sopra ha smesso di misurare.
        let lunga = "Depositata nel deposito del notch, clicca per rimetterla sulla Scrivania"
        let troppo = ceil((lunga as NSString)
            .size(withAttributes: [.font: NotchPanel.carattereAvviso]).width)
            + NotchPanel.cromaturaAvviso
        prove.append(("polo negativo: una frase lunga sfonda", troppo > NotchPanel.avvisoLargo))

        // Un menu con due righe uguali è un difetto visto il 18/08: la voce
        // fissata mostrava «Togli dal deposito» sia per liberare sia per
        // togliere davvero (C11).
        prove.append(("liberare e togliere sono parole diverse",
                      S.libera != S.togliDalDeposito && S.libera != S.fissa))

        // Polo negativo: una frase in traduttese DEVE essere presa. Se questa
        // riga diventa verde, il metro ha smesso di misurare.
        let finta = "Rilascia il file nella drop zone e premi cancel"
        let prese = inglesi(in: finta)
        prove.append(("polo negativo: la frase finta è bocciata (trovate: \(prese.joined(separator: ", ")))",
                      !prese.isEmpty))

        return esito("banco delle stringhe", prove)
    }

    /// Le parole che tradiscono una traduzione dall'inglese. Confronto su
    /// parola intera e senza distinzione di maiuscole.
    private static func inglesi(in testo: String) -> [String] {
        let sospette: Set<String> = [
            "drop", "zone", "cancel", "ok", "item", "items", "clipboard",
            "shelf", "pin", "unpin", "settings", "preferences", "quit",
            "share", "convert", "preview", "empty", "clear", "paste",
            // Aggiunte il 6/09: il metro non le prendeva, e il braccio delle
            // schermate le ha scoperte. Un cancello che non conosce la parola
            // che stai per scrivere non ti sta proteggendo.
            "click", "desktop", "screenshot", "folder", "done", "undo",
        ]
        let parole = testo.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return parole.filter { sospette.contains($0) }
    }

    // MARK: - Le schermate (C98-C103, 6/09)

    /// Il banco della sentinella. **Le fixture portano la variabile sotto
    /// esame:** un file senza l'attributo esteso non prova niente sul
    /// riconoscimento, e un PNG intero non prova niente sull'attesa. Lezione
    /// pagata tre volte la notte del 19/08.
    static func schermate() -> Int32 {
        var prove: [(String, Bool)] = []
        let fm = FileManager.default
        let banco = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("limbo-schermate-\(UUID().uuidString)")
        try? fm.createDirectory(at: banco, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: banco) }

        /// Un PNG vero, minimo, scritto da noi: 1x1 opaco.
        func scriviPng(_ url: URL) {
            let img = NSImage(size: NSSize(width: 1, height: 1))
            img.lockFocus()
            NSColor.black.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            img.unlockFocus()
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            try? png.write(to: url)
        }

        /// Marca il file come fa `screencapture`: un plist binario con `true`
        /// dentro l'attributo esteso. Marcarlo a mano è l'unico modo di avere
        /// la variabile nel banco senza chiedergli di scattare una schermata.
        func marca(_ url: URL) {
            guard let dati = try? PropertyListSerialization.data(
                fromPropertyList: true, format: .binary, options: 0) else { return }
            url.withUnsafeFileSystemRepresentation { percorso in
                guard let percorso else { return }
                _ = dati.withUnsafeBytes { grezzo in
                    setxattr(percorso, "com.apple.metadata:kMDItemIsScreenCapture",
                             grezzo.baseAddress, dati.count, 0, 0)
                }
            }
        }

        // C99 — il riconoscimento, positivo e negativo sugli stessi due file.
        let marcata = banco.appendingPathComponent("qualunque-nome.png")
        scriviPng(marcata); marca(marcata)
        let nuda = banco.appendingPathComponent("foto-normale.png")
        scriviPng(nuda)
        prove.append(("un file marcato è una schermata anche col nome sbagliato",
                      SentinellaSchermate.eSchermata(marcata)))
        prove.append(("polo negativo: un PNG qualunque non lo è",
                      !SentinellaSchermate.eSchermata(nuda)))
        // E il ripiego dal nome deve restare un RIPIEGO che funziona: il nome
        // italiano che Screenshoss non prenderebbe qui passa.
        let italiana = banco.appendingPathComponent("Schermata 2026-09-06 alle 01.47.png")
        scriviPng(italiana)
        prove.append(("il ripiego dal nome prende anche «Schermata», che Screenshoss perde",
                      SentinellaSchermate.eSchermata(italiana)))

        // C100 — il file finito di scrivere. Il polo che conta è quello
        // TRONCATO: un PNG a metà sta fermo fra due letture ravvicinate, e
        // senza il controllo sul decodificatore passerebbe.
        let troncata = banco.appendingPathComponent("mezza.png")
        if let intera = try? Data(contentsOf: marcata), intera.count > 8 {
            try? intera.prefix(intera.count / 2).write(to: troncata)
        }
        let esitoTronca = MainActor.assumeIsolated {
            semaforo { await SentinellaSchermate.eFerma(troncata, attesaMillisecondi: 10) }
        }
        let esitoIntera = MainActor.assumeIsolated {
            semaforo { await SentinellaSchermate.eFerma(marcata, attesaMillisecondi: 10) }
        }
        prove.append(("polo negativo: un PNG troncato non è pronto", esitoTronca == false))
        prove.append(("un PNG completo è pronto", esitoIntera == true))

        // C101 — la cartella viene dal sistema. Senza la chiave è la
        // Scrivania, che è il suo caso verificato il 6/09.
        let cartella = SentinellaSchermate.cartellaDiCattura()
        prove.append(("la cartella di cattura esiste ed è una cartella",
                      (try? cartella.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true))

        // C104 — la zona sensibile della X. **È l'unica cosa che decide se la
        // X si preme**, perché il colpo del mouse lo prende comunque la vista
        // AppKit: se il rettangolo è nel posto sbagliato, la X si vede e non
        // risponde, che è esattamente com'è uscita la prima volta il 6/09.
        let sorgente = SorgenteTrascinamento.VistaSorgente(
            frame: NSRect(x: 0, y: 0, width: 100, height: 120))
        sorgente.latoX = 34
        let zona = sorgente.zonaX
        // La vista non è ribaltata: l'alto è `maxY`. Il polo che conta è
        // proprio questo, perché con `minY` la zona finisce in basso e tutto
        // il resto sembra a posto.
        prove.append(("la zona della X sta IN ALTO a destra",
                      zona?.contains(CGPoint(x: 90, y: 110)) == true))
        prove.append(("polo negativo: in basso a destra NON c'è",
                      zona?.contains(CGPoint(x: 90, y: 10)) == false))
        prove.append(("polo negativo: al centro NON c'è",
                      zona?.contains(CGPoint(x: 50, y: 60)) == false))
        sorgente.latoX = 0
        prove.append(("senza X non c'è nessuna zona esclusa", sorgente.zonaX == nil))
        // La zona è più larga del disegno: lui la punta avvicinandosi.
        // **Il polo che il video del 6/09 ha reso obbligatorio.** Non basta
        // che la zona sia più larga del disegno: il disegno deve stare DENTRO
        // la zona, cioè dentro la vista che riceve il colpo. Con la X spinta
        // fuori dall'angolo di 7 punti questa riga sarebbe rossa, e quella
        // versione è arrivata fino alle sue mani.
        let ingombroX = SchedaDeposito.latoX + SchedaDeposito.bordoX * 2
        prove.append((String(format: "il disegno della X sta dentro la zona sensibile (%.0f <= %.0f)",
                             ingombroX, SchedaDeposito.zonaX),
                      ingombroX <= SchedaDeposito.zonaX))
        prove.append(("la X non sborda dalla scheda", SchedaDeposito.bordoX >= 0))

        // L'apertura dopo un braccio di SCHERMATA va al deposito, non alle
        // chat (6/09). Prima usava lo stesso `ultimoAvviso` delle chat, e
        // per un minuto dopo ogni assorbimento il pannello si apriva su
        // Agents: l'ha scoperto il mouse sintetico, non io.
        let (dopoSchermata, dopoChat) = MainActor.assumeIsolated { () -> (Scheda, Scheda) in
            let statoScreen = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
            let finta = VoceDeposito(id: UUID(), url: URL(fileURLWithPath: "/tmp/x.png"),
                                     nome: "x.png", quando: Date(), fissata: false, nostra: true)
            statoScreen.scopriBraccioPerSonda(AvvisoChat(testo: S.braccioSchermata, ai: .ignoto,
                                                         sessione: nil, schermata: finta))
            statoScreen.ultimoAvviso = Date()
            statoScreen.ultimoAvvisoEraSchermata = true
            let a = statoScreen.schedaIniziale()
            statoScreen.ultimoAvvisoEraSchermata = false
            let b = statoScreen.schedaIniziale()
            return (a, b)
        }
        // Togliere dal deposito deve far ridisegnare la vista che legge il
        // deposito ATTRAVERSO lo stato (6/09). Senza l'inoltro questa riga è
        // rossa e a schermo la scheda resta, con l'indice già aggiornato.
        // **In un archivio di sabbia, non in quello vero.** `Deposito(perSonda:)`
        // usa l'archivio VERO, e `togli` ci scrive l'indice: la prima stesura
        // di questo polo ha svuotato l'indice del suo deposito durante la
        // build del 6/09 (3 voci → 0, file intatti, ricostruito a mano).
        // Un banco che muta lo stato passa SEMPRE da un archivio suo.
        let ridisegna = MainActor.assumeIsolated { () -> Bool in
            let dep = Deposito(archivio: Archivio(cartella: "banco-inoltro-\(UUID().uuidString)"))
            dep.aggiungi(url: URL(fileURLWithPath: "/tmp/y.png"), nome: "y.png", nostra: false)
            let st = StatoNotch(appunti: Appunti(perSonda: []), deposito: dep)
            var scattato = false
            let c = st.objectWillChange.sink { _ in scattato = true }
            dep.togli(dep.voci[0])
            c.cancel()
            return scattato
        }
        prove.append(("togliere dal deposito ridisegna lo stato del notch", ridisegna))
        // **Una sonda non tocca l'archivio vero** (6/09): la prova è che aprire
        // e chiudere un pannello su un deposito per sonda lascia intatto
        // l'indice vero, byte per byte. Prima di oggi lo svuotava.
        let indiceVero = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/Limbo/deposito/indice.json")
        let prima = try? Data(contentsOf: indiceVero)
        MainActor.assumeIsolated {
            let st = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
            st.aperto = true
            st.deposito.raccogliOrfani(orizzonte: 0)
            st.aperto = false
        }
        let dopo = try? Data(contentsOf: indiceVero)
        prove.append(("una sonda che apre il pannello non tocca l'indice vero", prima == dopo))

        // La scheda che scivola sotto il puntatore fermo (video del 6/09,
        // 03:20). Il sistema non manda `mouseEntered` quando è il bordo a
        // passare sotto la mano: lo stato si riallinea guardando dov'è il
        // puntatore. Qui il pezzo che decide, a due poli.
        let scatola = NSRect(x: 0, y: 0, width: 100, height: 120)
        prove.append(("puntatore dentro la scheda scivolata → sfiorata",
                      SorgenteTrascinamento.VistaSorgente.dentro(bounds: scatola, puntatore: NSPoint(x: 90, y: 110))))
        prove.append(("polo negativo: puntatore fuori → non sfiorata",
                      !SorgenteTrascinamento.VistaSorgente.dentro(bounds: scatola, puntatore: NSPoint(x: 140, y: 110))))
        // **La riga di bordo in cima, dove sta la X** (audit del 6/09): AppKit la
        // conta dentro e `contains` la contava fuori. Il metro nostro deve
        // rispondere come AppKit, altrimenti torna la scheda spenta all'angolo.
        prove.append(("la riga di pixel in cima alla scheda è DENTRO, come per AppKit",
                      SorgenteTrascinamento.VistaSorgente.dentro(bounds: scatola, puntatore: NSPoint(x: 90, y: 120))))
        prove.append(("polo negativo: con `contains` quella riga era fuori (il difetto)",
                      !scatola.contains(NSPoint(x: 90, y: 120))))
        prove.append(("dopo il braccio di una schermata si apre sul deposito", dopoSchermata == .deposito))
        prove.append(("polo negativo: dopo il braccio di una chat si apre sulle chat", dopoChat == .sessioni))

        return esito("banco delle schermate", prove)
    }

    /// Aspetta un lavoro asincrono da un banco sincrono. Sta qui e non nel
    /// codice dell'app apposta: è un attrezzo del banco.
    private static func semaforo<T: Sendable>(_ lavoro: @escaping @Sendable () async -> T) -> T? {
        let gruppo = DispatchGroup()
        let scatola = Scatola<T>()
        gruppo.enter()
        Task.detached { scatola.valore = await lavoro(); gruppo.leave() }
        _ = gruppo.wait(timeout: .now() + 10)
        return scatola.valore
    }

    private final class Scatola<T>: @unchecked Sendable { var valore: T? }

    // MARK: - La geometria del notch

    /// Il guscio da chiuso deve essere ESATTAMENTE il notch quando il notch
    /// c'è, e una linguetta quando non c'è. Il polo negativo è il Mac senza
    /// notch: se rispondesse `haNotch` anche lì, l'app disegnerebbe un
    /// rettangolo nero appeso al nulla in cima allo schermo.
    static func geometria() -> Int32 {
        let conNotch = Geometria(largoNotch: 200, altoNotch: 37)
        let senza = Geometria(largoNotch: 0, altoNotch: 0)

        let prove: [(String, Bool)] = [
            ("con notch: haNotch", conNotch.haNotch),
            ("con notch: il guscio chiuso è il notch (200×37)",
             conNotch.chiuso == CGSize(width: 200, height: 37)),
            ("polo negativo: senza notch NON dice haNotch", !senza.haNotch),
            ("senza notch: il guscio chiuso è la linguetta, non 0×0",
             senza.chiuso.width > 0 && senza.chiuso.height > 0),
            ("il guscio chiuso sta dentro quello aperto",
             conNotch.chiuso.width <= NotchPanel.apertoLargo
                && conNotch.chiuso.height <= NotchPanel.apertoAlto),
        ]
        return esito("banco della geometria", prove)
    }

    // MARK: - Il deposito che possiede

    /// La regola del 18/08: entrare nel deposito SPOSTA (l'origine resta
    /// vuota), uscire di mano passa dal Cestino, uscire per atterraggio
    /// elimina la copia nostra. Più la zona del clic senza tetto e la presa
    /// del rilascio (C1–C8, C10).
    @MainActor
    static func deposito() -> Int32 {
        var prove: [(String, Bool)] = []
        let fm = FileManager.default
        let sandbox = "banco-\(UUID().uuidString)"
        let archivio = Archivio(cartella: sandbox)
        defer { try? fm.removeItem(at: archivio.radice) }

        func origine(_ nome: String, _ contenuto: String = "ciao") -> URL {
            let url = fm.temporaryDirectory.appendingPathComponent(nome)
            try? Data(contenuto.utf8).write(to: url)
            return url
        }

        // C1 — spostare: l'origine non c'è più, la copia è nell'archivio.
        let a = origine("banco-sposta.txt", "il contenuto viaggia intero")
        let dentroA = archivio.sposta(a)
        prove.append(("spostare porta il file nell'archivio",
                      dentroA?.path.hasPrefix(archivio.radice.path) == true))
        prove.append(("spostare svuota l'origine (la sua regola)",
                      !fm.fileExists(atPath: a.path)))
        prove.append(("il contenuto arriva intero",
                      dentroA.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
                          == "il contenuto viaggia intero"))

        // Due file con lo stesso nome non si pestano.
        let b = origine("banco-sposta.txt", "secondo")
        let dentroB = archivio.sposta(b)
        prove.append(("stesso nome, due percorsi",
                      dentroB != nil && dentroB != dentroA))

        // C2 — se spostare non si può (cartella d'origine in sola lettura),
        // si copia e l'origine RESTA: la voce è comunque nostra.
        let gabbia = fm.temporaryDirectory.appendingPathComponent("banco-gabbia-\(UUID().uuidString)")
        try? fm.createDirectory(at: gabbia, withIntermediateDirectories: true)
        let chiuso = gabbia.appendingPathComponent("prigioniero.txt")
        try? Data("resto qui".utf8).write(to: chiuso)
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: gabbia.path)
        let dentroC = archivio.sposta(chiuso)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gabbia.path)
        prove.append(("origine intoccabile: entra comunque, per copia",
                      dentroC != nil && fm.fileExists(atPath: chiuso.path)))
        try? fm.removeItem(at: gabbia)

        // A4, polo negativo — un file inesistente non entra.
        let fantasma = fm.temporaryDirectory.appendingPathComponent("banco-fantasma-\(UUID()).txt")
        prove.append(("polo negativo: un file inesistente non entra",
                      archivio.sposta(fantasma) == nil))

        // C3/C15 — atterrata: la voce esce ma il file RESTA (il Finder copia
        // in modo asincrono: cancellare subito era il -43). Lo raccoglie
        // l'orizzonte degli orfani, e solo quando l'uscita è vecchia.
        let dep = Deposito(archivio: archivio)
        let atterra = archivio.scriviByte(Data("volo".utf8), estensione: "txt")!
        dep.aggiungi(url: atterra, nome: "volo.txt", nostra: true)
        dep.togli(dep.voci.first { $0.url == atterra }!, atterrata: true)
        prove.append(("atterrata: la voce esce e il file RESTA (mai strappato al Finder)",
                      !dep.voci.contains { $0.url == atterra } && fm.fileExists(atPath: atterra.path)))
        archivio.eliminaOrfani(tranne: Set(dep.voci.map(\.url.path)), orizzonte: 3600)
        prove.append(("polo positivo: dentro l'orizzonte l'orfano sopravvive",
                      fm.fileExists(atPath: atterra.path)))
        archivio.eliminaOrfani(tranne: Set(dep.voci.map(\.url.path)), orizzonte: -1)
        prove.append(("oltre l'orizzonte l'orfano si raccoglie",
                      !fm.fileExists(atPath: atterra.path)))
        let indiceURL = archivio.radice.appendingPathComponent("indice.json")
        try? Data("[]".utf8).write(to: indiceURL)
        archivio.eliminaOrfani(tranne: [], orizzonte: -1)
        prove.append(("polo negativo: l'indice non si raccoglie mai, nemmeno oltre l'orizzonte",
                      fm.fileExists(atPath: indiceURL.path)))

        // C4 — di mano: nel Cestino, con il nome ritrovabile.
        let firma = "banco-cestino-\(UUID().uuidString)"
        let daCestinare = archivio.scriviByte(Data("in salvo".utf8), estensione: "txt")!
        let rinominato = archivio.radice.appendingPathComponent("\(firma).txt")
        try? fm.moveItem(at: daCestinare, to: rinominato)
        dep.aggiungi(url: rinominato, nome: "\(firma).txt", nostra: true)
        dep.togli(dep.voci.first { $0.url == rinominato }!)
        let nelCestino = (try? fm.contentsOfDirectory(atPath: NSHomeDirectory() + "/.Trash"))?
            .first { $0.hasPrefix(firma) }
        prove.append(("di mano: la copia va nel Cestino, mai eliminata secca",
                      !fm.fileExists(atPath: rinominato.path) && nelCestino != nil))
        if let nelCestino {
            try? fm.removeItem(atPath: NSHomeDirectory() + "/.Trash/" + nelCestino)
        }

        // Una voce legacy non nostra si de-indicizza e il file resta.
        let suo = origine("banco-suo-\(UUID().uuidString).txt")
        dep.aggiungi(url: suo, nome: suo.lastPathComponent, nostra: false)
        dep.togli(dep.voci.first { $0.url == suo }!)
        prove.append(("una voce legacy non nostra: il file resta dov'era",
                      fm.fileExists(atPath: suo.path)))
        try? fm.removeItem(at: suo)

        // C6 — aprire il pannello pota i morti.
        let morto = archivio.radice.appendingPathComponent("mai-esistito.txt")
        let vivo = archivio.scriviByte(Data("vivo".utf8), estensione: "txt")!
        dep.aggiungi(url: morto, nome: "morto.txt", nostra: true)
        dep.aggiungi(url: vivo, nome: "vivo.txt", nostra: true)
        let stato = StatoNotch(appunti: Appunti(perSonda: []), deposito: dep)
        stato.toccato()
        prove.append(("aprire pota la voce morta",
                      !dep.voci.contains { $0.url == morto }))
        prove.append(("polo positivo: la voce viva sopravvive all'apertura",
                      dep.voci.contains { $0.url == vivo }))

        // C8 — il clic senza tetto: dentro sul bordo altissimo, fuori di lato.
        let zona = NSRect(x: 117.5, y: 228, width: 385, height: 40)
        prove.append(("clic al centro del notch: dentro",
                      VistaTracciamento.dentroSenzaTetto(NSPoint(x: 310, y: 240), zona)))
        prove.append(("clic sull'ultima riga dello schermo (y inchiodata): dentro",
                      VistaTracciamento.dentroSenzaTetto(NSPoint(x: 310, y: 268), zona)))
        prove.append(("clic ben sopra il tetto della zona: dentro (senza tetto)",
                      VistaTracciamento.dentroSenzaTetto(NSPoint(x: 310, y: 500), zona)))
        prove.append(("clic sul bordo sinistro esatto: dentro",
                      VistaTracciamento.dentroSenzaTetto(NSPoint(x: 117.5, y: 240), zona)))
        prove.append(("polo negativo: sotto la zona è fuori",
                      !VistaTracciamento.dentroSenzaTetto(NSPoint(x: 310, y: 227), zona)))
        prove.append(("polo negativo: di lato è fuori",
                      !VistaTracciamento.dentroSenzaTetto(NSPoint(x: 100, y: 240), zona)))

        // La scheda d'apertura (19/08, sua regola): appunti di norma,
        // deposito se ha ricevuto qualcosa da poco. `adesso` iniettato:
        // sei prove con lo stesso orologio non proverebbero niente.
        let statoApertura = StatoNotch(appunti: Appunti(perSonda: []), deposito: dep)
        prove.append(("apre su deposito subito dopo un ingresso",
                      statoApertura.schedaIniziale(adesso: Date()) == .deposito))
        prove.append(("polo: passata la recenza apre su appunti",
                      statoApertura.schedaIniziale(
                          adesso: Date().addingTimeInterval(StatoNotch.recenzaDeposito + 60)) == .appunti))
        let statoVergine = StatoNotch(appunti: Appunti(perSonda: []),
                                      deposito: Deposito(perSonda: []))
        prove.append(("polo: senza ingressi recenti apre su appunti",
                      statoVergine.schedaIniziale() == .appunti))

        // Il sopralzo (19/08): la zona viva arriva al TETTO della finestra,
        // che sborda oltre lo schermo — così la riga su cui il sistema
        // inchioda il puntatore (il bordo fisico) è una riga INTERNA.
        // Riprodotto coi clic sintetici: a y=1 apriva, a y=0 no.
        let statoZona = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
        statoZona.geometria = Geometria(largoNotch: 185, altoNotch: 32)
        let zonaChiusa = NotchPanel.zonaViva(stato: statoZona)
        prove.append(("la zona viva sale fino al tetto della finestra (\(Int(zonaChiusa.maxY)) = \(Int(NotchPanel.altezzaFinestra)))",
                      zonaChiusa.maxY == NotchPanel.altezzaFinestra))
        prove.append(("il bordo dello schermo è una riga interna della zona",
                      zonaChiusa.contains(NSPoint(x: 310, y: NotchPanel.apertoAlto))))
        prove.append(("polo negativo: senza sopralzo quel clic sarebbe fuori",
                      !NSRect(x: zonaChiusa.minX, y: zonaChiusa.minY,
                              width: zonaChiusa.width,
                              height: zonaChiusa.height - NotchPanel.sopralzo)
                          .contains(NSPoint(x: 310, y: NotchPanel.apertoAlto))))

        // C7 — la presa del rilascio: da chiuso è la zona sensibile, da
        // aperto è il guscio.
        let geo = Geometria(largoNotch: 185, altoNotch: 32)
        prove.append(("presa da chiuso = zona sensibile (\(Int(geo.sensibile.width))×\(Int(geo.sensibile.height)))",
                      geo.presa(guscio: geo.chiuso) == geo.sensibile))
        let apertoPieno = CGSize(width: NotchPanel.apertoLargo,
                                 height: NotchPanel.altezzaGuscio(notch: 32))
        prove.append(("presa da aperto = il guscio",
                      geo.presa(guscio: apertoPieno) == apertoPieno))

        // C10 — le miniature: il primo accesso decodifica, il secondo è cache.
        let grande = NSImage(size: NSSize(width: 3024, height: 1964), flipped: false) { r in
            NSGradient(colors: [.systemBlue, .systemOrange])?.draw(in: r, angle: 40)
            return true
        }
        let pngGrande: URL? = grande.tiffRepresentation
            .flatMap { NSBitmapImageRep(data: $0) }
            .flatMap { $0.representation(using: .png, properties: [:]) }
            .flatMap { archivio.scriviByte($0, estensione: "png") }
        if let pngGrande {
            let t0 = DispatchTime.now()
            let prima = Miniature.caricaSincrona(pngGrande)
            let t1 = DispatchTime.now()
            let seconda = Miniature.caricaSincrona(pngGrande)
            let t2 = DispatchTime.now()
            let msPrima = Double(t1.uptimeNanoseconds - t0.uptimeNanoseconds) / 1_000_000
            let msSeconda = Double(t2.uptimeNanoseconds - t1.uptimeNanoseconds) / 1_000_000
            prove.append(("la miniatura esce al lato giusto (≤\(Miniature.lato))",
                          prima != nil && max(prima!.size.width, prima!.size.height) <= CGFloat(Miniature.lato)))
            prove.append((String(format: "cache: %.2f ms contro %.2f ms di decodifica (≥10×)",
                                 msSeconda, msPrima),
                          seconda != nil && msSeconda * 10 < msPrima))
        } else {
            prove.append(("la PNG di prova si scrive", false))
        }
        prove.append(("polo negativo: miniatura di un file inesistente = niente",
                      Miniature.caricaSincrona(fantasma) == nil))

        // C97 — la scadenza del deposito (20/08). Quattro poli, perché una
        // pota che cancella troppo costa un originale: la nostra è spesso
        // l'unica copia.
        // Archivio suo: il deposito del banco qui sopra ha gia' delle voci, e
        // una pota conta QUANTE ne toglie — su un indice condiviso quel numero
        // misurerebbe anche il lavoro di un altro banco.
        let archivioScad = Archivio(cartella: "\(sandbox)-scadenza")
        defer { try? fm.removeItem(at: archivioScad.radice) }
        let scad = Deposito(archivio: archivioScad)
        let firmaScad = "banco-scadenza-\(UUID().uuidString)"
        func voceDiProva(_ suffisso: String) -> URL {
            let url = archivioScad.radice.appendingPathComponent("\(firmaScad)-\(suffisso).txt")
            try? Data("scado".utf8).write(to: url)
            scad.aggiungi(url: url, nome: url.lastPathComponent, nostra: true)
            return url
        }
        let vecchia = voceDiProva("vecchia")
        prove.append(("polo negativo: dentro la finestra non scade niente",
                      scad.potaScadute(orizzonte: 3600) == 0
                          && fm.fileExists(atPath: vecchia.path)))
        prove.append(("oltre la finestra la voce scade",
                      scad.potaScadute(orizzonte: -1) == 1
                          && !scad.voci.contains { $0.url == vecchia }
                          && !fm.fileExists(atPath: vecchia.path)))
        let cestinata = (try? fm.contentsOfDirectory(atPath: NSHomeDirectory() + "/.Trash"))?
            .first { $0.hasPrefix(firmaScad) }
        prove.append(("scaduta: nel Cestino, mai eliminata secca (la nostra e' l'unica copia)",
                      cestinata != nil))
        if let cestinata {
            try? fm.removeItem(atPath: NSHomeDirectory() + "/.Trash/" + cestinata)
        }

        // Il fissaggio e' la promessa che nessuna pota automatica lo tocca.
        let ferma = voceDiProva("ferma")
        scad.fissa(scad.voci.first { $0.url == ferma }!)
        prove.append(("polo negativo: una voce tenuta ferma non scade mai",
                      scad.potaScadute(orizzonte: -1) == 0
                          && fm.fileExists(atPath: ferma.path)))
        try? fm.removeItem(at: ferma)

        // La preferenza: «mai» e «mai scelto» sono opposti, e `integer(forKey:)`
        // li confonderebbe entrambi in 0 — e' il motivo per cui il campo si
        // legge con `object(forKey:)`.
        let difese = UserDefaults.standard
        let prima = difese.object(forKey: Deposito.chiaveScadenza)
        difese.removeObject(forKey: Deposito.chiaveScadenza)
        prove.append(("mai scelto: vale il default di \(Deposito.giorniScadenzaDefault) giorni",
                      Deposito.giorniScadenza == Deposito.giorniScadenzaDefault))
        difese.set(0, forKey: Deposito.chiaveScadenza)
        let eterna = voceDiProva("eterna")
        prove.append(("polo negativo: scelto «mai», non scade niente",
                      Deposito.giorniScadenza == 0 && scad.potaScadute() == 0
                          && fm.fileExists(atPath: eterna.path)))
        try? fm.removeItem(at: eterna)
        if let prima { difese.set(prima, forKey: Deposito.chiaveScadenza) }
        else { difese.removeObject(forKey: Deposito.chiaveScadenza) }

        return esito("banco del deposito", prove)
    }

    // MARK: - Quello che e' arrivato il 19/08

    /// Lettura del testo, conversione, scorrimento fra le schede, e la
    /// finestra delle impostazioni che deve stare al CENTRO.
    @MainActor
    static func nuove() -> Int32 {
        var prove: [(String, Bool)] = []
        let fm = FileManager.default
        let sandbox = "banco-\(UUID().uuidString)"
        let archivio = Archivio(cartella: sandbox)
        defer { try? fm.removeItem(at: archivio.radice) }

        // --- La TESTATA non si sovrappone. Il 19/08 «Svuota» scritto per
        // esteso finiva sopra la linguetta «Converti»: con tre schede il
        // selettore centrato è cresciuto e nessuno teneva il conto.
        prove.append((String(format: "il selettore e il blocco destro non si toccano (%.0f pt di respiro)",
                             NotchPanel.respiroTestata),
                      NotchPanel.respiroTestata > 8))
        // Polo negativo: la pillola col testo (76 pt) DEVE risultare rotta,
        // altrimenti questo banco non sta misurando la sovrapposizione.
        let respiroColTesto = (NotchPanel.larghezzaUtile - NotchPanel.larghezzaSelettore) / 2
            - (NotchPanel.larghezzaConteggio + NotchPanel.stacchiTestata + 76)
        prove.append((String(format: "polo negativo: col tastino scritto sarebbe rotta (%.0f pt)",
                             respiroColTesto),
                      respiroColTesto < 0))
        // Una scheda in più domani stringe il respiro: il banco lo dice prima
        // che lo veda lui.
        prove.append(("c'è respiro anche per il conteggio più lungo",
                      NotchPanel.larghezzaConteggio >= 70))

        // --- La fila è larga quanto le schede, non quanto il pannello: è
        // quello che restituisce il nero vuoto allo scorrimento fra schede.
        prove.append(("due schede occupano una fila stretta (\(Int(MisuraScheda.larghezzaFila(2))) pt)",
                      MisuraScheda.larghezzaFila(2) < NotchPanel.larghezzaUtile / 2))
        prove.append(("otto schede sfondano la riga utile e la fila si ferma lì",
                      MisuraScheda.larghezzaFila(8) > NotchPanel.larghezzaUtile))
        prove.append(("polo negativo: zero schede non occupano niente",
                      MisuraScheda.larghezzaFila(0) == 0))

        // --- Lo swipe: la soglia c'è ed è alta abbastanza da non scattare
        // per uno sfioro (suo rilievo del 19/08, «troppo sensibile»).
        prove.append(("la soglia dello swipe è alta (\(Int(VistaTracciamento.sogliaSwipe)) pt)",
                      VistaTracciamento.sogliaSwipe >= 40))

        // La riga di Converti e la finestra Impostazioni hanno lo stesso
        // respiro, e stanno larghe dentro il pannello senza toccarne i bordi.
        prove.append((String(format: "la riga di Converti sta nel pannello con margine (%.0f pt per lato)",
                             (NotchPanel.larghezzaUtile - NotchPanel.larghezzaRigaConverti) / 2),
                      NotchPanel.larghezzaRigaConverti < NotchPanel.larghezzaUtile - 40))
        prove.append(("polo negativo: la riga non è stretta come prima (380)",
                      NotchPanel.larghezzaRigaConverti > 420))

        // --- Le scritte dei tre bersagli stanno in una riga, MISURATE col
        // font vero invece che contate a caratteri. Con tre bersagli lo
        // spazio per ciascuno è sceso, e una nota che va a capo alza il suo
        // titolo rispetto agli altri due.
        let largoBersaglio = (NotchPanel.larghezzaUtile - 20) / 3 - 16
        func largaQuanto(_ testo: String, _ corpo: CGFloat, _ peso: NSFont.Weight) -> CGFloat {
            NSAttributedString(string: testo,
                               attributes: [.font: NSFont.systemFont(ofSize: corpo, weight: peso)])
                .size().width
        }
        for (nome, titolo, nota) in [("AirDrop", S.airdrop, S.mandaloVia),
                                     ("Alleggerisci", S.alleggerisci, S.notaAlleggerisci),
                                     ("Deposito", S.deposito, S.tienilodaParte)] {
            let lt = largaQuanto(titolo, 13, .medium)
            let ln = largaQuanto(nota, 10, .regular)
            prove.append((String(format: "il bersaglio %@ sta in una riga (titolo %.0f, nota %.0f, spazio %.0f)",
                                 nome, lt, ln, largoBersaglio),
                          lt < largoBersaglio && ln < largoBersaglio))
        }
        // Polo negativo: la nota lunga di prima DEVE risultare fuori misura.
        prove.append(("polo negativo: la nota lunga di prima non ci stava",
                      largaQuanto("Ne esce una copia leggera nel deposito", 10, .regular) > largoBersaglio))

        // --- Lo scorrimento fra le schede: si ferma ai capi, non gira.
        prove.append(("da appunti avanti si va sul deposito",
                      Scheda.appunti.scorrendo(avanti: true) == .deposito))
        prove.append(("dal deposito avanti si va sul convertitore",
                      Scheda.deposito.scorrendo(avanti: true) == .convertitore))
        prove.append(("dal convertitore avanti si va sulle chat",
                      Scheda.convertitore.scorrendo(avanti: true) == .sessioni))
        prove.append(("polo negativo: dall'ultima scheda avanti non si va da nessuna parte",
                      Scheda.sessioni.scorrendo(avanti: true) == .sessioni
                      && Scheda.allCases.last == .sessioni))
        prove.append(("polo negativo: da appunti indietro non si va da nessuna parte",
                      Scheda.appunti.scorrendo(avanti: false) == .appunti))

        // --- La lettura del testo, con due poli VERI: un'immagine con del
        // testo dentro deve darlo, una senza deve dare niente.
        let parola = "LIMBO"
        let conTesto = NSImage(size: NSSize(width: 640, height: 200), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            let stile = [NSAttributedString.Key.font: NSFont.systemFont(ofSize: 96,
                                                                        weight: .semibold),
                         .foregroundColor: NSColor.black]
            parola.draw(at: NSPoint(x: 40, y: 50), withAttributes: stile)
            return true
        }
        let senzaTesto = NSImage(size: NSSize(width: 640, height: 200), flipped: false) { r in
            NSColor.systemTeal.setFill(); r.fill()
            return true
        }
        func scrivi(_ img: NSImage, _ nome: String) -> URL? {
            guard let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return nil }
            let url = archivio.radice.appendingPathComponent(nome)
            try? png.write(to: url)
            return url
        }
        if let urlTesto = scrivi(conTesto, "con-testo.png"),
           let urlVuota = scrivi(senzaTesto, "senza-testo.png") {
            let letto = Ocr.testo(in: urlTesto)
            prove.append(("il testo dentro l'immagine si legge (trovato: «\(letto ?? "niente")»)",
                          letto?.uppercased().contains(parola) == true))
            prove.append(("polo negativo: un'immagine senza testo non ne inventa",
                          Ocr.testo(in: urlVuota) == nil))

            // --- La conversione: esce il formato chiesto, e l'originale resta.
            for formato in Convertitore.Formato.allCases {
                let uscita = archivio.radice
                    .appendingPathComponent("uscita-\(formato.rawValue).\(formato.estensione)")
                let fatta = Convertitore.scrivi(immagine: urlTesto, in: uscita, formato: formato)
                let tipo = fatta.flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
                    .flatMap { CGImageSourceGetType($0) as String? }
                prove.append(("converto in \(formato.titolo) e il tipo e' quello (\(tipo ?? "niente"))",
                              tipo == formato.tipo.identifier))
            }
            prove.append(("l'originale non si tocca mai",
                          fm.fileExists(atPath: urlTesto.path)))
            prove.append(("polo negativo: un file che non e' un'immagine non si converte",
                          Convertitore.scrivi(
                            immagine: archivio.radice.appendingPathComponent("non-esisto.png"),
                            in: archivio.radice.appendingPathComponent("mai.heic"),
                            formato: .heic) == nil))
        } else {
            prove.append(("le immagini di prova si scrivono", false))
        }

        // --- Da documento a PDF (sua richiesta del 19/08: «un docx in pdf»).
        // La fixture è un .docx VERO, costruito a mano e committato: provare
        // la conversione su un RTF scritto da noi vorrebbe dire misurare il
        // formato più facile invece di quello che gli serve.
        let docx = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixture/prova.docx")
        if fm.fileExists(atPath: docx.path) {
            let uscita = archivio.radice.appendingPathComponent("prova.pdf")
            let pdf = Documenti.pdf(da: docx, in: uscita)
            prove.append(("il docx diventa un PDF", pdf != nil))
            // E il PDF si RILEGGE: il testo dentro è quello del documento.
            // Un file che esiste non è un file giusto.
            if let pdf, let doc = PDFDocument(url: pdf) {
                let dentro = (0..<doc.pageCount)
                    .compactMap { doc.page(at: $0)?.string }.joined()
                prove.append(("il testo del documento è dentro il PDF (trovato: «\(dentro.prefix(28))»)",
                              dentro.contains("PIETRAMILIARE")))
                prove.append(("il PDF ha almeno una pagina", doc.pageCount >= 1))
            } else {
                prove.append(("il PDF prodotto si rilegge", false))
            }
        } else {
            prove.append(("la fixture .docx esiste (\(docx.lastPathComponent))", false))
        }
        prove.append(("polo negativo: un .png non è un documento da impaginare",
                      !Documenti.sappiamoLeggerlo(URL(fileURLWithPath: "/x/y.png"))))
        prove.append(("un .docx invece sì", Documenti.sappiamoLeggerlo(URL(fileURLWithPath: "/x/y.docx"))))

        // --- La ricodifica di un video CON AUDIO. È il banco che mancava:
        // il 19/08 la ricodifica si piantava su qualunque video con una
        // traccia audio (0% di CPU, file a 0 byte, nessun errore), e non me
        // ne ero accorto perché avevo misurato solo registrazioni dello
        // schermo, che audio non ne hanno. Ha 20 secondi di tempo: uno stallo
        // non deve fermare il banco, deve farlo fallire.
        let conAudio = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixture/con-audio.mp4")
        if fm.fileExists(atPath: conAudio.path) {
            let uscita = archivio.radice.appendingPathComponent("ricodificato.mp4")
            let esito = attendi(secondi: 20) {
                await RicodificaVideo.comprimi(conAudio, in: uscita, qualita: 0.55)
            }
            prove.append(("un video con audio si ricodifica senza piantarsi",
                          esito != nil))
            if let fatto = esito {
                let peso = (try? fatto.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                prove.append(("il file prodotto non è vuoto (\(peso) byte)", peso > 1000))
                let riletto = AVURLAsset(url: fatto)
                let tracce = attendi(secondi: 10) {
                    (try? await riletto.loadTracks(withMediaType: .audio))?.count ?? -1
                } ?? -1
                prove.append(("l'audio è ancora dentro (\(tracce) tracce)", tracce == 1))
            }
        } else {
            prove.append(("la fixture con audio esiste", false))
        }

        // Il pannello che si apre DA SOLO deve potersi richiudere da solo, e
        // non deve farlo se ci sei sopra col puntatore.
        let statoNotifica = StatoNotch(appunti: Appunti(perSonda: []),
                                       deposito: Deposito(perSonda: []))
        statoNotifica.aperto = true
        prove.append(("aperto e col puntatore fuori: si richiude da solo",
                      statoNotifica.puoChiudersiDaSola()))
        statoNotifica.puntatore(true)
        prove.append(("polo negativo: col puntatore sopra NON si richiude",
                      !statoNotifica.puoChiudersiDaSola()))
        statoNotifica.puntatore(false)
        statoNotifica.inArrivo = true
        prove.append(("polo negativo: mentre trascini NON si richiude",
                      !statoNotifica.puoChiudersiDaSola()))
        prove.append(("il messaggio che arriva da solo dura più di quello breve",
                      StatoNotch.soffioDaSolo > StatoNotch.soffioBreve))

        // --- Un video GIRATO COL TELEFONO non deve uscire schiacciato. Il
        // 19/08 un suo video di cucina (pixel 1920×1080 più «ruota di 90»,
        // visto verticale) è uscito compresso in orizzontale, e nessun banco
        // lo prendeva: le fixture erano tutte senza rotazione, cioè il caso
        // in cui il difetto non può esistere.
        let ruotato = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixture/ruotato.mp4")
        if fm.fileExists(atPath: ruotato.path) {
            let uscita = archivio.radice.appendingPathComponent("ruotato-uscita.mp4")
            let fatto = attendi(secondi: 40) {
                await RicodificaVideo.comprimi(ruotato, in: uscita, qualita: 0.55)
            }
            prove.append(("il video ruotato si ricodifica", fatto != nil))
            if fatto != nil {
                let prima = misuraVista(ruotato)
                let dopo = misuraVista(uscita)
                prove.append((String(format: "le proporzioni VISTE restano (%.0f×%.0f → %.0f×%.0f)",
                                     prima.width, prima.height, dopo.width, dopo.height),
                              prima == dopo && prima.height > prima.width))
            }
        } else {
            prove.append(("la fixture ruotata esiste", false))
        }

        prove.append(("un lavoro è «lungo» oltre i tre secondi, non oltre zero",
                      Convertitore.lavoroLungo >= 3))

        // --- Le due qualità video sono davvero due preset diversi.
        prove.append(("leggero e fedele sono due qualità diverse, e fedele è la più alta",
                      Convertitore.Qualita.leggero.valore < Convertitore.Qualita.fedele.valore))
        prove.append(("polo negativo: nessuna delle due è al massimo (sarebbe non comprimere)",
                      Convertitore.Qualita.fedele.valore < 1.0))

        // --- La finestra delle impostazioni sta al CENTRO dello schermo, non
        // appiccicata alla barra dei menu (suo rilievo del 19/08). Si
        // COSTRUISCE senza mostrarla: aprirla ruberebbe lo schermo a chi
        // lavora.
        if let schermo = NSScreen.main {
            let stato = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
            let finestra = Impostazioni.costruisci(stato: stato)
            let f = finestra.frame
            let dxCentro = abs(f.midX - schermo.visibleFrame.midX)
            let quantoSotto = schermo.visibleFrame.maxY - f.maxY
            prove.append((String(format: "centrata in orizzontale (scarto %.0f pt)", dxCentro),
                          dxCentro < 2))
            prove.append(("ha una misura vera, non zero",
                          f.width > 200 && f.height > 120))
            // Il difetto da prendere è quello del 19/08: la finestra in alto a
            // SINISTRA, incollata alla barra dei menu, perché lo stile assegnato
            // dopo il costruttore rifaceva il telaio. Il metro non può essere una
            // distanza fissa dal bordo (la soglia dei 20 pt bocciava il runner
            // della CI, schermo piccolo e finestra alta: 2 pt, ma centrata) e
            // nemmeno la simmetria, perché `center()` di Apple mette la finestra
            // un po' SOPRA il centro (84 pt sopra contro 249 sotto, misurato).
            // Quello che vale su ogni schermo: sta sotto la barra dei menu, e ci
            // sta dentro tutta.
            let quantoSopra = f.minY - schermo.visibleFrame.minY
            prove.append((String(format: "sotto la barra dei menu (%.0f pt)", quantoSotto),
                          quantoSotto > 0))
            prove.append((String(format: "tutta dentro lo schermo (%.0f pt liberi sotto)",
                                 quantoSopra),
                          schermo.visibleFrame.insetBy(dx: -1, dy: -1).contains(f)))
            // Polo negativo: la finestra del difetto, in alto a sinistra.
            let difetto = NSRect(x: schermo.visibleFrame.minX,
                                 y: schermo.visibleFrame.maxY - f.height,
                                 width: f.width, height: f.height)
            prove.append(("polo negativo: in alto a sinistra non passa",
                          !(schermo.visibleFrame.maxY - difetto.maxY > 0)
                            && abs(difetto.midX - schermo.visibleFrame.midX) >= 2))
        }

        return esito("banco di quello che e' arrivato il 19/08", prove)
    }

    // MARK: - Il movimento

    /// L'invariante misurato nella Fase 0: smorzamento pieno su apertura e
    /// chiusura, e apertura più svelta della chiusura. Il giorno che qualcuno
    /// «rende il notch più vivace» alzando il rimbalzo, questo banco diventa
    /// rosso e la decisione torna a essere una decisione.
    static func movimento() -> Int32 {
        let prove: [(String, Bool)] = [
            ("smorzamento pieno (\(Movimento.smorzamento))", Movimento.smorzamento == 1.0),
            ("apre più svelta di chiude (\(Movimento.rispostaApre) < \(Movimento.rispostaChiude))",
             Movimento.rispostaApre < Movimento.rispostaChiude),
            ("le due risposte stanno sotto il mezzo secondo",
             Movimento.rispostaApre < 0.5 && Movimento.rispostaChiude < 0.5),
            // I raggi annidati sono concentrici (regola 14 del gusto):
            // esterno = interno + padding, cioè interno = esterno − padding.
            ("raggi concentrici: \(Raggi.scheda) − \(Raggi.respiro) = \(Raggi.dentro)",
             Raggi.dentro == Raggi.scheda - Raggi.respiro),
            // Il vuoto che si VEDE sopra le linguette e quello sotto devono
            // coincidere. Sopra vale lo stacco piu' il gioco che la fila lascia
            // all'ingrandimento della scheda; sotto vale il respiro basso.
            ("i vuoti attorno alle linguette coincidono (\(NotchPanel.stacco + NotchPanel.giocoFila) = \(NotchPanel.respiroBasso))",
             NotchPanel.stacco + NotchPanel.giocoFila == NotchPanel.respiroBasso),
            // Il guscio aperto deve entrare nella finestra, che non cambia mai
            // misura: se un giorno il contenuto cresce, questo diventa rosso
            // prima che il pannello esca dallo schermo.
            ("il guscio aperto sta nella finestra (\(NotchPanel.altezzaGuscio(notch: 38)) <= \(NotchPanel.apertoAlto))",
             NotchPanel.altezzaGuscio(notch: 38) <= NotchPanel.apertoAlto),
            // Polo negativo: la stessa formula con un raggio sbagliato deve
            // risultare falsa, altrimenti sta confrontando due costanti sue.
            ("polo negativo: un raggio interno errato è bocciato",
             !(Raggi.scheda + 1 == Raggi.scheda - Raggi.respiro)),
        ]
        return esito("banco del movimento", prove)
    }

    // MARK: - La scheda Chat (C67–C72)

    /// Il banco legge e scrive SOLO in una cartella di prova: la vera
    /// `notch-sessions` è di LifeOS e Limbo non ci scrive mai (A5).
    @MainActor
    static func chat() -> Int32 {
        var prove: [(String, Bool)] = []
        let fm = FileManager.default
        let cartella = fm.temporaryDirectory
            .appendingPathComponent("banco-chat-\(UUID().uuidString)")
        try? fm.createDirectory(at: cartella, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: cartella) }

        let adesso = Date()
        let iso = ISO8601DateFormatter()
        func corpo(_ attivita: String, eta: TimeInterval = 60,
                   dettaglio: String? = nil, etichetta: String? = nil) -> Data {
            let quando = iso.string(from: adesso.addingTimeInterval(-eta))
            var testo = """
            {"description":"Sistemo la scheda Chat","activity":"\(attivita)",
             "ascent":{"key":"ascending","icon":"🧗","label":"Ascending","color":"#7dcfff"},
             "progress":{"done":12,"total":24},"project":"Limbo","ai":"claude",
             "cwd":"/tmp","iterm":"w0t2p0:ABCD-1234",
             "startedAt":"\(quando)","updatedAt":"\(quando)"}
            """
            if let dettaglio {
                testo = testo.replacingOccurrences(
                    of: "\"activity\":", with: "\"detail\":\"\(dettaglio)\",\"activity\":")
            }
            if let etichetta {
                testo = testo.replacingOccurrences(
                    of: "\"activity\":", with: "\"label\":\"\(etichetta)\",\"activity\":")
            }
            return Data(testo.utf8)
        }

        // --- La decodifica: campi giusti, rotto fuori, scaduto fuori (C67/C68).
        let voce = SessioniChat.decodifica(corpo("working"), id: "a", adesso: adesso)
        prove.append(("una voce piena si decodifica con i campi giusti",
                      voce?.descrizione == "Sistemo la scheda Chat"
                      && voce?.attivita == .lavora
                      && voce?.avanzamento == "12/24"
                      && voce?.progetto == "Limbo"
                      && voce?.etichetta == "Ascending"))
        prove.append(("polo negativo: un file rotto non entra",
                      SessioniChat.decodifica(Data("garbage{{{".utf8), id: "x", adesso: adesso) == nil))
        prove.append(("una voce più vecchia di 24 ore non si elenca",
                      SessioniChat.decodifica(corpo("working", eta: 25 * 3600), id: "y", adesso: adesso) == nil))

        // --- Il sonno: solo chi LAVORA muto da oltre 10 minuti (C68).
        let muta = SessioniChat.decodifica(corpo("working", eta: 11 * 60), id: "m", adesso: adesso)
        let attesa = SessioniChat.decodifica(corpo("waiting", eta: 11 * 60), id: "w", adesso: adesso)
        prove.append(("una chat che lavora muta da 11 minuti dorme",
                      muta?.inSonno(adesso: adesso) == true))
        prove.append(("una chat che aspetta te non dorme mai",
                      attesa?.inSonno(adesso: adesso) == false))
        prove.append(("una chat viva da 1 minuto non dorme",
                      voce?.inSonno(adesso: adesso) == false))

        // --- Il colore arriva scritto, mai calcolato: si legge e basta.
        prove.append(("il colore esadecimale si legge",
                      SessioneChat.colore(esadecimale: "#7dcfff") != nil))
        prove.append(("polo negativo: un colore rotto torna niente",
                      SessioneChat.colore(esadecimale: "zzz") == nil))

        // --- Il rilevatore di transizioni (C70/C71): la prima lettura tace,
        // un cambio verso «aspetta» o «finita» parla una volta sola, e con
        // l'avviso spento tace del tutto mentre la scheda resta viva.
        let store = SessioniChat(cartella: cartella)
        var avvisi: [(String, SessioneChat.Attivita)] = []
        store.nota = { avvisi.append(($0.id, $0.attivita)) }
        func scrivi(_ nome: String, _ dati: Data) {
            try? dati.write(to: cartella.appendingPathComponent("\(nome).json"))
        }
        scrivi("a", corpo("working"))
        store.ricarica(adesso: adesso)
        prove.append(("la prima lettura non avvisa mai", avvisi.isEmpty))
        scrivi("a", corpo("waiting", dettaglio: "Metodo auth"))
        store.ricarica(adesso: adesso)
        prove.append(("lavora → aspetta avvisa, una volta",
                      avvisi.count == 1 && avvisi.last?.1 == .aspetta))
        store.ricarica(adesso: adesso)
        prove.append(("lo stesso stato riletto non riavvisa", avvisi.count == 1))
        store.avvisaAttivo = false
        scrivi("a", corpo("done"))
        store.ricarica(adesso: adesso)
        prove.append(("con l'avviso spento il rilevatore tace (la scheda resta)",
                      avvisi.count == 1 && store.voci.first?.attivita == .finita))
        store.avvisaAttivo = true
        scrivi("b", corpo("working"))
        store.ricarica(adesso: adesso)
        scrivi("b", corpo("done"))
        store.ricarica(adesso: adesso)
        prove.append(("lavora → finita avvisa", avvisi.count == 2 && avvisi.last?.1 == .finita))

        // --- Il ciclo di vita del watcher (C72): vive quanto l'uso reale.
        prove.append(("avviso acceso → il watcher vive sempre",
                      SessioniChat.deveVivere(avvisa: true, pannelloAperto: false)))
        prove.append(("avviso spento + pannello aperto → vive",
                      SessioniChat.deveVivere(avvisa: false, pannelloAperto: true)))
        prove.append(("polo negativo: tutto spento e chiuso → non vive",
                      !SessioniChat.deveVivere(avvisa: false, pannelloAperto: false)))
        store.attiva()
        let vivaDopoAttiva = store.viva
        store.ferma()
        prove.append(("attiva apre il watcher e ferma lo chiude",
                      vivaDopoAttiva && !store.viva))
        let orfano = SessioniChat(cartella: cartella.appendingPathComponent("non-esiste"))
        orfano.attiva()
        prove.append(("polo negativo: senza cartella il watcher non nasce (e non esplode)",
                      !orfano.viva))

        // --- L'ordinamento: la più recente in cima.
        scrivi("vecchia", corpo("working", eta: 3600))
        store.ricarica(adesso: adesso)
        prove.append(("l'elenco è ordinato dalla più recente",
                      store.voci.first?.id != "vecchia" && store.voci.last?.id == "vecchia"))

        // --- IL BRACCIO DEL NOTCH (sua correzione del 19/08 sera). Tre
        // domande meccaniche: ci sta nella finestra? parte dal bordo del
        // notch invece che dal nulla? e la finestra gli lascia i clic?
        let geo = Geometria(largoNotch: 185, altoNotch: 32)
        let cornice = NotchPanel.corniceAvviso(geometria: geo)
        prove.append((String(format: "il braccio sta dentro la finestra (bordo destro %.0f <= %.0f)",
                             cornice.maxX, NotchPanel.apertoLargo),
                      cornice.maxX <= NotchPanel.apertoLargo))
        prove.append(("parte dal bordo destro del notch, senza cucitura",
                      abs(cornice.minX - (NotchPanel.apertoLargo + geo.chiuso.width) / 2) <= 1))
        prove.append(("e' alto quanto il notch, cioe' resta nella barra dei menu",
                      cornice.height == geo.chiuso.height))

        // Il clic sul braccio NON deve essere rubato dal notch, che da chiuso
        // si prende tutta la sua fascia. Tre poli sul predicato puro.
        let inFinestra = NotchPanel.corniceAvvisoInFinestra(geometria: geo)
        let zonaNotch = NotchPanel.zonaViva(stato: chiuso(geo))
        // Il punto va preso dove i due rettangoli si SOVRAPPONGONO davvero:
        // la zona sensibile del notch finisce prima della meta' del braccio,
        // quindi senza l'esclusione meta' braccio apre il pannello e meta' no.
        let suBraccio = NSPoint(x: inFinestra.minX + 20, y: inFinestra.midY)
        prove.append(("col braccio fuori, quel punto sarebbe del notch",
                      VistaTracciamento.nostro(suBraccio, zona: zonaNotch, esclusa: nil)))
        prove.append(("col braccio scoperto, il clic e' del braccio",
                      !VistaTracciamento.nostro(suBraccio, zona: zonaNotch, esclusa: inFinestra)))
        let suNotch = NSPoint(x: NotchPanel.apertoLargo / 2, y: NotchPanel.apertoAlto - 4)
        prove.append(("polo negativo: il notch resta suo, braccio o non braccio",
                      VistaTracciamento.nostro(suNotch, zona: zonaNotch, esclusa: inFinestra)))

        let conAvviso = StatoNotch(appunti: Appunti(perSonda: []),
                                   deposito: Deposito(perSonda: []),
                                   chat: SessioniChat(cartella: cartella))
        conAvviso.geometria = geo
        let finta = SessioniChat.decodifica(corpo("waiting", dettaglio: "Approva"), id: "z", adesso: adesso)!
        conAvviso.mostraAvviso(AvvisoChat(
            testo: S.braccio(progetto: "LifeOS", titolo: nil), ai: finta.ai, sessione: finta))

        // --- IL TESTO E LA MISURA DEL BRACCIO (sua correzione del 20/08).
        prove.append(("il braccio dice il progetto e basta, senza verbo",
                      S.braccio(progetto: "Kalamos", titolo: nil) == "Kalamos"))
        prove.append(("col titolo il braccio dice SOLO quello, non lo appiccica al progetto",
                      S.braccio(progetto: "LifeOS", titolo: "dashboard") == "dashboard"))
        prove.append(("polo negativo: un titolo vuoto non lascia il separatore appeso",
                      S.braccio(progetto: "Kalamos", titolo: "  ") == "Kalamos"))
        let cortoLargo = NotchPanel.larghezzaAvviso(testo: "Kalamos")
        let lungoLargo = NotchPanel.larghezzaAvviso(
            testo: "Biologo · igiene ed epidemiologia della vecchiaia")
        prove.append((String(format: "una parola sola non prende tutta la barra (%.0f < %.0f)",
                             cortoLargo, NotchPanel.avvisoLargo),
                      cortoLargo < NotchPanel.avvisoLargo))
        prove.append(("polo negativo: un testo lungo si ferma al tetto, non allarga il braccio",
                      lungoLargo == NotchPanel.avvisoLargo))
        // Il polo che avrebbe preso «Lif…»: il testo misurato deve entrare
        // nello spazio che il braccio gli lascia davvero.
        let spazioTesto = cortoLargo - NotchPanel.cromaturaAvviso
        let misuraKalamos = ("Kalamos" as NSString)
            .size(withAttributes: [.font: NotchPanel.carattereAvviso]).width
        prove.append((String(format: "il testo ci entra davvero (%.0f in %.0f)",
                             misuraKalamos, spazioTesto),
                      spazioTesto >= misuraKalamos))
        prove.append(("il braccio corto non scende sotto la misura minima",
                      NotchPanel.larghezzaAvviso(testo: "x") == NotchPanel.avvisoLargoMin))
        prove.append(("la zona che la finestra non ruba segue il braccio vero",
                      NotchPanel.corniceAvviso(geometria: geo, largo: cortoLargo).width == cortoLargo))
        prove.append(("il titolo corto arriva dal file di stato, non si inventa qui",
                      SessioniChat.decodifica(corpo("working", etichetta: "le ancore"),
                                              id: "t", adesso: adesso)?.titolo == "le ancore"))
        prove.append(("polo negativo: senza `label` nel file non c'è titolo",
                      finta.titolo == nil))
        // --- La scheda su cui si apre dopo un avviso (sua regola del 20/08).
        let dopoAvviso = StatoNotch(appunti: Appunti(perSonda: []),
                                    deposito: Deposito(perSonda: []),
                                    chat: SessioniChat(cartella: cartella))
        dopoAvviso.ultimoAvviso = adesso
        prove.append(("apri il notch entro un minuto dall'avviso e trovi le chat",
                      dopoAvviso.schedaIniziale(adesso: adesso) == .sessioni))
        prove.append(("polo negativo: passato il minuto si torna agli appunti",
                      dopoAvviso.schedaIniziale(
                        adesso: adesso.addingTimeInterval(StatoNotch.recenzaAvviso + 1)) == .appunti))
        prove.append(("polo negativo: senza avviso nessun dirottamento",
                      StatoNotch(appunti: Appunti(perSonda: []),
                                 deposito: Deposito(perSonda: []),
                                 chat: SessioniChat(cartella: cartella))
                        .schedaIniziale(adesso: adesso) == .appunti))
        prove.append(("il braccio scoperto segna l'ora, altrimenti la regola del minuto non parte",
                      { let s = StatoNotch(appunti: Appunti(perSonda: []),
                                           deposito: Deposito(perSonda: []),
                                           chat: SessioniChat(cartella: cartella))
                        s.mostraAvviso(AvvisoChat(testo: "x", ai: .claude, sessione: nil))
                        return s.ultimoAvviso != nil }()))
        prove.append(("la linguetta non porta il nome del suo assistente",
                      S.chat == "Agents"))

        prove.append(("il glifo distingue chi aspetta te da chi ha finito",
                      AvvisoChat(testo: "x", ai: .claude, sessione: finta).simbolo == "hourglass"))
        prove.append(("l'avviso mette il braccio e NON spalanca il pannello",
                      conAvviso.avviso != nil && conAvviso.aperto == false))
        conAvviso.chiudiAvviso()
        prove.append(("il braccio si richiude subito", !conAvviso.braccioScoperto))
        attendiSecondi(Movimento.rispostaChiude + 0.25)
        prove.append(("e la vista se ne va DOPO essersi richiusa, non prima",
                      conAvviso.avviso == nil))
        prove.append(("il segno è quello di Claude quando lo dice il file",
                      finta.ai == .claude))
        prove.append(("polo negativo: un'AI sconosciuta non finge di essere Claude",
                      SegnoAI(codice: "qualcosaltro") == .ignoto && SegnoAI(codice: nil) == .ignoto))

        // --- LA TOLLERANZA quando esci dal nero (sua richiesta del 19/08).
        prove.append((String(format: "da aperto la zona viva scende %.0f punti sotto il guscio",
                             NotchPanel.grazia),
                      NotchPanel.zonaViva(stato: aperto(geo)).height
                        > NotchPanel.altezzaGuscio(notch: geo.altoNotch) + NotchPanel.sopralzo))
        prove.append(("polo negativo: da CHIUSO la zona resta stretta (o si aprirebbe passando per la barra dei menu)",
                      NotchPanel.zonaViva(stato: chiuso(geo)).height
                        <= geo.sensibile.height + NotchPanel.sopralzo))
        prove.append(("la zona allargata non esce dalla finestra",
                      NotchPanel.zonaViva(stato: aperto(geo)).minY >= 0))

        return esito("banco della scheda Chat", prove)
    }

    /// Due stati minimi per interrogare `zonaViva`, che legge solo `aperto` e
    /// la geometria.
    @MainActor private static func aperto(_ geo: Geometria) -> StatoNotch {
        let s = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
        s.geometria = geo
        s.aperto = true
        return s
    }

    @MainActor private static func chiuso(_ geo: Geometria) -> StatoNotch {
        let s = StatoNotch(appunti: Appunti(perSonda: []), deposito: Deposito(perSonda: []))
        s.geometria = geo
        return s
    }

    /// Il tempo di grazia: uscire NON chiude subito, e rientrare annulla.
    /// Sta in un banco suo perché deve aspettare davvero.
    @MainActor
    static func grazia() -> Int32 {
        var prove: [(String, Bool)] = []
        let geo = Geometria(largoNotch: 185, altoNotch: 38)

        let s = aperto(geo)
        s.puntatore(false)
        prove.append(("uscito dal nero, resta aperta all'istante",
                      s.aperto && s.chiusuraInSospeso))
        s.puntatore(true)
        prove.append(("rientrando, la chiusura in attesa è annullata",
                      s.aperto && !s.chiusuraInSospeso))

        // E chi se ne va davvero? Si chiude, dopo la grazia. Senza questo polo
        // il primo direbbe solo «non si chiude mai», che è un difetto diverso.
        let via = aperto(geo)
        via.puntatore(false)
        let semaforo = DispatchSemaphore(value: 0)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(StatoNotch.graziaTempo + 0.25))
            semaforo.signal()
        }
        while semaforo.wait(timeout: .now()) == .timedOut {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        prove.append((String(format: "chi se ne va davvero chiude dopo %.2f s", StatoNotch.graziaTempo),
                      !via.aperto && !via.chiusuraInSospeso))

        // --- LA SCADENZA DEL TRASCINAMENTO (ricerca del 19/08, voce 5: la
        // zona di rilascio che resta incollata a schermo perché il sistema non
        // ha mandato il `dragExited` promesso). Si abbassa la scadenza e si
        // ASPETTA che scatti: dichiararla e non vederla scattare non prova
        // niente.
        let vera = StatoNotch.scadenzaArrivo
        StatoNotch.scadenzaArrivo = 0.25
        defer { StatoNotch.scadenzaArrivo = vera }
        let bloccato = aperto(geo)
        bloccato.mira(true)
        prove.append(("mirato: la zona di rilascio è su", bloccato.inArrivo))
        attendiSecondi(StatoNotch.scadenzaArrivo + 0.3)
        prove.append(("senza il `dragExited` del sistema, la zona si toglie da sola",
                      !bloccato.inArrivo && !bloccato.aperto))

        // Polo negativo: un rilascio ANDATO A BUON FINE non deve subire la
        // scadenza, o si chiuderebbe sotto le mani mentre guardi l'esito.
        let riuscito = aperto(geo)
        riuscito.mira(true)
        riuscito.miraConsumata()
        riuscito.aperto = true
        attendiSecondi(StatoNotch.scadenzaArrivo + 0.3)
        prove.append(("polo negativo: dopo un rilascio riuscito la scadenza non chiude niente",
                      riuscito.aperto && !riuscito.inArrivo))

        // --- LO SCHERMO GIUSTO (ricerca del 19/08, voce 1: il difetto più
        // segnalato delle app-notch). Qui si prova la SCELTA, che è pura; il
        // monitor vero resta una prova sua.
        prove.append(("senza schermi non si sceglie niente, e non si esplode",
                      NotchPanel.schermoGiusto(fra: [], principale: nil) == nil))

        return esito("banco della grazia del puntatore", prove)
    }

    /// Aspetta davvero, tenendo vivo il run loop: i lavori di questi stati
    /// girano sull'attore principale, e un `sleep` secco li bloccherebbe
    /// insieme al banco.
    @MainActor
    private static func attendiSecondi(_ secondi: TimeInterval) {
        let fine = Date().addingTimeInterval(secondi)
        while Date() < fine {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
    }

    // MARK: - L'aggiornamento

    /// Le decisioni pure dell'aggiornamento, tutte e due i poli: il caso buono
    /// verde E il caso storto rosso. Sta qui e non solo nei test perché
    /// `build-app.sh` non chiama `swift test`, e un cancello che gira solo
    /// quando qualcuno se lo ricorda non è un cancello.
    static func aggiornamenti() -> Int32 {
        var prove: [(String, Bool)] = []

        // Il confronto è numerico per componente: fra stringhe "0.10.0" starebbe
        // PRIMA di "0.9.0", ed è il difetto che questo polo esiste per prendere.
        prove.append(("0.10.0 batte 0.9.0",
                      Aggiornamenti.versionePiuNuova(installata: "0.9.0", tagRemoto: "v0.10.0") == "0.10.0"))
        prove.append(("la stessa versione non è un aggiornamento",
                      Aggiornamenti.versionePiuNuova(installata: "0.6.0", tagRemoto: "v0.6.0") == nil))
        prove.append(("una più vecchia non è un aggiornamento",
                      Aggiornamenti.versionePiuNuova(installata: "0.6.0", tagRemoto: "v0.5.9") == nil))
        prove.append(("un tag che non è un numero non muove niente",
                      Aggiornamenti.versionePiuNuova(installata: "0.6.0", tagRemoto: "ultima") == nil))
        prove.append(("0.6 e 0.6.0 sono la stessa cosa",
                      Aggiornamenti.versionePiuNuova(installata: "0.6", tagRemoto: "v0.6.0") == nil))

        prove.append(("senza controlli precedenti si guarda",
                      Aggiornamenti.eOra(ultimoControllo: nil, adesso: Date())))
        prove.append(("mezz'ora fa non si riguarda",
                      !Aggiornamenti.eOra(ultimoControllo: Date().addingTimeInterval(-1_800),
                                          adesso: Date(), intervallo: 3_600)))
        // Un orologio che va indietro (fuso, sincronizzazione) spegnerebbe il
        // controllo per sempre se la differenza negativa contasse come «poco fa».
        prove.append(("una data futura vale come scaduta",
                      Aggiornamenti.eOra(ultimoControllo: Date().addingTimeInterval(9_000),
                                         adesso: Date(), intervallo: 3_600)))

        let inApplicazioni = "/Applications/Limbo.app"
        let conCaskroom: (String) -> Bool = { $0 == "/opt/homebrew/Caskroom/limbo" }
        prove.append(("nel Caskroom e in /Applications: viene da brew",
                      Aggiornamenti.provenienza(percorsoBundle: inApplicazioni,
                                                radiciCaskroom: ["/opt/homebrew/Caskroom"],
                                                casa: "/Users/esempio",
                                                esiste: conCaskroom) == .homebrew))
        prove.append(("stesso posto, ma il Caskroom non ce l'ha: è a mano",
                      Aggiornamenti.provenienza(percorsoBundle: inApplicazioni,
                                                radiciCaskroom: ["/opt/homebrew/Caskroom"],
                                                casa: "/Users/esempio",
                                                esiste: { _ in false }) == .aMano))
        prove.append(("fuori da /Applications è a mano anche col Caskroom pieno",
                      Aggiornamenti.provenienza(percorsoBundle: "/Users/esempio/Scaricati/Limbo.app",
                                                radiciCaskroom: ["/opt/homebrew/Caskroom"],
                                                casa: "/Users/esempio",
                                                esiste: conCaskroom) == .aMano))

        prove.append(("da brew si aggiorna col cask del tap",
                      Aggiornamenti.azione(per: .homebrew, versione: "0.6.0")
                        == .aggiornaERiapri(argomenti: ["upgrade", "--cask", "xmasyx/tap/limbo"])))
        prove.append(("a mano si apre la pagina di QUELLA versione",
                      Aggiornamenti.azione(per: .aMano, versione: "0.6.0")
                        == .apriLaPagina(URL(string: "https://github.com/xmasyx/limbo/releases/tag/v0.6.0")!)))

        let json = Data(#"{"tag_name":"v0.6.0","name":"Limbo 0.6.0"}"#.utf8)
        prove.append(("il tag si legge dal JSON di GitHub",
                      Aggiornamenti.tagUltimaRelease(dalJSON: json) == "v0.6.0"))
        prove.append(("una risposta senza tag non inventa una versione",
                      Aggiornamenti.tagUltimaRelease(dalJSON: Data(#"{"name":"niente"}"#.utf8)) == nil))
        prove.append(("una risposta che non è JSON non inventa una versione",
                      Aggiornamenti.tagUltimaRelease(dalJSON: Data("<html>".utf8)) == nil))

        return esito("l'aggiornamento", prove)
    }
}
