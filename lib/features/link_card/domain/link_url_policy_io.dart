import 'dart:io';

import 'link_url_policy_common.dart';

typedef InternetAddressLookup =
    Future<List<InternetAddress>> Function(String host);

Future<void> ensurePublicDestination(
  Uri uri, {
  InternetAddressLookup lookup = InternetAddress.lookup,
}) async {
  final normalized = normalizeLinkUrl(uri.toString());
  final addresses = await lookup(normalized.host);
  if (addresses.isEmpty ||
      addresses.any((address) => !_isPublicAddress(address))) {
    throw const LinkUrlValidationException('Tujuan jaringan tidak aman.');
  }
}

bool _isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 4) {
    final a = bytes[0];
    final b = bytes[1];
    return a != 0 &&
        a != 10 &&
        a != 127 &&
        !(a == 169 && b == 254) &&
        !(a == 172 && b >= 16 && b <= 31) &&
        !(a == 192 && b == 168) &&
        a < 224;
  }
  if (bytes.every((byte) => byte == 0) ||
      (bytes.sublist(0, 15).every((byte) => byte == 0) && bytes[15] == 1)) {
    return false;
  }
  return bytes[0] != 0xff &&
      !(bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) &&
      (bytes[0] & 0xfe) != 0xfc;
}
