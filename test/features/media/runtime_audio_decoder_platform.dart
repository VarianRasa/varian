import 'runtime_audio_decoder_platform_stub.dart'
    if (dart.library.html) 'runtime_audio_decoder_platform_web.dart'
    as platform;

void registerRuntimeAudioDecoderPlatform() =>
    platform.registerRuntimeAudioDecoderPlatform();
