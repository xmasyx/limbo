import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Quello che si vede: un guscio nero appeso al notch che cresce quando lo
/// sfiori e si riempie di quello che hai copiato o messo da parte.
///
/// Composizione (regola 7 del gusto: una decisione forte per schermata): la
/// decisione forte è la **fila di schede**. Le linguette in cima e il
/// conteggio a destra sono minuscoli apposta, e stanno zitti per lasciarla
/// fare.
struct NotchView: View {
    @ObservedObject var stato: StatoNotch

    /// Quale dei due bersagli ha l'oggetto sopra in questo momento.
    @State private var miroAirdrop = false
    @State private var miroDeposito = false
    @State private var miroAlleggerisci = false

    /// **Le uniche due differenze fra l'app e la sonda, e vanno dichiarate
    /// perche' una sonda che tace su cio' che non misura e' peggio di nessuna
    /// sonda.** `ImageRenderer` disegna fuori da una finestra, e li' due cose
    /// non si comportano come nell'app:
    ///
    /// 1. **`ScrollView` esce vuoto.** Provato il 2026-08-18: dieci PNG
    ///    salvati con la spunta verde e nessuna scheda dentro.
    /// 2. **`onDrop` dipinge di GIALLO tutta la sua area.** Stessa giornata,
    ///    misurato: l'angolo leggeva R 1,00 G 0,80 B 0,00. Bisezione a tre
    ///    passaggi (contenuto, ritaglio, stile dell'angolo tutti scagionati);
    ///    tolto `onDrop`, l'angolo torna al grigio del fondo.
    ///
    /// Quindi la fotografia NON prova esattamente due cose: che le schede
    /// oltre la quinta si raggiungano scorrendo, e che il bersaglio del
    /// trascinamento sia agganciato. Quelle si provano con le mani. Tutto il
    /// resto (schede, testata, guscio, livrea, misure) e' la vista vera.
    var perSonda = false

    /// Il sopralzo fuori schermo esiste solo nella finestra vera: la sonda
    /// fotografa a `apertoAlto`, e regalarle 40 punti di trasparenza in cima
    /// sposterebbe ogni misura fatta sulle fotografie.
    private var sopralzo: CGFloat { perSonda ? 0 : NotchPanel.sopralzo }

    var body: some View {
        VStack(spacing: 0) {
            guscio
            Spacer(minLength: 0)
        }
        .frame(width: NotchPanel.apertoLargo,
               height: NotchPanel.apertoAlto + sopralzo, alignment: .top)
        // Le zone vuote della finestra non esistono per il mouse: la finestra
        // è grande quanto il pannello aperto anche da chiusa, e senza questa
        // riga si mangerebbe i clic su mezza barra dei menu.
        .allowsHitTesting(true)
        .overlay(alignment: .topLeading) { avvisoLaterale }
        .animation(Movimento.contenuto, value: stato.avviso)
    }

    /// La pillola dell'avviso, appesa a destra sotto il notch. Esce da sotto
    /// il nero scivolando verso destra.
    ///
    /// Solo a pannello CHIUSO: da aperto finirebbe sopra il contenuto, e in
    /// quel momento la riga della chat è già lì nella scheda Agents, a due
    /// centimetri. Un avviso che copre quello che stavi guardando è la cosa
    /// che poi si vuole spegnere.
    @ViewBuilder
    private var avvisoLaterale: some View {
        if let avviso = stato.avviso, !stato.aperto {
            VistaBraccioNotch(avviso: avviso,
                              alto: stato.geometria.chiuso.height,
                              largo: stato.larghezzaAvviso,
                              mostrato: stato.braccioScoperto) { stato.apriDallAvviso() }
                .offset(x: NotchPanel.avvisoDaSinistra(notch: stato.geometria.chiuso.width),
                        y: sopralzo)
        }
    }

    // MARK: - Il guscio

    private var misura: CGSize {
        stato.aperto
            ? CGSize(width: NotchPanel.apertoLargo,
                     height: NotchPanel.altezzaGuscio(notch: stato.geometria.altoNotch))
            : stato.geometria.chiuso
    }

    /// La cornice che AGGANCIA un rilascio: mai più stretta della zona
    /// sensibile (C7). Il calcolo vive in `Geometria` perché il banco lo
    /// misuri senza montare la vista.
    private var presa: CGSize {
        stato.geometria.presa(guscio: misura)
    }

    private var guscio: some View {
        VStack(spacing: 0) {
            // Niente entra sotto la plastica nera dello schermo.
            Spacer().frame(height: stato.geometria.altoNotch)
            if stato.aperto {
                contenuto
                    .transition(.opacity)
            }
        }
        .frame(width: misura.width, height: misura.height)
        .background(sagoma)
        .clipShape(sagomaRitaglio)
        // Il clic che apre NON sta più qui: lo giudica la finestra
        // (`VistaTracciamento`, stessa lezione dell'hover del 18/08) — così
        // prende su TUTTO il rettangolo nero, fotocamera compresa, e anche
        // con il puntatore inchiodato dal sistema sul bordo altissimo.
        //
        // La PRESA del trascinamento invece è questa cornice: da chiuso è
        // larga quanto la zona sensibile, non quanto il notch — chiedere di
        // centrare 185×32 con il puntatore nascosto sotto la plastica era il
        // «primo tentativo che non funziona» (C7). Da aperto coincide con il
        // guscio, e i bersagli grandi dentro fanno il resto.
        // Il sopralzo della finestra sta SOPRA il bordo dello schermo: il
        // guscio scende di `sopralzo` dentro questa cornice, così la parte
        // visibile non si sposta e la presa copre anche la riga in cui il
        // sistema inchioda il puntatore.
        .padding(.top, sopralzo)
        .frame(width: presa.width, height: presa.height + sopralzo,
               alignment: .top)
        .contentShape(Rectangle())
        .modifier(BersaglioTrascinamento(attivo: !perSonda, mirato: bersaglio,
                                         accogli: accogli))
        .animation(Movimento.guscio(aperto: stato.aperto), value: stato.aperto)
        .animation(Movimento.sfiora, value: stato.inArrivo)
    }

    /// Il guscio è nero pieno con i soli angoli bassi arrotondati: così
    /// continua il notch invece di disegnargli attorno un rettangolo. Da
    /// chiuso su un Mac senza notch prende anche gli angoli alti, perché lì
    /// non c'è nessun hardware con cui fondersi.
    private var sagomaRitaglio: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(bottomLeading: Raggi.guscio,
                               // Col braccio fuori l'angolo destro si SQUADRA:
                               // due neri adiacenti che arrotondano entrambi
                               // lasciano una strozzatura in mezzo, e le due
                               // forme si leggono come due cose invece che
                               // come il notch che si allunga (visto nella
                               // fotografia dal vivo del 19/08).
                               bottomTrailing: braccioFuori ? 0 : Raggi.guscio),
            style: .continuous
        )
    }

    /// Il braccio dell'avviso è scoperto adesso.
    private var braccioFuori: Bool {
        stato.avviso != nil && stato.braccioScoperto && !stato.aperto
    }

    private var sagoma: some View {
        sagomaRitaglio
            .fill(Livrea.guscio)
            // Durante un trascinamento il bordo si accende: è l'unico momento
            // in cui il guscio dice qualcosa da solo.
            .overlay {
                if stato.inArrivo {
                    sagomaRitaglio.strokeBorder(Livrea.penna, lineWidth: 2)
                }
            }
    }

    private var bersaglio: Binding<Bool> {
        Binding(get: { stato.inArrivo }, set: { stato.mira($0) })
    }

    /// Il binding di un bersaglio interno: tiene il proprio evidenziato E
    /// alimenta la mira condivisa, così passare da un bersaglio all'altro
    /// non chiude la zona di rilascio.
    private func mirato(_ locale: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { locale.wrappedValue },
            set: { valore in
                locale.wrappedValue = valore
                stato.mira(valore)
            }
        )
    }

    // MARK: - Il contenuto

    @ViewBuilder
    private var contenuto: some View {
        // Le linguette stanno IN BASSO, non sotto il notch (sua richiesta del
        // 18/08, provando l'app). Ed e' anche piu' giusto: il puntatore entra
        // dall'alto passando sul notch, quindi i comandi vicino al bordo alto
        // se li ritrova sotto la mano appena il pannello si apre, senza
        // averli cercati.
        VStack(spacing: NotchPanel.stacco) {
            // **La conferma SOSTITUISCE il contenuto, non ci si sovrappone.**
            // Prima era un `overlay` con il fondo nero: durante la
            // dissolvenza il fondo diventa semitrasparente e per qualche
            // fotogramma si vedeva la schermata di sotto trasparire —
            // il «glitch» che lui ha registrato il 19/08, e che si vede
            // fermando il filmato (la V col cerchio, e dietro le righe
            // Immagini/Video/Documenti sbiadite). Sostituendo non c'è più
            // niente sotto da vedere: il difetto non si attenua, sparisce.
            //
            // Il cambio è netto e senza dissolvenza incrociata, che
            // rimetterebbe due viste semitrasparenti una sopra l'altra.
            Group {
                if stato.soffio != nil {
                    copertina
                } else if stato.inArrivo {
                    zonaRilascio
                } else {
                    fila
                }
            }
            .animation(nil, value: stato.soffio)
            testata
        }
        .padding(.horizontal, 18)
        .padding(.top, NotchPanel.respiroAlto)
        .padding(.bottom, NotchPanel.respiroBasso)
        .animation(Movimento.contenuto, value: stato.soffio)
    }

    /// La conferma a tutta area: sfondo pieno, e quando è una cosa RIUSCITA
    /// un cerchio grande con la V — sua richiesta del 19/08, perché la
    /// conversione finisce così in fretta che senza un segno non si sa
    /// nemmeno che è successa.
    @ViewBuilder
    private var copertina: some View {
        if let messaggio = stato.soffio {
            VStack(spacing: 10) {
                if let simbolo = stato.simboloConferma {
                    ZStack {
                        Circle()
                            .fill(Livrea.penna)
                            .frame(width: 56, height: 56)
                        Image(systemName: simbolo)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                Text(messaggio)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.9))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: NotchPanel.altezzaFila)
        }
    }

    private var testata: some View {
        ZStack {
            SegmentiCasa(
                voci: Scheda.allCases,
                titolo: { $0.titolo },
                scelta: Binding(get: { stato.scheda }, set: { stato.scheda = $0 }),
                larghezzaVoce: NotchPanel.larghezzaVoceScheda,
                suCarta: false
            )
            HStack(spacing: NotchPanel.stacchiTestata) {
                Spacer()
                // Il conteggio in una casella FISSA (MacAppRules §7): «3 voci»
                // e «128 voci» occupano lo stesso spazio, così le linguette al
                // centro non si spostano mai.
                Text(conteggio)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: NotchPanel.larghezzaConteggio, alignment: .trailing)
                // Svuota è un CESTINO, non la parola: con tre schede il
                // selettore centrato è cresciuto e la pillola «Svuota» gli
                // finiva sopra (sua fotografia del 19/08 — il conto dice
                // −14 punti). L'icona lascia 32 punti di respiro, e il
                // banco della testata li difende.
                //
                // La casella c'è SEMPRE, anche vuota: se comparisse solo
                // quando serve, il conteggio accanto ballerebbe.
                Group {
                    if puoSvuotare {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Livrea.sopraGuscio.opacity(0.8))
                            .frame(width: NotchPanel.larghezzaSvuota, height: 24)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .contentShape(Capsule())
                            .onTapGesture { svuota() }
                            .help(stato.scheda == .appunti ? S.svuotaAppunti : S.svuotaDeposito)
                    }
                }
                .frame(width: NotchPanel.larghezzaSvuota, height: 24)
            }
        }
    }

    /// Il cestino c'è dove ha senso: su una scheda che ha qualcosa dentro, e
    /// mai mentre stai trascinando. Vale anche per gli appunti (sua richiesta
    /// del 19/08), non solo per il deposito.
    private var puoSvuotare: Bool {
        guard !stato.inArrivo else { return false }
        switch stato.scheda {
        case .appunti: return !stato.appunti.voci.isEmpty
        case .deposito: return !stato.deposito.voci.isEmpty
        case .convertitore, .sessioni: return false
        }
    }

    /// Svuota la scheda su cui sei. Le due cose NON sono la stessa: il
    /// deposito manda nel Cestino, perché quella è spesso l'unica copia del
    /// tuo file; gli appunti no, perché sono copie di roba che hai già
    /// altrove e riempire il Cestino di ritagli effimeri sarebbe un dispetto.
    /// Il messaggio dice quale delle due è successa.
    private func svuota() {
        switch stato.scheda {
        case .appunti:
            stato.appunti.svuota()
            stato.soffia(S.svuotati, simbolo: Simboli.cestino)
        case .deposito:
            stato.deposito.svuota()
            stato.soffia(S.nelCestino, simbolo: Simboli.cestino)
        case .convertitore, .sessioni:
            break
        }
    }

    private var quante: Int {
        stato.scheda == .appunti ? stato.appunti.voci.count : stato.deposito.voci.count
    }

    /// Il conteggio della testata, nella lingua della scheda: voci per
    /// appunti e deposito, chat per le chat, niente per il convertitore
    /// (li' non c'e' niente da contare, e uno «0 voci» direbbe il falso).
    private var conteggio: String {
        switch stato.scheda {
        case .appunti, .deposito: S.voci(quante)
        case .sessioni: S.chatQuante(stato.chat.voci.count)
        case .convertitore: ""
        }
    }

    @ViewBuilder
    private var fila: some View {
        switch stato.scheda {
        case .appunti:
            if stato.appunti.voci.isEmpty {
                vuoto(S.appuntiVuoti)
            } else {
                scorrevole(quanti: stato.appunti.voci.count) {
                    ForEach(stato.appunti.voci) { voce in
                        SchedaAppunto(voce: voce, stato: stato)
                    }
                }
            }
        case .deposito:
            if stato.deposito.voci.isEmpty {
                vuoto(S.depositoVuoto)
            } else {
                scorrevole(quanti: stato.deposito.voci.count) {
                    ForEach(stato.deposito.voci) { voce in
                        SchedaDeposito(voce: voce, stato: stato, perSonda: perSonda)
                            // **Una scheda tolta sparisce di colpo, le vicine
                            // scorrono.** Senza questo la fila anima anche
                            // l'uscita, e la scheda in dissolvenza viene
                            // ridisegnata col file già nel Cestino: icona
                            // bianca generica, che è il «glitch bianco» del suo
                            // video delle 03:42 (fotogrammi a 60 fps, 45,0 s).
                            // Lui: «deve essere pulita l'eliminazione».
                            .transition(.identity)
                    }
                }
            }
        case .convertitore:
            PannelloConvertitore(stato: stato, convertitore: stato.convertitore, perSonda: perSonda)
                .frame(height: NotchPanel.altezzaFila)
        case .sessioni:
            SchedaChat(chat: stato.chat, stato: stato, perSonda: perSonda)
        }
    }

    /// La fila è larga quanto le schede che contiene, MAI quanto il pannello.
    /// Il motivo è lo scorrimento a due dita (suo rilievo del 19/08): una
    /// `ScrollView` larga tutto si prende gli eventi anche sul nero vuoto a
    /// destra delle schede, e lì lo scorrimento deve cambiare scheda invece.
    /// Stretta al contenuto, il nero resta della finestra, che è chi decide.
    private func scorrevole<Contenuto: View>(quanti: Int,
                                             @ViewBuilder _ dentro: () -> Contenuto) -> some View {
        let riga = HStack(spacing: MisuraScheda.stacco) { dentro() }.padding(.horizontal, 1)
        let larga = min(NotchPanel.larghezzaUtile, MisuraScheda.larghezzaFila(quanti))
        return HStack(spacing: 0) {
            Group {
                if !perSonda {
                    ScrollView(.horizontal, showsIndicators: false) { riga }
                } else {
                    riga.frame(maxWidth: .infinity, alignment: .leading).clipped()
                }
            }
            .frame(width: larga, height: NotchPanel.altezzaFila)
            Spacer(minLength: 0)
        }
        .frame(height: NotchPanel.altezzaFila)
        .animation(Movimento.contenuto, value: quanti)
    }

    private func vuoto(_ testo: String) -> some View {
        Text(testo)
            .font(.system(size: 12))
            .foregroundStyle(Livrea.sopraGuscio.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: NotchPanel.altezzaFila)
    }

    /// Durante un trascinamento sparisce tutto e restano DUE bersagli: a
    /// sinistra mandarlo via, a destra tenerlo da parte (sua richiesta del
    /// 18/08). Grandi, perché in quel momento non stai scegliendo fra cinque
    /// schede: stai mirando con un oggetto appeso al dito.
    ///
    /// AirDrop a sinistra e non a destra perché il deposito è la cosa che fai
    /// dieci volte al giorno, e la mano che sale al notch arriva da sotto:
    /// il bersaglio più usato sta dove la mano si ferma per prima.
    private var zonaRilascio: some View {
        HStack(spacing: 10) {
            bersaglioRilascio(
                simbolo: "paperplane", titolo: S.airdrop, nota: S.mandaloVia,
                mirato: mirato($miroAirdrop)
            ) { fornitori in mandaConAirdrop(fornitori) }

            // Il terzo bersaglio, nato dal suo rilievo del 19/08: la scheda
            // «Converti» era scomoda perché quando trascini il notch è
            // CHIUSO, e quello che si apre sono i bersagli, non le schede.
            // È uno solo e non due (converti + comprimi) perché la domanda
            // «immagine o video?» la risponde il file: alleggerire è la
            // stessa intenzione, e chiederla sarebbe far scegliere una cosa
            // che si sa già.
            bersaglioRilascio(
                simbolo: "arrow.down.right.and.arrow.up.left",
                titolo: S.convertitore, nota: S.notaAlleggerisci,
                mirato: mirato($miroAlleggerisci)
            ) { fornitori in alleggerisci(fornitori) }

            bersaglioRilascio(
                simbolo: "tray.and.arrow.down", titolo: S.deposito, nota: S.tienilodaParte,
                mirato: mirato($miroDeposito)
            ) { fornitori in accogli(fornitori) }
        }
        .frame(height: NotchPanel.altezzaFila)
    }

    private func bersaglioRilascio(
        simbolo: String, titolo: String, nota: String,
        mirato: Binding<Bool>, azione: @escaping ([NSItemProvider]) -> Void
    ) -> some View {
        RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous)
            .fill(Livrea.penna.opacity(mirato.wrappedValue ? 0.28 : 0.0))
            .overlay {
                RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous)
                    .strokeBorder(
                        Livrea.penna.opacity(mirato.wrappedValue ? 1 : 0.55),
                        style: StrokeStyle(lineWidth: mirato.wrappedValue ? 2.5 : 2, dash: [7, 5]))
            }
            .overlay {
                VStack(spacing: 5) {
                    // Casella fissa anche per l'icona: i simboli di sistema
                    // hanno altezze diverse fra loro (il vassoio è più alto
                    // dell'aeroplano), e un VStack centrato traduceva quella
                    // differenza in titoli a quote diverse — 4 punti, ma su
                    // tre riquadri affiancati si vedono.
                    Image(systemName: simbolo)
                        .font(.system(size: 22, weight: .light))
                        .frame(height: 26)
                    Text(titolo).font(.system(size: 13, weight: .medium))
                    // La nota vive in una casella di altezza FISSA, come la
                    // didascalia delle schede: una nota che va a capo alzava
                    // il titolo del bersaglio in mezzo rispetto agli altri
                    // due, e tre bersagli affiancati con i titoli a quote
                    // diverse si vedono (MacAppRules §2, visto nella sonda
                    // del 19/08).
                    Text(nota)
                        .font(.system(size: 10))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(height: 26, alignment: .top)
                        .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
                }
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.9))
            }
            // Il riquadro cresce appena di sotto il puntatore: dice quale dei
            // due prenderà l'oggetto, senza spostare l'altro.
            .scaleEffect(mirato.wrappedValue ? 1.02 : 1.0)
            .animation(Movimento.sfiora, value: mirato.wrappedValue)
            .frame(maxWidth: .infinity)
            // Anche questi passano dal flag della sonda: senza, `ImageRenderer`
            // li dipinge di giallo col divieto sopra, e la fotografia dei due
            // bersagli diventa inservibile proprio dove serve.
            .modifier(BersaglioTrascinamento(attivo: !perSonda, mirato: mirato,
                                             accogli: azione))
    }

    /// Manda via senza passare dal deposito: quello che stai trascinando non
    /// lo stai mettendo da parte, lo stai spedendo.
    private func mandaConAirdrop(_ fornitori: [NSItemProvider]) {
        Task { @MainActor in
            // Prima i percorsi veri dal pasteboard del trascinamento (i
            // fornitori di `onDrop` sono lossy — stesso difetto dell'ingresso
            // nel deposito, stessa cura): così AirDrop spedisce il FILE, non
            // una copia dei suoi byte con un nome inventato.
            var urls = Deposito.percorsiTrascinati()
            if urls.isEmpty {
                for fornitore in fornitori {
                    if let url = await stato.deposito.urlPerCondivisione(fornitore) {
                        urls.append(url)
                    }
                }
            }
            stato.miraConsumata()
            guard !urls.isEmpty, let servizio = NSSharingService(named: .sendViaAirDrop) else {
                stato.soffia(S.nienteDaCondividere)
                return
            }
            servizio.perform(withItems: urls)
        }
    }

    /// Alleggerisce senza passare per il deposito d'ingresso: il risultato ci
    /// atterra da solo, e l'originale non si tocca.
    private func alleggerisci(_ fornitori: [NSItemProvider]) {
        let formato = Convertitore.Formato(rawValue: stato.formatoImmagine) ?? .heic
        stato.convertitore.accogli(fornitori, formato: formato)
        stato.miraConsumata()
        stato.scheda = .convertitore
    }

    private func accogli(_ fornitori: [NSItemProvider]) {
        Task { @MainActor in
            let entrate = await stato.deposito.accogliRilascio(fornitori)
            stato.miraConsumata()
            if entrate > 0 {
                // **Nessuna conferma quando un file entra** (sua richiesta del
                // 19/08: «non mi deve fare la spunta»). La scheda che atterra
                // nel deposito È la conferma, e la copertina copriva proprio
                // quella: dicevo «fatto» nascondendo la cosa fatta. Le
                // conferme restano dove non c'è niente da vedere — una copia
                // negli appunti, un cestino svuotato, una conversione lunga
                // finita mentre guardavi altrove.
                stato.scheda = .deposito
            } else {
                // Un rilascio che non entra lo DICE (18/08: falliva muto, e
                // sembrava che il deposito «non funzionasse» senza un perché).
                stato.soffia(S.nonPreso)
            }
        }
    }
}

/// Aggiunge il bersaglio del trascinamento solo quando serve. Esiste perche'
/// `onDrop` non si puo' applicare "a meta'" dentro una catena di modificatori
/// senza cambiare il tipo della vista.
private struct BersaglioTrascinamento: ViewModifier {
    let attivo: Bool
    let mirato: Binding<Bool>
    let accogli: ([NSItemProvider]) -> Void

    func body(content: Content) -> some View {
        if attivo {
            content.onDrop(of: [.item], isTargeted: mirato) { fornitori in
                accogli(fornitori)
                return true
            }
        } else {
            content
        }
    }
}
