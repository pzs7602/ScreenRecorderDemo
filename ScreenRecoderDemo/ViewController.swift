//
//  ViewController.swift
//  ScreenRecoderDemo
//
//  Created by pan zhansheng on 16/7/2.
//  Copyright © 2016年 pan zhansheng. All rights reserved.
//

import UIKit

class ViewController: UIViewController,ScreenRecorderDelegate {
    var recorder:ScreenRecorder?
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        recorder = ScreenRecorder.sharedInstance
        recorder?.delegate = self
    }

    @IBAction func startStop(sender: AnyObject) {
        if self.recorder!.isRecording{
            self.recorder!.stopRecordingWithCompletion{
                print("record end")
            }
        }
        else{
            print("start record")
            self.recorder!.startRecording()
        }
    }
    func writeBackgroundFrameInContext(contextRef:CGContextRef)
    {
        print("unimplemented")
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

