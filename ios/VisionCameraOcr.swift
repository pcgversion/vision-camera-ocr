import Vision
import AVFoundation
import MLKitVision
import MLKitTextRecognition
import UIKit
import Foundation
import CoreMedia
import CoreVideo
import CoreImage
import ImageIO
import CoreML

// Define the structure for a block (can be expanded based on the actual data you expect)
struct FrameData: Codable{
    let x: Double
    let y: Double
    let boundingCenterX: Double
    let boundingCenterY: Double
    let width: Double
    let height: Double
}
struct Point: Codable{
    let x: Double
    let y: Double
}
struct BlockData: Codable {
    // Add properties as needed
    let cornerPoints:[Point]
    let recognizedLanguages: [String]
    let text:String
    let frame:FrameData
}
struct Block: Codable {
    // Add properties as needed
    let cornerPoints:[Point]
    let recognizedLanguages: [String]
    let text:String
    let frame:FrameData
    let lines:[BlockData]
}

// Define the Result structure
struct ResultData: Codable {
    let blocks: [Block]
    let text: String
}
// Define the root structure that contains the "result"
struct RootObject: Codable {
    var result: ResultData
}
   

@objc(OCRFrameProcessorPlugin)
public class OCRFrameProcessorPlugin: NSObject, FrameProcessorPluginBase {
    

    private static var textRecognizer = TextRecognizer.textRecognizer(options: TextRecognizerOptions.init())
    
    private static func getBlockArray(_ blocks: [TextBlock]) -> [[String: Any]] {
        
        var blockArray: [[String: Any]] = []
        
        for block in blocks {
            blockArray.append([
                "text": block.text,
                "recognizedLanguages": getRecognizedLanguages(block.recognizedLanguages),
                "cornerPoints": getCornerPoints(block.cornerPoints),
                "frame": getFrame(block.frame),
                "lines": getLineArray(block.lines),
            ])
        }
        
        return blockArray
    }
    
    private static func getLineArray(_ lines: [TextLine]) -> [[String: Any]] {
        
        var lineArray: [[String: Any]] = []
        
        for line in lines {
            lineArray.append([
                "text": line.text,
                "recognizedLanguages": getRecognizedLanguages(line.recognizedLanguages),
                "cornerPoints": getCornerPoints(line.cornerPoints),
                "frame": getFrame(line.frame),
                "elements": getElementArray(line.elements),
            ])
        }
        
        return lineArray
    }
    
    private static func getElementArray(_ elements: [TextElement]) -> [[String: Any]] {
        
        var elementArray: [[String: Any]] = []
        
        for element in elements {
            elementArray.append([
                "text": element.text,
                "cornerPoints": getCornerPoints(element.cornerPoints),
                "frame": getFrame(element.frame),
            ])
        }
        
        return elementArray
    }
    
    private static func getRecognizedLanguages(_ languages: [TextRecognizedLanguage]) -> [String] {
        
        var languageArray: [String] = []
        
        for language in languages {
            guard let code = language.languageCode else {
                print("No language code exists")
                break;
            }
            languageArray.append(code)
        }
        
        return languageArray
    }
    
    private static func getCornerPoints(_ cornerPoints: [NSValue]) -> [[String: CGFloat]] {
        
        var cornerPointArray: [[String: CGFloat]] = []
        
        for cornerPoint in cornerPoints {
            guard let point = cornerPoint as? CGPoint else {
                print("Failed to convert corner point to CGPoint")
                break;
            }
            cornerPointArray.append([ "x": point.x, "y": point.y])
        }
        
        return cornerPointArray
    }
    
    private static func getFrame(_ frameRect: CGRect) -> [String: CGFloat] {
        
        let offsetX = (frameRect.midX - ceil(frameRect.width)) / 2.0
        let offsetY = (frameRect.midY - ceil(frameRect.height)) / 2.0

        let x = frameRect.maxX + offsetX
        let y = frameRect.minY + offsetY

        return [
          "x": frameRect.midX + (frameRect.midX - x),
          "y": frameRect.midY + (y - frameRect.midY),
          "width": frameRect.width,
          "height": frameRect.height,
          "boundingCenterX": frameRect.midX,
          "boundingCenterY": frameRect.midY
        ]
    }
    
    @objc
    public static func callback(_ frame: Frame!, withArgs _: [Any]!) -> Any! {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(frame.buffer) else {
          print("Failed to get image buffer from sample buffer.")
          return nil
        }

        var ciImage = CIImage(cvPixelBuffer: imageBuffer)
        var curDeviceOrientation = UIDevice.current.orientation
        let isLandscape = isDeviceInLandscapeWhenFaceUp()
        //print("current Device Orientation: \(curDeviceOrientation) \(isLandscape)")
        switch curDeviceOrientation {
            case UIDeviceOrientation.portraitUpsideDown:  // Device oriented vertically, Home button on the top
                ciImage = ciImage.oriented(forExifOrientation: 3)
            case UIDeviceOrientation.landscapeLeft:       // Device oriented horizontally, Home button on the right
                ciImage = ciImage.oriented(forExifOrientation: 3)
            case UIDeviceOrientation.landscapeRight:      // Device oriented horizontally, Home button on the left
                ciImage = ciImage.oriented(forExifOrientation: 3)
            case UIDeviceOrientation.portrait:            // Device oriented vertically, Home button on the bottom
                ciImage = ciImage.oriented(forExifOrientation: 1)
            case UIDeviceOrientation.faceUp:
            ciImage = ciImage.oriented(forExifOrientation: isLandscape ? 3 : 1)
            case UIDeviceOrientation.faceDown:
                ciImage = ciImage.oriented(forExifOrientation: isLandscape ? 3 : 1)
            case UIDeviceOrientation.unknown:
                ciImage = ciImage.oriented(forExifOrientation: 1)
            default:
                ciImage = ciImage.oriented(forExifOrientation: 1)
        }
        guard let cgImage = CIContext().createCGImage(ciImage, from: ciImage.extent) else {
            print("Failed to create bitmap from image.")
            return nil
        }
       
        let image = UIImage(cgImage: cgImage)
       
        var visionResultData:Any? = []
        recognizeTextInImage(image){results in if let results = results {
            visionResultData = results
            } else {
            print("No results found.")
            }
        }
       
        /*** Google MLKit Vision Code ***/
        //let visionImage = VisionImage(image: image)
        //let visionImage = MLImage(image: mlImage)
        //visionImage.orientation = image.imageOrientation
       
        // if let pngData = image.pngData() {
        //     // Define file path where you want to save the image
        //     let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        //     let fileURL = documentsDirectory.appendingPathComponent("image.png")
            
        //     do {
        //         // Write PNG data to file
        //         try pngData.write(to: fileURL)
        //         print("Image saved successfully at \(fileURL)")
        //     } catch {
        //         print("Error saving image: \(error)")
        //     }
        // } else {
        //     print("Failed to convert UIImage to PNG data")
        // }
        // print("FrameData: \(image.size.width)x\(image.size.height)")
   
        
        //    var result: Text
        //    do {
        //      result = try textRecognizer.results(in: visionImage)
        //      print("ocr text result: \(result.text)")
        //    } catch let error {
        //      print("Failed to recognize text with error: \(error.localizedDescription).")
        //      return nil
        //    }
        //     textRecognizer.process(visionImage) { result, error in
        //         guard error == nil, let result = result else {
        //             // Handle error
        //             print("Text recognition failed: \(String(describing: error))")
        //             return
        //         }
        //         print("result data...\(result.text), \(result.blocks)")
        //     }
        //     return [
        //        "result": [
        //            "text": result.text,
        //            "blocks":getBlockArray(result.blocks),
        //        ]
        //     ]

        /*** End of Google MLKit Vision Code ***/

        return visionResultData
    }
   
  
}

    // MARK: - Text Recognition
    func recognizeTextInImage(_ image: UIImage, completion: @escaping (Any?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        // Create a request for text recognition
        let request = VNRecognizeTextRequest { (request, error) in
            if let error = error {
                print("Error recognizing text: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
               completion(nil)
               return
           }
                   
            var resultData = handleTextRecognitionResults(results: request.results, image: image)!
            completion(resultData)
        }
        
        // Specify recognition level (accurate or fast)
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en"] // Optional: Specify languages
        
        // Create a request handler for the image
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        // Perform the request
        DispatchQueue.global(qos: .userInitiated).sync {
            do {
                try requestHandler.perform([request])
            } catch {
                print("Error performing text recognition request: \(error)")
            }
        }
        
    }
    
    // Handle the text recognition results
    func handleTextRecognitionResults(results: [Any]?, image: UIImage) -> Any! {
        guard let observations = results as? [VNRecognizedTextObservation] else { return nil }
        var stringBlocks:[String] = []
        var textBlocks:[Any] = []
        var finalBlocks:[Any] = []
        for observation in observations {
            guard let topCandidate = observation.topCandidates(1).first else { continue }
            //print("Recognized text: \(topCandidate.string)")
            
            stringBlocks.append(topCandidate.string)
            // You can also get the bounding box of the recognized text
            
            let imageSize = CGSize(width: image.size.width, height: image.size.height) // Actual size of the image
            //convert the text recoginition data to real pixels data to map on image
            let data = convert(observation.boundingBox, to: CGRect(origin: .zero, size: imageSize))
            
            var textBlock: [String: Any] = [:]
            //print("data: \(data) \(data["x"])")
            var height = data["height"] as! CGFloat
            var width = data["width"] as! CGFloat
            var top = data["y"] as! CGFloat
            var left = data["x"] as! CGFloat
            var right = left+width
            var bottom = top+height

            textBlock["text"] = topCandidate.string
            textBlock["recognizedLanguages"] = [""] //need to keep empty for now
            
            textBlock["cornerPoints"] = [
                ["x":left, "y":top],
                ["x":right, "y":top],
                ["x":right, "y":bottom],
                ["x":left, "y":bottom]
            ]
            var frameWidth = width
            var frameHeight = height
            var frameBoundingCenterX = frameWidth/2 + left
            var frameBoundingCenterY = frameHeight/2 + top
            var frameX = frameBoundingCenterX/2
            var frameY = (frameBoundingCenterY/2) - (frameHeight/2) + top
            textBlock["frame"] = [
                "x": frameX,
                "y": frameY,
                "width": frameWidth,
                "height": frameHeight,
                "boundingCenterX": frameBoundingCenterX,
                "boundingCenterY": frameBoundingCenterY
            ]
            var lineObject: [String: Any] = [:]
            lineObject["text"] = textBlock["text"]
            lineObject["frame"] = textBlock["frame"]
            lineObject["cornerPoints"] = textBlock["cornerPoints"]
            lineObject["frame"] = textBlock["frame"]

            textBlock["lines"] = [lineObject]
            textBlocks.append(textBlock);

            let frameObject = FrameData(x: frameX, y: frameY, boundingCenterX: frameBoundingCenterX, boundingCenterY: frameBoundingCenterY, width: frameWidth, height: frameHeight)
            let textObject = topCandidate.string
            let cornerPoints = [Point(x:left, y: top), Point(x:right, y:top), Point(x:right, y:bottom), Point(x:left, y:bottom)]
            let recognizedLanguages = ""


            let blockData = BlockData(cornerPoints:cornerPoints, recognizedLanguages:[recognizedLanguages], text: textObject, frame: frameObject)
            let block = Block(cornerPoints:cornerPoints, recognizedLanguages:[recognizedLanguages],  text: textObject, frame: frameObject, lines:[blockData])
            
        }
       
        textBlocks.append(["text":stringBlocks.joined(separator: "\n")])
        return [
            "result": [
                "text": stringBlocks.joined(separator: "\n"),
                "blocks":textBlocks,
            ]
        ]
        
    }

/// - Returns: The bounding box in pixel coordinates, flipped vertically so 0,0 is in the upper left corner
func convert(_ boundingBox: CGRect, to bounds: CGRect) -> [String: Any] {
    let imageWidth = bounds.width
    let imageHeight = bounds.height

    // Begin with input rect.
    var rect = boundingBox

    // Reposition origin.
    rect.origin.x *= imageWidth
    rect.origin.x += bounds.minX
    rect.origin.y = (1 - rect.maxY) * imageHeight + bounds.minY

    // Rescale normalized coordinates.
    rect.size.width *= imageWidth
    rect.size.height *= imageHeight

    let data: [String: CGFloat] = ["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height]
    return data
}

func isDeviceInLandscapeWhenFaceUp() -> Bool {
    let orientation = UIDevice.current.orientation
    
    // If the device is face up, check the interface orientation
    if orientation == .faceUp {
        // Get the current interface orientation
        let interfaceOrientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation
        
        if let interfaceOrientation = interfaceOrientation {
            return interfaceOrientation.isLandscape
        }
    }
    
    // Otherwise, check if the current device orientation is landscape
    return orientation == .landscapeLeft || orientation == .landscapeRight
}
