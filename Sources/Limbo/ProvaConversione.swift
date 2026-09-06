import AVFoundation
import AppKit

/// `--prova-conversione <file>`: converte davvero e stampa i numeri. Nasce il
/// 19/08 dalla sua domanda «da MOV a MP4 non cambia tanto, perché?»: a una
/// domanda sul risparmio si risponde con una misura, non con una teoria.
enum ProvaConversione {
    static func esegui(percorso: String) -> Int32 {
        let url = URL(fileURLWithPath: percorso)
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("✗ non c'è nessun file in \(percorso)"); return 2
        }
        let prima = peso(url)
        print("── \(url.lastPathComponent)")
        print("prima: \(leggibile(prima))")

        let attesa = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var esito: Int32 = 1
        Task {
            esito = await converti(url)
            attesa.signal()
        }
        attesa.wait()
        return esito
    }

    private static func converti(_ url: URL) async -> Int32 {
        let filmato = AVURLAsset(url: url)
        guard let traccia = try? await filmato.loadTracks(withMediaType: .video).first else {
            print("✗ nessuna traccia video"); return 2
        }
        let misura = (try? await traccia.load(.naturalSize)) ?? .zero
        let bitrate = (try? await traccia.load(.estimatedDataRate)) ?? 0
        let formati = (try? await traccia.load(.formatDescriptions)) ?? []
        let codec = formati.first.map {
            let t = CMFormatDescriptionGetMediaSubType($0)
            return String(bytes: [UInt8(t >> 24 & 255), UInt8(t >> 16 & 255),
                                  UInt8(t >> 8 & 255), UInt8(t & 255)], encoding: .ascii) ?? "?"
        } ?? "?"
        print("dentro: \(Int(misura.width))×\(Int(misura.height)), codec \(codec), "
              + String(format: "%.1f Mbit/s", bitrate / 1_000_000))

        // Il metodo nuovo: qualità costante, risoluzione piena.
        for (nome, q) in [("qualità 0,55 piena", Float(0.55)),
                          ("qualità 0,75 piena", Float(0.75))] {
            let uscita = FileManager.default.temporaryDirectory
                .appendingPathComponent("prova-\(UUID().uuidString).mp4")
            let inizio = Date()
            if await RicodificaVideo.comprimi(url, in: uscita, qualita: q) != nil {
                let dopo = peso(uscita)
                print(String(format: "  %@: %@ (%.0f%% dell'originale) in %.0f s",
                             nome, leggibile(dopo), Double(dopo) / Double(max(1, peso(url))) * 100,
                             Date().timeIntervalSince(inizio)))
            } else {
                print("  \(nome): fallita")
            }
            try? FileManager.default.removeItem(at: uscita)
        }

        for (nome, preset) in [("preset Apple 1080p", AVAssetExportPresetHEVC1920x1080)] {
            guard AVAssetExportSession.exportPresets(compatibleWith: filmato).contains(preset),
                  let sessione = AVAssetExportSession(asset: filmato, presetName: preset) else {
                print("  \(nome): non disponibile"); continue
            }
            let uscita = FileManager.default.temporaryDirectory
                .appendingPathComponent("prova-\(UUID().uuidString).mp4")
            sessione.outputURL = uscita
            sessione.outputFileType = .mp4
            let inizio = Date()
            await withCheckedContinuation { r in sessione.exportAsynchronously { r.resume() } }
            guard sessione.status == .completed else {
                print("  \(nome): fallito (\(sessione.error?.localizedDescription ?? "?"))"); continue
            }
            let dopo = peso(uscita)
            let quanto = Double(dopo) / Double(max(1, peso(URL(fileURLWithPath: filmato.url.path))))
            print(String(format: "  %@: %@ (%.0f%% dell'originale) in %.0f s",
                         nome, leggibile(dopo), quanto * 100, Date().timeIntervalSince(inizio)))
            try? FileManager.default.removeItem(at: uscita)
        }
        return 0
    }

    private static func peso(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap(Int64.init) ?? 0
    }

    private static func leggibile(_ byte: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byte, countStyle: .file)
    }
}
