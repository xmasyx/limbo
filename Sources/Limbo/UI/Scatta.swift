import AppKit
import SwiftUI

// La sonda visiva: `Limbo --scatta <cartella>` fotografa il pannello SENZA
// aprire finestre (MacAppRules §7 — una finestra di prova compare sullo Space
// attivo, cioè sotto le mani di chi sta usando il Mac).
//
// Fotografa l'INQUADRATURA INTERA e non il comando appena toccato
// (MacAppRules §2): l'armonia non è una proprietà di un controllo, è la
// relazione fra controlli vicini, e nell'inquadratura stretta quella
// differenza non esiste.
@MainActor
enum Scatta {
    static func esegui(cartella: String) -> Int32 {
        let dir = URL(fileURLWithPath: cartella, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // La geometria VERA di questo schermo quando c'è, altrimenti quella di
        // un MacBook Pro. Leggerla batte inventarla (MacAppRules §0.1), e
        // stamparla dice su cosa è stata fatta la fotografia.
        let geometria = NSScreen.main.map(Geometria.init)
            ?? Geometria(largoNotch: 200, altoNotch: 38)
        print("  geometria: notch \(Int(geometria.largoNotch))×\(Int(geometria.altoNotch))"
              + (geometria.haNotch ? "" : " (schermo senza notch)"))

        let finti = FintiDati()
        var esiti: [String] = []

        for scuro in [false, true] {
            let suffisso = scuro ? "-scuro" : ""

            esiti.append(salva(
                pannello(geometria: geometria, aperto: false, scheda: .appunti,
                         inArrivo: false, dati: finti, scuro: scuro),
                in: dir, nome: "chiuso\(suffisso).png", scuro: scuro))

            esiti.append(salva(
                pannello(geometria: geometria, aperto: true, scheda: .appunti,
                         inArrivo: false, dati: finti, scuro: scuro),
                in: dir, nome: "appunti\(suffisso).png", scuro: scuro))

            esiti.append(salva(
                pannello(geometria: geometria, aperto: true, scheda: .deposito,
                         inArrivo: false, dati: finti, scuro: scuro),
                in: dir, nome: "deposito\(suffisso).png", scuro: scuro))

            esiti.append(salva(
                pannello(geometria: geometria, aperto: true, scheda: .deposito,
                         inArrivo: true, dati: finti, scuro: scuro),
                in: dir, nome: "in-arrivo\(suffisso).png", scuro: scuro))
        }

        // Il vuoto: la schermata che si vede al primo avvio, ed è quella che
        // di solito nessuno guarda finché non la vede lui.
        esiti.append(salva(
            pannello(geometria: geometria, aperto: true, scheda: .appunti,
                     inArrivo: false, dati: FintiDati(vuoto: true), scuro: false),
            in: dir, nome: "vuoto.png"))

        // Un Mac senza notch: la linguetta esiste e non è un rettangolo nero
        // appeso al nulla.
        esiti.append(salva(
            pannello(geometria: Geometria(largoNotch: 0, altoNotch: 0), aperto: false,
                     scheda: .appunti, inArrivo: false, dati: finti, scuro: false),
            in: dir, nome: "senza-notch-chiuso.png"))

        // Le icone candidate per la conferma dell'eliminazione, affiancate:
        // sceglierne una a occhio dal nome non funziona, e mostrargliele
        // costa una fotografia (sua richiesta del 19/08, «il cestino non mi
        // fa impazzire»).
        esiti.append(salva(
            HStack(spacing: 18) {
                ForEach(["trash.fill", "trash", "arrow.up.trash", "xmark.bin.fill",
                         "sparkles", "wind"], id: \.self) { nome in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(Livrea.penna).frame(width: 56, height: 56)
                            Image(systemName: nome)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text(nome)
                            .font(.system(size: 9))
                            .foregroundStyle(Livrea.sopraGuscio.opacity(0.6))
                    }
                }
            }
            .padding(24)
            .background(Livrea.guscio),
            in: dir, nome: "icone-cestino.png"))

        // Il lavoro in corso: la barra deve esserci dal primo istante.
        do {
            let lavoro = FintiDati()
            let stato = StatoNotch(appunti: lavoro.appunti, deposito: lavoro.deposito)
            stato.geometria = geometria
            stato.aperto = true
            stato.scheda = .convertitore
            stato.convertitore.fingiLavoro("Registrazione schermo 2026-08-19.mov",
                                           avanzamento: 0.34)
            esiti.append(salva(NotchView(stato: stato, perSonda: true)
                .environment(\.colorScheme, .light)
                .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto),
                in: dir, nome: "convertitore-lavoro.png"))
        }

        // La conferma che copre: è la prova che il messaggio NON si
        // sovrappone più a quello che c'è sotto (suo rilievo del 19/08).
        esiti.append(salva(
            pannello(geometria: geometria, aperto: true, scheda: .convertitore,
                     inArrivo: false, dati: finti, scuro: false,
                     soffio: (S.convertito, Simboli.fatto)),
            in: dir, nome: "conferma.png"))
        esiti.append(salva(
            pannello(geometria: geometria, aperto: true, scheda: .deposito,
                     inArrivo: false, dati: FintiDati(vuoto: true), scuro: false,
                     soffio: (S.nelCestino, Simboli.cestino)),
            in: dir, nome: "conferma-cestino.png"))

        // La terza scheda, quella nata il 19/08.
        esiti.append(salva(
            pannello(geometria: geometria, aperto: true, scheda: .convertitore,
                     inArrivo: false, dati: finti, scuro: false),
            in: dir, nome: "convertitore.png"))

        // La quarta scheda: le chat del terminale. Le finte passano dalla
        // STESSA strada dei file veri (JSON su disco → decodifica), così la
        // fotografia prova anche la lettura, non solo il disegno. I colori
        // sono quelli che l'hook scrive davvero (tabella ascent di LifeOS).
        do {
            let sandbox = FileManager.default.temporaryDirectory
                .appendingPathComponent("scatta-chat-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sandbox) }
            let iso = ISO8601DateFormatter()
            func finta(_ nome: String, _ minuti: Double, _ corpo: String) {
                let quando = iso.string(from: Date().addingTimeInterval(-minuti * 60))
                let testo = corpo.replacingOccurrences(of: "QUANDO", with: quando)
                try? Data(testo.utf8).write(to: sandbox.appendingPathComponent("\(nome).json"))
            }
            finta("a", 1, """
            {"description":"Riscrivo il convertitore video di Limbo","label":"il convertitore","activity":"working",
             "ascent":{"key":"ascending","icon":"🧗","label":"Ascending","color":"#7dcfff"},
             "progress":{"done":12,"total":24},"project":"Limbo","cwd":"/tmp",
             "iterm":null,"startedAt":"QUANDO","updatedAt":"QUANDO"}
            """)
            finta("b", 3, """
            {"description":"Preparo il compendio per l'esame di novembre","label":"il compendio","activity":"waiting",
             "detail":"Approva: git push","ascent":{"key":"anchoring","icon":"⚓","label":"Anchoring","color":"#73daca"},
             "progress":{"done":40,"total":55},"project":"Biologo","cwd":"/tmp",
             "iterm":null,"startedAt":"QUANDO","updatedAt":"QUANDO"}
            """)
            finta("c", 8, """
            {"description":"Cerco i prezzi dei server per GBF","activity":"done",
             "ascent":{"key":"traverse","icon":"🥾","label":"Traverse","color":"#abb2bf"},
             "project":"GBF","cwd":"/tmp","iterm":null,
             "startedAt":"QUANDO","updatedAt":"QUANDO"}
            """)
            let chatFinte = SessioniChat(cartella: sandbox)
            chatFinte.avvisaAttivo = false
            chatFinte.ricarica()
            let stato = StatoNotch(appunti: finti.appunti, deposito: finti.deposito,
                                   chat: chatFinte)
            stato.geometria = geometria
            stato.aperto = true
            stato.scheda = .sessioni
            esiti.append(salva(NotchView(stato: stato, perSonda: true)
                .environment(\.colorScheme, .light)
                .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto),
                in: dir, nome: "chat.png"))

            // La pillola di lato: la cosa che vede davvero, perché arriva
            // mentre sta facendo altro. Il guscio è CHIUSO, come nella vita.
            let statoAvviso = StatoNotch(appunti: finti.appunti, deposito: finti.deposito,
                                         chat: chatFinte)
            statoAvviso.geometria = geometria
            // Due scatti, perché il braccio ha due misure: il solo nome del
            // progetto (il caso corto, quello che copre meno icone) e il
            // nome col titolo della chat, che è il caso lungo.
            statoAvviso.scopriBraccioPerSonda(AvvisoChat(
                testo: S.braccio(progetto: "Kalamos", titolo: nil), ai: .claude,
                sessione: chatFinte.voci.first))
            esiti.append(salva(NotchView(stato: statoAvviso, perSonda: true)
                .environment(\.colorScheme, .light)
                .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto),
                in: dir, nome: "avviso-laterale.png"))

            let statoTitolo = StatoNotch(appunti: finti.appunti, deposito: finti.deposito,
                                         chat: chatFinte)
            statoTitolo.geometria = geometria
            let attesa = chatFinte.voci.first { $0.attivita == .aspetta } ?? chatFinte.voci.first
            statoTitolo.scopriBraccioPerSonda(AvvisoChat(
                testo: S.braccio(progetto: "LifeOS", titolo: "dashboard"), ai: .claude,
                sessione: attesa))
            esiti.append(salva(NotchView(stato: statoTitolo, perSonda: true)
                .environment(\.colorScheme, .light)
                .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto),
                in: dir, nome: "avviso-laterale-titolo.png"))

            // E la scheda vuota, che è quella del primo sguardo.
            let statoVuoto = StatoNotch(appunti: finti.appunti, deposito: finti.deposito,
                                        chat: SessioniChat(cartella: sandbox.appendingPathComponent("niente")))
            statoVuoto.geometria = geometria
            statoVuoto.aperto = true
            statoVuoto.scheda = .sessioni
            esiti.append(salva(NotchView(stato: statoVuoto, perSonda: true)
                .environment(\.colorScheme, .light)
                .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto),
                in: dir, nome: "chat-vuota.png"))
        }

        // Le impostazioni: la PAGINA intera, per giudicare l'armonia sulle
        // righe vicine (MacAppRules §2), non il singolo comando.
        esiti.append(salva(
            ImpostazioniView(stato: StatoNotch(appunti: Appunti(perSonda: []),
                                               deposito: Deposito(perSonda: [])),
                             perSonda: true),
            in: dir, nome: "impostazioni.png"))

        for esito in esiti { print(esito) }
        return esiti.allSatisfy { $0.hasPrefix("✓") } ? 0 : 1
    }

    /// **Il banco della fluidità.** Rende il pannello aperto N volte e dice
    /// quanto costa un fotogramma.
    ///
    /// Misura il costo del `body`, non quello del compositore: un `body` che
    /// legge il disco costa uguale sullo schermo e qui, mentre lo scorrimento
    /// vero della grafica qui non c'è. È esattamente il pezzo che serve,
    /// perché è dove finiscono le letture di file fatte per sbaglio a ogni
    /// fotogramma. Soglia: a 60 fotogrammi al secondo un fotogramma dura
    /// 16,7 ms, e il `body` non dovrebbe prendersene più di un terzo.
    static func fluidita(giri: Int) -> Int32 {
        let geometria = NSScreen.main.map(Geometria.init)
            ?? Geometria(largoNotch: 185, altoNotch: 32)
        let finti = FintiDati()
        // Un giro a vuoto: la prima resa paga la costruzione dei caratteri e
        // non è rappresentativa di quelle dopo.
        _ = ImageRenderer(content: pannello(geometria: geometria, aperto: true, scheda: .deposito,
                                            inArrivo: false, dati: finti, scuro: false)).cgImage

        var esiti: [(String, Double)] = []
        for (nome, scheda) in [("deposito", Scheda.deposito), ("appunti", Scheda.appunti)] {
            // MEDIANA per giro, non media del blocco: la media somma anche i
            // picchi della macchina (Spotlight, una compilazione appena
            // finita, il termico), e il 19/08 il banco è diventato una
            // moneta — 4,3 e 6,2 ms per lo STESSO codice a minuti di
            // distanza. La mediana misura il fotogramma tipico, che è la
            // domanda vera; il picco isolato non è un difetto del `body`.
            var tempi: [Double] = []
            for _ in 0..<giri {
                let inizio = DispatchTime.now().uptimeNanoseconds
                _ = ImageRenderer(content: pannello(geometria: geometria, aperto: true,
                                                    scheda: scheda, inArrivo: false,
                                                    dati: finti, scuro: false)).cgImage
                tempi.append(Double(DispatchTime.now().uptimeNanoseconds - inizio) / 1_000_000)
            }
            esiti.append((nome, tempi.sorted()[tempi.count / 2]))
        }

        // E adesso il caso VERO, che è l'altro: non il pannello fermo, ma il
        // pannello a META' APERTURA. Lì il guscio cambia misura a ogni
        // fotogramma, quindi SwiftUI rifà l'impaginazione di tutte le schede
        // ogni volta, e in più deve costruirle la prima volta. È il momento
        // che lui descrive come impastato, e un banco sul pannello fermo non
        // lo vede nemmeno.
        do {
            let passi = 20
            var tempi: [Double] = []
            for i in 0..<passi {
                let frazione = Double(i) / Double(passi - 1)
                let inizio = DispatchTime.now().uptimeNanoseconds
                _ = ImageRenderer(content: pannelloAMeta(geometria: geometria, dati: finti,
                                                         frazione: frazione)).cgImage
                tempi.append(Double(DispatchTime.now().uptimeNanoseconds - inizio) / 1_000_000)
            }
            esiti.append(("in apertura", tempi.sorted()[tempi.count / 2]))
        }

        // **La soglia sta a un ORDINE DI GRANDEZZA dal tipico, non a filo.**
        // Il 19/08 questo cancello ha bocciato tre volte codice sano perché
        // stava al 20% sopra il valore normale: con la macchina carica (una
        // compilazione appena finita, il principale che lavora) lo stesso
        // identico codice dava 4,3 e 6,2 ms, e il cancello era diventato una
        // moneta — l'errore che OPERATIONAL_RULES chiama «un test che
        // asserisce l'ambiente prova la macchina, non il codice».
        //
        // Il difetto che questo banco ESISTE per prendere non è del 20%: è
        // una lettura di disco o una decodifica rimessa dentro il `body`, e
        // quelle costano 44 ms (una miniatura) o 589 ms (una schermata
        // ricodificata). Fra il tipico (~5 ms) e il difetto più piccolo mai
        // visto (44) c'è un fattore nove: la soglia sta in mezzo, a 12 ms, e
        // da lì non si muove per rumore. Il polo negativo qui sotto prova che
        // a 12 il difetto vero lo prende ancora.
        let soglia = 12.0
        var rotti = 0
        for (nome, ms) in esiti {
            let ok = ms < soglia
            if !ok { rotti += 1 }
            print(String(format: "  %@ %@: %.2f ms a fotogramma (soglia %.0f)",
                         ok ? "✓" : "✗", nome, ms, soglia))
        }

        // **Il polo negativo, ed è il pezzo che rende vero tutto il resto.**
        // Una vista che decodifica un'immagine intera a ogni fotogramma è
        // esattamente il difetto del 18/08. Se un giorno NON sfonda più la
        // soglia, il banco ha smesso di misurare e questa riga diventa rossa
        // al posto suo.
        let costoDifetto = misuraDifetto()
        let preso = costoDifetto > soglia
        if !preso { rotti += 1 }
        print(String(format: "  %@ polo negativo: una ricodifica nel corpo costa %.0f ms e sfonda la soglia",
                     preso ? "✓" : "✗", costoDifetto))

        print(rotti == 0 ? "✓ banco della fluidità" : "✗ banco della fluidità: \(rotti) su \(esiti.count + 1)")
        return rotti == 0 ? 0 : 1
    }

    /// Il costo di un `body` fatto MALE, e qui c'è una lezione pagata il
    /// 19/08: il primo polo che avevo scritto metteva `NSImage(contentsOf:)`
    /// dentro il corpo e costava **0,6 ms**, non i 44 che mi aspettavo.
    /// `NSImage` è PIGRO — apre l'intestazione e decodifica al disegno, in
    /// scala ridotta se la vista è piccola. Quindi quel polo non riproduceva
    /// nessun difetto e avrebbe dichiarato «preso» qualcosa che il banco non
    /// prende.
    ///
    /// Il difetto vero e documentato è un altro: la RICODIFICA di
    /// un'immagine grande sul thread che disegna, i 589 ms misurati il
    /// 18/08. Questo è il polo, e sfonda qualunque soglia ragionevole.
    private static func misuraDifetto() -> Double {
        let grande = NSImage(size: NSSize(width: 3024, height: 1964), flipped: false) { r in
            NSGradient(colors: [.systemBlue, .systemOrange])?.draw(in: r, angle: 40)
            return true
        }
        guard let tiff = grande.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        var tempi: [Double] = []
        for _ in 0..<3 {
            let inizio = DispatchTime.now().uptimeNanoseconds
            _ = rep.representation(using: .png, properties: [:])
            tempi.append(Double(DispatchTime.now().uptimeNanoseconds - inizio) / 1_000_000)
        }
        return tempi.sorted()[tempi.count / 2]
    }

    /// Il pannello a metà apertura: il guscio alla frazione data fra chiuso
    /// e aperto, esattamente come lo vede l'occhio durante la molla.
    private static func pannelloAMeta(geometria: Geometria, dati: FintiDati,
                                      frazione: Double) -> some View {
        let stato = StatoNotch(appunti: dati.appunti, deposito: dati.deposito)
        stato.geometria = geometria
        stato.aperto = frazione > 0.01
        stato.scheda = .deposito
        return NotchView(stato: stato, perSonda: true)
            .environment(\.colorScheme, .light)
            .frame(width: NotchPanel.apertoLargo * (0.3 + 0.7 * frazione),
                   height: NotchPanel.apertoAlto)
    }

    private static func pannello(
        geometria: Geometria, aperto: Bool, scheda: Scheda, inArrivo: Bool,
        dati: FintiDati, scuro: Bool, soffio: (String, String?)? = nil
    ) -> some View {
        let stato = StatoNotch(appunti: dati.appunti, deposito: dati.deposito)
        stato.geometria = geometria
        stato.aperto = aperto
        stato.scheda = scheda
        stato.inArrivo = inArrivo
        // Il messaggio si inietta a mano invece di chiamare `soffia`: quello
        // arma un timer che qui non servirebbe a niente.
        if let soffio {
            stato.soffio = soffio.0
            stato.simboloConferma = soffio.1
        }
        // Nessun fondo qui dentro. Un rettangolo di fondo chiesto a SwiftUI
        // usciva GIALLO (misurato il 2026-08-18: l'angolo del PNG leggeva
        // R 1,00 G 0,80 B 0,01 dove doveva esserci grigio), e la causa non
        // vale la pena di inseguirla: il fondo di una sonda è un fatto di
        // composizione, non di interfaccia, e si dipinge in AppKit dove il
        // colore è un numero e basta. Vedi `salva`.
        // `perSonda: true` — vedi il commento su NotchView.perSonda.
        return NotchView(stato: stato, perSonda: true)
        // `ImageRenderer` risolve i colori dal PROPRIO ambiente: il tema si
        // passa di qui, e NON con `performAsCurrentDrawingAppearance`, che in
        // un'altra app di casa ha prodotto un falso verde (file chiaro, sonda ✓).
        .environment(\.colorScheme, scuro ? .dark : .light)
        .frame(width: NotchPanel.apertoLargo, height: NotchPanel.apertoAlto)
    }

    private static func salva(_ vista: some View, in dir: URL, nome: String,
                              scuro: Bool = false) -> String {
        let renderer = ImageRenderer(content: vista)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { return "✗ \(nome): render vuoto" }
        guard let rep = suFondo(cg, scuro: scuro) else { return "✗ \(nome): composizione fallita" }
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return "✗ \(nome): niente png"
        }
        let url = dir.appendingPathComponent(nome)
        do { try png.write(to: url) } catch { return "✗ \(nome): \(error.localizedDescription)" }
        return "✓ \(nome) (\(rep.pixelsWide)×\(rep.pixelsHigh))"
    }

    /// Posa il render su un grigio medio, così il guscio nero si distingue dal
    /// nulla trasparente. Fatto in AppKit di proposito: qui un colore è tre
    /// numeri, non un valore che deve risolversi contro un ambiente che fuori
    /// da un'app non c'è.
    private static func suFondo(_ cg: CGImage, scuro: Bool) -> NSBitmapImageRep? {
        let larghezza = cg.width, altezza = cg.height
        guard let contesto = CGContext(
            data: nil, width: larghezza, height: altezza, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let grigio: CGFloat = scuro ? 0.16 : 0.62
        contesto.setFillColor(red: grigio, green: grigio, blue: grigio, alpha: 1)
        contesto.fill(CGRect(x: 0, y: 0, width: larghezza, height: altezza))
        contesto.draw(cg, in: CGRect(x: 0, y: 0, width: larghezza, height: altezza))
        guard let composto = contesto.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: composto)
    }
}

/// I dati finti della sonda. File veri su disco, perché il deposito mostra
/// icona e peso, e un file inesistente farebbe fotografare lo stato di errore
/// credendo di fotografare quello normale.
@MainActor
private struct FintiDati {
    let appunti: Appunti
    let deposito: Deposito

    init(vuoto: Bool = false) {
        if vuoto {
            appunti = Appunti(perSonda: [])
            deposito = Deposito(perSonda: [])
            return
        }

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("limbo-sonda", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let nota = dir.appendingPathComponent("Appunti di riunione.txt")
        try? "Preventivo rivisto, mancano i costi del server.".write(
            to: nota, atomically: true, encoding: .utf8)
        let dati = dir.appendingPathComponent("Preventivo GBF.pdf")
        try? Data(repeating: 0, count: 184_320).write(to: dati)
        let foto = dir.appendingPathComponent("Schermata 2026-08-18.png")
        if let png = Self.quadrato() { try? png.write(to: foto) }

        appunti = Appunti(perSonda: [
            .init(id: UUID(), contenuto: .testo(
                "Il vincolo non è il montaggio, è la pubblicazione: finché EP1 non esce, tutto il resto è preparazione."),
                  app: "Note", quando: Date()),
            .init(id: UUID(), contenuto: .immagine(foto), app: "Anteprima", quando: Date()),
            .init(id: UUID(), contenuto: .testo("bun LIFEOS/TOOLS/MergeSettings.ts"),
                  app: "Terminale", quando: Date()),
            .init(id: UUID(), contenuto: .file([dati]), app: "Finder", quando: Date()),
            .init(id: UUID(), contenuto: .testo("OVH VPS-2 — 4 vCore, 8 GB, 75 GB, €8,31"),
                  app: "Safari", quando: Date()),
        ])

        deposito = Deposito(perSonda: [
            .init(id: UUID(), url: foto, nome: "Schermata 2026-08-18.png",
                  quando: Date(), fissata: false, nostra: true),
            .init(id: UUID(), url: dati, nome: "Preventivo GBF.pdf",
                  quando: Date(), fissata: true, nostra: false),
            .init(id: UUID(), url: nota, nome: "Appunti di riunione.txt",
                  quando: Date(), fissata: false, nostra: false),
        ])
    }

    /// L'immagine di prova, alla misura di una schermata VERA del suo Mac
    /// (3024×1964). Era 400×260, e con quella il banco della fluidità
    /// rispondeva 3,88 ms cioè verde: stavo misurando il caso che avevo
    /// ricostruito io, non il suo. Una schermata reale è 57 volte più grande
    /// in pixel, e se la scheda la ridecodifica a ogni fotogramma la
    /// differenza è tutta lì.
    private static func quadrato() -> Data? {
        let immagine = NSImage(size: NSSize(width: 3024, height: 1964))
        immagine.lockFocus()
        NSColor(red: 0.184, green: 0.361, blue: 0.541, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 3024, height: 1964).fill()
        NSColor(red: 0.98, green: 0.968, blue: 0.941, alpha: 1).setFill()
        NSRect(x: 300, y: 300, width: 2400, height: 300).fill()
        NSRect(x: 300, y: 830, width: 1660, height: 300).fill()
        immagine.unlockFocus()
        guard let tiff = immagine.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
