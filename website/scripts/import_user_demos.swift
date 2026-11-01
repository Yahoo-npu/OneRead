import Foundation
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

let sources:[(String,String)]=[("magazines","外刊导入"),("reading","双语对照阅读"),("translation","一键翻译"),("word","划词翻译"),("clauses","长难句解析"),("vocabulary","墨墨云词本同步"),("updates","最新期刊推送")]
let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
let sourceDirectory=CommandLine.arguments.count > 1 ? URL(fileURLWithPath:(CommandLine.arguments[1] as NSString).expandingTildeInPath) : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/功能演示",isDirectory:true)
let out=root.appendingPathComponent("website/dist/assets/demos",isDirectory:true)
let review=root.appendingPathComponent(".local/user-demo-frames",isDirectory:true)
try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
try FileManager.default.createDirectory(at:review,withIntermediateDirectories:true)
var manifest:[[String:Any]]=[]
for (id,name) in sources {
 let source=sourceDirectory.appendingPathComponent(name+".mov")
 let asset=AVURLAsset(url:source)
 guard let track=asset.tracks(withMediaType:.video).first else {fatalError("Missing video: \(name)")}
 let duration=CMTimeGetSeconds(asset.duration)
 let destination=out.appendingPathComponent(id+".mp4")
 try? FileManager.default.removeItem(at:destination)
 // The supplied movies already contain H.264 at 60fps. Remux, without re-encoding.
 let exporter=AVAssetExportSession(asset:asset,presetName:AVAssetExportPresetPassthrough)!
 exporter.outputURL=destination;exporter.outputFileType = .mp4;exporter.shouldOptimizeForNetworkUse=true
 let finished=DispatchSemaphore(value:0);exporter.exportAsynchronously{finished.signal()};finished.wait()
 guard exporter.status == .completed else {fatalError("Export failed: \(name): \(String(describing:exporter.error))")}
 let generator=AVAssetImageGenerator(asset:asset);generator.appliesPreferredTrackTransform=true
 for (label,time) in [("start",min(0.2,duration/10)),("middle",duration*0.5),("end",max(0,duration-0.3))] {
  let image=try generator.copyCGImage(at:CMTime(seconds:time,preferredTimescale:600),actualTime:nil)
  let url=review.appendingPathComponent(id+"-"+label+".png")
  let d=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
  CGImageDestinationAddImage(d,image,nil);CGImageDestinationFinalize(d)
 }
 let attributes=try FileManager.default.attributesOfItem(atPath:destination.path)
 manifest.append(["id":id,"source":name+".mov","file":id+".mp4","width":Int(track.naturalSize.width),"height":Int(track.naturalSize.height),"fps":track.nominalFrameRate,"duration":duration,"bytes":attributes[.size]!,"processing":"H.264 passthrough remux; original video and audio retained"])
 print("Imported \(name): \(duration)s, \(track.nominalFrameRate)fps",terminator:"\n");fflush(stdout)
}
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("manifest.json"))
