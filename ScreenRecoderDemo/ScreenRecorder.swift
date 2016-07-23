//
//  ScreenRecorder.swift
//  ScreenRecoderDemo
//
//  Created by pan zhansheng on 16/7/2.
//  Copyright © 2016年 pan zhansheng. All rights reserved.
//  本程序只能录制屏幕操作，不能同食录制声音

import UIKit
import AVFoundation
import Photos
import QuartzCore

public typealias VideoCompletionBlock = (Void)->Void
public protocol ScreenRecorderDelegate{
    func writeBackgroundFrameInContext(_ contextRef:CGContext)
}

public class ScreenRecorder:NSObject{
    var videoWriter:AVAssetWriter?
    var videoWriterInput:AVAssetWriterInput?
    var audioWriterInput:AVAssetWriterInput?
    public var videoURL:URL?
    var avAdapter:AVAssetWriterInputPixelBufferAdaptor?
    var displayLink:CADisplayLink?
    var firstTimeStamp:CFTimeInterval?
    var outputBufferPoolAuxAttributes:NSDictionary?
    var isRecording:Bool = false
    public var delegate:ScreenRecorderDelegate?
    //
    var render_queue:DispatchQueue?
    var append_pixelBuffer_queue:DispatchQueue?
    var frameRenderingSemaphore:DispatchSemaphore?
    var pixelAppendSemaphore:DispatchSemaphore?
    
    var viewSize:CGSize?
    var scale:CGFloat?
    
    var rgbColorSpace:CGColorSpace?
    var outputBufferPool:CVPixelBufferPool?
    public static let sharedInstance = ScreenRecorder()
    public override convenience init()
    {
        self.init(path: "")
    }
    public init(path:String)
    {
        super.init()
        self.videoURL = URL(fileURLWithPath: path)
        let window = UIApplication.shared().delegate!.window!
        viewSize = window!.bounds.size
        scale = UIScreen.main().scale
        append_pixelBuffer_queue = DispatchQueue(label: "ASScreenRecorder.append_queue", attributes: DispatchQueueAttributes.serial)
        render_queue = DispatchQueue(label: "ASScreenRecorder.render_queue", attributes: DispatchQueueAttributes.serial)
        render_queue?.setTarget(queue: DispatchQueue.global( attributes: DispatchQueue.GlobalAttributes.qosUserInitiated));
        frameRenderingSemaphore = DispatchSemaphore(value: 1)
        pixelAppendSemaphore = DispatchSemaphore(value: 1)
        // try to use bluetooth mic or any other line-in mic
        do{
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, with: AVAudioSessionCategoryOptions.allowBluetooth)
            try AVAudioSession.sharedInstance().setPreferredInput(AVAudioSession.sharedInstance().availableInputs!.last)
            for a in AVAudioSession.sharedInstance().availableInputs!{
                print("available inputs:\(a.portName)")
            }
            try AVAudioSession.sharedInstance().setActive(true)
            
        }catch let err as NSError?{
            print("err=\(err!.description)")
        }

    }
    public func startRecording()
    {
        if !isRecording{
            self.setupWriter()
            isRecording = (self.videoWriter!.status == AVAssetWriterStatus.writing);
            self.displayLink = CADisplayLink(target: self, selector: #selector(writeVideoFrame))
            self.displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
        }
    }
    public func stopRecordingWithCompletion(_ completionBlock:VideoCompletionBlock)
    {
        if self.isRecording{
            self.isRecording = false
            self.displayLink?.remove(from: RunLoop.main, forMode: RunLoopMode.commonModes)
            self.completeRecordingSession(completionBlock)
        }
    }
    func setupWriter()
    {
        rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bufferAttributes:[NSString:NSObject] = [kCVPixelBufferPixelFormatTypeKey : NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferCGBitmapContextCompatibilityKey : true,
            kCVPixelBufferWidthKey : viewSize!.width * scale!,
            kCVPixelBufferHeightKey : viewSize!.height * scale!,
            kCVPixelBufferBytesPerRowAlignmentKey : viewSize!.width * scale! * 4
        ]
        outputBufferPool = nil
        CVPixelBufferPoolCreate(nil, nil, (bufferAttributes as CFDictionary), &outputBufferPool)
        do{
            self.videoWriter = try AVAssetWriter(url: self.videoURL != nil ? self.videoURL! : self.tempFileURL(), fileType: AVFileTypeQuickTimeMovie)
        }
        catch(let error as NSError?){
            print("error=\(error?.description)")
        }
//        NSParameterAssert(self.videoWriter)
        let pixelNumber = (viewSize?.width)! * (viewSize?.height)! * scale!
        let videoCompression = [AVVideoAverageBitRateKey: pixelNumber * 11.4]
        let videoSettings = [AVVideoCodecKey: AVVideoCodecH264,
            AVVideoWidthKey: viewSize!.width*scale!,
            AVVideoHeightKey: viewSize!.height*scale!,
            AVVideoCompressionPropertiesKey: videoCompression]
        self.videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings as? [String : AnyObject])
        self.videoWriterInput?.expectsMediaDataInRealTime = true
        self.videoWriterInput?.transform = self.videoTransformForDeviceOrientation()
        self.avAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.videoWriterInput!, sourcePixelBufferAttributes: nil)
        self.videoWriter?.add(self.videoWriterInput!)
        // add audio input
//        let audioSettings = [
//            AVFormatIDKey:NSNumber(unsignedInt: kAudioFormatMPEG4AAC),
//            AVNumberOfChannelsKey:NSNumber(integer:2),
//            AVSampleRateKey:NSNumber(double: 44100),
//            AVEncoderBitRateKey:NSNumber(integer: 64000)
//        ]
//        self.audioWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeAudio, outputSettings: audioSettings)
//        self.audioWriterInput?.expectsMediaDataInRealTime = true
//        self.videoWriter?.addInput(self.audioWriterInput!)
        self.videoWriter?.startWriting()
        self.videoWriter?.startSession(atSourceTime: CMTimeMake(0, 1000))
        
    }
    func videoTransformForDeviceOrientation() -> CGAffineTransform
    {
        var videoTransform:CGAffineTransform
        switch (UIDevice.current().orientation) {
//        case UIDeviceOrientation.LandscapeLeft:
//            videoTransform = CGAffineTransformMakeRotation(CGFloat(-M_PI_2))
//            break
//        case UIDeviceOrientation.LandscapeRight:
//            videoTransform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
//            break
//        case UIDeviceOrientation.PortraitUpsideDown:
//            videoTransform = CGAffineTransformMakeRotation(CGFloat(M_PI))
//            break
        default:
            videoTransform = CGAffineTransform.identity;
        }
        return videoTransform
    }
    func tempFileURL() -> URL
    {
        let outputPath = (NSHomeDirectory() as NSString).appendingPathComponent("tmp/screenCapture.mp4")
        self.removeTempFilePath(outputPath)
        return URL(fileURLWithPath: outputPath)
    }
    func removeTempFilePath(_ filePath:String)
    {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: filePath){
            do{
                try fileManager.removeItem(atPath: filePath)
            }
            catch(let error as NSError){
                print("error:\(error.description)")
            }
            catch{}
        }
    }
    func completeRecordingSession(_ completionBlock:VideoCompletionBlock)
    {
        append_pixelBuffer_queue!.sync{
            self.videoWriterInput?.markAsFinished()
            self.videoWriter?.finishWriting{
                let completion:(Void)->Void = {
                    self.cleanUp()
                    DispatchQueue.main.async{
                        completionBlock()
                    }
                }
                if (self.videoURL != nil){
                    completion()
                }
                else{
                    completion()
                    // write video to photo library
//                    var placeholder:PHObjectPlaceholder?
//                    PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
//                        let createAssetRequest:PHAssetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(self.videoWriter!.outputURL)!
//                        placeholder = createAssetRequest.placeholderForCreatedAsset!
//                        }, completionHandler: { (success, error) -> Void in
//                            if success == true{
//                                print("didFinishRecordingToOutputFileAtURL - success for ios9")
//                            }
//                            else{
//                                print("error createAssetRequest:\(error?.description)")
//                                self.removeTempFilePath((self.videoWriter?.outputURL.path!)!)
//                                completion()
//                            }
//                    })
                }
            }
        }
    }
    func cleanUp()
    {
        self.avAdapter = nil
        self.videoWriterInput = nil
        self.videoWriter = nil
        self.firstTimeStamp = 0
        self.outputBufferPoolAuxAttributes = nil
    }

    func writeVideoFrame()
    {
        if frameRenderingSemaphore!.wait(timeout: DispatchTime.now()) != 0{
            return
        }
        render_queue!.async{
            if !self.videoWriterInput!.isReadyForMoreMediaData{
                return
            }
            if (self.firstTimeStamp == nil){
                self.firstTimeStamp = self.displayLink!.timestamp
            }
            let elapsed = (self.displayLink!.timestamp - self.firstTimeStamp!)
            let time = CMTimeMakeWithSeconds(elapsed, 1000)
            var pixelBuffer:CVPixelBuffer? = nil
            let bitmapContext:CGContext = self.createPixelBufferAndBitmapContext(pixelBuffer)
            if let _ = self.delegate{
                self.delegate!.writeBackgroundFrameInContext(bitmapContext)
            }
            // draw each window into the context (other windows include UIKeyboard, UIAlert)
            // FIX: UIKeyboard is currently only rendered correctly in portrait orientation
            DispatchQueue.main.sync{
                UIGraphicsPushContext(bitmapContext)
                
                    for window:UIWindow in UIApplication.shared().windows {
                        window.drawHierarchy(in: CGRect(x: 0, y: 0, width: self.viewSize!.width, height: self.viewSize!.height), afterScreenUpdates:false)
                    }
                
                UIGraphicsPopContext()
            }
            // append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
            // must not overwhelm the queue with pixelBuffers, therefore:
            // check if _append_pixelBuffer_queue is ready
            // if it’s not ready, release pixelBuffer and bitmapContext
            if self.pixelAppendSemaphore!.wait(timeout: DispatchTime.now()) == 0{
                self.append_pixelBuffer_queue!.async{
                    let success = self.avAdapter!.append(pixelBuffer!, withPresentationTime:time)
                    if !success{
                        print("Warning: Unable to write buffer to video")
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
                    self.pixelAppendSemaphore!.signal()
                }
            }
            else{
                CVPixelBufferUnlockBaseAddress(pixelBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
            }
            self.frameRenderingSemaphore!.signal()
        }
    }
    func createPixelBufferAndBitmapContext(_ pixelBuffer:CVPixelBuffer?) -> CGContext
    {
        var pixelBuffer = pixelBuffer
        var pBuffer:CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, outputBufferPool!,&pBuffer)
        CVPixelBufferLockBaseAddress(pBuffer!, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
        
        var bitmapContext:CGContext?
        let bitmapInfo:CGBitmapInfo = [.byteOrder32Little,CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue)]
        bitmapContext = CGContext(data: CVPixelBufferGetBaseAddress(pBuffer!),
                                              width: CVPixelBufferGetWidth(pBuffer!),
                                              height: CVPixelBufferGetHeight(pBuffer!),
                                              bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pBuffer!), space: rgbColorSpace!,
                                              bitmapInfo: bitmapInfo.rawValue
        )
        bitmapContext?.scale(x: scale!, y: scale!)
        let flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, viewSize!.height);
        bitmapContext?.concatCTM(flipVertical);
        pixelBuffer = pBuffer
        return bitmapContext!
    }
}
