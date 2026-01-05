package com.nsplayer.ns_video_player_android

import android.content.Context
import android.util.Log
import android.util.LongSparseArray
import android.view.Surface
import androidx.annotation.NonNull
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/**
 * NsVideoPlayerPlugin
 * 
 * A forked version of video_player_android with custom buffer control.
 * This plugin allows configuring ExoPlayer buffer settings to reduce bandwidth usage.
 */
@UnstableApi
class NsVideoPlayerPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private lateinit var textureRegistry: TextureRegistry
    private val videoPlayers = LongSparseArray<NsVideoPlayer>()

    companion object {
        private const val TAG = "NsVideoPlayerPlugin"
        private const val CHANNEL_NAME = "flutter.io/videoPlayer/android"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        context = binding.applicationContext
        textureRegistry = binding.textureRegistry
        
        Log.d(TAG, "NsVideoPlayerPlugin attached with buffer control")
        Log.d(TAG, "Buffer config: maxBuffer=${BufferConfig.maxBufferMs}ms")
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init" -> {
                // Dispose all existing players
                for (i in 0 until videoPlayers.size()) {
                    videoPlayers.valueAt(i).dispose()
                }
                videoPlayers.clear()
                result.success(null)
            }
            "create" -> {
                val textureEntry = textureRegistry.createSurfaceTexture()
                val eventChannel = EventChannel(
                    channel.binaryMessenger,
                    "flutter.io/videoPlayer/videoEvents${textureEntry.id()}"
                )
                
                val player = NsVideoPlayer(
                    context,
                    eventChannel,
                    textureEntry,
                    call.argument("asset"),
                    call.argument("uri"),
                    call.argument("packageName"),
                    call.argument("formatHint"),
                    call.argument<Map<String, String>>("httpHeaders") ?: emptyMap()
                )
                
                videoPlayers.put(textureEntry.id(), player)
                
                result.success(mapOf("textureId" to textureEntry.id()))
            }
            "setBufferConfig" -> {
                val minBuffer = call.argument<Int>("minBufferMs")
                val maxBuffer = call.argument<Int>("maxBufferMs")
                val playbackBuffer = call.argument<Int>("bufferForPlaybackMs")
                val rebufferBuffer = call.argument<Int>("bufferForPlaybackAfterRebufferMs")
                val backBuffer = call.argument<Int>("backBufferDurationMs")
                
                if (minBuffer != null) BufferConfig.minBufferMs = minBuffer
                if (maxBuffer != null) BufferConfig.maxBufferMs = maxBuffer
                if (playbackBuffer != null) BufferConfig.bufferForPlaybackMs = playbackBuffer
                if (rebufferBuffer != null) BufferConfig.bufferForPlaybackAfterRebufferMs = rebufferBuffer
                if (backBuffer != null) BufferConfig.backBufferDurationMs = backBuffer
                
                Log.d(TAG, "Buffer config updated: maxBuffer=${BufferConfig.maxBufferMs}ms")
                result.success(true)
            }
            "getBufferConfig" -> {
                result.success(mapOf(
                    "minBufferMs" to BufferConfig.minBufferMs,
                    "maxBufferMs" to BufferConfig.maxBufferMs,
                    "bufferForPlaybackMs" to BufferConfig.bufferForPlaybackMs,
                    "bufferForPlaybackAfterRebufferMs" to BufferConfig.bufferForPlaybackAfterRebufferMs,
                    "backBufferDurationMs" to BufferConfig.backBufferDurationMs
                ))
            }
            else -> {
                val textureId = call.argument<Number>("textureId")?.toLong()
                if (textureId == null) {
                    result.error("INVALID_TEXTURE_ID", "Texture ID is required", null)
                    return
                }
                
                val player = videoPlayers.get(textureId)
                if (player == null) {
                    result.error("PLAYER_NOT_FOUND", "Player not found for texture ID: $textureId", null)
                    return
                }
                
                when (call.method) {
                    "dispose" -> {
                        player.dispose()
                        videoPlayers.remove(textureId)
                        result.success(null)
                    }
                    "setLooping" -> {
                        player.setLooping(call.argument<Boolean>("looping") ?: false)
                        result.success(null)
                    }
                    "setVolume" -> {
                        player.setVolume(call.argument<Double>("volume") ?: 1.0)
                        result.success(null)
                    }
                    "setPlaybackSpeed" -> {
                        player.setPlaybackSpeed(call.argument<Double>("speed") ?: 1.0)
                        result.success(null)
                    }
                    "play" -> {
                        player.play()
                        result.success(null)
                    }
                    "pause" -> {
                        player.pause()
                        result.success(null)
                    }
                    "seekTo" -> {
                        val position = call.argument<Number>("position")?.toLong() ?: 0L
                        player.seekTo(position)
                        result.success(null)
                    }
                    "position" -> {
                        result.success(player.getPosition())
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        for (i in 0 until videoPlayers.size()) {
            videoPlayers.valueAt(i).dispose()
        }
        videoPlayers.clear()
    }
}
