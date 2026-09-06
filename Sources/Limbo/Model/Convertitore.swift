import AVFoundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Converte le immagini e alleggerisce i video. Tutto sul Mac, con quello che
/// il sistema ha già: ImageIO per le immagini, AVFoundation per i video.
///
/// **La regola che decide tutto: l'originale non si tocca.** Convertire non è
/// spostare — è il contrario del deposito, e per questo il convertitore non è
/// un bersaglio quando trascini verso il notch chiuso: lì restano AirDrop e
/// Deposito (sua parola del 19/08). Quello che esce va nel deposito, e da lì
/// lo trascini dove vuoi.
@MainActor
final class Convertitore: ObservableObject {
    /// Il nome di quello che sto lavorando adesso, `nil` se sono fermo.
    @Published private(set) var inCorso: String?
    /// Da 0 a 1. Per le immagini non si vede nemmeno: durano un istante.
    @Published private(set) var avanzamento: Double = 0
    /// L'ultima cosa andata storta, da mostrare e poi dimenticare.
    @Published var problema: String?

    enum Formato: String, CaseIterable, Identifiable {
        case heic, jpeg, png
        var id: String { rawValue }
        /// HEIC è il default: stessa resa del JPEG a metà del peso, ed è
        /// nativo su tutto quello che lui usa. JPEG resta per chi deve
        /// mandarlo a un sistema vecchio, PNG per gli schermi con del testo.
        var titolo: String { rawValue.uppercased() }
        var tipo: UTType {
            switch self {
            case .heic: .heic
            case .jpeg: .jpeg
            case .png: .png
            }
        }
        var estensione: String { self == .jpeg ? "jpg" : rawValue }
        /// Il PNG non ha perdita: la qualità non lo riguarda.
        var qualita: Double { self == .png ? 1.0 : 0.82 }
    }

    /// La qualità del video, MISURATA il 19/08 su una sua registrazione
    /// (82,8 MB, H.264 3024×1964): «Leggero» la porta a **6,3 MB**, «Fedele»
    /// a 27. Il vecchio preset di Apple ne faceva 43,2 rimpicciolendo pure a
    /// 1080p: qualità costante batte bitrate fisso di sei volte, e non serve
    /// buttare via pixel.
    ///
    /// I due nomi dicono il compromesso vero, guardato su un fotogramma: a
    /// «Leggero» il testo minuscolo dentro una miniatura si impasta mentre
    /// tutto il resto resta identico; a «Fedele» torna leggibile.
    enum Qualita: String, CaseIterable, Identifiable {
        case leggero, fedele
        var id: String { rawValue }
        var titolo: String { self == .leggero ? S.leggero : S.fedele }
        var valore: Float { self == .leggero ? 0.55 : 0.80 }
    }

    private let deposito: Deposito

    init(deposito: Deposito) {
        self.deposito = deposito
    }

    /// Prende quello che è stato rilasciato e decide da sé se è un'immagine o
    /// un video: chiedertelo sarebbe chiederti una cosa che il file già dice.
    func accogli(_ fornitori: [NSItemProvider], formato: Formato, qualita: Qualita = .leggero) {
        let percorsi = Deposito.percorsiTrascinati()
        guard !percorsi.isEmpty else {
            problema = S.nonSoConvertire
            return
        }
        // Il nome si mostra PRIMA di cominciare: fra il rilascio e il primo
        // fotogramma compresso passano dei decimi (leggere le tracce del
        // filmato è già lavoro), e in quei decimi lui non capiva se avesse
        // agganciato o no.
        inCorso = percorsi[0].lastPathComponent
        avanzamento = 0
        inizioLavoro = Date()
        Task { for url in percorsi { await lavora(url, formato: formato, qualita: qualita) } }
    }

    /// La porta della sonda visiva: mostra un lavoro finto senza toccare
    /// nessun file, così la fotografia può ritrarre la barra.
    func fingiLavoro(_ nome: String, avanzamento quanto: Double) {
        inCorso = nome
        avanzamento = quanto
    }

    /// La CONFERMA che il lavoro è finito. Sua richiesta del 19/08: «è
    /// talmente rapido che non si sa neanche che l'ha fatto, serve una V».
    /// Il messaggio lo mostra il pannello e se ne va da solo.
    private var avvisa: ((String, Bool) -> Void)?
    func avvisaCon(_ chiamata: @escaping (String, Bool) -> Void) { avvisa = chiamata }

    /// Quando è cominciato il lavoro in corso: serve a sapere se è stato
    /// LUNGO, e quindi se vale la pena aprire il pannello per dirlo.
    private var inizioLavoro: Date?
    /// Oltre questo, il lavoro è «lungo»: te ne sei andato a fare altro.
    static let lavoroLungo: TimeInterval = 3

    private func fatto(_ nome: String) {
        let quanto = inizioLavoro.map { Date().timeIntervalSince($0) } ?? 0
        avvisa?(nome, quanto >= Self.lavoroLungo)
    }

    func lavora(_ url: URL, formato: Formato, qualita: Qualita = .leggero) async {
        if inizioLavoro == nil { inizioLavoro = Date() }
        if Miniature.sembraImmagine(url) {
            await converti(immagine: url, in: formato)
        } else if await sembraVideo(url) {
            await comprimi(video: url, qualita: qualita)
        } else if Documenti.sappiamoLeggerlo(url) {
            await inPdf(documento: url)
        } else {
            problema = S.nonSoConvertire
        }
    }

    // MARK: - Documenti

    private func inPdf(documento url: URL) async {
        inCorso = url.lastPathComponent
        avanzamento = 0
        defer { inCorso = nil; avanzamento = 0 }
        let uscita = FileManager.default.temporaryDirectory
            .appendingPathComponent("limbo-\(UUID().uuidString)")
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".pdf")
        guard let scritto = await Task.detached(priority: .userInitiated, operation: {
            Documenti.pdf(da: url, in: uscita)
        }).value else {
            problema = S.nonSoConvertire
            return
        }
        deposito.accogli(fileEsistente: scritto)
        fatto(scritto.lastPathComponent)
    }

    private func sembraVideo(_ url: URL) async -> Bool {
        guard let tipo = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return tipo.conforms(to: .movie) || tipo.conforms(to: .audiovisualContent)
    }

    // MARK: - Immagini

    private func converti(immagine url: URL, in formato: Formato) async {
        inCorso = url.lastPathComponent
        avanzamento = 0
        defer { inCorso = nil; avanzamento = 0 }

        let nome = url.deletingPathExtension().lastPathComponent + "." + formato.estensione
        let uscita = FileManager.default.temporaryDirectory
            .appendingPathComponent("limbo-\(UUID().uuidString)")
            .appendingPathComponent(nome)
        guard let scritto = await Task.detached(priority: .userInitiated, operation: {
            Self.scrivi(immagine: url, in: uscita, formato: formato)
        }).value else {
            problema = S.nonSoConvertire
            return
        }
        deposito.accogli(fileEsistente: scritto)
        fatto(scritto.lastPathComponent)
    }

    /// La conversione vera. `CGImageDestination` fa tutto: legge il formato di
    /// partenza da sé e scrive quello che gli chiedi, senza passare da
    /// `NSImage` (che ricodifica e costa centinaia di millisecondi, lezione
    /// del 18/08).
    nonisolated static func scrivi(immagine origine: URL, in uscita: URL,
                                   formato: Formato) -> URL? {
        try? FileManager.default.createDirectory(
            at: uscita.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let sorgente = CGImageSourceCreateWithURL(origine as CFURL, nil),
              let immagine = CGImageSourceCreateImageAtIndex(sorgente, 0, nil),
              let destinazione = CGImageDestinationCreateWithURL(
                uscita as CFURL, formato.tipo.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destinazione, immagine, [
            kCGImageDestinationLossyCompressionQuality: formato.qualita
        ] as CFDictionary)
        guard CGImageDestinationFinalize(destinazione) else { return nil }
        return uscita
    }

    // MARK: - Video

    /// **Quanto si guadagna davvero, misurato il 19/08** su una sua
    /// registrazione dello schermo (86,8 MB, H.264 3024×1964, 24,8 Mbit/s):
    /// 1080p → 43,2 MB (la metà), 540p → 16,5 MB (un quinto). Il guadagno non
    /// è un ordine di grandezza perché il file di partenza NON era grezzo:
    /// una registrazione dello schermo di macOS esce già compressa in H.264,
    /// e il MOV è solo la scatola. Quello che si guadagna è quindi meno
    /// pixel (3024 → 1920) più un codec migliore, non la prima compressione.
    private func comprimi(video url: URL, qualita: Qualita) async {
        inCorso = url.lastPathComponent
        avanzamento = 0
        defer { inCorso = nil; avanzamento = 0 }

        let nome = url.deletingPathExtension().lastPathComponent
        let uscita = FileManager.default.temporaryDirectory
            .appendingPathComponent("limbo-\(UUID().uuidString)")
            .appendingPathComponent("\(nome)-leggero.mp4")

        guard await RicodificaVideo.comprimi(
            url, in: uscita, qualita: qualita.valore,
            avanzamento: { [weak self] quanto in
                Task { @MainActor in self?.avanzamento = quanto }
            }) != nil else {
            problema = S.nonSoConvertire
            return
        }
        deposito.accogli(fileEsistente: uscita)
        fatto(uscita.lastPathComponent)
    }
}

private extension AVAssetExportSession {
    /// L'attesa dell'export in forma `async`. L'API con `await` nativa esiste
    /// solo da macOS 15, e qui il minimo è 14.
    func export() async {
        await withCheckedContinuation { ripresa in
            exportAsynchronously { ripresa.resume() }
        }
    }
}
