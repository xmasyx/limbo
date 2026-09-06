import AppKit
import SwiftUI

/// La misura di una scheda. Una sola costante per entrambe le file: due
/// schede vicine di taglia diversa si vedono, e qui le due file si alternano
/// nello stesso posto (MacAppRules §7, voci della stessa larghezza).
enum MisuraScheda {
    static let largo: CGFloat = 98
    static let alto: CGFloat = 128
    /// L'altezza della didascalia sotto l'anteprima. **Fissa**, e per due
    /// righe di nome: un nome corto e uno lungo devono lasciare l'anteprima
    /// alla stessa altezza, altrimenti la fila balla. Una riga sola dava
    /// «Scher…-18.png» e «Appun…one.txt», cioè tre nomi che si somigliavano
    /// tutti — un nome di file si riconosce dai suoi pezzi, non dal fatto che
    /// finisca in .png.
    static let didascalia: CGFloat = 44
    /// Lo stacco fra due schede vicine.
    static let stacco: CGFloat = 10

    /// Quanto è larga una fila di N schede. Serve alla vista per NON prendere
    /// più spazio del contenuto, e al banco per provarlo: sopra le schede lo
    /// scorrimento è della fila, sul nero vuoto è della finestra.
    static func larghezzaFila(_ quante: Int) -> CGFloat {
        guard quante > 0 else { return 0 }
        return CGFloat(quante) * largo + CGFloat(quante - 1) * stacco + 2
    }
}

/// Il guscio comune delle due schede: stessa taglia, stesso raggio, stesso
/// fondo, stessa reazione al puntatore. Le due si distinguono per quello che
/// mettono dentro, mai per come sono fatte.
private struct GuscioScheda<Anteprima: View>: View {
    let titolo: String
    let sotto: String?
    var fissata = false
    /// C'e' del testo dentro l'immagine (vedi `Ocr`): un segno piccolo in
    /// basso a sinistra. Non e' un comando, e' un fatto — il comando sta nel
    /// tasto destro.
    var haTesto = false
    /// Quando la scheda ha sopra una vista AppKit che si mangia gli eventi,
    /// il passaggio del puntatore arriva da lì invece che da `.onHover`.
    var sfiorataDaFuori: Binding<Bool>? = nil
    @ViewBuilder let anteprima: () -> Anteprima

    @State private var sfiorataPropria = false
    private var sfiorata: Bool { sfiorataDaFuori?.wrappedValue ?? sfiorataPropria }

    var body: some View {
        VStack(spacing: 0) {
            anteprima()
                .frame(width: MisuraScheda.largo - 12,
                       height: MisuraScheda.alto - MisuraScheda.didascalia - 14)
                .clipShape(RoundedRectangle(cornerRadius: Raggi.dentro, style: .continuous))

            VStack(spacing: 1) {
                Text(titolo)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)   // un nome di file si perde in mezzo, non in coda
                if let sotto {
                    Text(sotto)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Livrea.sopraGuscio.opacity(0.4))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(Livrea.sopraGuscio.opacity(0.85))
            .frame(height: MisuraScheda.didascalia)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
        }
        .padding(6)
        .frame(width: MisuraScheda.largo, height: MisuraScheda.alto)
        .background {
            RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous)
                .fill(Color.white.opacity(sfiorata ? 0.14 : 0.07))
        }
        .overlay(alignment: .bottomLeading) {
            if haTesto {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 9))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.55))
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if fissata {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Livrea.penna)
                    .padding(6)
            }
        }
        // La scala non tocca il layout: la scheda cresce sopra le vicine senza
        // spostarle, quindi la fila non si ricompone al passaggio del mouse.
        .scaleEffect(sfiorata ? 1.03 : 1.0)
        .animation(Movimento.sfiora, value: sfiorata)
        .contentShape(RoundedRectangle(cornerRadius: Raggi.scheda, style: .continuous))
        .onHover { dentro in if sfiorataDaFuori == nil { sfiorataPropria = dentro } }
    }
}

// MARK: - Una cosa copiata

struct SchedaAppunto: View {
    let voce: VoceAppunti
    @ObservedObject var stato: StatoNotch

    var body: some View {
        GuscioScheda(titolo: titolo, sotto: sotto, haTesto: voce.testoLetto != nil) {
            anteprima
        }
        .onTapGesture {
            stato.appunti.riporta(voce)
            stato.soffia(S.copiato, simbolo: Simboli.fatto)
        }
        .onDrag { fornitore() }
        .contextMenu {
            Button(S.copia) { stato.appunti.riporta(voce) }
            if let testo = voce.testoLetto {
                Button(S.copiaIlTesto) { Self.copia(testo: testo); stato.soffia(S.copiato, simbolo: Simboli.fatto) }
            }
            Button(S.deposito) { nelDeposito() }
            Divider()
            Button(S.togliDalDeposito, role: .destructive) { stato.appunti.dimentica(voce) }
        }
        .help(titolo)
    }

    /// La didascalia sono FATTI, mai una frase (regola 12 del gusto), e per
    /// un testo il fatto non e' il testo: quello e' gia' l'anteprima sopra.
    /// Ripeterlo troncato dava «Il vinc...nche' EP», che non dice niente e
    /// sporca la fila. Quello che serve e' da dove viene e quando.
    private var titolo: String {
        switch voce.contenuto {
        case .testo: voce.app ?? "Testo"
        case .immagine: "Immagine"
        case .file: voce.titolo
        }
    }

    private var sotto: String {
        switch voce.contenuto {
        case .testo: Self.ora.string(from: voce.quando)
        case .immagine, .file: voce.app ?? Self.ora.string(from: voce.quando)
        }
    }

    private static let ora: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private var anteprima: some View {
        switch voce.contenuto {
        case .testo(let t):
            // Il testo È l'anteprima: si legge il principio, che è quello che
            // ti fa riconoscere quale copia stai cercando.
            Text(t.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 9))
                .foregroundStyle(Livrea.sopraGuscio.opacity(0.8))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(5)
                .background(Color.white.opacity(0.05))

        case .immagine(let url):
            // MAI `NSImage(contentsOf:)` nel corpo: decodifica l'immagine
            // intera a ogni valutazione, sul thread che disegna (C10).
            MiniaturaView(url: url, segnaposto: nil)

        case .file(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(10)
        }
    }

    private func simbolo(_ nome: String) -> some View {
        Image(systemName: nome)
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fornitore() -> NSItemProvider {
        switch voce.contenuto {
        case .testo(let t): NSItemProvider(object: t as NSString)
        case .immagine(let url): NSItemProvider(contentsOf: url) ?? NSItemProvider()
        case .file(let urls): NSItemProvider(contentsOf: urls[0]) ?? NSItemProvider()
        }
    }

    /// Mette del testo negli appunti di sistema. Statica: la usano due
    /// schede diverse e non deve dipendere da nessuno stato.
    static func copia(testo: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(testo, forType: .string)
    }

    private func nelDeposito() {
        switch voce.contenuto {
        case .testo(let t):
            if let dati = t.data(using: .utf8) {
                let fornitore = NSItemProvider(item: dati as NSData, typeIdentifier: "public.utf8-plain-text")
                Task { _ = await stato.deposito.accogli([fornitore]) }
            }
        case .immagine(let url):
            // COPIA, non spostamento: gli appunti tengono la loro. E byte
            // così come sono, senza il giro da `NSImage` (589 ms, 18/08).
            stato.deposito.accogli(copiaDi: url)
        case .file(let urls):
            for url in urls { stato.deposito.accogli(fileEsistente: url) }
        }
        stato.scheda = .deposito
    }
}

// MARK: - Una cosa messa da parte

struct SchedaDeposito: View {
    let voce: VoceDeposito
    @ObservedObject var stato: StatoNotch
    /// Il passaggio del puntatore arriva da AppKit, non da SwiftUI: sopra la
    /// scheda c'è la sorgente del trascinamento, che prende tutti gli eventi.
    @State private var sfiorata = false
    /// La scheda sta volando sotto il puntatore: qui si nasconde, perché
    /// quello che si muove è LEI (suo rilievo del 19/08). Se il gesto non
    /// atterra, ricompare.
    @State private var inVolo = false
    /// Nella sonda la sorgente AppKit non si monta: `ImageRenderer` non sa
    /// disegnare una vista di AppKit e ci mette il suo segnaposto giallo col
    /// divieto sopra. È la spiegazione GENERALE del giallo visto il 18/08 —
    /// non era `onDrop` in quanto tale, era che `onDrop` si porta dietro una
    /// vista AppKit, come questa.
    var perSonda = false
    /// Forza lo stato «puntatore sopra» per la sonda visiva. Il passaggio del
    /// puntatore vero arriva da AppKit e in un `ImageRenderer` non succede
    /// mai: senza questo, la X non si potrebbe fotografare, e una funzione
    /// che non si può fotografare non si può dimostrare.
    var sfiorataPerSonda = false

    /// Il diametro della X. **Vive qui e la legge anche la zona sensibile**
    /// passata alla sorgente AppKit: due numeri in due posti sono il difetto
    /// del «Lif…» del 20/08, ed è il motivo per cui la prima X si vedeva e non
    /// si premeva. La zona è più larga del disegno perché lui la punta
    /// avvicinandosi, non centrandola.
    static let latoX: CGFloat = 24
    /// Lo stacco della X dal bordo. **Non è decorazione: decide se la X si
    /// preme.** Deve restare positivo, cioè la X DENTRO la scheda, perché la
    /// zona sensibile vive nelle coordinate della vista AppKit e fuori da
    /// quelle non c'è niente che riceva il colpo. Il 6/09 la X era spinta
    /// fuori dall'angolo di 7 punti: si vedeva, il puntatore ci arrivava, e il
    /// clic cadeva nel vuoto perché era oltre il bordo della vista. Il video
    /// che ha mandato lo mostra in sei fotogrammi.
    static let bordoX: CGFloat = 2
    static let zonaX: CGFloat = 34

    var body: some View {
        GuscioScheda(titolo: voce.nome, sotto: peso, fissata: voce.fissata,
                     haTesto: voce.testoLetto != nil,
                     sfiorataDaFuori: $sfiorata) {
            anteprima
        }
        .opacity(inVolo ? 0 : (voce.esiste ? 1 : 0.35))
        .animation(Movimento.sfiora, value: inVolo)
        // Tutti gli eventi del mouse di questa scheda passano di qui: clic,
        // tasto destro, passaggio del puntatore e trascinamento. È il prezzo
        // per sapere se il trascinamento è atterrato, che è la cosa che
        // separa un limbo da una clipboard.
        .overlay {
            if perSonda { EmptyView() } else {
            SorgenteTrascinamento(
                // L'anteprima che vola è quella in CACHE o niente: una
                // decodifica sincrona proprio all'inizio del gesto era metà
                // dell'impasto del trascinamento fuori (C10).
                url: voce.url, nome: voce.nome, anteprima: Miniature.pronta(per: voce.url),
                voci: vociDelMenu,
                clic: { apri() },
                sfiorata: { sfiorata = $0 },
                finito: { atterrato in
                    // Le voci tenute ferme fanno eccezione: è esattamente ciò
                    // che vuol dire tenerle ferme. Il gesto mancato rimette
                    // la scheda al suo posto.
                    guard atterrato, !voce.fissata else { inVolo = false; return }
                    stato.deposito.togli(voce, atterrata: true)
                },
                sparito: {
                    stato.soffia(S.fileSparito)
                    stato.deposito.potaSpariti()
                },
                iniziato: { inVolo = true },
                latoX: sfiorata ? Self.zonaX : 0,
                // Niente conferma (sua richiesta del 6/09: «non voglio
                // l'animazione nel cestino, mi basta che scompaia»). La X è
                // un gesto piccolo e mirato: la scheda che sparisce È la
                // conferma, e un messaggio sopra sarebbe rumore.
                xPremuta: { stato.deposito.togli(voce) }
            )
            }
        }
        // **La X sta SOPRA la sorgente del trascinamento, e l'ordine è la
        // funzione.** `SorgenteTrascinamento` è una vista AppKit che si prende
        // tutti gli eventi del mouse della scheda: una X messa prima sarebbe
        // disegno sotto vetro, visibile e non premibile — la stessa classe del
        // «bottone che è solo sfondo» delle regole di casa. Messa dopo,
        // l'overlay più recente vince il colpo.
        // **La X è DISEGNO, non un bottone**, e non è una scorciatoia: il
        // colpo lo prende la vista AppKit sotto (vedi `latoX` in
        // `SorgenteTrascinamento`), quindi un `Button` qui avrebbe un'azione
        // che non parte mai. Un comando con due padroni è un comando che non
        // funziona, ed è esattamente cosa è successo il 6/09.
        .overlay(alignment: .topTrailing) {
            if (sfiorata || sfiorataPerSonda) && voce.esiste {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Livrea.sopraGuscio)
                    .frame(width: Self.latoX, height: Self.latoX)
                    .background(Circle().fill(Color.black.opacity(0.78)))
                    .overlay(Circle().stroke(Livrea.sopraGuscio.opacity(0.3), lineWidth: 0.5))
                    // Appoggiata sull'angolo tondo, non oltre: si stacca dalla
                    // miniatura come voleva lui, ma resta dentro la vista che
                    // riceve il colpo.
                    .padding(Self.bordoX)
                    .transition(.opacity)
                    .help(S.togliDalDeposito)
                    // **Il disegno NON deve prendere il colpo.** Una vista di
                    // SwiftUI sopra la vista AppKit intercetta il clic anche
                    // se non ha un gesto: lo assorbe e non lo passa a nessuno.
                    // Terzo giro del 6/09: X raggiungibile su tutte e tre le
                    // schede, clic muto su tutte e tre — il colpo moriva qui.
                    .allowsHitTesting(false)
            }
        }
        .animation(Movimento.sfiora, value: sfiorata)
        .help(voce.esiste ? voce.url.path : S.fileSparito)
    }

    /// Le voci del tasto destro. In un posto solo perche' cambiano con la
    /// voce: il testo letto c'e' solo dentro un'immagine, e la conversione
    /// riguarda solo cio' che si sa convertire.
    private var vociDelMenu: [(titolo: String, azione: (() -> Void)?)] {
        var voci: [(String, (() -> Void)?)] = [
            (S.apri, { apri() }),
            (S.mostraNelFinder, { NSWorkspace.shared.activateFileViewerSelecting([voce.url]) }),
            ("", nil),
        ]
        if let testo = voce.testoLetto {
            voci.append((S.copiaIlTesto, {
                SchedaAppunto.copia(testo: testo)
                stato.soffia(S.copiato, simbolo: Simboli.fatto)
            }))
        }
        if Miniature.sembraImmagine(voce.url) {
            for formato in Convertitore.Formato.allCases {
                voci.append(("\(S.convertitore) in \(formato.titolo)", {
                    Task { await stato.convertitore.lavora(voce.url, formato: formato) }
                }))
            }
        } else {
            voci.append((S.comprimoVideo, {
                Task { await stato.convertitore.lavora(voce.url, formato: .heic) }
            }))
        }
        voci.append(("", nil))
        voci.append((S.airdrop, { airdrop() }))
        voci.append((S.condividi, { condividi() }))
        voci.append(("", nil))
        voci.append((voce.fissata ? S.libera : S.fissa, { stato.deposito.fissa(voce) }))
        voci.append((S.togliDalDeposito, { stato.deposito.togli(voce) }))
        return voci.map { (titolo: $0.0, azione: $0.1) }
    }

    /// Il peso del file, in una casella che non cambia larghezza.
    private var peso: String? {
        guard let valori = try? voce.url.resourceValues(forKeys: [.fileSizeKey]),
              let byte = valori.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byte), countStyle: .file)
    }

    @ViewBuilder
    private var anteprima: some View {
        if voce.esiste, Miniature.sembraImmagine(voce.url) {
            MiniaturaView(url: voce.url, segnaposto: voce.icona)
        } else {
            Image(nsImage: voce.icona)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(10)
        }
    }

    private func apri() {
        guard voce.esiste else {
            stato.soffia(S.fileSparito)
            stato.deposito.potaSpariti()
            return
        }
        NSWorkspace.shared.open(voce.url)
    }

    /// AirDrop è un servizio di condivisione come gli altri: il pannello di
    /// sistema lo apre già sul dispositivo giusto, e riscriverlo vorrebbe dire
    /// rifare una cosa che il Mac fa meglio.
    private func airdrop() {
        guard voce.esiste else { stato.soffia(S.fileSparito); return }
        guard let servizio = NSSharingService(named: .sendViaAirDrop) else {
            stato.soffia(S.nienteDaCondividere); return
        }
        servizio.perform(withItems: [voce.url])
    }

    private func condividi() {
        guard voce.esiste else { stato.soffia(S.fileSparito); return }
        let pannello = NSSharingServicePicker(items: [voce.url])
        guard let vista = NSApp.keyWindow?.contentView ?? NSApp.windows.first?.contentView else { return }
        pannello.show(relativeTo: .zero, of: vista, preferredEdge: .minY)
    }
}
