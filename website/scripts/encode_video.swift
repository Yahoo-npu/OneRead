import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import CoreVideo

struct Entry: Decodable { let file: String; let ms: Double }
let args=CommandLine.arguments
let entries=try JSONDecoder().decode([Entry].self,from:Data(contentsOf:URL(fileURLWithPath:args[1])))
let destination=URL(fileURLWithPath:args[2])
try? FileManager.default.removeItem(at:destination)
func load(_ path:String)->CGImage {
 let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:path) as CFURL,nil)!
 return CGImageSourceCreateImageAtIndex(source,0,nil)!
}
let first=load(entries[0].file)
let width=first.width + first.width%2, height=first.height + first.height%2
let writer=try AVAssetWriter(outputURL:destination,fileType:.mp4)
let input=AVAssetWriterInput(mediaType:.video,outputSettings:[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:width,AVVideoHeightKey:height,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:8_000_000,AVVideoExpectedSourceFrameRateKey:60,AVVideoMaxKeyFrameIntervalKey:120,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel,AVVideoAllowFrameReorderingKey:false]])
input.expectsMediaDataInRealTime=false
let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:width,kCVPixelBufferHeightKey as String:height,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
writer.add(input);writer.shouldOptimizeForNetworkUse=true
guard writer.startWriting() else {throw writer.error ?? NSError(domain:"start",code:1)};writer.startSession(atSourceTime:.zero)
var frame=0
var cumulative=0.0
for e in entries {
 try autoreleasepool {
  let img=load(e.file)
  var pixel:CVPixelBuffer?
  CVPixelBufferCreate(nil,width,height,kCVPixelFormatType_32ARGB,[kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true] as CFDictionary,&pixel)
  let p=pixel!
  CVPixelBufferLockBaseAddress(p,[])
  let ctx=CGContext(data:CVPixelBufferGetBaseAddress(p),width:width,height:height,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(p),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
  ctx.setFillColor(CGColor(gray:1,alpha:1));ctx.fill(CGRect(x:0,y:0,width:width,height:height));ctx.draw(img,in:CGRect(x:0,y:0,width:img.width,height:img.height))
  CVPixelBufferUnlockBaseAddress(p,[])
  cumulative += e.ms
  let end=Int((cumulative*60/1000).rounded())
  while frame<end {
   while !input.isReadyForMoreMediaData { if let error=writer.error {throw error};Thread.sleep(forTimeInterval:0.001) }
   guard adaptor.append(p,withPresentationTime:CMTime(value:Int64(frame),timescale:60)) else {throw writer.error ?? NSError(domain:"encode",code:1)}
   frame+=1
  }
 }
}
input.markAsFinished();writer.endSession(atSourceTime:CMTime(value:Int64(frame),timescale:60))
let done=DispatchSemaphore(value:0)
writer.finishWriting{done.signal()};done.wait()
guard writer.status == .completed else {throw writer.error ?? NSError(domain:"encode",code:2)}
print("Encoded \(destination.lastPathComponent): \(width)x\(height), 60fps, \(frame) frames")
