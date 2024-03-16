//
//  Embeddings.swift
//  simple-sync
//
//  Created by Wayne Carter on 2/24/24.
//

import UIKit
import Vision

struct Embeddings {
    static func featureEmbedding(from image: UIImage?, fitTo fitSize: CGSize? = nil, grayscale: Bool = false, completion: @escaping ([NSNumber]?) -> Void) {
        guard let cgImage = image?.cgImage else {
            completion(nil)
            return
        }
        
        // Run async on the background queue with high priority.
        DispatchQueue.global().async(qos: .userInitiated) {
            featureEmbedding(from: cgImage, fitTo: fitSize, grayscale: grayscale, completion: completion)
        }
    }
        
    private static func featureEmbedding(from cgImage: CGImage, fitTo fitSize: CGSize? = nil, grayscale: Bool = false, completion: @escaping ([NSNumber]?) -> Void) {
        var cgImage = cgImage
        
        // Fit to size if specified.
        if let fitSize = fitSize,
           let fitImage = cgImage.fit(to: fitSize)
        {
            cgImage = fitImage
        }
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest { request, error in
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                completion(nil)
                return
            }

            // Access the feature print data
            let data = observation.data
            guard data.isEmpty == false else {
                completion(nil)
                return
            }

            // Determine the element type and size
            let elementType = observation.elementType
            let elementCount = observation.elementCount
            let typeSize = VNElementTypeSize(elementType)
            var embedding: [NSNumber] = []
            
            // Handle the different element types
            switch elementType {
            case .float where typeSize == MemoryLayout<Float>.size:
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    let buffer = bytes.bindMemory(to: Float.self)
                    if buffer.count == elementCount {
                        embedding = buffer.map { NSNumber(value: $0) }
                    }
                }
            case .double where typeSize == MemoryLayout<Double>.size:
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    let buffer = bytes.bindMemory(to: Double.self)
                    if buffer.count == elementCount {
                        embedding = buffer.map { NSNumber(value: $0) }
                    }
                }
            default:
                print("Unsupported VNElementType: \(elementType)")
                completion(nil)
                return
            }

            completion(embedding)
        }

        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform the request: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    static func foregroundFeatureEmbedding(from image: UIImage?, fitTo fitSize: CGSize? = nil, grayscale: Bool = false, completion: @escaping ([NSNumber]?) -> Void) {
        guard let cgImage = image?.cgImage else {
            completion(nil)
            return
        }
        
        // Run async on the background queue with high priority.
        DispatchQueue.global().async(qos: .userInitiated) {
            foregroundFeatureEmbedding(from: cgImage, fitTo: fitSize, grayscale: grayscale, completion: completion)
        }
    }
    
    private static func foregroundFeatureEmbedding(from cgImage: CGImage, fitTo fitSize: CGSize? = nil, grayscale: Bool = false, completion: @escaping ([NSNumber]?) -> Void) {
        var cgImage = cgImage
        
        // Fit to size if specified.
        if let fitSize = fitSize, let fitImage = cgImage.fit(to: fitSize) {
            cgImage = fitImage
        }
        
        // Fit to size if specified.
        if grayscale, let grayscaleImage = cgImage.grayscale() {
            cgImage = grayscaleImage
        }
        
        // Get the foreground subjects as a masked image.
        let requst = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([requst])
        } catch {
            print("Failed to perform the request: \(error.localizedDescription)")
            completion(nil)
        }
        let foregroundImage: CGImage? = {
            if let result = requst.results?.first {
                let maskedImagePixelBuffer = try! result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: false
                )
                
                let ciContext = CIContext()
                let ciImage = CIImage(cvPixelBuffer: maskedImagePixelBuffer)
                let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
                
                return cgImage
            }
            
            return nil
        }()
        
        if let foregroundImage = foregroundImage {
            featureEmbedding(from: foregroundImage, completion: completion)
        } else {
            featureEmbedding(from: cgImage, completion: completion)
        }
    }
}

private extension CGImage {
    func fit(to targetSize: CGSize) -> CGImage? {
        let imageSize = CGSize(width: self.width, height: self.height)
        
        // Calculate the aspect ratios
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scaleFactor = min(widthRatio, heightRatio) // Use min to fit the content without cropping

        let scaledWidth = imageSize.width * scaleFactor
        let scaledHeight = imageSize.height * scaleFactor
        let offsetX = (targetSize.width - scaledWidth) / 2.0 // Center horizontally
        let offsetY = (targetSize.height - scaledHeight) / 2.0 // Center vertically
        let scaledRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1 // Use a scale factor of 1 for CGImage
        let rendererSize = CGSize(width: targetSize.width, height: targetSize.height)

        let renderer = UIGraphicsImageRenderer(size: rendererSize, format: rendererFormat)
        let fittedImage = renderer.image { _ in
            UIImage(cgImage: self).draw(in: scaledRect)
        }
        
        return fittedImage.cgImage
    }
    
    func grayscale() -> CGImage? {
        guard let currentFilter = CIFilter(name: "CIColorControls") else { return nil }
        let ciImage = CIImage(cgImage: self)
        currentFilter.setValue(ciImage, forKey: kCIInputImageKey)
        currentFilter.setValue(0.0, forKey: kCIInputSaturationKey)

        let context = CIContext(options: nil)
        guard let outputImage = currentFilter.outputImage, let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return cgImage
    }
}
