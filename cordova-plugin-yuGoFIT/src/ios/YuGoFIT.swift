
import AVFoundation
import CoreVideo
import MLKit

@objc(YuGoFIT) class YuGoFIT : CDVPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var cameraView: UIView!
    
    private var callbackid:String? = nil;
    
    private var currentDetector: Detector = .poseFast
    private var isUsingFrontCamera = true
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private lazy var captureSession = AVCaptureSession()
    private var videoConnection: AVCaptureConnection!
    private lazy var sessionQueue = DispatchQueue(label: "com.google.mlkit.visiondetector.SessionQueue")
    private var lastFrame: CMSampleBuffer?
    
    private var poseDetectorQueue = DispatchQueue(label: "com.google.mlkit.pose")
    
    /// The detector used for detecting poses. The pose detector's lifecycle is managed manually, so
    /// it is initialized on-demand via the getter override and set to `nil` when a new detector is
    /// chosen.
    private var _poseDetector: PoseDetector? = nil
    private var poseDetector: PoseDetector? {
        get {
            var detector: PoseDetector? = nil
            poseDetectorQueue.sync {
                if _poseDetector == nil {
                    let options = PoseDetectorOptions()
                    options.detectorMode = .stream
                    _poseDetector = PoseDetector.poseDetector(options: options)
                }
                detector = _poseDetector
            }
            return detector
        }
        set(newDetector) {
            poseDetectorQueue.sync {
                _poseDetector = newDetector
            }
        }
    }
    
    @objc(stop:)
    func stop(command: CDVInvokedUrlCommand) {
        stopSession()
        
        let pluginResult = CDVPluginResult(
        status: CDVCommandStatus_OK,
        messageAs: "{action: \"stop\"}"
        )
        pluginResult?.setKeepCallbackAs(true)
        self.commandDelegate!.send(
          pluginResult,
            callbackId: command.callbackId
        )
        
    }
    
    @objc(play:)
    func play(command: CDVInvokedUrlCommand) {
        
        callbackid = command.callbackId
        poseDetectorQueue = DispatchQueue(label: "com.google.mlkit.pose")

        cameraView = UIView(frame: UIScreen.main.bounds)
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        setUpCaptureSessionOutput()
        setUpCaptureSessionInput()
        
        startSession()

    }
    
    
    @objc(getLastFrame:)
    func getLastFrame(command: CDVInvokedUrlCommand) {
        
        let image = imageFromSampleBuffer(sampleBuffer: lastFrame)
        let res = image.jpegData(compressionQuality: 1)?.base64EncodedString() ?? ""
        let pluginResult = CDVPluginResult(
        status: CDVCommandStatus_OK,
            messageAs: res
        )
        self.commandDelegate!.send(
          pluginResult,
            callbackId: command.callbackId
        )
        
    }
        
    
    private func detectPose(in image: VisionImage, width: CGFloat, height: CGFloat) {
        if let poseDetector = self.poseDetector {
            var poses: [Pose]
            do {
                poses = try poseDetector.results(in: image)
            } catch let error {
                print("Failed to detect poses with error: \(error.localizedDescription).")
                return
            }
            guard !poses.isEmpty else {

                let pluginResult = CDVPluginResult(
                status: CDVCommandStatus_OK,
                messageAs: "{}"
                )
                pluginResult?.setKeepCallbackAs(true)
                self.commandDelegate!.send(
                  pluginResult,
                    callbackId: self.callbackid
                )
                return
            }
            DispatchQueue.main.sync {
                // Pose detected. Currently, only single person detection is supported.
                poses.forEach { pose in
                    
                    var dict = [String: [CGFloat]]()
                                        
                        for (startLandmarkType, endLandmarkTypesArray) in UIUtilities.poseConnections() {
                            let startLandmark = pose.landmark(ofType: startLandmarkType)
                            let startLandmarkPoint = normalizedPoint(
                                fromVisionPoint: startLandmark.position, width: width, height: height)
                            
                            let type = startLandmark.type
                            dict[type.rawValue] = [startLandmarkPoint.x, startLandmarkPoint.y]
                        }
                        
                        let encoder = JSONEncoder()
                        if let jsonData = try? encoder.encode(dict) {
                            if let jsonString = String(data: jsonData, encoding: .utf8) {
                                //JSON string
                                let pluginResult = CDVPluginResult(
                                status: CDVCommandStatus_OK,
                                messageAs: jsonString
                                )
                                pluginResult?.setKeepCallbackAs(true)
                                self.commandDelegate!.send(
                                  pluginResult,
                                    callbackId: self.callbackid
                                )
                            }
                        }
                }
            }
        }
    }
    
    private func setUpCaptureSessionOutput() {
        sessionQueue.async { [self] in
            self.captureSession.beginConfiguration()
            // When performing latency tests to determine ideal capture settings,
            // run the app in 'release' mode to get accurate performance metrics
            self.captureSession.sessionPreset = AVCaptureSession.Preset.medium
            
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                (kCVPixelBufferPixelFormatTypeKey as String): kCVPixelFormatType_32BGRA,
            ]
            output.alwaysDiscardsLateVideoFrames = true
            let outputQueue = DispatchQueue(label: "com.google.mlkit.visiondetector.VideoDataOutputQueue")
            output.setSampleBufferDelegate(self, queue: outputQueue)
            guard self.captureSession.canAddOutput(output) else {
                print("Failed to add capture session output.")
                return
            }
            self.captureSession.addOutput(output)
            self.captureSession.commitConfiguration()
            
            self.videoConnection = output.connection(with: .video)
        }
    }
    
    private func setUpCaptureSessionInput() {
        sessionQueue.async {
            let cameraPosition: AVCaptureDevice.Position = .front
            guard let device = self.captureDevice(forPosition: cameraPosition) else {
                print("Failed to get capture device for camera position: \(cameraPosition)")
                return
            }
            do {
                self.captureSession.beginConfiguration()
                let currentInputs = self.captureSession.inputs
                for input in currentInputs {
                    self.captureSession.removeInput(input)
                }
                
                let input = try AVCaptureDeviceInput(device: device)
                guard self.captureSession.canAddInput(input) else {
                    print("Failed to add capture session input.")
                    return
                }
                self.captureSession.addInput(input)
                self.captureSession.commitConfiguration()
            } catch {
                print("Failed to create capture device input: \(error.localizedDescription)")
            }
        }
    }
    
    private func startSession() {
        sessionQueue.async {
            self.captureSession.startRunning()
        }
    }
    
    private func stopSession() {
        sessionQueue.async {
            self.captureSession.stopRunning()
        }
    }
    
    
    private func captureDevice(forPosition position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if #available(iOS 10.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera],
                mediaType: .video,
                position: .unspecified

            )
            return discoverySession.devices.first { $0.position == position }
        }
        return nil
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to get image buffer from sample buffer.")
            return
        }
        connection.videoOrientation = .portrait
        connection.isVideoMirrored = true
        //let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer)

        lastFrame = sampleBuffer
        let visionImage = VisionImage(buffer: sampleBuffer)

        let orientation = UIUtilities.imageOrientation(
            fromDevicePosition: .front
        )
        
        visionImage.orientation = orientation
        let imageWidth = CGFloat(CVPixelBufferGetWidth(imageBuffer))
        let imageHeight = CGFloat(CVPixelBufferGetHeight(imageBuffer))
        
        detectPose(in: visionImage, width: imageWidth, height: imageHeight)
    }
    
    private func imageFromSampleBuffer(sampleBuffer:CMSampleBuffer!) -> UIImage {
        let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo:CGBitmapInfo = [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)]
        let context = CGContext(data: baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)!
        

        let quartzImage = context.makeImage()
        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let image = UIImage(cgImage: quartzImage!)
        
        return image
    }
    
    
    public enum Detector: String {
        case poseAccurate = "Pose, accurate"
        case poseFast = "Pose, fast"
    }
    
    private func normalizedPoint(
        fromVisionPoint point: VisionPoint,
        width: CGFloat,
        height: CGFloat
    ) -> CGPoint {
        let cgPoint = CGPoint(x: point.x, y: point.y)
        var normalizedPoint = CGPoint(x: cgPoint.x / width, y: cgPoint.y / height)
        normalizedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: normalizedPoint)
        return cgPoint
    }
}

