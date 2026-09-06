import AppKit
import os
import SwiftUI

/// Il trascinamento fuori dal deposito, con la risposta su com'è finito.
///
/// **Perché non basta `.onDrag` di SwiftUI.** Consegna un `NSItemProvider` e
/// non dice mai com'è andata: chi trascina non sa se la cosa è atterrata o se
/// l'hai lasciata cadere nel vuoto. Senza quella risposta il deposito non può
/// svuotarsi da solo, e un'app che tiene tutto quello che le dai è una
/// clipboard, non un limbo (sua parola, 18/08).
///
/// **Le due scorciatoie provate e bocciate, con la prova.**
/// 1. Registrare il file a mano con `registerFileRepresentation(fileOptions:
///    [.openInPlace])` per avere il callback: **ha rotto il trascinamento del
///    tutto**, dal deposito non usciva più niente.
/// 2. Tenere `NSItemProvider(contentsOf:)` e aggiungere in coda una
///    registrazione di `public.file-url` per il segnale: misurato il 18/08,
///    `loadObject(URL)` usa la rappresentazione di sistema e **il callback non
///    scatta**; scatta solo chiedendo i dati grezzi. Un segnale che dipende da
///    quale strada sceglie la destinazione non è un segnale.
///
/// **Quindi la sessione di AppKit**, che è la strada in cui la risposta esiste
/// per costruzione: `draggingSession(_:endedAt:operation:)` dice l'operazione
/// avvenuta, e vuota vuol dire «non è successo niente».
///
/// Il prezzo è che questa vista prende tutti gli eventi del mouse della
/// scheda, quindi clic, tasto destro e passaggio del puntatore li rimanda
/// indietro lei. È il prezzo che la prima volta avevo giudicato troppo alto,
/// e mi sbagliavo: senza, la funzione che definisce l'app non c'è.
struct SorgenteTrascinamento: NSViewRepresentable {
    let url: URL
    let nome: String
    /// L'immagine che vola sotto il puntatore. `nil` = l'icona del file.
    let anteprima: NSImage?
    /// Le voci del menu col tasto destro, nell'ordine in cui si vedono.
    /// `nil` come azione disegna un separatore.
    let voci: [(titolo: String, azione: (() -> Void)?)]
    let clic: () -> Void
    let sfiorata: (Bool) -> Void
    /// `true` se il trascinamento è atterrato da qualche parte.
    let finito: (Bool) -> Void
    /// Il file sotto la scheda non esiste più: il gesto non parte. Senza
    /// questa guardia il Finder risponde lui, con l'errore -43, che è il modo
    /// peggiore di scoprirlo.
    var sparito: () -> Void = {}
    /// Il trascinamento è PARTITO: la scheda si nasconde, perché quello che
    /// vola sotto il puntatore è LEI (suo rilievo del 19/08: «si muove il
    /// file ma rimane comunque l'icona, invece dovrebbe muoversi proprio
    /// quella»). Se il gesto non atterra, `finito(false)` la rimette.
    var iniziato: () -> Void = {}
    /// **Il lato del quadrato in alto a destra che NON appartiene al
    /// trascinamento: è la X che butta la voce.** Zero = nessuna esclusione.
    ///
    /// Esiste perché il 6/09 la X disegnata da SwiftUI *sopra* questa vista
    /// compariva e non si premeva: l'ordine degli `.overlay` decide il
    /// disegno, ma questa è una vista AppKit vera e il colpo del mouse lo
    /// prende lei, sempre. La riparazione non è impilare meglio, è **avere un
    /// solo padrone degli eventi** e fargli sapere che quell'angolo è di un
    /// altro — la stessa forma dell'esclusione del braccio dal notch (19/08).
    var latoX: CGFloat = 0
    /// Premuta la X. Il trascinamento non parte e il clic non si conta.
    var xPremuta: () -> Void = {}

    func makeNSView(context: Context) -> VistaSorgente { VistaSorgente() }

    func updateNSView(_ vista: VistaSorgente, context: Context) {
        vista.url = url
        vista.nome = nome
        vista.anteprima = anteprima
        vista.voci = voci
        vista.clic = clic
        vista.sfiorata = sfiorata
        vista.finito = finito
        vista.sparito = sparito
        vista.iniziato = iniziato
        vista.latoX = latoX
        vista.xPremuta = xPremuta
    }

    final class VistaSorgente: NSView, NSDraggingSource {
        var url: URL?
        var nome: String = ""
        var anteprima: NSImage?
        var voci: [(titolo: String, azione: (() -> Void)?)] = []
        var clic: () -> Void = {}
        var sfiorata: (Bool) -> Void = { _ in }
        var finito: (Bool) -> Void = { _ in }
        var sparito: () -> Void = {}
        var iniziato: () -> Void = {}
        var latoX: CGFloat = 0
        var xPremuta: () -> Void = {}
        private let registro = Logger(subsystem: "app.limbo.mac", category: "trascina")

        /// Il quadrato della X, in coordinate della vista. `nil` quando la X
        /// non c'è. Sta qui e non nella vista SwiftUI perché deve rispondere
        /// alla stessa domanda che si fa `mouseDown`, con lo stesso sistema di
        /// coordinate: due geometrie in due posti sono il difetto del «Lif…».
        var zonaX: CGRect? {
            guard latoX > 0 else { return nil }
            // `maxY`, non `minY`: questa vista non è ribaltata (`isFlipped`
            // resta falso), quindi l'origine sta in BASSO a sinistra e
            // l'angolo in alto a destra è `maxY - lato`. Con `minY` la zona
            // sensibile finiva in basso, cioè dall'altra parte della scheda
            // rispetto alla X disegnata — il polo qui sotto lo prende.
            return CGRect(x: bounds.maxX - latoX, y: bounds.maxY - latoX,
                          width: latoX, height: latoX)
        }

        private var partenza: NSPoint?
        private var trascinato = false
        /// Il colpo è stato consumato dalla X: né trascinamento né clic.
        private var consumato = false
        private var area: NSTrackingArea?

        // MARK: - Passaggio del puntatore

        /// **Un solo metro per «dentro», e ogni scrittore lo usa.** L'audit
        /// del 6/09 (Codex + quattro sonde `swiftc` sul suo Mac) ha misurato
        /// che AppKit e `NSRect.contains` NON sono d'accordo sul bordo: sulla
        /// riga di pixel in cima alla scheda `NSMouseInRect` dice dentro e
        /// `contains` dice fuori (in fondo il contrario). Quindi un puntatore
        /// che arriva dall'alto e si FERMA sull'angolo riceveva l'«entrato» da
        /// AppKit e, al primo giro di impaginazione, un «fuori» dal mio
        /// riallineamento; e da lì nessun altro «entrato» poteva arrivare,
        /// perché per AppKit era già dentro. È l'angolo della X, ed è il
        /// motivo per cui la scheda restava spenta e il clic apriva il file.
        /// Il mouse sintetico non lo vedeva perché salta in mezzo alla scheda
        /// invece di fermarsi su un bordo.
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let nuova = NSTrackingArea(
                rect: bounds,
                // `.mouseMoved` è la riparazione automatica: uno stato
                // sbagliato dura fino al prossimo movimento, non fino alla
                // prossima uscita e rientro.
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self, userInfo: nil)
            addTrackingArea(nuova)
            area = nuova
            // Un'area ricostruita non sa niente dello stato: si riallinea.
            programmaRiallineamento()
        }

        /// Gli eventi non portano più una polarità: portano un punto, e il
        /// punto si giudica sempre con lo stesso metro (finding 1 dell'audit).
        /// Un evento di un'area vecchia, sopravvissuta alla ricostruzione, si
        /// ignora: l'ordine fra aree sovrapposte non è garantito.
        override func mouseEntered(with event: NSEvent) { giudica(event) }
        override func mouseExited(with event: NSEvent) { giudica(event) }
        override func mouseMoved(with event: NSEvent) { giudica(event) }

        private func giudica(_ event: NSEvent) {
            if let sua = event.trackingArea, let area, sua !== area { return }
            sfiorata(Self.dentro(bounds: bounds, puntatore: convert(event.locationInWindow, from: nil),
                                 ribaltata: isFlipped))
        }

        /// **Una scheda che scivola SOTTO il puntatore fermo non riceve
        /// nessun `mouseEntered`.** Il sistema manda entrata e uscita solo
        /// quando è il puntatore ad attraversare il bordo, non quando è il
        /// bordo a passare sotto il puntatore. Nel video del 6/09 (03:20) si
        /// vede esattamente questo: tolta una scheda, la vicina scorre al
        /// suo posto sotto la mano, non si accende, la X non compare, e il
        /// clic apre il file in Anteprima invece di buttarlo. Uscendo e
        /// rientrando funzionava, ed è il motivo per cui sembrava «il primo».
        /// Quindi a ogni cambio di geometria si guarda dov'è il puntatore
        /// ADESSO e si riallinea lo stato a mano.
        ///
        /// **Il riallineamento è DIFFERITO, non immediato, e la differenza è
        /// stata un altro video (03:27).** Dentro `setFrameSize` la vista ha la
        /// misura nuova ma spesso l'origine ancora vecchia: guardare il
        /// puntatore lì dentro rispondeva «fuori» a una scheda che il puntatore
        /// aveva appena davvero raggiunto, e quel «fuori» arrivava un istante
        /// DOPO il `mouseEntered` vero, spegnendola. Poi nessun altro
        /// «entrato» poteva arrivare, perché il puntatore era già dentro. Si
        /// vedeva come una X che si accende e sparisce entrando. Quindi si
        /// aspetta la fine del giro di impaginazione, quando origine e misura
        /// sono entrambe quelle definitive, e si guarda una volta sola.
        private var riallineamentoInCoda = false

        override func setFrameOrigin(_ nuovo: NSPoint) {
            super.setFrameOrigin(nuovo)
            programmaRiallineamento()
        }
        override func setFrameSize(_ nuovo: NSSize) {
            super.setFrameSize(nuovo)
            programmaRiallineamento()
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            programmaRiallineamento()
        }

        private func programmaRiallineamento() {
            guard !riallineamentoInCoda else { return }
            riallineamentoInCoda = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.riallineamentoInCoda = false
                self.riallineaSfiorata()
            }
        }

        func riallineaSfiorata() {
            guard let finestra = window, finestra.isVisible else { return }
            let nelloSchermo = NSEvent.mouseLocation
            let nellaFinestra = finestra.convertPoint(fromScreen: nelloSchermo)
            sfiorata(Self.dentro(bounds: bounds, puntatore: convert(nellaFinestra, from: nil),
                                 ribaltata: isFlipped))
        }

        /// La domanda, separata per il banco: il puntatore sta dentro? Col
        /// metro di AppKit (`NSMouseInRect`), non con `NSRect.contains`: i due
        /// differiscono proprio sulle righe di bordo, e il bordo alto è dove
        /// vive la X.
        static func dentro(bounds: NSRect, puntatore: NSPoint, ribaltata: Bool = false) -> Bool {
            NSMouseInRect(puntatore, bounds, ribaltata)
        }

        // MARK: - Clic e trascinamento

        override func mouseDown(with event: NSEvent) {
            partenza = event.locationInWindow
            trascinato = false
            consumato = false
            let punto = convert(event.locationInWindow, from: nil)
            let dentroX = zonaX?.contains(punto) ?? false
            // Il log è la sonda: un clic si prova leggendo dove è arrivato,
            // non guardando cosa non è successo.
            registro.info("mouseDown \(punto.x, privacy: .public),\(punto.y, privacy: .public) bounds \(self.bounds.width, privacy: .public)x\(self.bounds.height, privacy: .public) zonaX \(self.zonaX.map { "\($0)" } ?? "nessuna", privacy: .public) → \(dentroX ? "X" : "scheda", privacy: .public)")
            if dentroX {
                consumato = true
                xPremuta()
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !consumato else { return }
            guard !trascinato, let partenza, let url else { return }
            // Tre punti: sotto, è la mano che trema mentre clicca.
            let spostamento = hypot(event.locationInWindow.x - partenza.x,
                                    event.locationInWindow.y - partenza.y)
            guard spostamento > 3 else { return }
            // Un file morto non inizia il gesto: meglio dirlo noi subito che
            // farlo dire al Finder col -43 dopo che hai mirato.
            guard FileManager.default.fileExists(atPath: url.path) else {
                trascinato = true
                sparito()
                return
            }
            trascinato = true

            let elemento = NSDraggingItem(pasteboardWriter: url as NSURL)
            let immagine = anteprima ?? NSWorkspace.shared.icon(forFile: url.path)
            // 64 punti: si riconosce cosa stai spostando senza coprire la
            // cartella in cui stai mirando.
            let lato: CGFloat = 64
            let punto = convert(event.locationInWindow, from: nil)
            elemento.setDraggingFrame(
                NSRect(x: punto.x - lato / 2, y: punto.y - lato / 2, width: lato, height: lato),
                contents: immagine)
            iniziato()
            beginDraggingSession(with: [elemento], event: event, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            defer { partenza = nil; consumato = false }
            guard !consumato, !trascinato else { return }
            clic()
        }

        override func rightMouseDown(with event: NSEvent) {
            let menu = NSMenu()
            for voce in voci {
                guard let azione = voce.azione else {
                    menu.addItem(.separator())
                    continue
                }
                let elemento = NSMenuItem(title: voce.titolo,
                                          action: #selector(scegli(_:)), keyEquivalent: "")
                elemento.target = self
                elemento.representedObject = Azione(esegui: azione)
                menu.addItem(elemento)
            }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        @objc private func scegli(_ mittente: NSMenuItem) {
            (mittente.representedObject as? Azione)?.esegui()
        }

        /// Involucro per portare una closure dentro `representedObject`, che
        /// vuole un oggetto e non accetta una funzione.
        private final class Azione: NSObject {
            let esegui: () -> Void
            init(esegui: @escaping () -> Void) { self.esegui = esegui }
        }

        // MARK: - La risposta che serviva

        func draggingSession(
            _ sessione: NSDraggingSession,
            sourceOperationMaskFor contesto: NSDraggingContext
        ) -> NSDragOperation {
            // `.copy` e non `.move`: il file di destinazione lo scrive il
            // sistema, e un `.move` su un file SUO lo toglierebbe da dove
            // stava. Uscire dal limbo riguarda il limbo, non il disco.
            .copy
        }

        func draggingSession(
            _ sessione: NSDraggingSession,
            endedAt punto: NSPoint,
            operation: NSDragOperation
        ) {
            // Operazione vuota = lasciato cadere nel vuoto, o rifiutato dalla
            // destinazione. Lì la voce resta: perderla perché hai sbagliato
            // mira sarebbe il difetto peggiore dei due.
            finito(!operation.isEmpty)
        }
    }
}
