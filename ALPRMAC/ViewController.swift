//
//  ViewController.swift
//  ALPRMAC
//
//  Created by Xander Van Raemdonck on 12/04/16.
//  Copyright © 2016 TNTap. All rights reserved.
//

import Cocoa
import AVFoundation
import QuartzCore

class ViewController: NSViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    var captureSession : AVCaptureSession?
    var videoPreviewLayer : AVCaptureVideoPreviewLayer?
    let output = AVCaptureStillImageOutput()
    let outputStream = AVCaptureVideoDataOutput()
    
    var busy : Bool = false
    var start : Bool = false
    
    let txtPlate : NSText = NSText(frame: NSMakeRect(80, 20, 300, 50))
    let txtTryPlate : NSText = NSText(frame: NSMakeRect(650, 550, 100, 20))
    let txtType : NSText = NSText(frame: NSMakeRect(80, 20, 300, 10))
    
    // Create JSON Dictionary from string
    func JSONParseDictionary(string: String) -> [String: AnyObject]{
        
        if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
            do {
                if let dictionary = try NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments) as? [String: AnyObject] {
                    return dictionary
                }
            } catch _ {
                
            }
        }
        return [String: AnyObject]()
    }
    
    // Create JSON Dictionary from HTTP data
    func JSONParseDictionaryFromData(data: NSData) -> [String: AnyObject] {
        do {
            if let json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers) as? [String: AnyObject] {
                return json
            }
        } catch _{
            print("Error in parse!")
        }
        return [String: AnyObject]()
    }
    
    // Create JSON Array from string
    func JSONParseArray(string: String) -> [AnyObject] {
        if let data = string.dataUsingEncoding(NSUTF8StringEncoding) {
            do {
                if let array = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions.MutableContainers) as? [AnyObject] {
                    return array
                }
            } catch _ {
                
            }
        }
        return [AnyObject]()
        
    }
    
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        if let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            CVPixelBufferLockBaseAddress(imageBuffer, 0)
            
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
            let src = CVPixelBufferGetBaseAddress(imageBuffer)
            
            let image = CIImage(CVPixelBuffer: imageBuffer)
            let context = CIContext(options: nil)
            let myImage = context.createCGImage(image, fromRect: CGRectMake(0, 0, CGFloat(width), CGFloat(height)))
            let finalImage = NSImage(CGImage: myImage, size: NSSize(width: width, height: height))
            
            if let data = finalImage.TIFFRepresentation {
                CVPixelBufferUnlockBaseAddress(imageBuffer, 0)
                
                let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
                do {
                    try data.writeToFile(documentsPath + "/stream.jpg", options: .DataWritingAtomic)
                    system("/usr/local/Cellar/openalpr/2.2.0/bin/alpr -c eu -j " + documentsPath + "/stream.JPG > " + documentsPath + "/stream.txt")
                    self.scanText("/stream")
                } catch {
                    print(error)
                }
                
            }
        }
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.title = "PANPR - by Mathias & Xander"
        
        // Do any additional setup after loading the view.
        
        let captureDevice = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        var input : AVCaptureDeviceInput?
        do {
            input = try AVCaptureDeviceInput(device: captureDevice)
        } catch {
            print(error)
            
            return
        }
        
        captureSession = AVCaptureSession()
        captureSession?.addInput(input)
        captureSession?.sessionPreset = AVCaptureSessionPresetPhoto
        captureSession?.startRunning()
        
        
        output.outputSettings = [AVVideoCodecKey:AVVideoCodecJPEG]
        outputStream.setSampleBufferDelegate(self, queue: dispatch_queue_create("SampleBuffer", DISPATCH_QUEUE_SERIAL))
        
        captureSession?.addOutput(output)
        captureSession?.addOutput(outputStream)
        
        if let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession) {
            videoPreviewLayer.bounds = view.bounds
            videoPreviewLayer.position = CGPointMake(view.bounds.midX, view.bounds.midY)
            videoPreviewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
            
            
            view.layer?.addSublayer(videoPreviewLayer)
            
            
            let button : NSButton = NSButton(frame: NSMakeRect(30, 30, 40, 40))
            
            view.addSubview(button)
            view.addSubview(txtPlate)
            view.addSubview(txtType)
            view.addSubview(txtTryPlate)
            
            button.title = ">"
            button.setButtonType(.MomentaryLightButton)
            button.bezelStyle = .RoundedBezelStyle
            button.target = self
            button.action = #selector(ViewController.buttonPressed)
            button.hidden = true
            
            txtPlate.backgroundColor = NSColor.clearColor()
            txtPlate.textColor = NSColor.redColor()
            txtPlate.font = NSFont.boldSystemFontOfSize(30)
            txtPlate.editable = false
            
            txtTryPlate.backgroundColor = NSColor.clearColor()
            txtTryPlate.textColor = NSColor.blueColor()
            txtTryPlate.font = NSFont.boldSystemFontOfSize(15)
            txtTryPlate.editable = false
            
            txtType.backgroundColor = NSColor.clearColor()
            txtType.textColor = NSColor.greenColor()
            txtType.font = NSFont.boldSystemFontOfSize(15)
            txtType.editable = false
        }
    }
    
    func scanner() {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) {
            while(self.start) {
                if !self.busy {
                    
                    self.scanCamera()
                    sleep(1)
                    
                    
                }
            }
        }
    }
    
    func buttonPressed() {
        if start {
            start = false
            scanner()
        } else {
            start = true
            scanner()
        }
        
    }
    
    func sendPlate(plate : String) -> Bool {
        var flagged : Bool = false
        var data = NSData()
        var url = "https://api.tntap.be/?panpr&plate=" + plate
        url += "&appVersion=2"
        let endpoint = NSURL(string: url)
        do {
            try data = NSData(contentsOfURL: endpoint!, options: .DataReadingUncached)
            if let message : NSDictionary = self.JSONParseDictionaryFromData(data) {
                if message["message"] as? String == "success" {
                    dispatch_async(dispatch_get_main_queue()) {
                        if let type : String = message["type"] as? String {
                            self.txtType.string = type
                            if let correctPlate : String = message["text"] as? String {
                                self.txtPlate.string = self.craftPlate(correctPlate).uppercaseString
                            } else {
                                self.txtPlate.string = self.craftPlate(plate).uppercaseString
                            }
                        }
                    }
                    flagged = true
                }
            }
        } catch _ {
            NSLog("[HTTP REQUEST]: Network error!")
            self.sendPlate(plate)
        }
        
        return flagged
    }
    
    func logPlate(plate : String) -> Bool {
        var logged : Bool = false
        var data = NSData()
        var url = "https://api.tntap.be/?panpr&logPlate=" + plate
        url += "&appVersion=2"
        let endpoint = NSURL(string: url)
        do {
            try data = NSData(contentsOfURL: endpoint!, options: .DataReadingUncached)
            if let message : NSDictionary = self.JSONParseDictionaryFromData(data) {
                if message["message"] as? String == "success" {
                    logged = true
                }
            }
        } catch _ {
            NSLog("[HTTP REQUEST]: Network error!")
            self.logPlate(plate)
        }
        
        return logged
    }
    
    func isRealPlate(plate : String) -> Bool {
        var real : Bool = false
        
        let splitPlate = plate
        let length = NSString(string: splitPlate).length
        
        let letters = NSCharacterSet.letterCharacterSet()
        let numbers = NSCharacterSet.decimalDigitCharacterSet()
        
        func checkIfLetter(text : String, len : Int) -> Bool {
            var counter = 0
            for chr in text.utf16 {
                if letters.characterIsMember(chr) {
                    counter += 1
                }
            }
            return counter == len
        }
        
        func checkIfNumber(text : String, len : Int) -> Bool {
            var counter = 0
            for chr in text.utf16 {
                if numbers.characterIsMember(chr) {
                    counter += 1
                }
            }
            return counter == len
        }
        
        if length == 6 {
            
            
            if (checkIfLetter(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex..<splitPlate.startIndex.advancedBy(3))), len: 3) && checkIfNumber(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex.advancedBy(3)..<splitPlate.endIndex)), len: 3)) || (checkIfNumber(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex..<splitPlate.startIndex.advancedBy(3))), len: 3) && checkIfLetter(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex.advancedBy(3)..<splitPlate.endIndex)), len: 3)) {
                real = true
                return real
            }
        } else if length == 7 {
            if ((checkIfLetter(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex.advancedBy(1)..<splitPlate.startIndex.advancedBy(4))), len: 3)) && checkIfNumber(splitPlate.substringWithRange(Range<String.Index>(splitPlate.startIndex.advancedBy(4)..<splitPlate.endIndex)), len: 3)) && (splitPlate.substringToIndex(splitPlate.startIndex.advancedBy(1)).rangeOfCharacterFromSet(numbers) != nil) {
                real = true
                return real
            }
        }
        
        return real
    }
    
    
    func scanCamera() {
        busy = true
        if let videoConnection = output.connectionWithMediaType(AVMediaTypeVideo) {
            output.captureStillImageAsynchronouslyFromConnection(videoConnection, completionHandler: {
                (imageDataSampleBuffer, error) -> Void in
                if imageDataSampleBuffer != nil {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                    
                    let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
                    
                    imageData.writeToFile(documentsPath + "/output.JPG", atomically: true)
                    system("/usr/local/Cellar/openalpr/2.2.0/bin/alpr -c eu -j " + documentsPath + "/output.JPG > " + documentsPath + "/output.txt")
                    self.scanText("/output")
                }
            })
        }
        busy = false
    }
    
    func craftPlate(plate : String) -> String {
        let length = NSString(string: plate).length
        if (length == 6 || length == 7) {
            var craftedPlate = plate
            if length == 7 {
                craftedPlate.insert("-", atIndex: craftedPlate.startIndex.advancedBy(1))
                craftedPlate.insert("-", atIndex: craftedPlate.startIndex.advancedBy(5))
            } else {
                craftedPlate.insert("-", atIndex: craftedPlate.startIndex.advancedBy(3))
            }
            return craftedPlate
        } else {
            return ""
        }
    }
    
    func scanText(file : String) {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
        do {
            let text2 = try String(contentsOfFile: documentsPath + file + ".txt")
            
            
            let info : NSDictionary = self.JSONParseDictionary(text2)
            if info.count > 0 {
                if let plateArray : [[String : AnyObject]] = info["results"] as? [[String : AnyObject]] {
                    print("----- NEW ------")
                    var i : Int = 0
                    for item in plateArray {
                        i+=1
                        print(i)
                        if let plate : String = item["plate"] as? String {
                            print(plate)
                            if self.isRealPlate(plate) {
                                
                                self.logPlate(plate)
                                
                                let length = NSString(string: plate).length
                                if (length == 6 || length == 7) {
                                    dispatch_async(dispatch_get_main_queue()) {
                                        self.txtTryPlate.string = self.craftPlate(plate).uppercaseString
                                    }
                                }
                                
                                
                                if (length == 6 || length == 7) && self.sendPlate(plate) {
                                    
                                    
                                    print("WARNING!!!!")
                                    NSBeep()
                                }
                            }
                        }
                    }
                }
            }
            
            system("rm " + documentsPath + file + ".JPG")
            system("rm " + documentsPath +  file + ".txt")
        } catch {
            print(error)
            
        }
    }
    
    override var representedObject: AnyObject? {
        didSet {
            // Update the view, if already loaded.
        }
    }
    
    
}

