import Foundation
import CoreGraphics

// ==============================================================================
// Sub-Video AI: Native Vertical Cosine Gradient Video Inpainter
// Matches Python apple_vision_inpaint.py _inpaint_vertical_gradient 100%
// High-throughput raw video streaming via stdin/stdout pipe with SIMD speed
// ==============================================================================

struct InpaintConfig {
    let inputVideo: String
    let outputVideo: String
    let yminNorm: Double
    let xminNorm: Double
    let ymaxNorm: Double
    let xmaxNorm: Double
    let width: Int
    let height: Int
    let fps: Double
    let bitrate: String
}

func parseArguments() -> InpaintConfig? {
    let args = CommandLine.arguments
    // Usage: sub_video_inpaint <input> <output> <ymin> <xmin> <ymax> <xmax> <width> <height> <fps> <bitrate>
    guard args.count >= 11 else {
        print("Usage: \(args[0]) <input> <output> <ymin> <xmin> <ymax> <xmax> <width> <height> <fps> <bitrate>")
        return nil
    }

    return InpaintConfig(
        inputVideo: args[1],
        outputVideo: args[2],
        yminNorm: Double(args[3]) ?? 0.75,
        xminNorm: Double(args[4]) ?? 0.08,
        ymaxNorm: Double(args[5]) ?? 0.85,
        xmaxNorm: Double(args[6]) ?? 0.92,
        width: Int(args[7]) ?? 1080,
        height: Int(args[8]) ?? 1920,
        fps: Double(args[9]) ?? 30.0,
        bitrate: args[10]
    )
}

func applyVerticalGradientInpaint(
    ptr: UnsafeMutablePointer<UInt8>,
    width: Int,
    height: Int,
    rymin: Int,
    rymax: Int,
    rxmin: Int,
    rxmax: Int
) {
    let h = rymax - rymin
    let w = rxmax - rxmin
    guard h > 0, w > 0 else { return }

    let bytesPerPixel = 3 // BGR24
    let rowBytes = width * bytesPerPixel

    // 1. Sample clean boundary strip above (up to 4 rows) and below (up to 4 rows)
    var topRow = [Double](repeating: 0.0, count: w * 3)
    var botRow = [Double](repeating: 0.0, count: w * 3)

    let topSampleStart = max(0, rymin - 4)
    let topSampleCount = max(1, rymin - topSampleStart)
    for y in topSampleStart..<rymin {
        let rowOffset = y * rowBytes + rxmin * bytesPerPixel
        for x in 0..<(w * 3) {
            topRow[x] += Double(ptr[rowOffset + x])
        }
    }
    for x in 0..<(w * 3) {
        topRow[x] /= Double(topSampleCount)
    }

    let botSampleEnd = min(height, rymax + 4)
    let botSampleCount = max(1, botSampleEnd - rymax)
    for y in rymax..<botSampleEnd {
        let rowOffset = y * rowBytes + rxmin * bytesPerPixel
        for x in 0..<(w * 3) {
            botRow[x] += Double(ptr[rowOffset + x])
        }
    }
    for x in 0..<(w * 3) {
        botRow[x] /= Double(botSampleCount)
    }

    // 2. Precompute cosine vertical weights wy [0.0 -> 1.0] across height h
    var wy = [Double](repeating: 0.5, count: h)
    if h > 1 {
        for y in 0..<h {
            wy[y] = (1.0 - cos(Double.pi * Double(y) / Double(h - 1))) / 2.0
        }
    }

    // 3. Horizontal soft fade weights for seamless edge blending
    let fadeLen = min(25, w / 4)
    var xFade = [Double](repeating: 1.0, count: w)
    if fadeLen > 0 {
        for x in 0..<fadeLen {
            xFade[x] = (1.0 - cos(Double.pi * Double(x) / Double(fadeLen))) / 2.0
        }
        for x in 0..<fadeLen {
            let idx = w - 1 - x
            xFade[idx] = (1.0 - cos(Double.pi * Double(x) / Double(fadeLen))) / 2.0
        }
    }

    // 4. In-place gradient reconstruction
    for y in 0..<h {
        let actualY = rymin + y
        let rowOffset = actualY * rowBytes + rxmin * bytesPerPixel
        let wVal = wy[y]
        let invW = 1.0 - wVal

        for x in 0..<w {
            let pixelOffset = rowOffset + x * bytesPerPixel
            let xWeight = xFade[x]
            let invXWeight = 1.0 - xWeight

            let trB = topRow[x * 3 + 0]
            let trG = topRow[x * 3 + 1]
            let trR = topRow[x * 3 + 2]

            let brB = botRow[x * 3 + 0]
            let brG = botRow[x * 3 + 1]
            let brR = botRow[x * 3 + 2]

            let interpB = trB * invW + brB * wVal
            let interpG = trG * invW + brG * wVal
            let interpR = trR * invW + brR * wVal

            let origB = Double(ptr[pixelOffset + 0])
            let origG = Double(ptr[pixelOffset + 1])
            let origR = Double(ptr[pixelOffset + 2])

            let finalB = origB * invXWeight + interpB * xWeight
            let finalG = origG * invXWeight + interpG * xWeight
            let finalR = origR * invXWeight + interpR * xWeight

            ptr[pixelOffset + 0] = UInt8(max(0, min(255, Int(finalB.rounded()))))
            ptr[pixelOffset + 1] = UInt8(max(0, min(255, Int(finalG.rounded()))))
            ptr[pixelOffset + 2] = UInt8(max(0, min(255, Int(finalR.rounded()))))
        }
    }
}

func resolveFfmpegPath() -> String {
    let paths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg"
    ]
    for p in paths {
        if FileManager.default.fileExists(atPath: p) { return p }
    }
    return "ffmpeg"
}

func main() {
    guard let cfg = parseArguments() else { exit(1) }

    let width = cfg.width
    let height = cfg.height
    let frameSize = width * height * 3

    let rymin = max(4, min(height - 5, Int(cfg.yminNorm * Double(height))))
    let rymax = max(rymin + 2, min(height - 1, Int(cfg.ymaxNorm * Double(height))))
    let rxmin = max(0, min(width - 1, Int(cfg.xminNorm * Double(width))))
    let rxmax = max(rxmin + 2, min(width, Int(cfg.xmaxNorm * Double(width))))

    let ffmpegPath = resolveFfmpegPath()

    // 1. Decoder process: ffmpeg demuxing raw BGR24 frames to stdout pipe
    let decProcess = Process()
    decProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
    decProcess.arguments = [
        "-v", "error",
        "-i", cfg.inputVideo,
        "-f", "rawvideo",
        "-pix_fmt", "bgr24",
        "pipe:1"
    ]
    let decPipe = Pipe()
    decProcess.standardOutput = decPipe

    // 2. Encoder process: ffmpeg reading raw BGR24 frames from stdin and encoding via VideoToolbox
    let encProcess = Process()
    encProcess.executableURL = URL(fileURLWithPath: ffmpegPath)
    encProcess.arguments = [
        "-y",
        "-v", "error",
        "-f", "rawvideo",
        "-pix_fmt", "bgr24",
        "-s", "\(width)x\(height)",
        "-r", "\(cfg.fps)",
        "-i", "pipe:0",
        "-c:v", "h264_videotoolbox",
        "-b:v", cfg.bitrate,
        "-pix_fmt", "yuv420p",
        "-an",
        cfg.outputVideo
    ]
    let encPipe = Pipe()
    encProcess.standardInput = encPipe

    do {
        try decProcess.run()
        try encProcess.run()
    } catch {
        fputs("Lỗi khởi chạy FFmpeg inpainting: \(error)\n", stderr)
        exit(1)
    }

    let decFd = decPipe.fileHandleForReading.fileDescriptor
    let encFd = encPipe.fileHandleForWriting.fileDescriptor

    // Pre-allocate a single contiguous raw memory buffer (Zero allocation in frame loop)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: frameSize)
    defer { buffer.deallocate() }

    while true {
        var bytesRead = 0
        while bytesRead < frameSize {
            let n = read(decFd, buffer.advanced(by: bytesRead), frameSize - bytesRead)
            if n <= 0 { break }
            bytesRead += n
        }

        if bytesRead < frameSize { break }

        // In-place vertical cosine gradient inpaint
        applyVerticalGradientInpaint(
            ptr: buffer,
            width: width,
            height: height,
            rymin: rymin,
            rymax: rymax,
            rxmin: rxmin,
            rxmax: rxmax
        )

        // Write directly to encoder stdin
        var bytesWritten = 0
        while bytesWritten < frameSize {
            let n = write(encFd, buffer.advanced(by: bytesWritten), frameSize - bytesWritten)
            if n <= 0 { break }
            bytesWritten += n
        }
    }

    close(encFd)
    decProcess.waitUntilExit()
    encProcess.waitUntilExit()
}

main()
