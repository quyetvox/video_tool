import Foundation
import AVFoundation
import Vision
import CoreGraphics
import CoreMedia
import CoreImage

struct SubtitleSegment: Codable {
    let start: Double
    var end: Double
    var text: String
    var bbox: [Double]
}

func parseCommandLine() -> [String: String] {
    var args = [String: String]()
    let arguments = CommandLine.arguments
    var i = 1
    while i < arguments.count {
        let arg = arguments[i]
        if arg.hasPrefix("--") && i + 1 < arguments.count {
            let key = String(arg.dropFirst(2))
            let val = arguments[i + 1]
            args[key] = val
            i += 2
        } else {
            i += 1
        }
    }
    return args
}

func computeLuminanceDiff(img1: CGImage, img2: CGImage) -> Double {
    let w = min(img1.width, img2.width)
    let h = min(img1.height, img2.height)
    if w <= 0 || h <= 0 { return 999.0 }
    
    let sampleW = 32
    let sampleH = 16
    let bytesPerRow = sampleW
    
    var buf1 = [UInt8](repeating: 0, count: sampleW * sampleH)
    var buf2 = [UInt8](repeating: 0, count: sampleW * sampleH)
    
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let ctx1 = CGContext(data: &buf1, width: sampleW, height: sampleH, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue),
          let ctx2 = CGContext(data: &buf2, width: sampleW, height: sampleH, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
        return 999.0
    }
    
    ctx1.draw(img1, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
    ctx2.draw(img2, in: CGRect(x: 0, y: 0, width: sampleW, height: sampleH))
    
    var diffSum: Double = 0.0
    let count = sampleW * sampleH
    for k in 0..<count {
        let diff = abs(Int(buf1[k]) - Int(buf2[k]))
        diffSum += Double(diff)
    }
    return diffSum / Double(count)
}

func performVisionOCR(cgImage: CGImage, region: [Double]) -> (String, [Double])? {
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en", "vi"]
    
    do {
        try requestHandler.perform([request])
        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            return nil
        }
        
        var recognizedLines = [String]()
        let maxBox = [region[0], region[1], region[2], region[3]]
        
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let str = candidate.string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !str.isEmpty {
                recognizedLines.append(str)
            }
        }
        
        if recognizedLines.isEmpty {
            return nil
        }
        
        let fullText = recognizedLines.joined(separator: " ")
        return (fullText, maxBox)
    } catch {
        return nil
    }
}

func main() {
    let args = parseCommandLine()
    guard let videoPath = args["video"],
          let outputPath = args["output"] else {
        fputs("Usage: sub_video_vision_ocr --video <path> --output <path> [--region ymin,xmin,ymax,xmax] [--diff-threshold 8.0] [--fps 2.0]\n", stderr)
        exit(1)
    }
    
    var region: [Double] = [0.10, 0.0, 0.95, 1.0]
    if let regStr = args["region"] {
        let parts = regStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: CharacterSet.whitespaces)) }
        if parts.count == 4 {
            region = parts
        }
    }
    
    let diffThreshold = Double(args["diff-threshold"] ?? "8.0") ?? 8.0
    let sampleFps = Double(args["fps"] ?? "2.0") ?? 2.0
    
    let videoURL = URL(fileURLWithPath: videoPath)
    let asset = AVURLAsset(url: videoURL)
    
    guard let track = asset.tracks(withMediaType: .video).first else {
        fputs("Error: No video track found in \(videoPath)\n", stderr)
        exit(1)
    }
    
    let trackSize = track.naturalSize.applying(track.preferredTransform)
    let videoWidth = abs(trackSize.width)
    let videoHeight = abs(trackSize.height)
    
    guard let reader = try? AVAssetReader(asset: asset) else {
        fputs("Error: Failed to initialize AVAssetReader\n", stderr)
        exit(1)
    }
    
    let outputSettings: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(trackOutput)
    reader.startReading()
    
    let ymin = region[0]
    let xmin = region[1]
    let ymax = region[2]
    let xmax = region[3]
    
    let cropRect = CGRect(
        x: xmin * Double(videoWidth),
        y: ymin * Double(videoHeight),
        width: (xmax - xmin) * Double(videoWidth),
        height: (ymax - ymin) * Double(videoHeight)
    )
    
    var segments = [SubtitleSegment]()
    var lastImage: CGImage? = nil
    var currentSegment: SubtitleSegment? = nil
    var lastSampleTime: Double = -1.0
    let sampleInterval = 1.0 / sampleFps
    let ciContext = CIContext()
    
    while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
        let pts = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
        let timeSec = CMTimeGetSeconds(pts)
        
        if lastSampleTime >= 0 && (timeSec - lastSampleTime) < sampleInterval {
            continue
        }
        lastSampleTime = timeSec
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // CIImage coordinate origin is bottom-left, flip to crop correctly
        let ciCropRect = CGRect(
            x: cropRect.origin.x,
            y: Double(videoHeight) - cropRect.origin.y - cropRect.height,
            width: cropRect.width,
            height: cropRect.height
        )
        
        let croppedCI = ciImage.cropped(to: ciCropRect)
        guard let cgImage = ciContext.createCGImage(croppedCI, from: croppedCI.extent) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
            continue
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        
        var isDiff = true
        if let prevImg = lastImage {
            let diff = computeLuminanceDiff(img1: prevImg, img2: cgImage)
            if diff < diffThreshold {
                isDiff = false
            }
        }
        lastImage = cgImage
        
        if isDiff {
            if let (detectedText, bbox) = performVisionOCR(cgImage: cgImage, region: region) {
                let cleanText = detectedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !cleanText.isEmpty {
                    if var cur = currentSegment {
                        if cur.text == cleanText {
                            cur.end = max(cur.end, timeSec + 0.5)
                            currentSegment = cur
                        } else {
                            segments.append(cur)
                            currentSegment = SubtitleSegment(
                                start: round(timeSec * 100) / 100,
                                end: round((timeSec + 1.0) * 100) / 100,
                                text: cleanText,
                                bbox: bbox
                            )
                        }
                    } else {
                        currentSegment = SubtitleSegment(
                            start: round(timeSec * 100) / 100,
                            end: round((timeSec + 1.0) * 100) / 100,
                            text: cleanText,
                            bbox: bbox
                        )
                    }
                } else if let cur = currentSegment {
                    segments.append(cur)
                    currentSegment = nil
                }
            } else if let cur = currentSegment {
                segments.append(cur)
                currentSegment = nil
            }
        } else {
            // Frame is same as previous, extend time
            if var cur = currentSegment {
                cur.end = max(cur.end, round((timeSec + 0.5) * 100) / 100)
                currentSegment = cur
            }
        }
    }
    
    if let cur = currentSegment {
        segments.append(cur)
    }
    
    // Write out JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    if let data = try? encoder.encode(segments) {
        let outURL = URL(fileURLWithPath: outputPath)
        try? data.write(to: outURL)
        print("[Native Apple Vision OCR] Success: Extracted \(segments.count) segments -> \(outputPath)")
    } else {
        fputs("Error: Failed to serialize segments to JSON\n", stderr)
        exit(1)
    }
}

main()
