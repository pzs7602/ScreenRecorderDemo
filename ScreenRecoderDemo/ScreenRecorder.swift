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
    func writeBackgroundFrameInContext(contextRef:CGContextRef)
}

public class ScreenRecorder:NSObject{
    var videoWriter:AVAssetWriter?
    var videoWriterInput:AVAssetWriterInput?
    var audioWriterInput:AVAssetWriterInput?
    public var videoURL:NSURL?
    var avAdapter:AVAssetWriterInputPixelBufferAdaptor?
    var displayLink:CADisplayLink?
    var firstTimeStamp:CFTimeInterval?
    var outputBufferPoolAuxAttributes:NSDictionary?
    var isRecording:Bool = false
    public var delegate:ScreenRecorderDelegate?
    //
    var render_queue:dispatch_queue_t?
    var append_pixelBuffer_queue:dispatch_queue_t?
    var frameRenderingSemaphore:dispatch_semaphore_t?
    var pixelAppendSemaphore:dispatch_semaphore_t?
    
    var viewSize:CGSize?
    var scale:CGFloat?
    
    var rgbColorSpace:CGColorSpaceRef?
    var outputBufferPool:CVPixelBufferPoolRef?
    public static let sharedInstance = ScreenRecorder()
    public override convenience init()
    {
        self.init(path: "")
    }
    public init(path:String)
    {
        super.init()
        self.videoURL = NSURL(fileURLWithPath: path)
        let window = UIApplication.sharedApplication().delegate!.window!
        viewSize = window!.bounds.size
        scale = UIScreen.mainScreen().scale
        append_pixelBuffer_queue = dispatch_queue_create("ASScreenRecorder.append_queue", DISPATCH_QUEUE_SERIAL)
        render_queue = dispatch_queue_create("ASScreenRecorder.render_queue", DISPATCH_QUEUE_SERIAL)
        dispatch_set_target_queue(render_queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        frameRenderingSemaphore = dispatch_semaphore_create(1)
        pixelAppendSemaphore = dispatch_semaphore_create(1)
        // try to use bluetooth mic or any other line-in mic
        do{
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord, withOptions: AVAudioSessionCategoryOptions.AllowBluetooth)
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
            isRecording = (self.videoWriter!.status == AVAssetWriterStatus.Writing);
            self.displayLink = CADisplayLink(target: self, selector: #selector(writeVideoFrame))
            self.displayLink?.addToRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
        }
    }
    public func stopRecordingWithCompletion(completionBlock:VideoCompletionBlock)
    {
        if self.isRecording{
            self.isRecording = false
            self.displayLink?.removeFromRunLoop(NSRunLoop.mainRunLoop(), forMode: NSRunLoopCommonModes)
            self.completeRecordingSession(completionBlock)
        }
    }
    func setupWriter()
    {
        rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bufferAttributes:[NSString:NSObject] = [kCVPixelBufferPixelFormatTypeKey : NSNumber(unsignedInt: kCVPixelFormatType_32BGRA),
            kCVPixelBufferCGBitmapContextCompatibilityKey : true,
            kCVPixelBufferWidthKey : viewSize!.width * scale!,
            kCVPixelBufferHeightKey : viewSize!.height * scale!,
            kCVPixelBufferBytesPerRowAlignmentKey : viewSize!.width * scale! * 4
        ]
        outputBufferPool = nil
        CVPixelBufferPoolCreate(nil, nil, (bufferAttributes as CFDictionaryRef), &outputBufferPool)
        do{
            self.videoWriter = try AVAssetWriter(URL: self.videoURL != nil ? self.videoURL! : self.tempFileURL(), fileType: AVFileTypeQuickTimeMovie)
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
        self.videoWriter?.addInput(self.videoWriterInput!)
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
        self.videoWriter?.startSessionAtSourceTime(CMTimeMake(0, 1000))
        
    }
    func videoTransformForDeviceOrientation() -> CGAffineTransform
    {
        var videoTransform:CGAffineTransform
        switch (UIDevice.currentDevice().orientation) {
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
            videoTransform = CGAffineTransformIdentity;
        }
        return videoTransform
    }
    func tempFileURL() -> NSURL
    {
        let outputPath = (NSHomeDirectory() as NSString).stringByAppendingPathComponent("tmp/screenCapture.mp4")
        self.removeTempFilePath(outputPath)
        return NSURL(fileURLWithPath: outputPath)
    }
    func removeTempFilePath(filePath:String)
    {
        let fileManager = NSFileManager.defaultManager()
        if fileManager.fileExistsAtPath(filePath){
            do{
                try fileManager.removeItemAtPath(filePath)
            }
            catch(let error as NSError){
                print("error:\(error.description)")
            }
            catch{}
        }
    }
    func completeRecordingSession(completionBlock:VideoCompletionBlock)
    {
        dispatch_sync(append_pixelBuffer_queue!){
            self.videoWriterInput?.markAsFinished()
            self.videoWriter?.finishWritingWithCompletionHandler{
                let completion:(Void)->Void = {
                    self.cleanUp()
                    dispatch_async(dispatch_get_main_queue()){
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
        if dispatch_semaphore_wait(frameRenderingSemaphore!, DISPATCH_TIME_NOW) != 0{
            return
        }
        dispatch_async(render_queue!){
            if !self.videoWriterInput!.readyForMoreMediaData{
                return
            }
            if (self.firstTimeStamp == nil){
                self.firstTimeStamp = self.displayLink!.timestamp
            }
            let elapsed = (self.displayLink!.timestamp - self.firstTimeStamp!)
            let time = CMTimeMakeWithSeconds(elapsed, 1000)
            var pixelBuffer:CVPixelBufferRef? = nil
            let bitmapContext:CGContextRef = self.createPixelBufferAndBitmapContext(&pixelBuffer)
            if let _ = self.delegate{
                self.delegate!.writeBackgroundFrameInContext(bitmapContext)
            }
            // draw each window into the context (other windows include UIKeyboard, UIAlert)
            // FIX: UIKeyboard is currently only rendered correctly in portrait orientation
            dispatch_sync(dispatch_get_main_queue()){
                UIGraphicsPushContext(bitmapContext)
                
                    for window:UIWindow in UIApplication.sharedApplication().windows {
                        window.drawViewHierarchyInRect(CGRectMake(0, 0, self.viewSize!.width, self.viewSize!.height), afterScreenUpdates:false)
                    }
                
                UIGraphicsPopContext()
            }
            // append pixelBuffer on a async dispatch_queue, the next frame is rendered whilst this one appends
            // must not overwhelm the queue with pixelBuffers, therefore:
            // check if _append_pixelBuffer_queue is ready
            // if it’s not ready, release pixelBuffer and bitmapContext
            if dispatch_semaphore_wait(self.pixelAppendSemaphore!, DISPATCH_TIME_NOW) == 0{
                dispatch_async(self.append_pixelBuffer_queue!){
                    let success = self.avAdapter!.appendPixelBuffer(pixelBuffer!, withPresentationTime:time)
                    if !success{
                        print("Warning: Unable to write buffer to video")
                    }
                    CVPixelBufferUnlockBaseAddress(pixelBuffer!, 0)
                    dispatch_semaphore_signal(self.pixelAppendSemaphore!)
                }
            }
            else{
                CVPixelBufferUnlockBaseAddress(pixelBuffer!, 0)
            }
            dispatch_semaphore_signal(self.frameRenderingSemaphore!)
        }
    }
    func createPixelBufferAndBitmapContext(inout pixelBuffer:CVPixelBufferRef?) -> CGContextRef
    {
        var pBuffer:CVPixelBufferRef?
        CVPixelBufferPoolCreatePixelBuffer(nil, outputBufferPool!,&pBuffer)
        CVPixelBufferLockBaseAddress(pBuffer!, 0)
        
        var bitmapContext:CGContextRef?
        let bitmapInfo:CGBitmapInfo = [.ByteOrder32Little,CGBitmapInfo(rawValue:CGImageAlphaInfo.PremultipliedFirst.rawValue)]
        bitmapContext = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pBuffer!),
                                              CVPixelBufferGetWidth(pBuffer!),
                                              CVPixelBufferGetHeight(pBuffer!),
                                              8, CVPixelBufferGetBytesPerRow(pBuffer!), rgbColorSpace,
                                              bitmapInfo.rawValue
        )
        CGContextScaleCTM(bitmapContext, scale!, scale!)
        let flipVertical = CGAffineTransformMake(1, 0, 0, -1, 0, viewSize!.height);
        CGContextConcatCTM(bitmapContext, flipVertical);
        pixelBuffer = pBuffer
        return bitmapContext!
    }
}
