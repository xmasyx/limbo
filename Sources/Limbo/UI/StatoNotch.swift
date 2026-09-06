import AppKit
import Combine
import SwiftUI

enum Scheda: String, CaseIterable, Identifiable {
    case appunti, deposito, convertitore, sessioni
    var id: String { rawValue }
    var titolo: String {
        switch self {
        case .appunti: S.appunti
        case .deposito: S.deposito
        case .convertitore: S.convertitore
        case .sessioni: S.chat
        }
    }

    /// La scheda accanto, nella direzione dello scorrimento. Non gira: alla
    /// fine ci si ferma, invece di ricominciare da capo — un elenco corto che
    /// si riavvolge fa perdere il senso di dove sei.
    func scorrendo(avanti: Bool) -> Scheda {
        let tutte = Scheda.allCases
        guard let i = tutte.firstIndex(of: self) else { return self }
        let j = avanti ? i + 1 : i - 1
        guard j >= 0, j < tutte.count else { return self }
        return tutte[j]
    }
}

/// Lo stato del pannello: aperto o chiuso, quale scheda, e se in questo
/// momento c'è una mano che sta trascinando qualcosa sopra il notch.
///
/// Sta in un oggetto suo e non dentro la vista perché lo tocca anche la
/// finestra (per riposizionarsi) e lo tocca la barra dei menu.
@MainActor
final class StatoNotch: ObservableObject {
    /// A ogni APERTURA il deposito si pota dei file morti (C6): `potaSpariti`
    /// solo all'avvio lasciava in vista schede il cui file era già sparito, e
    /// il -43 lo scoprivi trascinandole. Nel `didSet` e non nei tre punti che
    /// aprono, così il prossimo punto che aprirà non potrà dimenticarselo.
    @Published var aperto = false {
        didSet {
            if aperto && !oldValue {
                deposito.potaSpariti()
                deposito.potaScadute()
                deposito.raccogliOrfani()
                chat.ricarica()
                // La cartella di cattura può essere cambiata da fuori mentre
                // l'app era su (C101): `attiva` esce subito se è la stessa,
                // quindi qui costa niente e ripara il caso in cui costerebbe
                // caro, cioè una sentinella che guarda una cartella morta.
                if assorbiSchermate { schermate.attiva() }
            }
            // Il watcher delle chat vive quanto l'uso reale (C72): aprire e
            // chiudere il pannello è uno dei due fatti che lo decidono.
            aggiornaVitaChat()
        }
    }
    @Published var scheda: Scheda = .appunti
    /// Qualcuno sta trascinando qualcosa sopra di noi. È separato da `aperto`
    /// perché cambia la faccia del pannello: durante un trascinamento sparisce
    /// tutto tranne il bersaglio.
    @Published var inArrivo = false
    @Published var geometria = Geometria(largoNotch: 0, altoNotch: 0)
    /// Un messaggio breve che compare e se ne va da solo. **Fino al 19/08
    /// non era disegnato da nessuna parte:** dieci punti dell'app lo
    /// scrivevano e nessuno lo mostrava, che è il difetto più silenzioso che
    /// ci sia — codice che gira e non emette niente.
    @Published var soffio: String?
    /// Il simbolo dentro il cerchio della conferma: `nil` = nessun cerchio,
    /// solo il testo. Un cestino dice «buttato» meglio di una spunta, che
    /// dice solo «fatto» (sua richiesta del 19/08).
    @Published var simboloConferma: String?

    let appunti: Appunti
    let deposito: Deposito
    /// Costruito qui perché lavora sul deposito: quello che converte ci
    /// atterra dentro.
    let convertitore: Convertitore
    /// Le chat Claude aperte nel terminale (scheda Chat). Legge i file di
    /// stato che gli hook di LifeOS depositano; non scrive mai niente (A5).
    let chat: SessioniChat

    /// La sentinella delle schermate (C98-C103, 6/09): guarda la cartella di
    /// cattura e fa entrare nel deposito quello che macOS ci scrive.
    let schermate: SentinellaSchermate

    /// L'avviso automatico delle chat: quando una finisce o aspetta te, il
    /// notch si apre da solo. Si spegne nelle Impostazioni (C71) — si spegne
    /// l'AVVISO, la scheda resta.
    @AppStorage("avvisaChat") private(set) var avvisaChat = true

    func imposta(avvisaChat nuovo: Bool) {
        avvisaChat = nuovo
        chat.avvisaAttivo = nuovo
        aggiornaVitaChat()
    }

    private func aggiornaVitaChat() {
        if SessioniChat.deveVivere(avvisa: avvisaChat, pannelloAperto: aperto) {
            chat.attiva()
        } else {
            chat.ferma()
        }
    }

    /// L'assorbimento delle schermate (C103). Acceso di default: è la
    /// funzione, non un extra. Spegnendolo la sentinella muore e le schermate
    /// restano dove macOS le scrive.
    @AppStorage("assorbiSchermate") private(set) var assorbiSchermate = true

    func imposta(assorbiSchermate nuovo: Bool) {
        assorbiSchermate = nuovo
        aggiornaVitaSchermate()
    }

    /// La sentinella vive quando l'interruttore è acceso, e basta: assorbire
    /// serve **mentre fai altro**, quindi legarla all'apertura del pannello
    /// (come si fa col watcher delle chat) la renderebbe inutile. Sono due
    /// regole diverse perché sono due usi diversi.
    private func aggiornaVitaSchermate() {
        if assorbiSchermate { schermate.attiva() } else { schermate.ferma() }
    }

    /// La scheda scelta dal formato del convertitore.
    @AppStorage("formatoImmagine") var formatoImmagine = Convertitore.Formato.heic.rawValue
    @AppStorage("qualitaVideo") var qualitaVideo = Convertitore.Qualita.leggero.rawValue

    /// Apre passandoci sopra col puntatore. **Spento di default dal 18/08**,
    /// suo rilievo usandola: «ogni volta che ci passo sopra si apre». Il notch
    /// sta sul percorso che il puntatore fa per arrivare alla barra dei menu,
    /// quindi aprirsi al passaggio vuol dire aprirsi quando non gliel'hai
    /// chiesto. Adesso si apre con un clic, e resta la scorciatoia per chi la
    /// vuole al volo.
    @AppStorage("apriConIlPuntatore") var apriConIlPuntatore = false

    private var lavoroSoffio: Task<Void, Never>?
    private var lavoroArrivo: Task<Void, Never>?

    /// Un bersaglio del trascinamento ha (o ha perso) l'oggetto sopra di sé.
    /// Fra un bersaglio e l'altro SwiftUI attraversa un fotogramma in cui
    /// NESSUNO è mirato: chiudere lì fa lampeggiare la zona di rilascio
    /// sotto l'oggetto (suo video del 19/08: «non rimane visibile quale zona
    /// corrisponde al deposito e quale ad AirDrop»). Il vero vince subito;
    /// il falso vince solo se nessuno riprende la mira entro un quarto di
    /// secondo.
    /// **Ogni stato «sto ricevendo un trascinamento» ha una scadenza.** Il
    /// sistema promette un `dragExited` per ogni `dragEntered`, e a volte non
    /// lo manda: allora la zona di rilascio resta incollata a schermo per
    /// sempre, e l'unico modo di toglierla è rientrare e riuscire. È la voce 5
    /// della ricerca del 19/08 sulle app-notch (boring.notch #1127), ed è un
    /// difetto che non si scopre provando, perché nella prova il sistema la
    /// notifica la manda.
    ///
    /// Variabile e non costante perché il banco la abbassa e aspetta davvero:
    /// una scadenza dichiarata e mai vista scattare non è una scadenza.
    static var scadenzaArrivo: TimeInterval = 12

    private var lavoroScadenzaArrivo: Task<Void, Never>?

    func mira(_ dentro: Bool) {
        lavoroArrivo?.cancel()
        if dentro {
            lavoroScadenzaArrivo?.cancel()
            lavoroScadenzaArrivo = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.scadenzaArrivo))
                guard let self, !Task.isCancelled, self.inArrivo else { return }
                withAnimation(Movimento.guscio(aperto: false)) {
                    self.inArrivo = false
                    self.aperto = false
                }
            }
            guard !inArrivo else { return }
            withAnimation(Movimento.guscio(aperto: true)) {
                inArrivo = true
                aperto = true
                scheda = .deposito
            }
        } else {
            lavoroScadenzaArrivo?.cancel()
            lavoroArrivo = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                withAnimation(Movimento.guscio(aperto: true)) { self.inArrivo = false }
            }
        }
    }

    /// Il rilascio è stato consumato: la zona si chiude subito, senza
    /// aspettare il debounce.
    func miraConsumata() {
        lavoroArrivo?.cancel()
        lavoroScadenzaArrivo?.cancel()
        inArrivo = false
    }

    /// **Il deposito che cambia deve far ridisegnare chi lo legge attraverso
    /// di me.** `NotchView` osserva `stato` e legge `stato.deposito.voci`: un
    /// oggetto annidato non propaga, quindi togliere una voce dal deposito
    /// non ridisegnava niente. Fino al 6/09 nessuno se n'era accorto perché
    /// ogni uscita dal deposito era seguita da un soffio, che è un
    /// `@Published` MIO e ridisegnava tutto per caso. Tolto il soffio dalla
    /// X (sua richiesta), la scheda restava a schermo con l'indice già a 3 su
    /// 4 — l'ha mostrato una fotografia del pannello. È la lezione del 19/08
    /// («ogni oggetto osservabile letto da una vista va osservato da quella
    /// vista»), pagata una seconda volta.
    private var inoltri: Set<AnyCancellable> = []

    init(appunti: Appunti, deposito: Deposito, chat: SessioniChat? = nil) {
        self.appunti = appunti
        self.deposito = deposito
        self.convertitore = Convertitore(deposito: deposito)
        self.chat = chat ?? SessioniChat()
        self.schermate = SentinellaSchermate(deposito: deposito)
        deposito.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &inoltri)
        // La conferma a lavoro finito passa dal soffio, che è il posto dove
        // vivono già tutti i messaggi brevi dell'app.
        // Un lavoro lungo finisce quando non stai guardando: il notch si
        // APRE da solo per dirlo (sua richiesta del 19/08). Solo per i lavori
        // lunghi — sotto i tre secondi te ne sei accorto da solo, e un
        // pannello che salta su per ogni immagine convertita sarebbe la cosa
        // che poi si vuole spegnere.
        convertitore.avvisaCon { [weak self] _, lungo in
            guard let self else { return }
            let apertoDaMe = lungo && !self.aperto
            if apertoDaMe {
                withAnimation(Movimento.apre) {
                    self.scheda = .convertitore
                    self.aperto = true
                }
            }
            self.soffia(S.convertito, simbolo: Simboli.fatto,
                        durata: lungo ? Self.soffioDaSolo : Self.soffioBreve,
                        poiChiudi: apertoDaMe)
        }
        // Una chat che finisce o aspetta te NON spalanca più il pannello
        // (sua correzione del 19/08): esce una pillola piccola di lato, col
        // segno dell'AI. Il pannello grande resta per le conferme che nascono
        // da un tuo gesto; questo arriva mentre fai altro, e una cosa che
        // arriva da sola non ha diritto a mezzo schermo.
        self.chat.avvisaAttivo = avvisaChat
        self.chat.nota = { [weak self] sessione in
            guard let self else { return }
            self.mostraAvviso(AvvisoChat(
                testo: S.braccio(progetto: sessione.progetto, titolo: sessione.titolo),
                ai: sessione.ai,
                sessione: sessione))
        }
        aggiornaVitaChat()
        // Una schermata assorbita esce dallo stesso braccio delle chat: è la
        // forma che lui ha già in mano, e inventarne una seconda per dire una
        // cosa più piccola sarebbe una decisione forte di troppo.
        self.schermate.nota = { [weak self] voce in
            guard let self else { return }
            self.mostraAvviso(AvvisoChat(testo: S.braccioSchermata, ai: .ignoto,
                                         sessione: nil, schermata: voce))
        }
        aggiornaVitaSchermate()
    }

    // MARK: - L'avviso laterale

    /// La pillola che esce di lato. `nil` = non c'è niente da dire.
    @Published var avviso: AvvisoChat?

    /// Quanto resta a schermo. Come la conferma che arriva da sola: sta
    /// chiamando l'attenzione da un'altra parte dello schermo.
    static let avvisoDura: TimeInterval = 4.0

    private var lavoroAvviso: Task<Void, Never>?

    /// Il braccio è SCOPERTO (largo) o ancora nascosto sotto la plastica del
    /// notch (largo zero). Due stati separati da `avviso` perché la vista deve
    /// esistere a larghezza zero PRIMA di crescere: inserirla già larga non
    /// anima niente, compare e basta.
    @Published private(set) var braccioScoperto = false

    /// La larghezza del braccio adesso: quella del suo testo, col tetto.
    /// La usa anche la finestra per non rubare i clic dove non c'è nero.
    var larghezzaAvviso: CGFloat {
        guard let avviso else { return NotchPanel.avvisoLargo }
        return NotchPanel.larghezzaAvviso(testo: avviso.testo)
    }

    /// **Solo per la sonda**: il braccio già scoperto, senza aspettare
    /// l'animazione. La fotografia si scatta in un istante, e `mostraAvviso`
    /// scopre il braccio un attimo DOPO: senza questa, lo scatto del braccio
    /// era un notch chiuso e non lo vedeva nessuno (20/08).
    func scopriBraccioPerSonda(_ nuovo: AvvisoChat) {
        avviso = nuovo
        braccioScoperto = true
    }

    func mostraAvviso(_ nuovo: AvvisoChat) {
        lavoroAvviso?.cancel()
        ultimoAvviso = Date()
        ultimoAvvisoEraSchermata = nuovo.schermata != nil
        avviso = nuovo
        braccioScoperto = false
        lavoroAvviso = Task { [weak self] in
            // Un giro di orologio: il tempo che la vista esista a larghezza
            // zero. Senza, SwiftUI vede un solo fotogramma e non ha niente da
            // animare.
            try? await Task.sleep(for: .milliseconds(16))
            guard let self, !Task.isCancelled else { return }
            // La STESSA animazione del guscio del notch: il braccio è il
            // notch che si allunga, non un cartello che arriva da fuori.
            withAnimation(Movimento.guscio(aperto: true)) { self.braccioScoperto = true }
            try? await Task.sleep(for: .seconds(Self.avvisoDura))
            guard !Task.isCancelled else { return }
            self.chiudiAvviso()
        }
    }

    func chiudiAvviso() {
        lavoroAvviso?.cancel()
        withAnimation(Movimento.guscio(aperto: false)) { braccioScoperto = false }
        // La vista se ne va DOPO che si è richiusa: toglierla subito
        // farebbe sparire il braccio invece di farlo rientrare.
        lavoroAvviso = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Movimento.rispostaChiude + 0.1))
            guard let self, !Task.isCancelled else { return }
            self.avviso = nil
        }
    }

    /// Il clic sulla pillola: ti porta alla chat e la pillola se ne va. Se
    /// quella sessione non c'è più lo dice, invece di non fare niente.
    func apriDallAvviso() {
        // La schermata prima di tutto: mentre il braccio la annuncia, il clic
        // significa «rimettila fuori», non «portami alla chat» (C102).
        if let voce = avviso?.schermata {
            let tornata = schermate.rimettiFuori(voce)
            chiudiAvviso()
            soffia(tornata == nil ? S.chatSparita : S.braccioSchermata,
                   simbolo: tornata == nil ? nil : Simboli.fatto)
            return
        }
        guard let sessione = avviso?.sessione else { chiudiAvviso(); return }
        let trovata = chat.porta(inPrimoPiano: sessione)
        chiudiAvviso()
        if !trovata { soffia(S.chatSparita) }
    }

    /// Uno scorrimento orizzontale deciso cambia scheda. Il quando lo decide
    /// la finestra (`VistaTracciamento`), non la vista: sopra la fila delle
    /// schede lo scorrimento appartiene alla fila, e lì questo non viene
    /// nemmeno chiamato — è la regola che gli avevo promesso il 19/08.
    func scorri(avanti: Bool) {
        let nuova = scheda.scorrendo(avanti: avanti)
        guard nuova != scheda else { return }
        withAnimation(Movimento.contenuto) { scheda = nuova }
    }

    /// Quanto a lungo un ingresso nel deposito conta come «da poco» per la
    /// scheda d'apertura. Cinque minuti: parametro mio sotto la sua regola
    /// del 19/08, si ritocca qui.
    static let recenzaDeposito: TimeInterval = 300

    /// Quanto a lungo un avviso appena passato dirotta l'apertura sulla
    /// scheda delle chat. Un minuto, sua regola del 20/08: se apri il notch
    /// subito dopo il braccio, stai andando a vedere QUELLA chat.
    static let recenzaAvviso: TimeInterval = 60

    /// Quando è uscito l'ultimo braccio. Separato da `avviso`, che sparisce
    /// dopo quattro secondi: qui serve la memoria del minuto dopo. Il banco
    /// lo scrive a mano per provare la scadenza.
    var ultimoAvviso: Date?
    /// Di COSA parlava l'ultimo braccio. Un braccio per una schermata
    /// assorbita non deve dirottare l'apertura sulle chat: ci stai andando
    /// a vedere il deposito. Scoperto il 6/09 col mouse sintetico, che dopo
    /// ogni assorbimento apriva il pannello su Agents.
    var ultimoAvvisoEraSchermata = false

    /// La scheda su cui il pannello si APRE: appunti, il caso di ogni
    /// giorno — a meno che il deposito non abbia ricevuto qualcosa da poco,
    /// perché lì ci stai lavorando e riaprirti altrove sarebbe un dispetto
    /// (sua regola del 19/08). `adesso` è iniettabile per il banco.
    func schedaIniziale(adesso: Date = Date()) -> Scheda {
        // Un avviso appena passato vince su tutto: apri il notch entro un
        // minuto dal braccio e ti trovi le chat, non gli appunti.
        if let quando = ultimoAvviso,
           adesso.timeIntervalSince(quando) < Self.recenzaAvviso {
            // Il braccio della schermata porta al deposito, quello delle
            // chat alle chat: si va a vedere la cosa di cui parlava.
            return ultimoAvvisoEraSchermata ? .deposito : .sessioni
        }
        if let quando = deposito.ultimoIngresso,
           adesso.timeIntervalSince(quando) < Self.recenzaDeposito {
            return .deposito
        }
        return .appunti
    }

    /// Il puntatore è entrato o uscito dalla zona che conta. È l'UNICO posto
    /// che apre e chiude per movimento: prima erano due (`.onHover` sul guscio
    /// e uno sul bersaglio invisibile), e si contraddicevano appena il guscio
    /// cambiava misura.
    /// Dove sta il puntatore adesso. Serve a sapere se il pannello aperto DA
    /// SOLO può richiudersi da solo: se ci stai sopra, no.
    private(set) var puntatoreDentro = false

    /// Un pannello che si è aperto da solo deve chiudersi da solo, e questa è
    /// la condizione. Fuori dal timer perché il banco possa provarla senza
    /// aspettare (il 19/08 il notch si apriva a fine conversione e restava
    /// aperto per sempre: l'unico punto che chiudeva era l'uscita del
    /// puntatore, e se il puntatore non era mai entrato non usciva mai).
    func puoChiudersiDaSola() -> Bool {
        aperto && !puntatoreDentro && !inArrivo
    }

    /// Quanto si aspetta prima di chiudere, dopo che il puntatore è uscito.
    /// **Non è un ritardo estetico, è la seconda metà della tolleranza** (sua
    /// richiesta del 19/08: continuava a chiudersi mentre ci stava ancora
    /// lavorando attorno). La grazia in PUNTI copre chi si allontana poco; la
    /// grazia nel TEMPO copre chi esce e rientra subito, o passa di lato dove
    /// la finestra non arriva.
    ///
    /// **Da 0,3 a 0,7 secondi il 6/09**, suo rilievo usandola: «appena mi
    /// allontano dal notch, il notch si chiude, quando avevamo detto che ci
    /// deve essere un tempo di latenza». I 300 ms erano la mia stima del 19/08
    /// di «chi se ne va davvero non torna», e la stima era sbagliata: a quella
    /// soglia il pannello si chiude anche a chi sta solo spostando la mano.
    /// La misura vera è la sua percezione, e questo è il tipo di numero che
    /// non si può ricavare da un banco.
    static let graziaTempo: TimeInterval = 0.7

    private var lavoroChiusura: Task<Void, Never>?

    /// C'è una chiusura in attesa che il tempo di grazia scada. Il banco la
    /// guarda: senza, «non si è chiuso» e «si chiuderà fra poco» sarebbero
    /// indistinguibili.
    private(set) var chiusuraInSospeso = false

    func puntatore(_ dentro: Bool) {
        puntatoreDentro = dentro
        if dentro {
            // Rientrato: la chiusura che stava per partire non parte più.
            lavoroChiusura?.cancel()
            chiusuraInSospeso = false
            if apriConIlPuntatore && !aperto {
                scheda = schedaIniziale()
                aperto = true
            }
        } else if !inArrivo {
            lavoroChiusura?.cancel()
            chiusuraInSospeso = true
            lavoroChiusura = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.graziaTempo))
                guard let self, !Task.isCancelled else { return }
                self.chiusuraInSospeso = false
                guard !self.puntatoreDentro, !self.inArrivo else { return }
                withAnimation(Movimento.guscio(aperto: false)) { self.aperto = false }
            }
        }
    }

    /// Il clic sul guscio chiuso: apre. Sul guscio aperto non fa niente,
    /// perché lì i clic appartengono alle schede.
    func toccato() {
        guard !aperto else { return }
        scheda = schedaIniziale()
        aperto = true
    }

    func mostra(_ scheda: Scheda) {
        self.scheda = scheda
        aperto = true
    }

    /// Un messaggio breve che compare e se ne va. `conSpunta` mette la V:
    /// serve per i lavori che finiscono così in fretta da non vedersi (sua
    /// parola del 19/08 sul convertitore, «serve una V che compare»).
    /// Quanto resta un messaggio. Quello che compare mentre stai già
    /// guardando può essere breve; quello che ARRIVA da solo a fine lavoro
    /// dev'essere più lungo, perché sta chiamando la tua attenzione da
    /// un'altra parte dello schermo.
    static let soffioBreve: TimeInterval = 1.4
    static let soffioDaSolo: TimeInterval = 3.0

    func soffia(_ messaggio: String, simbolo: String? = nil,
                durata: TimeInterval = soffioBreve, poiChiudi: Bool = false) {
        lavoroSoffio?.cancel()
        simboloConferma = simbolo
        soffio = messaggio
        lavoroSoffio = Task { [weak self] in
            try? await Task.sleep(for: .seconds(durata))
            guard let self, !Task.isCancelled else { return }
            // **L'ordine conta, ed è il difetto del 19/08.** Togliere il
            // messaggio e chiudere insieme faceva riapparire per un istante
            // la schermata di sotto mentre il guscio si stava già
            // richiudendo: due animazioni sovrapposte, e si vedeva. Quando il
            // pannello deve chiudersi, la copertina RESTA finché il guscio
            // non è chiuso, e sparisce dopo, quando non la guarda più
            // nessuno.
            if poiChiudi && self.puoChiudersiDaSola() {
                withAnimation(Movimento.guscio(aperto: false)) { self.aperto = false }
                try? await Task.sleep(for: .seconds(Movimento.rispostaChiude + 0.1))
                guard !Task.isCancelled else { return }
                self.soffio = nil
            } else {
                self.soffio = nil
            }
        }
    }
}
