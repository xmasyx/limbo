import AppKit
import CoreText
import UniformTypeIdentifiers

/// Da documento a PDF, senza aprire niente.
///
/// Nasce dalla sua richiesta del 19/08: «un docx in pdf è comodo, adesso devo
/// aprire il doc, fare command+p, salva pdf». Qui lo trascini e basta.
///
/// **Come, e il limite dichiarato.** `NSAttributedString` sa leggere i formati
/// di Word e compagni (è la stessa macchina che usa TextEdit), e CoreText li
/// impagina su un PDF. Il testo, i corsivi, i grassetti, gli elenchi e le
/// immagini in linea passano; un impaginato complicato — colonne, caselle di
/// testo ancorate, intestazioni ripetute — no. Per quello il «Salva come PDF»
/// di Word resta migliore, e va detto invece che scoperto.
enum Documenti {
    /// I formati che sappiamo leggere, con il tipo che dice a
    /// `NSAttributedString` come interpretarli.
    static let tipi: [String: NSAttributedString.DocumentType] = [
        "docx": .officeOpenXML,
        "doc": .docFormat,
        "odt": .openDocument,
        "rtf": .rtf,
        "rtfd": .rtfd,
        "html": .html,
        "htm": .html,
        "txt": .plain,
        "md": .plain,
    ]

    static func sappiamoLeggerlo(_ url: URL) -> Bool {
        tipi[url.pathExtension.lowercased()] != nil
    }

    /// A4 con margini di due centimetri: la misura che esce da una stampante
    /// europea, non la Letter americana.
    private static let pagina = CGRect(x: 0, y: 0, width: 595, height: 842)
    private static let margine: CGFloat = 56

    nonisolated static func pdf(da origine: URL, in uscita: URL) -> URL? {
        guard let tipo = tipi[origine.pathExtension.lowercased()] else { return nil }
        guard let testo = try? NSAttributedString(
            url: origine,
            options: [.documentType: tipo],
            documentAttributes: nil), testo.length > 0 else {
            registro.error("documento illeggibile: \(origine.lastPathComponent, privacy: .public)")
            return nil
        }
        try? FileManager.default.createDirectory(
            at: uscita.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let consumatore = CGDataConsumer(url: uscita as CFURL) else { return nil }
        var misura = pagina
        guard let contesto = CGContext(consumer: consumatore, mediaBox: &misura, nil) else { return nil }

        let impaginatore = CTFramesetterCreateWithAttributedString(testo)
        let cornice = CGPath(rect: pagina.insetBy(dx: margine, dy: margine), transform: nil)
        var da = 0
        // Il tetto sulle pagine è una cintura, non un limite di prodotto: se
        // l'impaginatore smettesse di avanzare, un `while` senza fondo
        // scriverebbe un PDF infinito invece di fallire.
        var pagine = 0
        while da < testo.length && pagine < 2000 {
            contesto.beginPDFPage(nil)
            let riquadro = CTFramesetterCreateFrame(
                impaginatore, CFRange(location: da, length: 0), cornice, nil)
            CTFrameDraw(riquadro, contesto)
            contesto.endPDFPage()
            let scritto = CTFrameGetVisibleStringRange(riquadro)
            guard scritto.length > 0 else { break }   // non avanza: si esce
            da += scritto.length
            pagine += 1
        }
        contesto.closePDF()
        guard pagine > 0 else { return nil }
        registro.info("PDF scritto in \(pagine, privacy: .public) pagine")
        return uscita
    }
}
