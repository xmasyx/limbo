import SwiftUI

// I controlli di casa. Nella pagina non entra un controllo di sistema
// (MacAppRules §7): il segmented di macOS porta la pillola blu di Apple, cioè
// i colori di qualcun altro dentro la nostra livrea, e si vede subito.
//
// Regola della stessa sezione: **le voci hanno tutte la stessa larghezza**,
// dentro un controllo e fra controlli vicini. Il testo scala, la voce no —
// altrimenti la pillola si allarga cambiando scheda e il resto della riga
// balla.

/// Il selettore a due (o più) voci, larghezza fissa per voce.
struct SegmentiCasa<T: Hashable & Identifiable>: View {
    let voci: [T]
    let titolo: (T) -> String
    @Binding var scelta: T
    /// La larghezza di UNA voce. Una sola costante per schermata: se due
    /// selettori vicini hanno numeri diversi, si vede.
    var larghezzaVoce: CGFloat = 96
    var suCarta = true

    var body: some View {
        HStack(spacing: 2) {
            ForEach(voci) { voce in
                let scelto = voce == scelta
                Button {
                    withAnimation(Movimento.contenuto) { scelta = voce }
                } label: {
                    Text(titolo(voce))
                        .font(.system(size: 12, weight: scelto ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()          // «Deposito» non diventa «Depos…»
                        .frame(width: larghezzaVoce, height: 24)
                        .foregroundStyle(coloreTesto(scelto: scelto))
                        .background {
                            if scelto {
                                Capsule().fill(Livrea.penna)
                            }
                        }
                        .contentShape(Capsule())   // si clicca tutta la pillola
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            Capsule().fill(fondoBinario)
        }
    }

    private func coloreTesto(scelto: Bool) -> Color {
        if scelto { return .white }
        return suCarta ? Livrea.inchiostro.opacity(0.75) : Livrea.sopraGuscio.opacity(0.65)
    }

    private var fondoBinario: Color {
        suCarta ? Livrea.inchiostro.opacity(0.07) : Color.white.opacity(0.08)
    }
}

/// Il bottone di casa: tutto il rettangolo è cliccabile e il rettangolo si
/// vede (MacAppRules §3 e §5). Un comando che è solo testo tenue non si
/// riconosce come comando.
struct BottoneCasa: View {
    let titolo: String
    var simbolo: String?
    var tenue = false
    let azione: () -> Void

    var body: some View {
        Button(action: azione) {
            HStack(spacing: 5) {
                if let simbolo {
                    Image(systemName: simbolo).font(.system(size: 11, weight: .medium))
                }
                Text(titolo).font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(tenue ? Livrea.sopraGuscio.opacity(0.8) : .white)
            .background {
                Capsule().fill(tenue ? Color.white.opacity(0.10) : Livrea.penna)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}


/// La barra di avanzamento di casa: due capsule sovrapposte.
///
/// Non `ProgressView`: quello è un controllo di SISTEMA (MacAppRules §7, «nella
/// pagina non entra un controllo di sistema»), porta i colori di Apple, e in
/// più `ImageRenderer` non lo sa disegnare — nella sonda del 19/08 usciva un
/// rettangolo GIALLO col divieto, cioè la fotografia non poteva provare
/// niente proprio sulla schermata che stavamo aggiustando.
struct BarraCasa: View {
    /// Da 0 a 1.
    let quanto: Double
    var larghezza: CGFloat = 260
    var spessore: CGFloat = 6

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.14))
            Capsule()
                .fill(Livrea.penna)
                .frame(width: max(spessore, larghezza * min(1, max(0, quanto))))
        }
        .frame(width: larghezza, height: spessore)
        .animation(Movimento.contenuto, value: quanto)
    }
}
