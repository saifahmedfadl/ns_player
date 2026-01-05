// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import AVKit
import Flutter
import GLKit
import UIKit

/// Buffer configuration for AVPlayer
public class BufferConfig {
    /// Preferred forward buffer duration in seconds
    /// Default: 30 seconds (reduced from system default)
    public static var preferredForwardBufferDuration: TimeInterval = 30.0
    
    /// Whether to automatically wait to minimize stalling
    public static var automaticallyWaitsToMinimizeStalling: Bool = true
    
    /// Preferred peak bitrate (0 = no limit)
    public static var preferredPeakBitRate: Double = 0
    
    /// Apply minimal buffer preset (15s)
    public static func applyMinimal() {
        preferredForwardBufferDuration = 15.0
    }
    
    /// Apply low buffer preset (30s)
    public static func applyLow() {
        preferredForwardBufferDuration = 30.0
    }
    
    /// Apply medium buffer preset (60s)
    public static func applyMedium() {
        preferredForwardBufferDuration = 60.0
    }
    
    /// Apply high buffer preset (120s)
    public static func applyHigh() {
        preferredForwardBufferDuration = 120.0
    }
}

public class NsVideoPlayerPlugin: NSObject, FlutterPlugin {
    private var registry: FlutterTextureRegistry
    private var messenger: FlutterBinaryMessenger
    private var players: [Int64: NsVideoPlayer] = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter.io/videoPlayer/ios",
            binaryMessenger: registrar.messenger()
        )
        let instance = NsVideoPlayerPlugin(
            registry: registrar.textures(),
            messenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    init(registry: FlutterTextureRegistry, messenger: FlutterBinaryMessenger) {
        self.registry = registry
        self.messenger = messenger
        super.init()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            // Dispose all existing players
            for player in players.values {
                player.dispose()
            }
            players.removeAll()
            result(nil)
            
        case "create":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                return
            }
            
            let player = NsVideoPlayer(
                registry: registry,
                messenger: messenger,
                asset: args["asset"] as? String,
                uri: args["uri"] as? String,
                packageName: args["packageName"] as? String,
                formatHint: args["formatHint"] as? String,
                httpHeaders: args["httpHeaders"] as? [String: String] ?? [:]
            )
            
            players[player.textureId] = player
            result(["textureId": player.textureId])
            
        case "setBufferConfig":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
                return
            }
            
            if let maxBuffer = args["maxBufferMs"] as? Int {
                BufferConfig.preferredForwardBufferDuration = TimeInterval(maxBuffer) / 1000.0
            }
            
            NSLog("NsVideoPlayerPlugin: Buffer config updated - preferredForwardBuffer: \(BufferConfig.preferredForwardBufferDuration)s")
            result(true)
            
        case "getBufferConfig":
            result([
                "preferredForwardBufferDuration": BufferConfig.preferredForwardBufferDuration,
                "automaticallyWaitsToMinimizeStalling": BufferConfig.automaticallyWaitsToMinimizeStalling
            ])
            
        default:
            guard let args = call.arguments as? [String: Any],
                  let textureId = args["textureId"] as? Int64,
                  let player = players[textureId] else {
                result(FlutterError(code: "INVALID_TEXTURE_ID", message: "Player not found", details: nil))
                return
            }
            
            switch call.method {
            case "dispose":
                player.dispose()
                players.removeValue(forKey: textureId)
                result(nil)
                
            case "setLooping":
                player.setLooping(args["looping"] as? Bool ?? false)
                result(nil)
                
            case "setVolume":
                player.setVolume(args["volume"] as? Double ?? 1.0)
                result(nil)
                
            case "setPlaybackSpeed":
                player.setPlaybackSpeed(args["speed"] as? Double ?? 1.0)
                result(nil)
                
            case "play":
                player.play()
                result(nil)
                
            case "pause":
                player.pause()
                result(nil)
                
            case "seekTo":
                let position = args["position"] as? Int ?? 0
                player.seekTo(position)
                result(nil)
                
            case "position":
                result(player.getPosition())
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

class NsVideoPlayer: NSObject, FlutterTexture {
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var displayLink: CADisplayLink?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    private var registry: FlutterTextureRegistry
    private var isInitialized = false
    private var isLooping = false
    private var pixelBuffer: CVPixelBuffer?
    private var videoOutput: AVPlayerItemVideoOutput?
    
    let textureId: Int64
    
    init(registry: FlutterTextureRegistry,
         messenger: FlutterBinaryMessenger,
         asset: String?,
         uri: String?,
         packageName: String?,
         formatHint: String?,
         httpHeaders: [String: String]) {
        
        self.registry = registry
        self.textureId = registry.register(NsVideoPlayer.self as! FlutterTexture)
        
        super.init()
        
        // Setup event channel
        eventChannel = FlutterEventChannel(
            name: "flutter.io/videoPlayer/videoEvents\(textureId)",
            binaryMessenger: messenger
        )
        eventChannel?.setStreamHandler(self)
        
        // Create player item
        var playerItem: AVPlayerItem?
        
        if let asset = asset {
            let assetPath: String
            if let packageName = packageName {
                assetPath = "packages/\(packageName)/\(asset)"
            } else {
                assetPath = asset
            }
            
            if let path = Bundle.main.path(forResource: assetPath, ofType: nil) {
                let url = URL(fileURLWithPath: path)
                playerItem = AVPlayerItem(url: url)
            }
        } else if let uri = uri, let url = URL(string: uri) {
            var asset: AVURLAsset
            
            if !httpHeaders.isEmpty {
                asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": httpHeaders])
            } else {
                asset = AVURLAsset(url: url)
            }
            
            playerItem = AVPlayerItem(asset: asset)
        }
        
        guard let item = playerItem else {
            NSLog("NsVideoPlayer: Failed to create player item")
            return
        }
        
        self.playerItem = item
        
        // Apply buffer settings
        if #available(iOS 10.0, *) {
            item.preferredForwardBufferDuration = BufferConfig.preferredForwardBufferDuration
            NSLog("NsVideoPlayer: Applied buffer duration: \(BufferConfig.preferredForwardBufferDuration)s")
        }
        
        // Create player
        player = AVPlayer(playerItem: item)
        player?.automaticallyWaitsToMinimizeStalling = BufferConfig.automaticallyWaitsToMinimizeStalling
        
        // Setup video output
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        item.add(videoOutput!)
        
        // Add observers
        item.addObserver(self, forKeyPath: "status", options: [.new], context: nil)
        item.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: nil)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemDidReachEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        
        // Setup display link for texture updates
        displayLink = CADisplayLink(target: self, selector: #selector(updateTexture))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func updateTexture() {
        guard let output = videoOutput,
              let item = playerItem,
              output.hasNewPixelBuffer(forItemTime: item.currentTime()) else {
            return
        }
        
        pixelBuffer = output.copyPixelBuffer(forItemTime: item.currentTime(), itemTimeForDisplay: nil)
        registry.textureFrameAvailable(textureId)
    }
    
    // MARK: - FlutterTexture
    
    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        guard let buffer = pixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
    
    // MARK: - KVO
    
    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey : Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard let item = playerItem else { return }
        
        if keyPath == "status" {
            if item.status == .readyToPlay && !isInitialized {
                isInitialized = true
                sendInitialized()
            } else if item.status == .failed {
                eventSink?(FlutterError(
                    code: "VideoError",
                    message: item.error?.localizedDescription ?? "Unknown error",
                    details: nil
                ))
            }
        } else if keyPath == "loadedTimeRanges" {
            sendBufferingUpdate()
        }
    }
    
    @objc private func playerItemDidReachEnd() {
        if isLooping {
            player?.seek(to: .zero)
            player?.play()
        } else {
            eventSink?(["event": "completed"])
        }
    }
    
    private func sendInitialized() {
        guard let item = playerItem,
              let track = item.asset.tracks(withMediaType: .video).first else {
            return
        }
        
        let size = track.naturalSize.applying(track.preferredTransform)
        let duration = CMTimeGetSeconds(item.duration) * 1000
        
        eventSink?([
            "event": "initialized",
            "duration": Int(duration),
            "width": Int(abs(size.width)),
            "height": Int(abs(size.height))
        ])
    }
    
    private func sendBufferingUpdate() {
        guard let item = playerItem,
              let timeRange = item.loadedTimeRanges.first?.timeRangeValue else {
            return
        }
        
        let start = CMTimeGetSeconds(timeRange.start) * 1000
        let end = CMTimeGetSeconds(CMTimeAdd(timeRange.start, timeRange.duration)) * 1000
        
        eventSink?([
            "event": "bufferingUpdate",
            "values": [[Int(start), Int(end)]]
        ])
    }
    
    // MARK: - Controls
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func setLooping(_ looping: Bool) {
        isLooping = looping
    }
    
    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }
    
    func setPlaybackSpeed(_ speed: Double) {
        player?.rate = Float(speed)
    }
    
    func seekTo(_ position: Int) {
        let time = CMTime(value: Int64(position), timescale: 1000)
        player?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func getPosition() -> Int {
        guard let time = player?.currentTime() else { return 0 }
        return Int(CMTimeGetSeconds(time) * 1000)
    }
    
    func dispose() {
        displayLink?.invalidate()
        displayLink = nil
        
        playerItem?.removeObserver(self, forKeyPath: "status")
        playerItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        
        NotificationCenter.default.removeObserver(self)
        
        player?.pause()
        player = nil
        playerItem = nil
        
        eventChannel?.setStreamHandler(nil)
        registry.unregisterTexture(textureId)
    }
}

// MARK: - FlutterStreamHandler

extension NsVideoPlayer: FlutterStreamHandler {
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}
