//
//  CVPixelBufferExtension.swift

import Foundation
import Accelerate

extension CVPixelBuffer {
    func resized(to size: CGSize) -> CVPixelBuffer? {
        let imageWidth = CVPixelBufferGetWidth(self)
        let imageHeight = CVPixelBufferGetHeight(self)
        let pixelBufferType = CVPixelBufferGetPixelFormatType(self)
        
        assert(pixelBufferType == kCVPixelFormatType_32BGRA)
        
        let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
        let imageChannels = 4
        
        let thumbnailSize = min(imageWidth, imageHeight) // new
        CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        
        var originX = 0 // new
        var originY = 0 // new
        
        // new
        if imageWidth > imageHeight {
            originX = (imageWidth - imageHeight) / 2 // set the center
        }
        else {
            originY = (imageHeight - imageWidth) / 2 // set the center
        }
        
        // new
        guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self)?.advanced(
                by: originY * inputImageRowBytes + originX * imageChannels) else {
              return nil
        }
        
//        guard let inputBaseAddress = CVPixelBufferGetBaseAddress(self) else {
//          return nil
//        }
        
        // new
        var inputVImageBuffer = vImage_Buffer(
                data: inputBaseAddress, height: UInt(thumbnailSize), width: UInt(thumbnailSize),
                rowBytes: inputImageRowBytes)
        
//        var inputVImageBuffer = vImage_Buffer(
        //data: inputBaseAddress, height: UInt(imageHeight), width: UInt(imageWidth), rowBytes: inputImageRowBytes)
        
        // new
        let thumbnailRowBytes = Int(size.width) * imageChannels
        guard  let thumbnailBytes = malloc(Int(size.height) * thumbnailRowBytes) else {
            return nil
        }
        
//        let scaledImageRowBytes = Int(size.width) * imageChannels
//        guard  let scaledImageBytes = malloc(Int(size.height) * scaledImageRowBytes) else {
//          return nil
//        }
        
        // new
        var thumbnailVImageBuffer = vImage_Buffer(data: thumbnailBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: thumbnailRowBytes)
        
//        var scaledVImageBuffer = vImage_Buffer(data: scaledImageBytes, height: UInt(size.height), width: UInt(size.width), rowBytes: scaledImageRowBytes)
        
        // new
        let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &thumbnailVImageBuffer, nil, vImage_Flags(0))
        
//        let scaleError = vImageScale_ARGB8888(&inputVImageBuffer, &scaledVImageBuffer, nil, vImage_Flags(0))
        
        CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
        
        guard scaleError == kvImageNoError else {
          return nil
        }
        
        let releaseCallBack: CVPixelBufferReleaseBytesCallback = {mutablePointer, pointer in

          if let pointer = pointer {
            free(UnsafeMutableRawPointer(mutating: pointer))
          }
        }
        
        // new
        var thumbnailPixelBuffer: CVPixelBuffer?
        
//        var scaledPixelBuffer: CVPixelBuffer?
        
        // new
        let conversionStatus = CVPixelBufferCreateWithBytes(
                nil, Int(size.width), Int(size.height), pixelBufferType, thumbnailBytes,
                thumbnailRowBytes, releaseCallBack, nil, nil, &thumbnailPixelBuffer)
        
//        let conversionStatus = CVPixelBufferCreateWithBytes(nil, Int(size.width), Int(size.height), pixelBufferType, scaledImageBytes, scaledImageRowBytes, releaseCallBack, nil, nil, &scaledPixelBuffer)
        
        // new
        guard conversionStatus == kCVReturnSuccess else {
              free(thumbnailBytes)
              return nil
        }
        
//        guard conversionStatus == kCVReturnSuccess else {
//
//          free(scaledImageBytes)
//          return nil
//        }
        
        return thumbnailPixelBuffer
        
        // return scaledPixelBuffer
    }
}
