// Host audio output for the Windows route.
//
// A Windows guest opens a wave device and writes PCM into it. Rosetta used to
// accept those writes, complete the buffer immediately, and hand the guest a
// perfect ledger of frames nobody could hear - `lib/audio` calls that a
// `clocked_null_sink`. It is the right *fallback*, because a mixer that runs
// on a correct clock keeps the guest's timing honest, but it is not audio.
//
// This bridge is the audible half: one CoreAudio output queue, one byte ring,
// and counters that separate "the guest produced nothing" from "the host never
// asked". The second question is the one silence cannot answer on its own,
// which is why `callbacks_served` is a status field rather than a log line.

#ifndef ROSETTE_NATIVE_AUDIO_BRIDGE_H
#define ROSETTE_NATIVE_AUDIO_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct RosetteAudioOutputStatus {
    uint32_t open;
    uint32_t sample_rate;
    uint32_t channels;
    uint32_t bits_per_sample;
    uint32_t is_float;
    /// Bytes the guest handed to the sink.
    uint64_t submitted_bytes;
    /// Bytes the host device actually consumed.
    uint64_t played_bytes;
    /// Bytes dropped because the ring was full. A steady non-zero value means
    /// the guest is ahead of the device, which is a pacing problem and not a
    /// silence problem.
    uint64_t dropped_bytes;
    /// Callbacks the device served that found the ring short. A steady
    /// non-zero value means the opposite: the guest is behind the device.
    uint64_t underruns;
    /// Callbacks the device served at all. Zero here is the one reading that
    /// proves the host never asked for audio.
    uint64_t callbacks_served;
    /// The last non-zero OSStatus from CoreAudio, or 0.
    int32_t last_status;
} RosetteAudioOutputStatus;

/// Open the host output device for a guest wave format.
///
/// Returns 1 on success and 0 when the format is unsupported or CoreAudio
/// refused. A refusal is not an error the caller has to escalate: the wave
/// device stays open and falls back to the clocked null sink, and the status
/// says which one is in use.
int rosette_native_audio_open(uint32_t sample_rate,
                              uint32_t channels,
                              uint32_t bits_per_sample,
                              uint32_t is_float);

/// Hand `length` bytes of interleaved PCM to the device. Returns the number of
/// bytes accepted; the rest were dropped because the ring was full.
uint32_t rosette_native_audio_submit(const void *data, uint32_t length);

/// Stop and release the device. Safe to call when nothing is open.
void rosette_native_audio_close(void);

RosetteAudioOutputStatus rosette_native_audio_status(void);

#ifdef __cplusplus
}
#endif

#endif  // ROSETTE_NATIVE_AUDIO_BRIDGE_H
