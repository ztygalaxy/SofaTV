import Foundation
@main struct HlsQualityChecks {
 static func main() throws {
  let text = """
  #EXTM3U
  #EXT-X-STREAM-INF:BANDWIDTH=3200000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
  fake-1080.m3u8?token=a%2Bb
  #EXT-X-STREAM-INF:BANDWIDTH=1800000,RESOLUTION=1280x720
  real-720.m3u8
  #EXT-X-STREAM-INF:BANDWIDTH=600000,RESOLUTION=640x360
  real-360.m3u8
  """
  let variants=HlsQualitySelection.variants(Data(text.utf8),base:URL(string:"https://example.com/live/master.m3u8")!)
  precondition(variants.count==3)
  let high=HlsQualitySelection.ordered(variants,quality:0)
  precondition(high.first!.advertised==HlsResolution(width:1920,height:1080))
  precondition(high.first!.url.absoluteString=="https://example.com/live/fake-1080.m3u8?token=a%2Bb")
  let mislabeled=HlsVariantProbe(variant:high[0],actual:HlsResolution(width:640,height:360))
  let real=HlsVariantProbe(variant:high[1],actual:HlsResolution(width:1280,height:720))
  precondition(!mislabeled.matchesAdvertised && real.matchesAdvertised)
  precondition(HlsQualitySelection.best([mislabeled,real],quality:0)?.variant.url==real.variant.url)
  precondition(HlsQualitySelection.best([HlsVariantProbe(variant:high[0],actual:nil),real],quality:2)?.variant.url==real.variant.url)
  precondition(HlsQualitySelection.ordered(variants,quality:1).first!.advertised==HlsResolution(width:1280,height:720))
  precondition(HlsQualitySelection.ordered(variants,quality:2).first!.advertised==HlsResolution(width:640,height:360))
  precondition(HlsQualitySelection.resolution(in:Data(repeating:0,count:188))==nil)
  if CommandLine.arguments.count>1 {
   let root=URL(fileURLWithPath:CommandLine.arguments[1])
   let expected=[HlsResolution(width:640,height:360),HlsResolution(width:1280,height:720),HlsResolution(width:1024,height:576),HlsResolution(width:854,height:480),HlsResolution(width:640,height:360)]
   for i in expected.indices {
    let data=try Data(contentsOf:root.appendingPathComponent("Safari-\(i).ts"))
    let actual=HlsQualitySelection.resolution(in:data)
    precondition(actual==expected[i],"Unexpected TS geometry for variant \(i)")
   }
  }
  print("HLS quality: mislabeled 1080p, actual resolution ranking, unknown probes, relative URLs and quality modes passed")
 }
}
