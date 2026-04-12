//#!/usr/bin/env swift

import Foundation
import Vision
import CoreImage
import AppKit
import CryptoKit

// --- 1. Helper Functions ---

func printUsage() {
    let usage = """
    Usage: ./classify_image [options] <image_path1> <image_path2> ...
    
    Options:
      -c, --confidence <value>   Set minimum confidence threshold (0.0 to 1.0). Default is 0.6.
      -h, --human                Use the dedicated Human Detection API.
      -a, --animal               Use the dedicated Animal Detection API (Cats/Dogs).
      -t, --train <folder>       Extract and save cropped objects to subfolders in this directory.
      -l, --list                 Print list of all possible recognized object categories.
      -v, --version              Print the current Git version of this tool.
      --help                     Show this help message.
    """
    print(usage)
}

func printList() {
    let request = VNClassifyImageRequest()
    do {
        let identifiers = try request.supportedIdentifiers()
        print(identifiers.joined(separator: "\n"))
    } catch {
        print("Error retrieving taxonomy: \(error.localizedDescription)")
    }
}

// Crops the image using Vision's normalized coordinates and saves using SHA256 deduplication
func extractAndSave(cgImage: CGImage, boundingBox: CGRect, category: String, exportPath: String) {
    let imageWidth = CGFloat(cgImage.width)
    let imageHeight = CGFloat(cgImage.height)
    
    // Vision origin is bottom-left; CGImage origin is top-left. We must flip the Y axis.
    let x = boundingBox.origin.x * imageWidth
    let y = (1.0 - boundingBox.origin.y - boundingBox.height) * imageHeight
    let width = boundingBox.width * imageWidth
    let height = boundingBox.height * imageHeight
    
    let cropRect = CGRect(x: x, y: y, width: width, height: height)
    
    guard let croppedCG = cgImage.cropping(to: cropRect) else { return }
    
    // Convert to JPEG
    let bitmap = NSBitmapImageRep(cgImage: croppedCG)
    guard let jpegData = bitmap.representation(using: .jpeg, properties: [:]) else { return }
    
    // Hash for deduplication (creates a unique filename based on the image's pixels)
    let hashString = SHA256.hash(data: jpegData).compactMap { String(format: "%02x", $0) }.joined()
    let fileName = "\(hashString).jpg"
    
    // Create Category Folder
    let categoryURL = URL(fileURLWithPath: exportPath).appendingPathComponent(category)
    do {
        try FileManager.default.createDirectory(at: categoryURL, withIntermediateDirectories: true)
        let fileURL = categoryURL.appendingPathComponent(fileName)
        
        // Only write if it doesn't already exist
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try jpegData.write(to: fileURL)
        }
    } catch {
        print("Error saving crop: \(error.localizedDescription)")
    }
}

// --- 2. The Main Entry Point ---

@main
struct SecurityCameraFilter {
    
    static func main() {
        var confidenceThreshold: Float = 0.6
        var useHumanDetection = false
        var useAnimalDetection = false
        var trainingExportPath: String? = nil
        var imagePaths: [String] = []

        let args = CommandLine.arguments.dropFirst()

        if args.isEmpty { printUsage(); exit(0) }
        
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            switch arg {
            case "--help":
                printUsage(); exit(0)
            case "-v", "--version":
                // This variable is securely injected at compile time by the Makefile
                print("classify_image version \(appVersion)"); exit(0)
            case "-l", "--list":
                printList(); exit(0)
            case "-h", "--human":
                useHumanDetection = true
            case "-a", "--animal":
                useAnimalDetection = true
            case "-c", "--confidence":
                guard let valString = iterator.next(), let val = Float(valString) else {
                    print("Error: Missing confidence value."); exit(1)
                }
                confidenceThreshold = val
            case "-t", "--train":
                guard let pathString = iterator.next() else {
                    print("Error: Missing folder path for --train."); exit(1)
                }
                trainingExportPath = pathString
            default:
                imagePaths.append(arg)
            }
        }

        if imagePaths.isEmpty { printUsage(); exit(0) }

        // --- 3. Image Processing Loop ---

        let resultLock = NSLock()

        for path in imagePaths {
            let fileURL = URL(fileURLWithPath: path)
            
            // We load as CGImage source first so we have the raw pixel data available for cropping
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("\(path) ERROR:Failed_to_load_image")
                continue
            }
            
            let ciImage = CIImage(cgImage: cgImage)
            var outputData: [(name: String, confidence: Float)] = []
            var requestError = false
            var requests: [VNRequest] = []
            
            // 3a. Human Request
            if useHumanDetection {
                let request = VNDetectHumanRectanglesRequest { req, error in
                    if error != nil { resultLock.lock(); requestError = true; resultLock.unlock(); return }
                    guard let observations = req.results as? [VNHumanObservation] else { return }
                    
                    let confident = observations.filter { $0.confidence >= confidenceThreshold }
                    let items = confident.map { ("person", $0.confidence) }
                    
                    // Extract and save crops if training path is set
                    if let exportPath = trainingExportPath {
                        for obs in confident {
                            extractAndSave(cgImage: cgImage, boundingBox: obs.boundingBox, category: "person", exportPath: exportPath)
                        }
                    }
                    
                    resultLock.lock()
                    outputData.append(contentsOf: items)
                    resultLock.unlock()
                }
                requests.append(request)
            }
            
            // 3b. Animal Request
            if useAnimalDetection {
                let request = VNRecognizeAnimalsRequest { req, error in
                    if error != nil { resultLock.lock(); requestError = true; resultLock.unlock(); return }
                    guard let observations = req.results as? [VNRecognizedObjectObservation] else { return }
                    
                    let confident = observations.filter { $0.confidence >= confidenceThreshold }
                    
                    var items: [(String, Float)] = []
                    for obs in confident {
                        if let topLabel = obs.labels.first {
                            let name = topLabel.identifier.lowercased()
                            items.append((name, obs.confidence))
                            
                            // Extract and save crops
                            if let exportPath = trainingExportPath {
                                extractAndSave(cgImage: cgImage, boundingBox: obs.boundingBox, category: name, exportPath: exportPath)
                            }
                        }
                    }
                    
                    resultLock.lock()
                    outputData.append(contentsOf: items)
                    resultLock.unlock()
                }
                requests.append(request)
            }
            
            // 3c. Generic Fallback (Cannot be cropped)
            if !useHumanDetection && !useAnimalDetection {
                let request = VNClassifyImageRequest { req, error in
                    if error != nil { resultLock.lock(); requestError = true; resultLock.unlock(); return }
                    guard let observations = req.results as? [VNClassificationObservation] else { return }
                    
                    let confident = observations.filter { $0.confidence >= confidenceThreshold }
                    let items = confident.map { ($0.identifier, $0.confidence) }
                    
                    resultLock.lock()
                    outputData.append(contentsOf: items)
                    resultLock.unlock()
                }
                requests.append(request)
            }
            
            // 4. Execute
            let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
            do { try handler.perform(requests) } 
            catch { print("\(path) ERROR:Handler_failed"); continue }
            
            // 5. Output
            if requestError {
                print("\(path) ERROR:Vision_request_failed")
            } else if outputData.isEmpty {
                print("\(path) NONE")
            } else {
                let sortedData = outputData.sorted { $0.confidence > $1.confidence }
                let formattedStrings = sortedData.map { String(format: "%@:%.2f", $0.name, $0.confidence) }
                print("\(path) \(formattedStrings.joined(separator: " "))")
            }
        }
    }
}