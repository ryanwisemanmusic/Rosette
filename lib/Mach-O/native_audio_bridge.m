// CoreAudio output for the Windows route. See native_audio_bridge.h for why
// this exists beside the clocked null sink rather than replacing it.
//
// ## Shape
//
// One `AudioQueue` with a small fixed set of buffers, fed from a byte ring the
// guest's `waveOutWrite` fills. The queue's callback runs on CoreAudio's own
// thread, so the ring is behind a plain mutex: the critical sections are two
// `memcpy`s of at most one buffer, and a lock-free ring here would buy nothing
// but a harder correctness argument.
//
// ## Underrun policy
//
// A callback that finds the ring short fills the remainder with silence and
// enqueues the buffer anyway. Stalling the queue instead would make the device
// stop asking, and a device that has stopped asking looks exactly like a guest
// that stopped producing - which is the confusion this whole file exists to
// prevent. The underrun is counted instead, so the two are distinguishable.

#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>
#import <string.h>

#include "native_audio_bridge.h"

// Three buffers is enough to keep the device fed across a scheduling hiccup
// without adding latency the guest will notice as lag.
#define ROSETTE_AUDIO_BUFFER_COUNT 3
// 20 ms at 48 kHz stereo float is 7,680 bytes; 6 channels is 23,040. Round up
// so a 5.1 frame fits in one buffer.
#define ROSETTE_AUDIO_BUFFER_BYTES 24576
// Roughly a quarter second of 5.1 float at 48 kHz. Large enough that a guest
// which bursts a few frames is not dropped, small enough that a guest running
// ahead is reported rather than buffered into minutes of latency.
#define ROSETTE_AUDIO_RING_BYTES (24576 * 12)

typedef struct RosetteAudioState {
    pthread_mutex_t lock;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[ROSETTE_AUDIO_BUFFER_COUNT];
    unsigned char ring[ROSETTE_AUDIO_RING_BYTES];
    uint32_t ring_head;
    uint32_t ring_used;
    uint32_t frame_bytes;
    RosetteAudioOutputStatus status;
    int started;
} RosetteAudioState;

static RosetteAudioState g_audio = {
    .lock = PTHREAD_MUTEX_INITIALIZER,
};

static uint32_t rosette_ring_read_locked(unsigned char *destination, uint32_t wanted) {
    uint32_t available = g_audio.ring_used < wanted ? g_audio.ring_used : wanted;
    uint32_t remaining = available;
    uint32_t offset = 0;
    while (remaining != 0) {
        uint32_t contiguous = ROSETTE_AUDIO_RING_BYTES - g_audio.ring_head;
        uint32_t chunk = remaining < contiguous ? remaining : contiguous;
        memcpy(destination + offset, g_audio.ring + g_audio.ring_head, chunk);
        g_audio.ring_head = (g_audio.ring_head + chunk) % ROSETTE_AUDIO_RING_BYTES;
        g_audio.ring_used -= chunk;
        offset += chunk;
        remaining -= chunk;
    }
    return available;
}

static uint32_t rosette_ring_write_locked(const unsigned char *source, uint32_t length) {
    uint32_t free_bytes = ROSETTE_AUDIO_RING_BYTES - g_audio.ring_used;
    uint32_t accepted = length < free_bytes ? length : free_bytes;
    uint32_t remaining = accepted;
    uint32_t offset = 0;
    uint32_t tail = (g_audio.ring_head + g_audio.ring_used) % ROSETTE_AUDIO_RING_BYTES;
    while (remaining != 0) {
        uint32_t contiguous = ROSETTE_AUDIO_RING_BYTES - tail;
        uint32_t chunk = remaining < contiguous ? remaining : contiguous;
        memcpy(g_audio.ring + tail, source + offset, chunk);
        tail = (tail + chunk) % ROSETTE_AUDIO_RING_BYTES;
        offset += chunk;
        remaining -= chunk;
    }
    g_audio.ring_used += accepted;
    return accepted;
}

static void rosette_audio_callback(void *user_data, AudioQueueRef queue, AudioQueueBufferRef buffer) {
    (void)user_data;
    unsigned char *bytes = (unsigned char *)buffer->mAudioData;
    uint32_t capacity = buffer->mAudioDataBytesCapacity;

    pthread_mutex_lock(&g_audio.lock);
    g_audio.status.callbacks_served += 1;
    uint32_t filled = rosette_ring_read_locked(bytes, capacity);
    if (filled < capacity) {
        // Silence, not a short buffer: a short buffer would let the queue
        // drain and stop asking.
        memset(bytes + filled, 0, capacity - filled);
        g_audio.status.underruns += 1;
    }
    g_audio.status.played_bytes += filled;
    pthread_mutex_unlock(&g_audio.lock);

    buffer->mAudioDataByteSize = capacity;
    OSStatus status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
    if (status != noErr) {
        pthread_mutex_lock(&g_audio.lock);
        g_audio.status.last_status = (int32_t)status;
        pthread_mutex_unlock(&g_audio.lock);
    }
}

int rosette_native_audio_open(uint32_t sample_rate,
                              uint32_t channels,
                              uint32_t bits_per_sample,
                              uint32_t is_float) {
    if (sample_rate == 0 || channels == 0 || channels > 8) return 0;
    if (bits_per_sample != 8 && bits_per_sample != 16 && bits_per_sample != 32) return 0;
    if (is_float && bits_per_sample != 32) return 0;

    pthread_mutex_lock(&g_audio.lock);
    if (g_audio.status.open) {
        int same = g_audio.status.sample_rate == sample_rate &&
                   g_audio.status.channels == channels &&
                   g_audio.status.bits_per_sample == bits_per_sample &&
                   g_audio.status.is_float == is_float;
        pthread_mutex_unlock(&g_audio.lock);
        // Re-opening with a different format is a guest bug, not something to
        // paper over by silently keeping the old device.
        return same ? 1 : 0;
    }
    pthread_mutex_unlock(&g_audio.lock);

    AudioStreamBasicDescription format;
    memset(&format, 0, sizeof(format));
    format.mSampleRate = (Float64)sample_rate;
    format.mFormatID = kAudioFormatLinearPCM;
    format.mFormatFlags = kLinearPCMFormatFlagIsPacked;
    if (is_float) {
        format.mFormatFlags |= kLinearPCMFormatFlagIsFloat;
    } else if (bits_per_sample > 8) {
        // 8-bit PCM is unsigned on Windows; everything wider is signed.
        format.mFormatFlags |= kLinearPCMFormatFlagIsSignedInteger;
    }
    format.mChannelsPerFrame = channels;
    format.mBitsPerChannel = bits_per_sample;
    format.mFramesPerPacket = 1;
    format.mBytesPerFrame = channels * (bits_per_sample / 8);
    format.mBytesPerPacket = format.mBytesPerFrame;

    AudioQueueRef queue = NULL;
    OSStatus status = AudioQueueNewOutput(&format, rosette_audio_callback, NULL, NULL, NULL, 0, &queue);
    if (status != noErr || queue == NULL) {
        pthread_mutex_lock(&g_audio.lock);
        g_audio.status.last_status = (int32_t)status;
        pthread_mutex_unlock(&g_audio.lock);
        return 0;
    }

    pthread_mutex_lock(&g_audio.lock);
    g_audio.queue = queue;
    g_audio.ring_head = 0;
    g_audio.ring_used = 0;
    g_audio.frame_bytes = format.mBytesPerFrame;
    g_audio.status.open = 1;
    g_audio.status.sample_rate = sample_rate;
    g_audio.status.channels = channels;
    g_audio.status.bits_per_sample = bits_per_sample;
    g_audio.status.is_float = is_float;
    g_audio.status.submitted_bytes = 0;
    g_audio.status.played_bytes = 0;
    g_audio.status.dropped_bytes = 0;
    g_audio.status.underruns = 0;
    g_audio.status.callbacks_served = 0;
    g_audio.status.last_status = 0;
    pthread_mutex_unlock(&g_audio.lock);

    for (int index = 0; index < ROSETTE_AUDIO_BUFFER_COUNT; ++index) {
        AudioQueueBufferRef buffer = NULL;
        status = AudioQueueAllocateBuffer(queue, ROSETTE_AUDIO_BUFFER_BYTES, &buffer);
        if (status != noErr || buffer == NULL) {
            pthread_mutex_lock(&g_audio.lock);
            g_audio.status.last_status = (int32_t)status;
            pthread_mutex_unlock(&g_audio.lock);
            rosette_native_audio_close();
            return 0;
        }
        g_audio.buffers[index] = buffer;
        // Prime with silence so the queue has something to start on; the
        // callback takes over from there.
        memset(buffer->mAudioData, 0, ROSETTE_AUDIO_BUFFER_BYTES);
        buffer->mAudioDataByteSize = ROSETTE_AUDIO_BUFFER_BYTES;
        status = AudioQueueEnqueueBuffer(queue, buffer, 0, NULL);
        if (status != noErr) {
            pthread_mutex_lock(&g_audio.lock);
            g_audio.status.last_status = (int32_t)status;
            pthread_mutex_unlock(&g_audio.lock);
            rosette_native_audio_close();
            return 0;
        }
    }

    status = AudioQueueStart(queue, NULL);
    if (status != noErr) {
        pthread_mutex_lock(&g_audio.lock);
        g_audio.status.last_status = (int32_t)status;
        pthread_mutex_unlock(&g_audio.lock);
        rosette_native_audio_close();
        return 0;
    }
    g_audio.started = 1;
    return 1;
}

uint32_t rosette_native_audio_submit(const void *data, uint32_t length) {
    if (data == NULL || length == 0) return 0;
    pthread_mutex_lock(&g_audio.lock);
    if (!g_audio.status.open) {
        pthread_mutex_unlock(&g_audio.lock);
        return 0;
    }
    uint32_t accepted = rosette_ring_write_locked((const unsigned char *)data, length);
    g_audio.status.submitted_bytes += accepted;
    g_audio.status.dropped_bytes += (length - accepted);
    pthread_mutex_unlock(&g_audio.lock);
    return accepted;
}

void rosette_native_audio_close(void) {
    AudioQueueRef queue = NULL;
    pthread_mutex_lock(&g_audio.lock);
    queue = g_audio.queue;
    g_audio.queue = NULL;
    g_audio.status.open = 0;
    g_audio.ring_head = 0;
    g_audio.ring_used = 0;
    for (int index = 0; index < ROSETTE_AUDIO_BUFFER_COUNT; ++index) {
        g_audio.buffers[index] = NULL;
    }
    int was_started = g_audio.started;
    g_audio.started = 0;
    pthread_mutex_unlock(&g_audio.lock);

    if (queue != NULL) {
        if (was_started) AudioQueueStop(queue, true);
        AudioQueueDispose(queue, true);
    }
}

RosetteAudioOutputStatus rosette_native_audio_status(void) {
    pthread_mutex_lock(&g_audio.lock);
    RosetteAudioOutputStatus snapshot = g_audio.status;
    pthread_mutex_unlock(&g_audio.lock);
    return snapshot;
}
