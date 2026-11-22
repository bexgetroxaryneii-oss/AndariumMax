// SPDX-License-Identifier: GPL-2.0-or-later

#include "in_process_service.hpp"

#include "capture_source.hpp"
#include "microphone_capture_source.hpp"
#include "period_clock.hpp"
#include "playback_sink.hpp"
#include "vhost_user_server.hpp"
#include "virtio_sound_device.hpp"

#if defined(__APPLE__)
#include <pthread/qos.h>
#endif

namespace uml::audio {

std::unique_ptr<uml::gpu::InProcessVhostUserService> makeInProcessService(
    const ServiceOptions& options)
{
    return std::make_unique<uml::gpu::InProcessVhostUserService>(
        "Virtio Sound", "uml-audio", [options] {
#if defined(__APPLE__)
            /* The factory runs on the service thread, which completes the
             * guest's periods. The guest's ALSA ring is short (Android's HAL
             * keeps four 5 ms periods), so a completion that waits behind
             * the vCPU threads, which can fill every core at the QoS this
             * thread would otherwise inherit, leaves the guest without room
             * and the output underruns.
             * The thread sleeps between periods and does little each time,
             * so it runs at the class the system gives interactive work. */
            (void)::pthread_set_qos_class_self_np(
                QOS_CLASS_USER_INTERACTIVE, 0);
#endif
            auto clock = makePeriodClock();
            auto sink = options.output == OutputMode::null
                ? makeNullPlaybackSink()
                : makeApplePlaybackSink(clock);
            auto capture = options.microphone
                ? makeMicrophoneCaptureSource(
                      options.microphone, makeAppleMicrophoneInput(), clock)
                : makeSilentCaptureSource();
            return std::make_unique<VirtioSoundDevice>(
                std::move(sink), std::move(capture), std::move(clock));
        });
}

} // namespace uml::audio
