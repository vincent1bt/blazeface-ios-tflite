//
//  ModelHandlerTF.swift
//  FaceRecognitionAppTF
//
//  Created by vicente rodriguez on 23/01/21.
//

import TensorFlowLite
import UIKit

import VideoToolbox

typealias FileInfo = (name: String, extension: String)

class ModelHandlerTF: NSObject {
    let threadCount: Int
    let threadCountLimit = 10

    let threshold: Float = 0.75
    
    let batchSize = 1
    let inputChannels = 3
    let inputWidth = 128
    let inputHeight = 128
    let boxesCount = 896
    
    private var myInterpreter: Interpreter
    
    private let bgraPixel = (channels: 4, alphaComponent: 3, lastBgrComponent: 2)
    private let rgbPixelChannels = 3
    private let AMS = AverageMaximumSuppresion()
    
    init?(modelFileInfo: FileInfo, threadCount: Int = 1) {
        let modelFilename = modelFileInfo.name
        
        guard let modelPath = Bundle.main.path(
            forResource: modelFilename,
            ofType: modelFileInfo.extension
        ) else {
            print("Failed to load the model file with name: \(modelFilename).")
            return nil
        }
        
        self.threadCount = threadCount
        var options = Interpreter.Options()
        options.threadCount = threadCount
        
        do {
            myInterpreter = try Interpreter(modelPath: modelPath, options: options)
            try myInterpreter.allocateTensors()
        } catch let error {
            print("Failed to create the interpreter with error: \(error.localizedDescription)")
            return nil
        }
        
        super.init()
    }
    
    func runModel(onFrame pixelBuffer: CVPixelBuffer, cameraSize: CGRect) -> ([BoxPrediction], UIImage) {
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer) // 1080
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer) // 1920
        let sourcePixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        assert(sourcePixelFormat == kCVPixelFormatType_32ARGB ||
                     sourcePixelFormat == kCVPixelFormatType_32BGRA ||
                       sourcePixelFormat == kCVPixelFormatType_32RGBA)
        
        let imageChannels = 4
        assert(imageChannels >= inputChannels)
        
        let scaledSize = CGSize(width: inputWidth, height: inputHeight)
        guard let scaledPixelBuffer = pixelBuffer.resized(to: scaledSize) else {
            return ([AverageMaximumSuppresion.emptyBox], UIImage.init(named: "test.png")!)
        }
        
        let tensorPredictions: Tensor
        let tensorBoxes: Tensor
        
        var resizedCgImage: CGImage?
        // change pixelBuffer to scaledPixelBuffer to have the cropped image
        VTCreateCGImageFromCVPixelBuffer(scaledPixelBuffer, options: nil, imageOut: &resizedCgImage)
        let resizedUiImage = UIImage(cgImage: resizedCgImage!)
        
//        let resizedCiImage = CIImage(cvPixelBuffer: pixelBuffer)
//        let resixedUiImage = UIImage(ciImage: resizedCiImage)
        
        do {
            let inputTensor = try myInterpreter.input(at: 0)
            
            guard let rgbData = rgbDataFromBuffer(
                scaledPixelBuffer,
                byteCount: batchSize * inputWidth * inputHeight * inputChannels,
                isModelQuantized: inputTensor.dataType == .uInt8
            ) else {
                print("Failed to convert the image buffer to RGB data.")
                return ([AverageMaximumSuppresion.emptyBox], UIImage.init(named: "test.png")!)
            }
            
            try myInterpreter.copy(rgbData, toInputAt: 0)
            try myInterpreter.invoke()
            
            tensorPredictions = try myInterpreter.output(at: 0)
            tensorBoxes = try myInterpreter.output(at: 1)
            
            // shape [1, 896, 1]
            let predictions = [Float](unsafeData: tensorPredictions.data) ?? []
            
            // shape [1, 896, 4]
            let boxes = [Float](unsafeData: tensorBoxes.data) ?? []
            
            let arrays = getArrays(boxes: boxes)
            
            let finalBoxes: [BoxPrediction] = AMS.getFinalBoxes(rawXArray: arrays.xArray, rawYArray: arrays.yarray, rawWidthArray: arrays.width, rawHeightArray: arrays.height, classPredictions: predictions, imageWidth: Float(imageWidth), imageHeight: Float(imageHeight), cameraSize: cameraSize)
            
            return (finalBoxes, resizedUiImage)

        } catch let error {
            print("Failed to invoke the interpreter with error: \(error.localizedDescription)")
            return ([AverageMaximumSuppresion.emptyBox], UIImage.init(named: "test.png")!)
        }
        
    }
    
    func getArrays(boxes: [Float]) -> (xArray: [Float], yarray: [Float], width: [Float], height: [Float]) {
        var xArray: [Float] = []
        var yarray: [Float] = []
        var width: [Float] = []
        var height: [Float] = []

        for i in 0..<boxesCount {
            xArray.append(boxes[4 * i])
            yarray.append(boxes[4 * i + 1])
            width.append(boxes[4 * i + 2])
            height.append(boxes[4 * i + 3])
        }
        
        return (xArray, yarray, width, height)
    }
    
    private func rgbDataFromBuffer(
    _ buffer: CVPixelBuffer,
    byteCount: Int,
    isModelQuantized: Bool
    ) -> Data? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let mutableRawPointer = CVPixelBufferGetBaseAddress(buffer) else {
          return nil
        }
        assert(CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA)
        
        let count = CVPixelBufferGetDataSize(buffer)
        let bufferData = Data(bytesNoCopy: mutableRawPointer, count: count, deallocator: .none)
        var rgbBytes = [UInt8](repeating: 0, count: byteCount)
        var pixelIndex = 0
        
        for component in bufferData.enumerated() {
          let bgraComponent = component.offset % bgraPixel.channels;
          let isAlphaComponent = bgraComponent == bgraPixel.alphaComponent;
          guard !isAlphaComponent else {
            pixelIndex += 1
            continue
          }
          // Swizzle BGR -> RGB.
          let rgbIndex = pixelIndex * rgbPixelChannels + (bgraPixel.lastBgrComponent - bgraComponent)
          rgbBytes[rgbIndex] = component.element
        }
        
        if isModelQuantized {
            print("ModelQuantized")
            return Data(rgbBytes)
        }
        
        return Data(copyingBufferOf: rgbBytes.map { Float($0) / 255.0 })
    }
}

extension Data {
  /// Creates a new buffer by copying the buffer pointer of the given array.
  ///
  /// - Warning: The given array's element type `T` must be trivial in that it can be copied bit
  ///     for bit with no indirection or reference-counting operations; otherwise, reinterpreting
  ///     data from the resulting buffer has undefined behavior.
  /// - Parameter array: An array with elements of type `T`.
  init<T>(copyingBufferOf array: [T]) {
    self = array.withUnsafeBufferPointer(Data.init)
  }
}

extension Array {
  /// Creates a new array from the bytes of the given unsafe data.
  ///
  /// - Warning: The array's `Element` type must be trivial in that it can be copied bit for bit
  ///     with no indirection or reference-counting operations; otherwise, copying the raw bytes in
  ///     the `unsafeData`'s buffer to a new array returns an unsafe copy.
  /// - Note: Returns `nil` if `unsafeData.count` is not a multiple of
  ///     `MemoryLayout<Element>.stride`.
  /// - Parameter unsafeData: The data containing the bytes to turn into an array.
  init?(unsafeData: Data) {
    guard unsafeData.count % MemoryLayout<Element>.stride == 0 else { return nil }
//    #if swift(>=5.0)
    self = unsafeData.withUnsafeBytes { .init($0.bindMemory(to: Element.self)) }
//    #else
//    self = unsafeData.withUnsafeBytes {
//      .init(UnsafeBufferPointer<Element>(
//        start: $0,
//        count: unsafeData.count / MemoryLayout<Element>.stride
//      ))
//    }
//    #endif  // swift(>=5.0)
  }
}
