import AppKit
import SwiftUI

/// Il pannello che vive nel notch.
///
/// **La decisione che regge tutto: la finestra non cambia mai misura.** Sta
/// sempre alla taglia da aperta, e quello che si apre e si chiude è la vista
/// SwiftUI dentro. Ridimensionare un `NSWindow` a ogni passaggio del puntatore
/// vuol dire che AppKit e SwiftUI animano due cose diverse con due orologi
/// diversi, e si vede: il guscio arriva prima del contenuto, il testo si
/// ricompone a metà strada. La sua regola dice che le transizioni non muovono
/// il testo (MacAppRules §7), e con la finestra viva quella regola non è
/// ottenibile, solo approssimabile.
///
/// Il prezzo è una finestra grande e quasi tutta trasparente. Si paga con
/// `ignoresMouseEvents` sulle zone vuote, che è una riga.
final class NotchPanel: NSPanel {
    /// Quanto è grande da aperto. La larghezza è la decisione forte della
    /// schermata: sotto i 560 le schede degli appunti diventano francobolli.
    static let apertoLargo: CGFloat = 620

    /// L'altezza della FINESTRA sotto il bordo dello schermo, che è sempre
    /// più grande del guscio: la finestra non cambia mai misura, il guscio
    /// sì. Tiene il notch più alto che si vede sui Mac (38) più il contenuto.
    static let apertoAlto: CGFloat = 268

    /// Quanto la finestra SBORDA sopra il bordo fisico dello schermo. Il
    /// puntatore spinto in alto viene inchiodato dal sistema ESATTAMENTE sul
    /// bordo, e un clic lì cade sul CONFINE del frame: un confine non è
    /// dentro, e la finestra non riceveva niente. Riprodotto il 19/08 con i
    /// clic sintetici: a y=1 apriva, a y=0 no — ed è il suo «sotto la
    /// fotocamera sì, più in alto no». Sbordando, il bordo dello schermo
    /// diventa una riga INTERNA della finestra: il rettangolo del notch, per
    /// il mouse, continua oltre lo schermo (sua immagine, 19/08).
    static let sopralzo: CGFloat = 40

    /// L'altezza totale della finestra: il sopralzo fuori schermo più tutto
    /// il resto sotto il bordo.
    static let altezzaFinestra: CGFloat = apertoAlto + sopralzo

    // Le misure del contenuto, in un posto solo. Il guscio si somma da qui,
    // così il vuoto sotto le linguette è uguale a quello sopra invece di
    // essere l'avanzo di un'altezza decisa a mano (suo rilievo del 18/08:
    // «la stessa distanza che c'è tra le note e appunti-deposito deve
    // esserci anche sotto»).
    static let respiroAlto: CGFloat = 8
    /// La fila e' due punti piu' alta di una scheda per lato: serve a lasciar
    /// crescere la scheda sotto il puntatore (scala 1,03) senza che il bordo
    /// venga rasato dal ritaglio dello scorrimento.
    static let giocoFila: CGFloat = 2
    static let altezzaFila: CGFloat = 128 + giocoFila * 2
    /// Lo stacco DICHIARATO fra la fila e le linguette. Il vuoto che si VEDE
    /// e' questo piu' il gioco qui sopra, ed e' il motivo per cui i due numeri
    /// non sono uguali: il vuoto sotto vale `stacco + giocoFila`, cosi' quello
    /// che l'occhio misura sopra e sotto e' lo stesso (sua richiesta del
    /// 18/08: «la stessa distanza che c'e' tra le note e appunti-deposito deve
    /// esserci anche sotto»).
    static let stacco: CGFloat = 8
    static let altezzaLinguette: CGFloat = 28

    // --- Le misure della TESTATA, in un posto solo perché il banco le
    // importa invece di ricopiarle. Il 19/08 «Svuota» finiva SOPRA la
    // linguetta «Converti»: con tre schede il selettore centrato è cresciuto
    // e nessuno teneva il conto di quanto spazio restasse ai lati.
    static let margineTestata: CGFloat = 18
    /// 96 con tre schede; scesa a 78 quando è arrivata la quarta («Chat»,
    /// 19/08): a 96 il selettore mangiava il blocco destro (respiro −16, e
    /// il banco della testata lo dice). «Deposito» a 12 pt semibold sta in
    /// ~58, quindi la pillola non tronca niente.
    static let larghezzaVoceScheda: CGFloat = 78
    static let larghezzaConteggio: CGFloat = 78
    static let larghezzaSvuota: CGFloat = 30
    /// Le voci dei selettori della scheda Converti. Più larghe di prima: la
    /// riga si è allargata e due pillole piccole in mezzo a tanto vuoto
    /// sembrano un ripensamento.
    static let larghezzaVoceConverti: CGFloat = 76
    /// La riga della scheda Converti: la stessa larghezza della finestra
    /// Impostazioni, così le due pagine dell'app hanno lo stesso respiro.
    static let larghezzaRigaConverti: CGFloat = 470
    static let stacchiTestata: CGFloat = 6

    /// Quanto è larga la riga utile dentro il guscio.
    static var larghezzaUtile: CGFloat { apertoLargo - margineTestata * 2 }

    /// Il selettore delle schede, centrato: cresce con le schede.
    static var larghezzaSelettore: CGFloat {
        larghezzaVoceScheda * CGFloat(Scheda.allCases.count) + 4
    }

    /// Lo spazio che resta fra il bordo del selettore e il blocco di destra
    /// (conteggio più cestino). **Negativo = si sovrappongono**, ed è
    /// esattamente il difetto che lui ha fotografato.
    static var respiroTestata: CGFloat {
        let mezzoLibero = (larghezzaUtile - larghezzaSelettore) / 2
        let bloccoDestro = larghezzaConteggio + stacchiTestata + larghezzaSvuota
        return mezzoLibero - bloccoDestro
    }
    static let respiroBasso: CGFloat = stacco + giocoFila

    /// L'altezza del guscio aperto su uno schermo con quel notch.
    static func altezzaGuscio(notch: CGFloat) -> CGFloat {
        notch + respiroAlto + altezzaFila + stacco + altezzaLinguette + respiroBasso
    }

    // --- L'AVVISO LATERALE: la pillola che esce da sotto il notch verso
    // destra quando una chat finisce o aspetta te (sua richiesta del 19/08,
    // «leggermente di lato verso destra o poco verso il basso, l'icona di
    // Claude invece di tutta l'animazione grande»).
    //
    // Vive DENTRO la finestra da 620, che non cambia mai misura: a destra del
    // notch (185 punti, centrato) restano 217 punti, e la pillola ne usa 210
    // meno la sovrapposizione. Il banco lo verifica invece di crederci.
    static let avvisoLargo: CGFloat = 210

    /// Il carattere del braccio. Uno solo, condiviso da chi misura e da chi
    /// disegna: due caratteri diversi danno una larghezza che non è quella
    /// che si vede, e il testo esce dal nero.
    static let carattereAvviso = NSFont.systemFont(ofSize: 11, weight: .medium)
    // Le misure del braccio stanno QUI, e il disegno le legge da qui. Sono
    // scritte una volta sola apposta: al primo scatto del 20/08 la somma era
    // sei punti sotto il disegno e «LifeOS» usciva «Lif…» dentro un braccio
    // mezzo vuoto. Un numero copiato in due posti non dà un errore, dà una
    // parola troncata.
    static let margineAvvisoSinistro: CGFloat = 10
    static let segnoAvviso: CGFloat = 14
    static let staccoAvviso: CGFloat = 8
    static let glifoAvviso: CGFloat = 12
    static let margineAvvisoDestro: CGFloat = 14
    /// Due punti di gioco: il testo disegnato non è mai al micron quello
    /// misurato, e un troncamento da arrotondamento è comunque un difetto.
    static let giocoAvviso: CGFloat = 2
    /// Tutto ciò che nel braccio non è testo.
    ///
    /// **Il glifo è opzionale, e non per risparmiare.** Esiste per sostituire
    /// il verbo (sua regola del 19/08: «Kalamos», non «Kalamos aspetta te»),
    /// quindi in un avviso che il verbo ce l'ha scritto dentro è una
    /// ripetizione. Toglierlo libera 20 punti — glifo più uno stacco — ed
    /// erano esattamente i punti che mancavano al braccio della schermata,
    /// scoperti fotografando la barra dei menu il 6/09 e leggendo
    /// «Depositata · click = desk…».
    static func cromaturaAvviso(conGlifo: Bool = true) -> CGFloat {
        margineAvvisoSinistro + segnoAvviso + staccoAvviso * (conGlifo ? 2 : 1)
            + (conGlifo ? glifoAvviso : 0)
            + margineAvvisoDestro + giocoAvviso
    }
    static var cromaturaAvviso: CGFloat { cromaturaAvviso(conGlifo: true) }
    /// Sotto questa misura il braccio è un moncone, non una forma.
    static let avvisoLargoMin: CGFloat = 84

    /// **Il braccio è largo quanto il suo testo, mai di più.**
    /// Prima era sempre 210 e copriva le icone della barra dei menu anche per
    /// dire una parola (suo, 20/08: «già so che ogni tanto mi copre le icone,
    /// dura poco però è fastidiosa»). Il tetto resta 210: oltre, il testo si
    /// tronca con i puntini invece di allargare la forma.
    static func larghezzaAvviso(testo: String, conGlifo: Bool = true) -> CGFloat {
        min(avvisoLargo, max(avvisoLargoMin, fabbisognoAvviso(testo: testo, conGlifo: conGlifo)))
    }

    /// Quanto CHIEDEREBBE il braccio se non ci fosse un tetto. È la misura che
    /// serve ai banchi: `larghezzaAvviso` applica `min`, quindi confrontarla
    /// col tetto è una tautologia — un polo scritto così rispondeva verde
    /// mentre a schermo il testo era troncato (6/09).
    static func fabbisognoAvviso(testo: String, conGlifo: Bool = true) -> CGFloat {
        let largoTesto = (testo as NSString)
            .size(withAttributes: [.font: carattereAvviso]).width
        return ceil(largoTesto) + cromaturaAvviso(conGlifo: conGlifo)
    }

    /// Il bordo sinistro del braccio: il bordo DESTRO del notch, meno un
    /// punto. Il punto in meno non è pignoleria: due forme nere adiacenti
    /// arrotondate lasciano una cucitura chiara di mezzo pixel, e si vede.
    /// `largoChiuso` è la larghezza del guscio CHIUSO, che è già il notch dove
    /// c'è e la linguetta dove non c'è: un `max` in mezzo qui dentro sarebbe
    /// una seconda regola sullo stesso fatto, e infatti spostava il braccio di
    /// un punto e mezzo (preso dal banco, 19/08).
    static func avvisoDaSinistra(notch largoChiuso: CGFloat) -> CGFloat {
        (apertoLargo + largoChiuso) / 2 - 1
    }

    /// Il rettangolo del braccio, dall'alto della vista. Serve al banco per
    /// provare che sta dentro la finestra, e alla finestra per NON rubargli i
    /// clic (sta nella fascia del notch, che da chiusa si prende tutto).
    static func corniceAvviso(geometria: Geometria, largo: CGFloat = avvisoLargo) -> CGRect {
        CGRect(x: avvisoDaSinistra(notch: geometria.chiuso.width), y: 0,
               width: largo, height: geometria.chiuso.height)
    }

    /// Lo stesso rettangolo in coordinate della FINESTRA (origine in basso a
    /// sinistra), che è il sistema in cui ragiona `VistaTracciamento`.
    static func corniceAvvisoInFinestra(geometria: Geometria,
                                        largo: CGFloat = avvisoLargo) -> NSRect {
        let c = corniceAvviso(geometria: geometria, largo: largo)
        return NSRect(x: c.minX, y: apertoAlto - c.height, width: c.width, height: c.height)
    }

    /// **Quanto ci si può allontanare dal guscio aperto prima che si chiuda.**
    /// Sua richiesta del 19/08: «se resto nella zona intorno, anche fuori dal
    /// nero, deve restare aperta, a meno che non mi allontani abbastanza».
    /// Il guscio aperto è già largo quanto la finestra, quindi la tolleranza
    /// che si può dare è quella VERSO IL BASSO, che è anche la direzione in
    /// cui il puntatore esce nove volte su dieci: si torna al lavoro.
    /// 44 punti, e ne restano 6 di finestra sotto: oltre quelli sei uscito
    /// davvero.
    static let grazia: CGFloat = 44

    private let stato: StatoNotch

    /// Il clic destro sul notch apre il menu con le impostazioni e l'uscita.
    /// La barra dei menu non c'è più (sua scelta del 19/08), quindi «Esci»
    /// DEVE vivere qui: senza, l'unica via per chiudere l'app sarebbe
    /// Monitoraggio Attività.
    var apriImpostazioni: () -> Void = {}

    init(stato: StatoNotch) {
        self.stato = stato
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.apertoLargo, height: Self.altezzaFinestra),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        // Sopra ogni Space e anche a schermo intero: il notch c'è sempre, e un
        // deposito che sparisce quando apri un video a tutto schermo è un
        // deposito che non puoi usare mentre lavori.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        // Senza questa riga `.onHover` non riceve niente su un pannello che
        // non prende il fuoco, e l'app sembra morta finché non ci clicchi.
        acceptsMouseMovedEvents = true

        // Il tracciamento del puntatore vive QUI, non in SwiftUI. Il motivo è
        // un difetto vero (18/08): `.onHover` risponde alla vista che sta
        // sotto il puntatore, e aprire il pannello TOGLIE quella vista da
        // sotto il puntatore — il bersaglio invisibile del guscio chiuso
        // sparisce nell'istante in cui l'apertura comincia. SwiftUI legge
        // «sei uscito» e richiude subito, che è esattamente quello che lui
        // vedeva: «clicco, mi muovo, scompare».
        //
        // A livello di finestra la posizione del mouse è un fatto, non una
        // conseguenza di quali viste esistono in questo fotogramma.
        let tracciante = VistaTracciamento()
        tracciante.zonaViva = { [weak stato] in
            guard let stato else { return .zero }
            return Self.zonaViva(stato: stato)
        }
        tracciante.cambio = { [weak stato] dentro in
            guard let stato else { return }
            withAnimation(Movimento.guscio(aperto: dentro)) { stato.puntatore(dentro) }
        }
        // Anche il CLIC che apre si giudica qui, come l'hover: a livello di
        // finestra il punto del mouse è un fatto. Sua richiesta del 18/08:
        // deve prendere in QUALUNQUE punto del rettangolo nero — sotto la
        // fotocamera, ai bordi, e con il puntatore sparato in alto oltre il
        // notch (il sistema lo inchioda sull'ultima riga, e quella riga deve
        // contare come dentro). La zona si ruba solo da chiuso: da aperto i
        // clic appartengono alle schede.
        tracciante.zonaClic = { [weak stato] in
            guard let stato, !stato.aperto else { return nil }
            return Self.zonaViva(stato: stato)
        }
        tracciante.clic = { [weak stato] in
            guard let stato else { return }
            withAnimation(Movimento.apre) { stato.toccato() }
        }
        tracciante.zonaEsclusa = { [weak stato] in
            guard let stato, stato.avviso != nil, !stato.aperto else { return nil }
            return Self.corniceAvvisoInFinestra(geometria: stato.geometria,
                                                largo: stato.larghezzaAvviso)
        }
        tracciante.menuContestuale = { [weak self] in self?.menuNotch }
        // Lo scorrimento a due dita cambia scheda — ma solo quello che arriva
        // FIN QUI. Sopra la fila delle schede lo prende la fila (è una
        // `ScrollView` orizzontale, e AppKit consegna l'evento alla vista più
        // profonda che lo gestisce): così scorrere le schede continua a
        // scorrerle, ed è il conflitto che gli avevo promesso di risolvere
        // così il 19/08.
        tracciante.scorrimento = { [weak stato] avanti in
            guard let stato, stato.aperto, !stato.inArrivo else { return }
            stato.scorri(avanti: avanti)
        }
        let ospite = NSHostingView(rootView: NotchView(stato: stato))
        ospite.translatesAutoresizingMaskIntoConstraints = false
        tracciante.addSubview(ospite)
        NSLayoutConstraint.activate([
            ospite.topAnchor.constraint(equalTo: tracciante.topAnchor),
            ospite.bottomAnchor.constraint(equalTo: tracciante.bottomAnchor),
            ospite.leadingAnchor.constraint(equalTo: tracciante.leadingAnchor),
            ospite.trailingAnchor.constraint(equalTo: tracciante.trailingAnchor),
        ])
        contentView = tracciante
        posiziona()

        NotificationCenter.default.addObserver(
            self, selector: #selector(schermoCambiato),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        // E anche al RISVEGLIO. Il caso che rompe le app-notch degli altri è
        // «coperchio chiuso, monitor collegato, poi risveglio»: lì i parametri
        // dello schermo cambiano mentre il Mac dorme, e chi ascolta solo la
        // notifica di sopra si sveglia posizionato dove non deve
        // (boring.notch #241, #250: «serve riavviare l'app»).
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(schermoCambiato),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func schermoCambiato() { posiziona() }

    /// Appesa al bordo FISICO alto dello schermo, centrata: è l'unico modo
    /// perché il guscio nero continui il notch invece di disegnarci accanto un
    /// rettangolo.
    /// **Lo schermo su cui vivere è quello che HA il notch, non quello attivo.**
    /// `NSScreen.main` è lo schermo della finestra col fuoco: collegato un
    /// monitor esterno e cliccatoci dentro, il pannello ci si trasferirebbe, e
    /// lì non c'è nessun notch con cui fondersi — resterebbe un rettangolo nero
    /// appeso in cima allo schermo sbagliato.
    ///
    /// Non è una mia ipotesi: è il difetto più segnalato delle app-notch, e il
    /// gruppo di boring.notch lo tiene aperto da mesi su quattro issue distinte
    /// (#219, #241, #250, #227), ammettendo che servirebbe «un gestore
    /// multi-monitor proprio». Ricerca del 19/08, e qui costa cinque righe.
    static func schermoGiusto(fra schermi: [NSScreen], principale: NSScreen?) -> NSScreen? {
        schermi.first { Geometria(schermo: $0).haNotch } ?? principale ?? schermi.first
    }

    func posiziona() {
        guard let schermo = Self.schermoGiusto(fra: NSScreen.screens, principale: NSScreen.main)
        else { return }
        stato.geometria = Geometria(schermo: schermo)
        // Il tetto della finestra sta OLTRE il bordo dello schermo (vedi
        // `sopralzo`): la parte visibile resta identica, ma il clic con il
        // puntatore inchiodato sul bordo cade su una riga interna del frame.
        setFrame(NSRect(
            x: schermo.frame.midX - Self.apertoLargo / 2,
            y: schermo.frame.maxY - Self.apertoAlto,
            width: Self.apertoLargo,
            height: Self.altezzaFinestra
        ), display: true)
    }

    /// Il rettangolo che «conta» in coordinate della finestra: il guscio
    /// aperto quando è aperto, la zona sensibile allargata quando è chiuso.
    /// L'origine della finestra è in basso a sinistra, e il guscio è appeso in
    /// alto e centrato.
    static func zonaViva(stato: StatoNotch) -> NSRect {
        // Da APERTO la zona è il guscio PIÙ la grazia sotto: uscire dal nero
        // non è ancora andarsene. Da chiuso resta la zona sensibile, stretta,
        // perché lì la domanda è un'altra (ci stai puntando?) e allargarla
        // vorrebbe dire aprirsi quando passi per la barra dei menu.
        let misura: CGSize = stato.aperto
            ? CGSize(width: apertoLargo,
                     height: min(altezzaGuscio(notch: stato.geometria.altoNotch) + grazia,
                                 apertoAlto))
            : stato.geometria.sensibile
        return NSRect(
            x: (apertoLargo - misura.width) / 2,
            y: apertoAlto - misura.height,
            width: misura.width,
            // Fino al TETTO della finestra, sopralzo compreso: il puntatore
            // inchiodato sul bordo dello schermo deve risultare dentro anche
            // per l'hover, o il pannello aperto col clic lassù si
            // richiuderebbe da solo.
            height: misura.height + sopralzo)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var menuNotch: NSMenu {
        let menu = NSMenu()
        // `autoenablesItems` va spento, altrimenti AppKit decide da sé quali
        // voci sono attive guardando la catena dei responder e le disattiva
        // tutte su un pannello che non prende il fuoco.
        menu.autoenablesItems = false

        // Svuota il deposito: era nella barra dei menu e lì è tornato (sua
        // richiesta del 19/08). Spento quando il deposito è già vuoto: una
        // voce grigia dice «non c'è niente», una voce che non fa niente no.
        let svuota = NSMenuItem(title: S.svuotaDeposito,
                                action: #selector(voceSvuota), keyEquivalent: "")
        svuota.target = self
        svuota.isEnabled = !stato.deposito.voci.isEmpty
        menu.addItem(svuota)
        menu.addItem(.separator())

        let impostazioni = NSMenuItem(title: S.impostazioni,
                                      action: #selector(voceImpostazioni), keyEquivalent: "")
        impostazioni.target = self
        menu.addItem(impostazioni)
        menu.addItem(.separator())
        let esci = NSMenuItem(title: S.esci,
                              action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        esci.target = NSApp
        menu.addItem(esci)
        return menu
    }

    @objc private func voceImpostazioni() { apriImpostazioni() }

    @objc private func voceSvuota() {
        stato.deposito.svuota()
        stato.soffia(S.nelCestino, simbolo: Simboli.cestino)
    }
}

/// Le misure vere del notch di QUESTO schermo, lette dal sistema invece che
/// indovinate (MacAppRules §0.1: se un fatto è leggibile dal sistema, non si
/// chiede e non si stima).
struct Geometria: Equatable {
    /// Larghezza del notch fisico. Su un Mac senza notch è 0.
    let largoNotch: CGFloat
    /// Altezza del notch, cioè quanto scende la plastica nera.
    let altoNotch: CGFloat

    var haNotch: Bool { largoNotch > 0 && altoNotch > 0 }

    /// **La zona che risponde è più larga del guscio che si vede.** Il guscio
    /// chiuso è il notch: 185 punti su uno schermo da 1512, cioè un bersaglio
    /// che si manca. Suo rilievo del 18/08: «non me lo apre istantaneamente,
    /// anche se non sono ancora arrivato al notch» — stava cliccando vicino,
    /// non sopra. Si allarga di 40 punti per lato e di 6 in basso, che al
    /// centro della barra dei menu è spazio vuoto: lì non c'è nessun comando
    /// di sistema da rubare.
    var sensibile: CGSize {
        // 100 punti per lato e 8 in basso. Larga: al centro della barra dei
        // menu non c'è nessun comando di sistema da rubare, quindi allargare
        // costa zero e il notch da solo (185 punti su 1512) è un bersaglio che
        // si manca. Bassa con misura: oltre l'altezza della barra dei menu si
        // comincerebbe a mangiare i clic della finestra sotto.
        CGSize(width: chiuso.width + 200, height: chiuso.height + 8)
    }

    /// La cornice che AGGANCIA un rilascio: il guscio, ma mai più stretta
    /// della zona sensibile. Da chiuso il notch è 185×32 e il puntatore che
    /// trascina è NASCOSTO sotto la plastica: chiedere di centrarlo alla
    /// cieca era il «primo tentativo che non funziona» del 18/08.
    func presa(guscio: CGSize) -> CGSize {
        CGSize(width: max(guscio.width, sensibile.width),
               height: max(guscio.height, sensibile.height))
    }

    /// La misura del guscio da CHIUSO. Con il notch è il notch stesso, e
    /// l'app è invisibile finché non la sfiori. Senza notch è una linguetta
    /// discreta appesa in alto, che è l'unico modo di esistere su un Mac che
    /// non ha il posto.
    var chiuso: CGSize {
        haNotch
            ? CGSize(width: largoNotch, height: altoNotch)
            : CGSize(width: 190, height: 32)
    }

    init(schermo: NSScreen) {
        let inserto = schermo.safeAreaInsets.top
        if inserto > 0, let sinistra = schermo.auxiliaryTopLeftArea,
           let destra = schermo.auxiliaryTopRightArea {
            largoNotch = schermo.frame.width - sinistra.width - destra.width
            altoNotch = inserto
        } else {
            largoNotch = 0
            altoNotch = 0
        }
    }

    /// Il caso senza schermo, per i banchi headless.
    init(largoNotch: CGFloat, altoNotch: CGFloat) {
        self.largoNotch = largoNotch
        self.altoNotch = altoNotch
    }
}

/// La vista che sa dov'è il puntatore, e basta.
///
/// Non disegna niente e non intercetta i clic: l'area di tracciamento di
/// AppKit convive con le viste sopra, quindi le schede continuano a ricevere i
/// loro gesti. `.activeAlways` serve perché questo pannello non prende mai il
/// fuoco: senza, gli eventi arriverebbero solo quando l'app è quella davanti,
/// cioè mai.
final class VistaTracciamento: NSView {
    /// Il rettangolo che in questo momento conta come «dentro».
    var zonaViva: () -> NSRect = { .zero }
    /// Chiamata SOLO quando lo stato cambia davvero, non a ogni movimento.
    var cambio: (Bool) -> Void = { _ in }
    /// La zona in cui un clic ci appartiene, o `nil` quando i clic sono delle
    /// schede (pannello aperto).
    var zonaClic: () -> NSRect? = { nil }
    /// Il clic dentro la zona.
    var clic: () -> Void = {}

    private var eraDentro = false
    private var area: NSTrackingArea?

    /// «Dentro» senza tetto: `contains` di NSRect esclude i bordi massimi, e
    /// il puntatore sbattuto in cima allo schermo viene inchiodato dal sistema
    /// proprio sull'ultima riga — che deve contare come dentro. Dalla base
    /// della zona in su è tutto suo.
    static func dentroSenzaTetto(_ punto: NSPoint, _ zona: NSRect) -> Bool {
        punto.x >= zona.minX && punto.x <= zona.maxX && punto.y >= zona.minY
    }

    /// Da chiuso, gli eventi del mouse nella zona del notch sono nostri: senza
    /// questo furto il guscio nero di SwiftUI se li terrebbe senza farci
    /// niente, e il clic non arriverebbe mai a `mouseDown` qui sotto.
    /// Il rettangolo che, quando c'è, NON ci appartiene pur cadendo dentro la
    /// zona del clic: il braccio dell'avviso vive nella fascia del notch, e
    /// senza questo il clic sul braccio aprirebbe il pannello invece di
    /// portarti alla chat.
    var zonaEsclusa: () -> NSRect? = { nil }

    /// Il clic è nostro? Puro apposta: è la domanda che il banco può fare
    /// senza montare una finestra.
    static func nostro(_ punto: NSPoint, zona: NSRect?, esclusa: NSRect?) -> Bool {
        guard let zona, dentroSenzaTetto(punto, zona) else { return false }
        if let esclusa, esclusa.contains(punto) { return false }
        return true
    }

    override func hitTest(_ punto: NSPoint) -> NSView? {
        let mio = convert(punto, from: superview)
        if Self.nostro(mio, zona: zonaClic(), esclusa: zonaEsclusa()) { return self }
        return super.hitTest(punto)
    }

    override func mouseDown(with event: NSEvent) {
        let punto = convert(event.locationInWindow, from: nil)
        if Self.nostro(punto, zona: zonaClic(), esclusa: zonaEsclusa()) {
            clic()
            return
        }
        super.mouseDown(with: event)
    }

    /// Il menu del notch, da un fabbricatore perché contiene target vivi.
    var menuContestuale: () -> NSMenu? = { nil }

    /// Uno scorrimento orizzontale deciso: `true` = verso la scheda dopo.
    var scorrimento: (Bool) -> Void = { _ in }

    /// Quanto si è accumulato in QUESTO gesto, e se ha già cambiato scheda.
    /// Un dito solo manda decine di eventi: senza questi due, uno swipe
    /// deciso saltava due schede (suo rilievo del 19/08).
    private var accumulato: CGFloat = 0
    private var giaCambiato = false
    private var ultimoDiRotella = Date.distantPast

    /// Quanto va spinto perché conti come swipe. Alto apposta: uno sfioro
    /// mentre scorri qualcos'altro non deve cambiare pagina.
    static let sogliaSwipe: CGFloat = 45

    override func scrollWheel(with event: NSEvent) {
        // **L'inerzia non conta.** Dopo che alzi le dita il sistema continua
        // a mandare eventi «di lancio» per mezzo secondo: contarli vuol dire
        // cambiare due schede con un gesto solo, che è esattamente quello che
        // gli succedeva.
        guard event.momentumPhase == [] else { return }

        // Il trackpad dichiara le fasi del gesto: si azzera all'inizio e si
        // spara UNA volta sola finché il dito non si stacca.
        if event.phase.contains(.began) {
            accumulato = 0
            giaCambiato = false
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            accumulato = 0
            giaCambiato = false
            return
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        // Orizzontale DECISO: senza questo, un movimento in diagonale mentre
        // scorri cambierebbe scheda per sbaglio.
        guard abs(dx) > abs(dy) * 2 else { return }

        if event.phase == [] {
            // Una rotella di mouse non ha fasi: lì resta il tempo di guardia.
            guard Date().timeIntervalSince(ultimoDiRotella) > 0.4 else { return }
            guard abs(dx) > 6 else { return }
            ultimoDiRotella = Date()
            scorrimento(dx < 0)
            return
        }

        guard !giaCambiato else { return }
        accumulato += dx
        guard abs(accumulato) > Self.sogliaSwipe else { return }
        giaCambiato = true
        // Il segno: le dita verso sinistra portano avanti, come sfogliando.
        scorrimento(accumulato < 0)
    }

    override func rightMouseDown(with event: NSEvent) {
        let punto = convert(event.locationInWindow, from: nil)
        // Da chiuso vale la zona del clic; da aperto il guscio intero: gli
        // eventi non reclamati da SwiftUI risalgono fin qui, mentre le schede
        // (viste AppKit) si tengono i loro.
        let zona = zonaClic() ?? zonaViva()
        if Self.dentroSenzaTetto(punto, zona), let menu = menuContestuale() {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        super.rightMouseDown(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let nuova = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(nuova)
        area = nuova
    }

    override func mouseEntered(with event: NSEvent) { valuta(event) }
    override func mouseMoved(with event: NSEvent) { valuta(event) }

    override func mouseExited(with event: NSEvent) {
        // Uscito dalla finestra intera: dentro non ci sei di sicuro.
        if eraDentro { eraDentro = false; cambio(false) }
        spegniScheda()
    }

    private func valuta(_ event: NSEvent) {
        accendiSchedaSotto(event)
        let punto = convert(event.locationInWindow, from: nil)
        let dentro = zonaViva().contains(punto)
        guard dentro != eraDentro else { return }
        eraDentro = dentro
        cambio(dentro)
    }

    // MARK: - Il passaggio sulle schede si decide QUI, dov'è deciso il clic

    /// **La scheda accesa è quella che il colpo colpirebbe.** Fino al 6/09 il
    /// passaggio del puntatore sulle schede lo decidevano le aree di
    /// tracciamento delle singole viste AppKit, che con `.inVisibleRect`
    /// seguono il rettangolo VISIBILE, non la cornice: misurato quella notte,
    /// **gli ultimi 15 punti dell'ultima scheda non si accendevano mai** (col
    /// mouse sintetico: x ≤ 868 sì, x ≥ 872 no, con la scheda che finisce a
    /// 885), pur essendo disegnati e cliccabili. E lì sta la X. Il colpo invece
    /// passa da `hitTest`, che guarda la cornice intera. Due geometrie per la
    /// stessa domanda danno una X visibile e sorda (finding 4 dell'audit
    /// cross-vendor): quindi ora la scheda si accende con la geometria del
    /// colpo, a ogni movimento del puntatore. Le aree di tracciamento
    /// restano come aiuto, ma non decidono più.
    private weak var schedaSfiorata: SorgenteTrascinamento.VistaSorgente?

    private func accendiSchedaSotto(_ event: NSEvent) {
        guard let contenuto = window?.contentView else { return }
        let punto = contenuto.convert(event.locationInWindow, from: nil)
        var vista = contenuto.hitTest(punto)
        while let corrente = vista, !(corrente is SorgenteTrascinamento.VistaSorgente) {
            vista = corrente.superview
        }
        let nuova = vista as? SorgenteTrascinamento.VistaSorgente
        guard nuova !== schedaSfiorata else { return }
        schedaSfiorata?.sfiorata(false)
        nuova?.sfiorata(true)
        schedaSfiorata = nuova
    }

    private func spegniScheda() {
        schedaSfiorata?.sfiorata(false)
        schedaSfiorata = nil
    }
}
