import AppKit
import SwiftUI

/// La terza scheda: dice cosa diventa cosa, e ti lascia scegliere dove c'è
/// davvero una scelta.
///
/// **Perché non è più solo un riquadro dove trascinare** (suo rilievo del
/// 19/08): il riquadro c'era ma mostrava soltanto HEIC/JPEG/PNG, cioè le
/// immagini, e di video e documenti non diceva niente — così un video finiva
/// convertito senza che si capisse in che cosa. Adesso le tre righe sono
/// l'elenco di quello che l'app sa fare, e il rilascio funziona su tutta la
/// scheda comunque.
struct PannelloConvertitore: View {
    @ObservedObject var stato: StatoNotch
    /// **Osservato a parte, e non è un dettaglio.** `Convertitore` è un
    /// oggetto osservabile dentro un altro oggetto osservabile, e SwiftUI NON
    /// propaga da uno all'altro: leggere `convertitore.inCorso` senza
    /// osservarlo qui vuol dire che la vista si ridisegna solo quando cambia
    /// qualcos'altro. Era il difetto del 19/08: rilasciavi un video e la
    /// barra non compariva, poi cambiavi scheda e la trovavi già a metà.
    @ObservedObject var convertitore: Convertitore
    var perSonda = false

    @State private var mirato = false

    private var formato: Binding<Convertitore.Formato> {
        Binding(
            get: { Convertitore.Formato(rawValue: stato.formatoImmagine) ?? .heic },
            set: { stato.formatoImmagine = $0.rawValue }
        )
    }

    private var qualita: Binding<Convertitore.Qualita> {
        Binding(
            get: { Convertitore.Qualita(rawValue: stato.qualitaVideo) ?? .leggero },
            set: { stato.qualitaVideo = $0.rawValue }
        )
    }

    var body: some View {
        Group {
            if let inCorso = convertitore.inCorso {
                lavoro(inCorso)
            } else {
                elenco
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // Il fondo si accende quando ci passi sopra con qualcosa in mano:
            // è l'unico segno che serve, perché la scheda È il bersaglio.
            RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous)
                .fill(Livrea.penna.opacity(mirato ? 0.22 : 0.0))
        }
        .modifier(BersaglioConversione(attivo: !perSonda, mirato: $mirato) { fornitori in
            convertitore.accogli(fornitori,
                                       formato: formato.wrappedValue,
                                       qualita: qualita.wrappedValue)
        })
    }

    /// Tre righe, etichetta a sinistra e comandi sullo stesso bordo destro,
    /// come la pagina delle Impostazioni (MacAppRules §2). La terza riga non
    /// ha scelte e lo dice, invece di lasciare un vuoto.
    private var elenco: some View {
        VStack(spacing: 6) {
            riga(S.immagini) {
                SegmentiCasa(voci: Convertitore.Formato.allCases,
                             titolo: { $0.titolo }, scelta: formato,
                             larghezzaVoce: NotchPanel.larghezzaVoceConverti, suCarta: false)
            }
            riga(S.video) {
                SegmentiCasa(voci: Convertitore.Qualita.allCases,
                             titolo: { $0.titolo }, scelta: qualita,
                             larghezzaVoce: NotchPanel.larghezzaVoceConverti, suCarta: false)
            }
            riga(S.documenti) {
                // Niente larghezza fissa: così finisce sullo stesso bordo
                // destro dei due selettori sopra (MacAppRules §2, «tutti i
                // comandi della pagina sullo stesso bordo»). Centrato in una
                // casella da 130 restava indietro di quaranta punti.
                Text(S.inPdf)
                    .font(.system(size: 12))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.55))
                    .padding(.trailing, 4)
            }
            // La nota sta a METÀ fra l'ultima riga e le linguette (sua
            // misura del 19/08): due vuoti uguali sopra e sotto, non
            // appiccicata a «Documenti».
            Spacer(minLength: 0)
            Text(S.notaConversione)
                .font(.system(size: 10))
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.45))
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    private func riga(_ titolo: String, @ViewBuilder comando: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(titolo)
                .font(.system(size: 12))
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.85))
            Spacer(minLength: 8)
            comando()
        }
        // La larghezza è la stessa della finestra Impostazioni (470): le due
        // pagine dell'app respirano uguale. Ci si è arrivati per tentativi
        // con lui davanti — 380 era stretta con l'aria ai bordi, 560 era
        // troppo tirata verso i lati.
        .frame(width: NotchPanel.larghezzaRigaConverti)
    }

    /// Mentre lavora: il nome e una barra. Un video lungo ci mette dei minuti,
    /// e senza avanzamento sembrerebbe piantato.
    private func lavoro(_ nome: String) -> some View {
        VStack(spacing: 8) {
            Text(nome)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.9))
            HStack(spacing: 10) {
                BarraCasa(quanto: max(0.02, convertitore.avanzamento))
                // In una casella FISSA e a cifre monospaziate: «7%» e «100%»
                // occupano lo stesso spazio, quindi la barra accanto non si
                // sposta mentre il numero cresce (MacAppRules §7).
                Text("\(Int((convertitore.avanzamento * 100).rounded()))%")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.75))
                    .frame(width: 40, alignment: .trailing)
            }
            // Il sottotitolo lo decide il TIPO di file, non l'avanzamento:
            // legarlo all'avanzamento faceva dire «converto l'immagine» per
            // il primo mezzo secondo di ogni video.
            Text(nome.hasSuffix(".mov") || nome.hasSuffix(".mp4") || nome.hasSuffix(".m4v")
                 ? S.comprimoVideo : S.convertoImmagine)
                .font(.system(size: 10))
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
        }
    }
}

/// Lo stesso involucro del bersaglio del deposito: `onDrop` non si applica «a
/// metà» dentro una catena di modificatori senza cambiare il tipo, e nella
/// sonda va spento perché `ImageRenderer` lo dipinge di giallo.
private struct BersaglioConversione: ViewModifier {
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
