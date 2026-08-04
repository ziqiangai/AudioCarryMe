import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // carryme/video：AVFoundation 原生视频拼接（无 FFmpeg 依赖）。
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CarryMeVideo")!
    let channel = FlutterMethodChannel(
      name: "carryme/video", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "concat",
        let args = call.arguments as? [String: Any],
        let paths = args["paths"] as? [String],
        let output = args["output"] as? String,
        paths.count >= 2
      else {
        result(FlutterError(code: "bad_args", message: "需要 paths(>=2) 与 output", details: nil))
        return
      }
      AppDelegate.concatVideos(paths: paths, output: output) { ok, err in
        if ok {
          result(true)
        } else {
          result(FlutterError(code: "concat_failed", message: err ?? "拼接失败", details: nil))
        }
      }
    }
  }

  /// 用 AVMutableComposition 顺序拼接多段视频，导出 mp4。
  static func concatVideos(
    paths: [String], output: String, completion: @escaping (Bool, String?) -> Void
  ) {
    let composition = AVMutableComposition()
    guard
      let videoTrack = composition.addMutableTrack(
        withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else {
      completion(false, "无法创建视频轨")
      return
    }
    let audioTrack = composition.addMutableTrack(
      withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)

    var cursor = CMTime.zero
    for (i, p) in paths.enumerated() {
      let asset = AVURLAsset(url: URL(fileURLWithPath: p))
      guard let v = asset.tracks(withMediaType: .video).first else {
        completion(false, "第 \(i + 1) 段视频读取失败")
        return
      }
      let range = CMTimeRange(start: .zero, duration: asset.duration)
      do {
        try videoTrack.insertTimeRange(range, of: v, at: cursor)
        if let a = asset.tracks(withMediaType: .audio).first {
          try audioTrack?.insertTimeRange(range, of: a, at: cursor)
        }
        if i == 0 {
          videoTrack.preferredTransform = v.preferredTransform
        }
      } catch {
        completion(false, "第 \(i + 1) 段拼接失败：\(error.localizedDescription)")
        return
      }
      cursor = CMTimeAdd(cursor, asset.duration)
    }

    try? FileManager.default.removeItem(atPath: output)
    guard
      let export = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality)
    else {
      completion(false, "导出器创建失败")
      return
    }
    export.outputURL = URL(fileURLWithPath: output)
    export.outputFileType = .mp4
    export.exportAsynchronously {
      DispatchQueue.main.async {
        completion(export.status == .completed, export.error?.localizedDescription)
      }
    }
  }
}
