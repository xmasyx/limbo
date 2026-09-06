import AVFoundation
import CoreMedia

/// La compressione video a QUALITÀ COSTANTE, con il chip.
///
/// **Perché esiste, e il numero che l'ha decisa (19/08).** Fino a stanotte il
/// video passava da `AVAssetExportSession` con un preset di Apple: su una sua
/// registrazione da 82,8 MB usciva **43,2 MB**, cioè la metà. Lo stesso file
/// con il metodo che avevamo già usato per i video di mobilità e di Otium —
/// `hevc_videotoolbox -q:v 55`, cioè qualità costante invece di bitrate
/// deciso da altri — esce a **7,0 MB, e a risoluzione PIENA**. Sei volte
/// meglio, senza rimpicciolire niente.
///
/// Qui quel metodo è nativo: stesso encoder (VideoToolbox), nessuna
/// dipendenza esterna, `AVVideoQualityKey` al posto di `-q:v`.
///
/// **Il prezzo, guardato e non stimato:** a qualità 0,55 il testo minuscolo
/// dentro una miniatura si impasta, mentre le scritte normali restano
/// identiche. Per questo la qualità è una scelta e non una costante.
enum RicodificaVideo {

    /// Comprime `origine` in `uscita`. `lato` limita il lato lungo (nil =
    /// risoluzione piena, che è il default giusto: rimpicciolire uccide il
    /// testo piccolo più della compressione).
    static func comprimi(
        _ origine: URL, in uscita: URL, qualita: Float, lato: CGFloat? = nil,
        avanzamento: @escaping @Sendable (Double) -> Void = { _ in }
    ) async -> URL? {
        let filmato = AVURLAsset(url: origine)
        guard let video = try? await filmato.loadTracks(withMediaType: .video).first,
              let lettore = try? AVAssetReader(asset: filmato) else { return nil }
        try? FileManager.default.removeItem(at: uscita)
        try? FileManager.default.createDirectory(
            at: uscita.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let scrittore = try? AVAssetWriter(outputURL: uscita, fileType: .mp4) else { return nil }

        let naturale = (try? await video.load(.naturalSize)) ?? .zero
        let trasformazione = (try? await video.load(.preferredTransform)) ?? .identity
        // **La misura è quella dei PIXEL che arrivano, non quella che si
        // vede.** Il 19/08 usavo `naturalSize.applying(transform)`, cioè la
        // misura ruotata, E impostavo anche il transform sull'uscita: su un
        // video girato col telefono (pixel 1920×1080 più «ruota di 90», visti
        // 1080×1920) l'encoder riceveva fotogrammi 1920×1080 e li schiacciava
        // dentro un riquadro 1080×1920, poi il player li ruotava di nuovo. Il
        // suo video di cucina è uscito compresso in orizzontale.
        //
        // Il reader consegna i pixel COME SONO: l'uscita si dichiara alla
        // loro misura, e il transform resta il cartello che dice al player
        // come girarli.
        let misura = misuraFinale(naturale, lato: lato)
        let durata = (try? await filmato.load(.duration).seconds) ?? 0

        // Video: HEVC a qualità costante. È la riga che vale i 36 MB.
        let uscitaVideo = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(misura.width),
            AVVideoHeightKey: Int(misura.height),
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: qualita],
        ])
        uscitaVideo.expectsMediaDataInRealTime = false
        uscitaVideo.transform = trasformazione
        guard scrittore.canAdd(uscitaVideo) else { return nil }
        scrittore.add(uscitaVideo)

        let ingressoVideo = AVAssetReaderTrackOutput(track: video, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        guard lettore.canAdd(ingressoVideo) else { return nil }
        lettore.add(ingressoVideo)

        // Audio, quando c'è: AAC 128k come nel comando di allora. Un video
        // senza la sua voce è un video diverso, non un video più leggero.
        var ingressoAudio: AVAssetReaderTrackOutput?
        var uscitaAudio: AVAssetWriterInput?
        if let audio = try? await filmato.loadTracks(withMediaType: .audio).first {
            let letturaA = AVAssetReaderTrackOutput(track: audio, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            let scritturaA = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 44100,
                AVEncoderBitRateKey: 128_000,
            ])
            scritturaA.expectsMediaDataInRealTime = false
            if lettore.canAdd(letturaA) && scrittore.canAdd(scritturaA) {
                lettore.add(letturaA); scrittore.add(scritturaA)
                ingressoAudio = letturaA; uscitaAudio = scritturaA
            }
        }

        guard lettore.startReading(), scrittore.startWriting() else { return nil }
        scrittore.startSession(atSourceTime: .zero)

        // **I due flussi si alimentano INSIEME, mai uno dopo l'altro.**
        // Il 19/08 li alimentavo in sequenza — prima tutto il video, poi
        // l'audio — e su un video CON audio la ricodifica si piantava: 0% di
        // CPU e il file fermo a 0 byte. `AVAssetWriter` deve interlacciare le
        // tracce, quindi smette di chiedere fotogrammi video finché l'audio
        // non avanza, e l'audio non avanzava perché stavo aspettando la fine
        // del video. Uno stallo perfetto, e senza errori.
        await withTaskGroup(of: Void.self) { gruppo in
            gruppo.addTask {
                await travasa(uscitaVideo, da: ingressoVideo, coda: "video",
                              durata: durata, avanzamento: avanzamento)
            }
            if let uscitaAudio, let ingressoAudio {
                gruppo.addTask {
                    await travasa(uscitaAudio, da: ingressoAudio, coda: "audio",
                                  durata: 0, avanzamento: { _ in })
                }
            }
        }

        await scrittore.finishWriting()
        guard scrittore.status == .completed else {
            registro.error("ricodifica fallita: \(scrittore.error?.localizedDescription ?? "senza motivo", privacy: .public)")
            return nil
        }
        return uscita
    }

    /// Sposta i campioni da una traccia letta a una scritta, chiedendo il
    /// prossimo solo quando l'encoder è pronto: così la memoria resta piatta
    /// anche su un filmato da due gigabyte.
    private nonisolated static func travasa(
        _ scrittura: AVAssetWriterInput, da lettura: AVAssetReaderTrackOutput,
        coda: String, durata: Double, avanzamento: @escaping @Sendable (Double) -> Void
    ) async {
        let fila = DispatchQueue(label: "app.limbo.ricodifica.\(coda)")
        await withCheckedContinuation { ripresa in
            nonisolated(unsafe) var finito = false
            scrittura.requestMediaDataWhenReady(on: fila) {
                while scrittura.isReadyForMoreMediaData {
                    guard let campione = lettura.copyNextSampleBuffer() else {
                        if !finito {
                            finito = true
                            scrittura.markAsFinished()
                            ripresa.resume()
                        }
                        return
                    }
                    if durata > 0 {
                        let quando = CMSampleBufferGetPresentationTimeStamp(campione).seconds
                        avanzamento(min(1, max(0, quando / durata)))
                    }
                    scrittura.append(campione)
                }
            }
        }
    }

    /// La misura finale dei PIXEL: pari (gli encoder li vogliono pari) e mai
    /// più grande dell'originale — chi chiede 1080 su un video 720 vuole 720,
    /// non un ingrandimento.
    private static func misuraFinale(_ vera: CGSize, lato: CGFloat?) -> CGSize {
        guard let lato, max(vera.width, vera.height) > lato else { return pari(vera) }
        let fattore = lato / max(vera.width, vera.height)
        return pari(CGSize(width: vera.width * fattore, height: vera.height * fattore))
    }

    private static func pari(_ m: CGSize) -> CGSize {
        CGSize(width: (Int(m.width.rounded()) / 2) * 2, height: (Int(m.height.rounded()) / 2) * 2)
    }
}
