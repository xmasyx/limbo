import AVFoundation
import CoreVideo
import Foundation

/// Conta i fotogrammi persi in una registrazione dello schermo.
///
/// È la misura promessa nella ripresa del 19/08: il rallentamento non si
/// indovina, si conta. Due segnali, letti insieme:
///
/// 1. **Stalli**: sequenze di fotogrammi IDENTICI nella striscia alta (dove
///    vive il pannello). Durante un'animazione un fotogramma uguale al
///    precedente è un fotogramma perso; a pannello fermo è semplicemente
///    quiete. Perciò si riportano solo gli stalli BREVI in mezzo al
///    movimento, con il momento esatto in cui accadono.
/// 2. **Vuoti nei tempi**: registrando lo schermo macOS non scrive i
///    fotogrammi in cui non cambia niente, quindi un buco nei timestamp più
///    largo del passo mediano durante il movimento è a sua volta uno stallo.
enum Fotogrammi {
    static func misura(percorso: String) -> Int32 {
        let url = URL(fileURLWithPath: percorso)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("✗ non c'è nessun file in \(percorso)")
            return 2
        }

        let asset = AVURLAsset(url: url)
        let attesa = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var tracce: [AVAssetTrack] = []
        Task {
            tracce = (try? await asset.loadTracks(withMediaType: .video)) ?? []
            attesa.signal()
        }
        attesa.wait()

        guard let traccia = tracce.first,
              let lettore = try? AVAssetReader(asset: asset) else {
            print("✗ il file non si legge come video")
            return 2
        }
        let uscita = AVAssetReaderTrackOutput(track: traccia, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        uscita.alwaysCopiesSampleData = false
        lettore.add(uscita)
        guard lettore.startReading() else {
            print("✗ la lettura non parte: \(lettore.error?.localizedDescription ?? "senza motivo")")
            return 2
        }

        var tempi: [Double] = []
        var impronte: [UInt64] = []
        while let campione = uscita.copyNextSampleBuffer() {
            let quando = CMSampleBufferGetPresentationTimeStamp(campione)
            guard let pixel = CMSampleBufferGetImageBuffer(campione) else { continue }
            tempi.append(quando.seconds)
            impronte.append(improntaStriscia(pixel))
        }
        guard tempi.count > 2 else {
            print("✗ troppo corto per misurare (\(tempi.count) fotogrammi)")
            return 2
        }

        let durata = tempi.last! - tempi.first!
        let passi = zip(tempi.dropFirst(), tempi).map(-)
        let passoMediano = passi.sorted()[passi.count / 2]

        print("── \(url.lastPathComponent)")
        print("fotogrammi scritti: \(tempi.count) in \(String(format: "%.1f", durata)) s")
        print("passo mediano: \(String(format: "%.1f", passoMediano * 1000)) ms (≈\(Int((1 / passoMediano).rounded())) fps)")

        // Gli stalli: corse di impronte identiche, brevi (il movimento le
        // circonda), più i vuoti nei timestamp oltre il doppio del passo.
        var stalli: [(inizio: Double, persi: Int)] = []
        var corsa = 1
        for i in 1..<impronte.count {
            if impronte[i] == impronte[i - 1] {
                corsa += 1
            } else {
                if corsa >= 2 && corsa <= 90 {
                    stalli.append((tempi[i - corsa], corsa - 1))
                }
                corsa = 1
            }
        }
        for i in 1..<tempi.count where passi[i - 1] > passoMediano * 2 {
            let persi = Int((passi[i - 1] / passoMediano).rounded()) - 1
            if persi >= 1 && persi <= 90 { stalli.append((tempi[i - 1], persi)) }
        }
        stalli.sort { $0.inizio < $1.inizio }

        if stalli.isEmpty {
            print("nessuno stallo breve: o è fluido, o è fermo del tutto")
        } else {
            let totale = stalli.reduce(0) { $0 + $1.persi }
            print("stalli brevi: \(stalli.count), fotogrammi persi: \(totale)")
            for (inizio, persi) in stalli.prefix(40) {
                print(String(format: "  al secondo %6.2f — %d persi", inizio, persi))
            }
            if stalli.count > 40 { print("  … e altri \(stalli.count - 40)") }
        }
        return 0
    }

    /// L'impronta della striscia alta di un fotogramma: le prime ~1/5 righe,
    /// campionate una ogni due, un pixel ogni quattro. Basta a dire «uguale al
    /// precedente» e costa poco anche su un video 3024×1964.
    private static func improntaStriscia(_ pixel: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixel, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixel) else { return 0 }
        let byte = base.assumingMemoryBound(to: UInt8.self)
        let altezza = CVPixelBufferGetHeight(pixel)
        let larghezza = CVPixelBufferGetWidth(pixel)
        let riga = CVPixelBufferGetBytesPerRow(pixel)
        let righe = min(altezza, max(64, altezza / 5))

        var accumulatore: UInt64 = 1469598103934665603
        var y = 0
        while y < righe {
            var x = 0
            let inizio = y * riga
            while x < larghezza * 4 {
                accumulatore = (accumulatore ^ UInt64(byte[inizio + x])) &* 1099511628211
                x += 16
            }
            y += 2
        }
        return accumulatore
    }
}
