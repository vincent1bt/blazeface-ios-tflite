//
//  ContentView.swift
//  FaceRecognitionAppTF
//
//  Created by vicente rodriguez on 19/01/21.
//

import SwiftUI
import AVFoundation
import UIKit

struct ContentView: View {
    var body: some View {
        CameraView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct FrameView: View {
    // 844.0, 390.0 iphone 6.1
    var boxes: [BoxPrediction] = []
    
    var body: some View {
        ForEach(boxes, id: \.id) { box in
            Rectangle().strokeBorder(Color.red).frame(width: box.rect.width, height: box.rect.height).position(x: box.rect.midX, y: box.rect.midY)
        }
    }
}

struct CameraView: View {
    @StateObject var camera = CameraModel()
    
    var body: some View {
        ZStack {
            CameraPreview(camera: camera).ignoresSafeArea(.all, edges: .all)
            FrameView(boxes: camera.boxes)
            Rectangle().strokeBorder(Color.blue).frame(width: camera.maxWidth, height: camera.maxHeight)
            Text(String(camera.frames)).position(x: 100, y: 100)
            VStack {
//                Image(uiImage: camera.myImage).resizable().frame(width: 128, height: 128).position(x: 64, y: 128)
//                Image(uiImage: camera.myImage).resizable().frame(width: 240, height: 426).position(x: 405, y: 440)
            }
        }.onAppear(perform: {
            camera.Check()
            camera.CheckModel()
        })
    }
}

class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isTaken = false
    @Published var session = AVCaptureSession()
    
    @Published var alert = false
    @Published var output = AVCaptureVideoDataOutput()
    
    @Published var preview: AVCaptureVideoPreviewLayer!
    
    var modelHandler: ModelHandlerTF? = ModelHandlerTF(modelFileInfo: (name: "face_keras_500", extension: "tflite"))
    
    @Published var boxes: [BoxPrediction] = []
    @Published var frames: Int = 60
    @Published var myImage: UIImage = UIImage(named: "test.png")!
    
    var maxWidth: CGFloat = 0
    var maxHeight: CGFloat = 0
    var cameraSizeRect: CGRect = CGRect.zero
    
    func Check() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { (status) in
                if status {
                    self.setUp()
                }
            }
        case .denied:
            self.alert.toggle()
            return
        default:
            return
        }
    }
    
    func CheckModel() {
        guard modelHandler != nil else {
            fatalError("Failed to load model")
        }
    }
    
    func setUp() {
        do {
            self.session.beginConfiguration()
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            
            let input = try AVCaptureDeviceInput(device: device!)
            
            if self.session.canAddInput(input) {
                self.session.addInput(input)
            }
            
            self.output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "sample buffer"))
            self.output.alwaysDiscardsLateVideoFrames = true
            self.output.videoSettings = [ String(kCVPixelBufferPixelFormatTypeKey) : kCMPixelFormat_32BGRA]
            
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
                self.output.connection(with: .video)?.videoOrientation = .portrait
            }
            
            self.session.commitConfiguration()
            
        } catch {
            print(error.localizedDescription)
        }
        
        cameraSizeRect = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        maxHeight = cameraSizeRect.width
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(sampleBuffer)
        
        guard let imagePixelBuffer = pixelBuffer else {
            return
        }
        
        let startTime = CACurrentMediaTime()

        let results = modelHandler?.runModel(onFrame: imagePixelBuffer, cameraSize: cameraSizeRect)
        let finalBoxes = results?.0 ?? [AverageMaximumSuppresion.emptyBox]
        
        let myResultImage = results!.1
        
        let finalTime = CACurrentMediaTime()
        
        let fullComputationFrames = 1 / (finalTime - startTime)
        
        DispatchQueue.main.async {
            self.boxes = finalBoxes
            self.frames = Int(fullComputationFrames)
            self.myImage = myResultImage
        }
    }
}

// @State is for variables that change the UI behaviour
// but we can't use it for structs or classes

// we need to say that a variable is @State since views are destroyed and created all the time
// But we want to keep some the state/values of some variables

//@Binding is used to mirror the value of one variable in a "parent" class

// when we want to use view that come from UIKit
// we must use UIViewRepresentable protocol

// and use two functions makeUIView and updateUIView

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        camera.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(camera.preview)
        
        camera.session.startRunning()
        
        camera.maxWidth = camera.preview.bounds.size.width
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
    }
}
