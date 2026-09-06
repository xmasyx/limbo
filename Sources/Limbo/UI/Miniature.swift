import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Le miniature delle schede, decodificate UNA volta, al lato giusto, mai sul
/// thread che disegna.
///
/// Il difetto che questo file toglie: `NSImage(contentsOf:)` dentro il corpo
/// di una vista decodifica l'immagine INTERA a ogni valutazione del corpo —
/// con le schermate vere (3024×1964) sono decine di millisecondi sul thread
/// principale, pagati a ogni apertura del pannello, a ogni passaggio del
/// puntatore e all'inizio di ogni trascinamento. È l'ipotesi 3 della ripresa
/// del 19/08, e il banco delle miniature la misura invece di raccontarla.
enum Miniature {
    /// Il lato massimo di una miniatura. Le schede mostrano ~86 punti (~172
    /// pixel Retina): 256 tiene margine senza pagare l'immagine intera.
    static let lato = 256

    private static let cache = NSCache<NSString, NSImage>()
    private static let coda = DispatchQueue(label: "app.limbo.miniature",
                                            qos: .userInitiated, attributes: .concurrent)

    /// La chiave lega percorso e data di modifica: un file riscritto non riusa
    /// la miniatura vecchia.
    private static func chiave(_ url: URL) -> NSString {
        let quando = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return "\(url.path)#\(quando?.timeIntervalSince1970 ?? 0)" as NSString
    }

    /// `true` se il file ha l'aria di un'immagine (dal tipo, non dai byte):
    /// decide solo se TENTARE la miniatura, mai il risultato.
    static func sembraImmagine(_ url: URL) -> Bool {
        guard let tipo = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return tipo.conforms(to: .image)
    }

    /// Quella già pronta, senza decodificare niente. Per l'immagine che vola
    /// sotto il puntatore: se non c'è ancora, meglio l'icona del file che una
    /// decodifica sincrona proprio all'inizio del gesto.
    static func pronta(per url: URL) -> NSImage? {
        cache.object(forKey: chiave(url))
    }

    /// Decodifica fuori dal thread principale e consegna sul principale. Se è
    /// già in cache, consegna subito e in modo sincrono.
    static func carica(_ url: URL, _ consegna: @escaping @MainActor (NSImage?) -> Void) {
        let k = chiave(url)
        if let subito = cache.object(forKey: k) {
            MainActor.assumeIsolated { consegna(subito) }
            return
        }
        coda.async {
            let immagine = caricaSincrona(url)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { consegna(immagine) }
            }
        }
    }

    /// Cache più decodifica, in modo sincrono: il cuore di `carica`, e la
    /// porta del banco delle miniature, che misura primo accesso (decodifica)
    /// contro secondo (cache) senza dipendere da un runloop.
    nonisolated static func caricaSincrona(_ url: URL) -> NSImage? {
        let k = chiave(url)
        if let pronta = cache.object(forKey: k) { return pronta }
        guard let immagine = decodifica(url) else { return nil }
        cache.setObject(immagine, forKey: k)
        return immagine
    }

    /// La sola decodifica, al lato massimo `lato`.
    nonisolated private static func decodifica(_ url: URL) -> NSImage? {
        guard let sorgente = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opzioni: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: lato,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(sorgente, 0, opzioni as CFDictionary)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// L'anteprima di una scheda: la cache subito se c'è, altrimenti il segnaposto
/// e poi la miniatura appena arriva. Nella sonda (`ImageRenderer`) `onAppear`
/// non scatta: si vede il segnaposto, che è la vista vera del primo istante.
struct MiniaturaView: View {
    let url: URL
    /// L'icona da mostrare finché la miniatura non c'è. `nil` = un simbolo.
    let segnaposto: NSImage?

    @State private var immagine: NSImage?

    var body: some View {
        Group {
            if let immagine {
                Image(nsImage: immagine)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let segnaposto {
                Image(nsImage: segnaposto)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Livrea.sopraGuscio.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { aggiorna() }
        .onChange(of: url) { aggiorna() }
    }

    private func aggiorna() {
        immagine = Miniature.pronta(per: url)
        guard immagine == nil else { return }
        let attesa = url
        Miniature.carica(url) { pronta in
            // La scheda può essere stata riusata per un'altra voce mentre la
            // decodifica correva: una miniatura consegnata al vecchio URL non
            // si applica.
            guard attesa == url else { return }
            immagine = pronta
        }
    }
}
