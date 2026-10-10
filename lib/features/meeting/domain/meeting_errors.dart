enum MeetingErrorCode {
  authorizationError,
  capacityFull,
  permissionDenied,
  providerUnavailable,
  ended,
  removed,
  unavailable,
}

extension MeetingErrorCodeWire on MeetingErrorCode {
  String toWire() => switch (this) {
    MeetingErrorCode.authorizationError => 'authorization_error',
    MeetingErrorCode.capacityFull => 'capacity_full',
    MeetingErrorCode.permissionDenied => 'permission_denied',
    MeetingErrorCode.providerUnavailable => 'provider_unavailable',
    MeetingErrorCode.ended => 'ended',
    MeetingErrorCode.removed => 'removed',
    MeetingErrorCode.unavailable => 'unavailable',
  };

  static MeetingErrorCode fromWire(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'authorization_error':
      case 'authorizationerror':
      case 'unauthorized':
        return MeetingErrorCode.authorizationError;
      case 'capacity_full':
      case 'capacityfull':
        return MeetingErrorCode.capacityFull;
      case 'permission_denied':
      case 'permissiondenied':
        return MeetingErrorCode.permissionDenied;
      case 'provider_unavailable':
      case 'providerunavailable':
      case 'provider_error':
        return MeetingErrorCode.providerUnavailable;
      case 'ended':
        return MeetingErrorCode.ended;
      case 'removed':
        return MeetingErrorCode.removed;
      case 'unavailable':
        return MeetingErrorCode.unavailable;
      default:
        return MeetingErrorCode.unavailable;
    }
  }
}

/// Stable, localized copy for errors that may be shown by meeting UI.
class MeetingErrorMessage {
  const MeetingErrorMessage._();

  static String forCode(MeetingErrorCode code) => switch (code) {
    MeetingErrorCode.authorizationError => 'Tidak dapat mengakses meeting ini.',
    MeetingErrorCode.capacityFull => 'Meeting sudah penuh. Coba lagi nanti.',
    MeetingErrorCode.permissionDenied =>
      'Akses kamera atau mikrofon ditolak. Izinkan akses lalu coba lagi.',
    MeetingErrorCode.providerUnavailable =>
      'Layanan video sedang tidak tersedia. Coba lagi.',
    MeetingErrorCode.ended => 'Meeting sudah diakhiri oleh host.',
    MeetingErrorCode.removed => 'Anda dikeluarkan dari meeting.',
    MeetingErrorCode.unavailable =>
      'Video meeting belum tersedia karena backend belum dikonfigurasi.',
  };
}
