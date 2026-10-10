import 'dart:io';

bool isPublicVideoHost(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null) return true;
  final bytes = address.rawAddress;
  if (bytes.length == 4) {
    return bytes[0] != 10 &&
        bytes[0] != 127 &&
        !(bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) &&
        !(bytes[0] == 192 && bytes[1] == 168);
  }
  return address.type != InternetAddressType.IPv6 ||
      (bytes.first & 0xfe) != 0xfc;
}
