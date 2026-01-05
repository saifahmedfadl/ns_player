package com.nsplayer.ns_video_player_android

import android.content.Context
import android.net.Uri
import android.util.Log
import android.view.Surface
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
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry

/**
 * NsVideoPlayer
 * 
 * A video player implementation using ExoPlayer with custom buffer control.
 * This class creates ExoPlayer instances with configurable buffer settings.
 */
@UnstableApi
class NsVideoPlayer(
    private val context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: TextureRegistry.SurfaceTextureEntry,
    asset: String?,
    uri: String?,
    packageName: String?,
    formatHint: String?,
    httpHeaders: Map<String, String>
) : Player.Listener {

    companion object {
        private const val TAG = "NsVideoPlayer"
    }

    private val exoPlayer: ExoPlayer
    private var eventSink: EventChannel.EventSink? = null
    private var isInitialized = false
    private val surface: Surface

    init {
        Log.d(TAG, "Creating NsVideoPlayer with buffer config: maxBuffer=${BufferConfig.maxBufferMs}ms")
        
        // Create custom LoadControl with buffer settings
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                BufferConfig.minBufferMs,
                BufferConfig.maxBufferMs,
                BufferConfig.bufferForPlaybackMs,
                BufferConfig.bufferForPlaybackAfterRebufferMs
            )
            .setBackBuffer(
                BufferConfig.backBufferDurationMs,
                BufferConfig.retainBackBufferFromKeyframe
            )
            .build()

        // Create data source factory with HTTP headers
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(httpHeaders)
            .setAllowCrossProtocolRedirects(true)

        val dataSourceFactory: DataSource.Factory = DefaultDataSource.Factory(context, httpDataSourceFactory)

        // Create ExoPlayer with custom LoadControl
        exoPlayer = ExoPlayer.Builder(context)
            .setLoadControl(loadControl)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSourceFactory))
            .build()

        // Setup surface
        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer.setVideoSurface(surface)

        // Setup audio
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .setUsage(C.USAGE_MEDIA)
            .build()
        exoPlayer.setAudioAttributes(audioAttributes, true)

        // Add listener
        exoPlayer.addListener(this)

        // Setup event channel
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })

        // Prepare media
        val mediaItem = when {
            asset != null -> {
                val assetUri = if (packageName != null) {
                    Uri.parse("asset:///$packageName/$asset")
                } else {
                    Uri.parse("asset:///$asset")
                }
                MediaItem.fromUri(assetUri)
            }
            uri != null -> MediaItem.fromUri(Uri.parse(uri))
            else -> throw IllegalArgumentException("Either asset or uri must be provided")
        }

        exoPlayer.setMediaItem(mediaItem)
        exoPlayer.prepare()
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState == Player.STATE_READY && !isInitialized) {
            isInitialized = true
            sendInitialized()
        }
        
        when (playbackState) {
            Player.STATE_BUFFERING -> sendBufferingUpdate(true)
            Player.STATE_READY -> sendBufferingUpdate(false)
            Player.STATE_ENDED -> sendComplete()
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        eventSink?.error("VideoError", error.message, null)
    }

    override fun onVideoSizeChanged(videoSize: VideoSize) {
        if (isInitialized) {
            sendInitialized()
        }
    }

    private fun sendInitialized() {
        val videoSize = exoPlayer.videoSize
        eventSink?.success(mapOf(
            "event" to "initialized",
            "duration" to exoPlayer.duration,
            "width" to videoSize.width,
            "height" to videoSize.height
        ))
    }

    private fun sendBufferingUpdate(isBuffering: Boolean) {
        eventSink?.success(mapOf(
            "event" to "bufferingUpdate",
            "values" to listOf(listOf(0, exoPlayer.bufferedPosition.toInt()))
        ))
        
        if (isBuffering) {
            eventSink?.success(mapOf("event" to "bufferingStart"))
        } else {
            eventSink?.success(mapOf("event" to "bufferingEnd"))
        }
    }

    private fun sendComplete() {
        eventSink?.success(mapOf("event" to "completed"))
    }

    fun play() {
        exoPlayer.play()
    }

    fun pause() {
        exoPlayer.pause()
    }

    fun setLooping(looping: Boolean) {
        exoPlayer.repeatMode = if (looping) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(volume: Double) {
        exoPlayer.volume = volume.toFloat()
    }

    fun setPlaybackSpeed(speed: Double) {
        exoPlayer.playbackParameters = PlaybackParameters(speed.toFloat())
    }

    fun seekTo(position: Long) {
        exoPlayer.seekTo(position)
    }

    fun getPosition(): Long {
        return exoPlayer.currentPosition
    }

    fun dispose() {
        exoPlayer.removeListener(this)
        exoPlayer.release()
        surface.release()
        textureEntry.release()
        eventChannel.setStreamHandler(null)
    }
}
