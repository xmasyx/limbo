import AppKit
import ServiceManagement
import SwiftUI

/// La finestra delle impostazioni. Si apre SOLO dal clic destro sul notch:
/// la voce nella barra dei menu non c'è più (sua scelta del 19/08, «lo
/// togliamo da lì»).
@MainActor
final class Impostazioni {
    private var finestra: NSWindow?

    /// Costruisce la finestra SENZA mostrarla. Separata da `mostra` perché il
    /// banco la costruisce e ne misura la posizione: aprirla davvero
    /// ruberebbe lo schermo a chi sta lavorando.
    static func costruisci(stato: StatoNotch) -> NSWindow {
        let ospite = NSHostingController(rootView: ImpostazioniView(stato: stato))
        // Lo stile si passa al COSTRUTTORE. Assegnarlo dopo rifà il telaio e
        // riporta la finestra in alto a sinistra: era il motivo per cui
        // compariva appiccicata alla barra dei menu invece che al centro
        // (suo rilievo del 19/08, «come le preferenze di Kalamos»).
        let finestra = NSWindow(
            contentRect: NSRect(origin: .zero, size: ospite.view.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        finestra.contentViewController = ospite
        finestra.title = S.titoloImpostazioni
        finestra.isReleasedWhenClosed = false
        // La misura si fissa PRIMA di centrare: centrare una finestra ancora
        // vuota la mette al centro di zero.
        finestra.setContentSize(ospite.view.fittingSize)
        finestra.center()
        return finestra
    }

    func mostra(stato: StatoNotch) {
        let finestra = self.finestra ?? Self.costruisci(stato: stato)
        self.finestra = finestra
        // Riaperta dopo essere stata chiusa: torna al centro, non dove
        // l'avevi lasciata la volta prima.
        if !finestra.isVisible { finestra.center() }
        // L'app è un accessorio (niente Dock): senza attivarla la finestra
        // comparirebbe dietro a quella di chiunque altro.
        NSApp.activate(ignoringOtherApps: true)
        finestra.makeKeyAndOrderFront(nil)
    }
}

/// La pagina: etichetta a sinistra, comando a destra sullo stesso bordo per
/// tutte le righe, nota sotto la cosa che spiega (MacAppRules §2). Solo
/// controlli di casa.
struct ImpostazioniView: View {
    @ObservedObject var stato: StatoNotch
    /// La sonda disegna la pagina ferma: senza questo, `onAppear` parte dentro
    /// l'`ImageRenderer` e la fotografia esce col tasto a metà di un controllo
    /// di rete, cioè non fotografa lo stato in cui la pagina si apre davvero.
    var perSonda = false
    @AppStorage("quanteCopie") private var quanteCopie = 100
    @AppStorage(Deposito.chiaveScadenza) private var giorniScadenza = Deposito.giorniScadenzaDefault
    @AppStorage(Ocr.chiavePreferenza) private var leggiTesto = true
    @State private var avvioAlLogin = SMAppService.mainApp.status == .enabled
    /// Il tasto degli aggiornamenti. `StateObject` e non `State`: l'oggetto
    /// deve sopravvivere ai ridisegni della pagina mentre `brew` sta lavorando.
    @StateObject private var aggiornatore = Aggiornatore()

    private enum SiNo: String, CaseIterable, Identifiable {
        case acceso, spento
        var id: String { rawValue }
        var titolo: String { self == .acceso ? S.acceso : S.spento }
    }

    private struct Quota: Hashable, Identifiable { let id: Int }
    private static let quote = [50, 100, 200]

    /// I giorni di scadenza del deposito. `0` è «mai», e sta per ultimo
    /// perché è l'uscita dalla regola, non una durata più lunga.
    private struct Giorni: Hashable, Identifiable { let id: Int }
    private static let scadenze = [1, 7, 30, 0]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            riga(S.avvioAlLogin, nota: S.notaAvvioAlLogin) {
                interruttore(
                    Binding(get: { avvioAlLogin }, set: { imposta(avvio: $0) }))
            }
            riga(S.apriConIlPuntatore, nota: S.notaApriConIlPuntatore) {
                interruttore(Binding(
                    get: { stato.apriConIlPuntatore },
                    set: { stato.apriConIlPuntatore = $0 }))
            }
            riga(S.leggiTesto, nota: S.notaLeggiTesto) {
                interruttore(Binding(get: { leggiTesto }, set: { leggiTesto = $0 }))
            }
            riga(S.assorbiSchermate, nota: S.notaAssorbiSchermate) {
                interruttore(Binding(
                    get: { stato.assorbiSchermate },
                    set: { stato.imposta(assorbiSchermate: $0) }))
            }
            riga(S.avvisaChat, nota: S.notaAvvisaChat) {
                interruttore(Binding(
                    get: { stato.avvisaChat },
                    set: { stato.imposta(avvisaChat: $0) }))
            }
            riga(S.quanteVoci, nota: S.notaQuanteVoci) {
                SegmentiCasa(
                    voci: Self.quote.map(Quota.init),
                    titolo: { "\($0.id)" },
                    scelta: Binding(
                        get: { Quota(id: Self.quote.contains(quanteCopie) ? quanteCopie : 100) },
                        set: { quanteCopie = $0.id; stato.appunti.tetto = $0.id }),
                    larghezzaVoce: 52)
            }
            riga(S.scadenzaDeposito, nota: S.notaScadenzaDeposito) {
                SegmentiCasa(
                    voci: Self.scadenze.map(Giorni.init),
                    titolo: { $0.id == 0 ? S.mai : "\($0.id)" },
                    scelta: Binding(
                        get: { Giorni(id: Self.scadenze.contains(giorniScadenza)
                                        ? giorniScadenza : Deposito.giorniScadenzaDefault) },
                        // Si applica SUBITO: cambiare la finestra e vedere il
                        // deposito ancora pieno finché non riapri il pannello
                        // è indistinguibile da un interruttore che non fa
                        // niente.
                        set: { giorniScadenza = $0.id; stato.deposito.potaScadute() }),
                    larghezzaVoce: 52)
            }
            riga(S.aggiornamenti, nota: notaDegliAggiornamenti) {
                // Pieno come le pillole selezionate della colonna: la forma
                // tenue di `BottoneCasa` porta i colori del guscio scuro e su
                // questa carta è illeggibile (sonda del 6/09).
                BottoneCasa(titolo: titoloDelTasto) { premi() }
                    .disabled(occupato)
                    .opacity(occupato ? 0.6 : 1)
            }
        }
        .padding(26)
        .frame(width: 470)
        .background(Livrea.carta)
        // Guarda quando la pagina si apre, non a ogni avvio dell'app: così il
        // tasto dice già com'è messa la versione invece di aspettare un clic,
        // e un Mac fuori rete non se ne accorge (l'errore resta muto).
        .onAppear { if !perSonda { aggiornatore.guardaSeEOra() } }
    }

    /// Il tasto dice SEMPRE lo stato in cui si trova, perché un tasto che
    /// dice «Verifica aggiornamenti» mentre sta scaricando è indistinguibile
    /// da un tasto che non ha fatto niente.
    private var titoloDelTasto: String {
        switch aggiornatore.stato {
        case .fermo: return S.verificaAggiornamenti
        case .guardo: return S.aggiornamentoGuardo
        case .aggiornata: return S.aggiornamentoUltima
        case .disponibile(let versione, _): return S.aggiornamentoCe(versione)
        // La riga di `brew` va nella NOTA, non qui: è lunga quanto vuole, e
        // dentro un tasto allargherebbe la pagina a ogni riga nuova.
        case .scarico: return S.aggiornamentoInCorso
        case .fallito: return S.aggiornamentoRiprova
        }
    }

    private var occupato: Bool {
        switch aggiornatore.stato {
        case .guardo, .scarico: return true
        default: return false
        }
    }

    /// Il motivo del fallimento sta nella nota, non dentro il tasto: nel tasto
    /// non ci sta, e troncato non spiega niente.
    private var notaDegliAggiornamenti: String {
        switch aggiornatore.stato {
        case .fallito(let motivo): return motivo
        case .scarico(let riga): return riga.isEmpty ? S.aggiornamentoPreparo : riga
        default: return S.notaAggiornamenti
        }
    }

    private func premi() {
        if case .disponibile(_, let azione) = aggiornatore.stato {
            aggiornatore.esegui(azione)
        } else {
            aggiornatore.guardaAdesso()
        }
    }

    /// L'interruttore di casa: due voci della stessa larghezza, come il
    /// selettore delle schede — la forma che l'app usa già, mai un controllo
    /// di sistema (MacAppRules §7).
    private func interruttore(_ valore: Binding<Bool>) -> some View {
        SegmentiCasa(
            voci: SiNo.allCases,
            titolo: { $0.titolo },
            scelta: Binding(
                get: { valore.wrappedValue ? SiNo.acceso : .spento },
                set: { valore.wrappedValue = ($0 == .acceso) }),
            larghezzaVoce: 52)
    }

    private func riga(_ titolo: String, nota: String,
                      @ViewBuilder controllo: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(titolo)
                    .font(.system(size: 13))
                    .foregroundStyle(Livrea.inchiostro)
                Spacer(minLength: 16)
                controllo()
            }
            Text(nota)
                .font(.system(size: 11))
                .foregroundStyle(Livrea.inchiostro.opacity(0.55))
        }
    }

    /// L'avvio al login si scrive nel sistema, non in una preferenza nostra:
    /// `SMAppService` è il registro, e si rilegge dopo la scrittura invece di
    /// fidarsi del gesto.
    private func imposta(avvio: Bool) {
        if avvio {
            try? SMAppService.mainApp.register()
        } else {
            try? SMAppService.mainApp.unregister()
        }
        avvioAlLogin = SMAppService.mainApp.status == .enabled
    }
}
