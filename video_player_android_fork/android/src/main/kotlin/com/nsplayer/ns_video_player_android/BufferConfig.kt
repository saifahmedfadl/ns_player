package com.nsplayer.ns_video_player_android

/**
 * Buffer configuration for ExoPlayer
 * These values control how much video data is buffered
 */
object BufferConfig {
    // Buffer durations in milliseconds
    var minBufferMs: Int = 2500
    var maxBufferMs: Int = 30000  // 30 seconds (reduced from default 50000)
    var bufferForPlaybackMs: Int = 1500
    var bufferForPlaybackAfterRebufferMs: Int = 3000
    var backBufferDurationMs: Int = 30000
    var retainBackBufferFromKeyframe: Boolean = false

    /**
     * Apply minimal buffer preset (15s max)
     * Best for saving bandwidth
     */
    fun applyMinimal() {
        minBufferMs = 2000
        maxBufferMs = 15000
        bufferForPlaybackMs = 1000
        bufferForPlaybackAfterRebufferMs = 2000
        backBufferDurationMs = 15000
    }

    /**
     * Apply low buffer preset (30s max)
     * Good balance between bandwidth and smoothness
     */
    fun applyLow() {
        minBufferMs = 2500
        maxBufferMs = 30000
        bufferForPlaybackMs = 1500
        bufferForPlaybackAfterRebufferMs = 3000
        backBufferDurationMs = 30000
    }

    /**
     * Apply medium buffer preset (60s max)
     * Smooth playback
     */
    fun applyMedium() {
        minBufferMs = 5000
        maxBufferMs = 60000
        bufferForPlaybackMs = 2500
        bufferForPlaybackAfterRebufferMs = 5000
        backBufferDurationMs = 60000
    }

    /**
     * Apply high buffer preset (120s max)
     * Best quality, high bandwidth usage
     */
    fun applyHigh() {
        minBufferMs = 15000
        maxBufferMs = 120000
        bufferForPlaybackMs = 5000
        bufferForPlaybackAfterRebufferMs = 10000
        backBufferDurationMs = 120000
    }
}
