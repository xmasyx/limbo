import AppKit
import SwiftUI

/// L'avviso di una chat: una pillola piccola che esce da sotto il notch verso
/// destra, col segno dell'AI e due parole. **Non è il pannello che si apre**
/// (sua richiesta del 19/08: «leggermente di lato verso destra o poco verso il
/// basso, l'icona di Claude invece di tutta l'animazione grande»).
///
/// Il pannello grande resta la casa delle conferme che nascono da un tuo gesto
/// — hai convertito, hai svuotato, stavi guardando. Questo invece arriva
/// mentre fai altro, e una cosa che arriva da sola non ha il diritto di
/// prendersi mezzo schermo.
struct AvvisoChat: Equatable {
    let testo: String
    let ai: SegnoAI
    /// La sessione da aprire se ci clicchi sopra.
    let sessione: SessioneChat?
    /// La schermata appena assorbita, quando l'avviso è quello (C102, 6/09).
    /// **Un braccio per volta, e i due sensi non convivono:** se questo campo
    /// c'è, il clic rimette il file sulla Scrivania invece di saltare alla
    /// chat. Non è ambiguità, è che i due stati sono separati nel tempo e la
    /// schermata ha la precedenza per la durata del suo avviso.
    var schermata: VoceDeposito? = nil

    /// Il glifo che sostituisce il verbo: senza «aspetta te» scritto, questa
    /// è l'unica cosa che distingue una chat che ti chiede una decisione da
    /// una che ha finito.
    /// Il glifo sostituisce il verbo (sua regola del 19/08). Per la schermata
    /// il verbo è «annulla», e lo dice la freccia che torna indietro: sua
    /// scelta del 6/09 dopo aver visto il braccio troncato, «mi piace il
    /// simbolino della freccia». Il testo si accorcia, il segno resta.
    var simbolo: String {
        if schermata != nil { return "arrow.uturn.backward" }
        return sessione?.attivita == .aspetta ? "hourglass" : "checkmark"
    }

    static func == (a: AvvisoChat, b: AvvisoChat) -> Bool {
        a.testo == b.testo && a.ai == b.ai && a.sessione?.id == b.sessione?.id
            && a.schermata?.id == b.schermata?.id
    }
}

/// Quale AI sta parlando. Oggi una, ma il campo arriva dal file di stato: il
/// giorno che una chat la tiene aperta un altro motore, la pillola porta il
/// suo segno senza toccare questa app.
enum SegnoAI: String, Equatable {
    case claude
    case ignoto

    init(codice: String?) {
        self = SegnoAI(rawValue: codice ?? "") ?? .ignoto
    }

    /// Il colore del segno. Il rosso-argilla è quello di Claude.
    var colore: Color {
        switch self {
        case .claude: Color(red: 0.851, green: 0.467, blue: 0.341)
        case .ignoto: Livrea.sopraGuscio.opacity(0.7)
        }
    }
}

/// Il segno di Claude: una raggiera di petali affusolati. È DISEGNATO, non un
/// file copiato da qualche parte — dodici raggi di due lunghezze alternate,
/// che è la forma che si riconosce a 18 punti.
struct RaggieraClaude: Shape {
    /// Quanti raggi. Dodici: sotto si legge come una stella, sopra come un
    /// disco sfrangiato.
    static let raggi = 12

    func path(in rect: CGRect) -> Path {
        var tracciato = Path()
        let centro = CGPoint(x: rect.midX, y: rect.midY)
        let raggio = min(rect.width, rect.height) / 2
        // Petali GRASSI, non spine: a 17 punti una raggiera sottile si legge
        // come un asterisco qualunque, e il segno di Claude si riconosce dalla
        // pienezza. Provato guardando la sonda, non calcolato.
        let dentro = raggio * 0.10
        let largo = raggio * 0.30

        for i in 0..<Self.raggi {
            let angolo = Double(i) / Double(Self.raggi) * 2 * .pi - .pi / 2
            // Lunghezze alternate: una raggiera tutta uguale è una ruota
            // dentata, non un segno.
            let fuori = raggio * (i.isMultiple(of: 2) ? 1.0 : 0.82)
            let dx = cos(angolo), dy = sin(angolo)
            let px = -sin(angolo), py = cos(angolo)

            func punto(_ lungo: CGFloat, _ lato: CGFloat) -> CGPoint {
                CGPoint(x: centro.x + dx * lungo + px * lato,
                        y: centro.y + dy * lungo + py * lato)
            }

            let base1 = punto(dentro, largo / 2)
            let punta = punto(fuori, 0)
            let base2 = punto(dentro, -largo / 2)
            tracciato.move(to: base1)
            tracciato.addQuadCurve(to: punta, control: punto(fuori * 0.62, largo * 0.44))
            tracciato.addQuadCurve(to: base2, control: punto(fuori * 0.62, -largo * 0.44))
            tracciato.closeSubpath()
        }
        return tracciato
    }
}

/// **Il braccio del notch.** Non una pillola che compare accanto: il notch
/// STESSO che si allunga verso destra dentro la barra dei menu, con la sua
/// forma e la sua animazione (sua correzione del 19/08 sera, seconda delle due
/// idee che aveva proposto).
///
/// Perché questa e non quella che scende: una cosa che scende copre quello che
/// stai guardando — nella prima prova dal vivo la pillola stava sopra la barra
/// delle schede del suo terminale. Un braccio che cresce di lato vive nello
/// spazio vuoto della barra dei menu accanto al notch, che non è di nessuno.
///
/// La larghezza si anima da zero: il contenuto sta fermo a misura piena e
/// viene SCOPERTO, non compresso. Comprimendo, il testo si ricomporrebbe a
/// metà strada, che è precisamente quello che la regola sulle transizioni
/// vieta (MacAppRules §7).
struct VistaBraccioNotch: View {
    let avviso: AvvisoChat
    /// L'altezza del notch di questo schermo: il braccio è alto quanto lui.
    let alto: CGFloat
    /// Quanto è largo da scoperto: la misura del suo testo, col tetto di 210
    /// (`NotchPanel.larghezzaAvviso`). Arriva da fuori perché la stessa
    /// misura serve alla finestra per non rubare i clic alla barra dei menu.
    var largo: CGFloat = NotchPanel.avvisoLargo
    /// Scoperto o ancora nascosto sotto la plastica.
    let mostrato: Bool
    var apri: () -> Void = {}

    @State private var sfiorato = false

    /// Il ritaglio: angolo basso a destra arrotondato come il guscio, in alto
    /// niente, perché lì il braccio è a filo del bordo dello schermo.
    private var sagoma: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            cornerRadii: .init(bottomTrailing: Raggi.guscio), style: .continuous)
    }

    var body: some View {
        Button(action: apri) {
            ZStack(alignment: .leading) {
                Livrea.guscio
                HStack(spacing: NotchPanel.staccoAvviso) {
                    RaggieraClaude()
                        .fill(avviso.ai.colore)
                        .frame(width: NotchPanel.segnoAvviso, height: NotchPanel.segnoAvviso)
                    // `.fixedSize()` qui TAGLIAVA: dentro un frame fisso con
                    // ritaglio, un testo a misura piena esce dal nero a metà
                    // parola invece di troncarsi. Con i puntini si legge che
                    // manca qualcosa, ed è la differenza fra corto e rotto.
                    Text(avviso.testo)
                        .font(Font(NotchPanel.carattereAvviso))
                        .foregroundStyle(Livrea.sopraGuscio.opacity(sfiorato ? 1 : 0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: avviso.simbolo)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Livrea.sopraGuscio.opacity(0.55))
                        .frame(width: NotchPanel.glifoAvviso)
                }
                .padding(.leading, NotchPanel.margineAvvisoSinistro)
                .padding(.trailing, NotchPanel.margineAvvisoDestro)
                .frame(width: largo, alignment: .leading)
            }
            .frame(width: mostrato ? largo : 0, height: alto,
                   alignment: .leading)
            .clipShape(sagoma)
            .contentShape(sagoma)
        }
        .buttonStyle(.plain)
        .onHover { dentro in sfiorato = dentro }
        .animation(Movimento.sfiora, value: sfiorato)
        .help(S.chatPorta)
    }
}
