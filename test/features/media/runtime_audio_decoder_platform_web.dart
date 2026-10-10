import 'package:audio_decoder/audio_decoder_platform_interface.dart';
import 'package:audio_decoder/audio_decoder_web.dart';

void registerRuntimeAudioDecoderPlatform() {
  AudioDecoderPlatform.instance = AudioDecoderWeb();
}
