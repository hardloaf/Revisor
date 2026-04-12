//#!/usr/bin/env swift

import Foundation
import Vision
import CoreImage
import ImageIO
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
    
    // File extensions considered images when recursing directories.
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "bmp", "heic", "heif", "webp"]
    
    // Entry point: parse arguments, expand directories, process images, and set exit code.
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
                // injected at build time by the Makefile
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
        
        // Expand directories (deep recursion). Non-directory entries and non-existent paths are preserved
        // so that the loader will produce clear error messages.
        imagePaths = collectImagePaths(from: imagePaths)
        
        if imagePaths.isEmpty { printUsage(); exit(0) }
        
        let resultLock = NSLock()
        var foundAnyMatches = false
        
        // Process each image and record whether any matched the requested detectors.
        for path in imagePaths {
            let matched = processImage(atPath: path,
                                       confidenceThreshold: confidenceThreshold,
                                       useHumanDetection: useHumanDetection,
                                       useAnimalDetection: useAnimalDetection,
                                       trainingExportPath: trainingExportPath,
                                       resultLock: resultLock)
            if matched { foundAnyMatches = true }
        }
        
        // Exit 0 if any image contained a matching detection; otherwise exit 1.
        exit(foundAnyMatches ? 0 : 1)
    }
    
    // Recursively collect image files from directory inputs. Returns file paths.
    static func collectImagePaths(from inputs: [String]) -> [String] {
        let fm = FileManager.default
        var results: [String] = []
        
        for inputPath in inputs {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: inputPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    let dirURL = URL(fileURLWithPath: inputPath)
                    if let enumerator = fm.enumerator(at: dirURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles], errorHandler: nil) {
                        for case let fileURL as URL in enumerator {
                            do {
                                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                                if resourceValues.isRegularFile == true {
                                    let ext = fileURL.pathExtension.lowercased()
                                    if allowedExtensions.contains(ext) {
                                        results.append(fileURL.path)
                                    }
                                }
                            } catch {
                                // Skip files that fail to report properties.
                                continue
                            }
                        }
                    }
                } else {
                    // Regular file: keep for processing (the loader will report format/load errors).
                    results.append(inputPath)
                }
            } else {
                // Path does not exist: keep it so the main loop prints a clear error.
                results.append(inputPath)
            }
        }
        
        return results
    }
    
    // Process a single image path. Returns true if any detection exceeded the threshold.
    static func processImage(atPath path: String,
                             confidenceThreshold: Float,
                             useHumanDetection: Bool,
                             useAnimalDetection: Bool,
                             trainingExportPath: String?,
                             resultLock: NSLock) -> Bool
    {
        let fileURL = URL(fileURLWithPath: path)
        
        // Load CGImage (raw pixels) so detected bounding boxes can be cropped and saved.
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("\(path) ERROR:Failed_to_load_image")
            return false
        }
        
        let ciImage = CIImage(cgImage: cgImage)
        var outputData: [(name: String, confidence: Float)] = []
        var requestError = false
        var requests: [VNRequest] = []
        
        // Human detection: provides bounding boxes that can be cropped.
        if useHumanDetection {
            let request = VNDetectHumanRectanglesRequest { req, error in
                if error != nil { resultLock.lock(); requestError = true; resultLock.unlock(); return }
                guard let observations = req.results as? [VNHumanObservation] else { return }
                
                let confident = observations.filter { $0.confidence >= confidenceThreshold }
                let items = confident.map { ("person", $0.confidence) }
                
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
        
        // Animal detection: labeled regions (cats/dogs etc.) that can be cropped.
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
        
        // Generic classification (no crops) when no specialized detectors requested.
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
        
        // Execute Vision requests; completion handlers above populate outputData.
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            print("\(path) ERROR:Handler_failed")
            return false
        }
        
        // Print results in the same format as before and return whether any matches were found.
        if requestError {
            print("\(path) ERROR:Vision_request_failed")
            return false
        } else if outputData.isEmpty {
            print("\(path) NONE")
            return false
        } else {
            let sortedData = outputData.sorted { $0.confidence > $1.confidence }
            let formattedStrings = sortedData.map { String(format: "%@:%.2f", $0.name, $0.confidence) }
            print("\(path) \(formattedStrings.joined(separator: " "))")
            return true
        }
    }
}
