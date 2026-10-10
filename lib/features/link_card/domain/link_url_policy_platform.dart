import 'link_url_policy_common.dart';

Future<void> ensurePublicDestination(Uri uri) async {
  normalizeLinkUrl(uri.toString());
}
