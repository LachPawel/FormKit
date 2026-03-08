//
//  CMSampleBuffer+Extension.swift
//
//  Created by Pawel Lach on 09/05/2025.
//

import AVFoundation
import CoreImage

extension CMSampleBuffer {
    var cgImage: CGImage? {
        let pixelBuffer: CVPixelBuffer? = CMSampleBufferGetImageBuffer(self)
        
        guard let imagePixelBuffer = pixelBuffer else {
            return nil
        }
        
        return CIImage(cvPixelBuffer: imagePixelBuffer).cgImage
    }
}
