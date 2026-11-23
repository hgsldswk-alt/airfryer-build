import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum ShareQR {
    static let placeholder = URL(string: "https://hgsldswk-alt.github.io/airfryer-support/")!

    static func downloadURL(storeID: String?) -> URL {
        guard let storeID, !storeID.isEmpty, storeID.allSatisfy(\.isASCII), storeID.allSatisfy(\.isNumber),
              let url = URL(string: "https://apps.apple.com/app/id" + storeID) else { return placeholder }
        return url
    }

    static func image(for url: URL, scale: CGFloat = 8) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let bounds = code.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds)
        let padded = code.composited(over: white).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let rendered = CIContext().createCGImage(padded, from: padded.extent) else { return nil }
        return UIImage(cgImage: rendered)
    }
}
