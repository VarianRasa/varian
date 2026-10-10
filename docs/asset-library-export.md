# Asset Library export and licensing

The asset library keeps binary data in local storage or Supabase Storage. The
canvas document, project package metadata, and CRDT operations contain asset
references and provenance metadata, not embedded binary bytes.

## Project and portable packages

`AssetExportPolicy` is applied before a project package or portable package is
created:

- the default policy excludes assets without a durable local or remote
  reference;
- `allowedLicenses` is an exact allow-list; an asset without a license is
  matched as `unknown`;
- `includedAssetIds`, `excludedAssetIds`, and `includedKinds` provide explicit
  selection filters;
- thumbnails are omitted by default because they are derived references, not
  package payloads; set `includeThumbnails` only when the consumer needs the
  reference metadata;
- `includeMissingSources` can retain an unresolved catalog record for review,
  but it does not make a package portable.

A portable archive receives bytes through `assetBytes`, keyed by the same
`DocumentAsset.id` used in the manifest. The encoder verifies declared
checksums and rejects bytes for unknown asset IDs. It never fetches arbitrary
URLs while exporting.

Rendered exports such as PNG, JPEG, PDF, and video do not have a universal
metadata channel for license notices. The export UI must therefore keep the
source, creator, license, attribution, and license URL visible before export;
when a destination supports a sidecar or credits page, include the provenance
from the document asset metadata. A provider license remains the user's
responsibility to verify against the individual asset terms.

## Loss / portability report

Before presenting a portable package as complete, inspect
`DocumentPackageArchive`:

- `missingAssetIds` lists manifest assets for which no bytes were supplied;
- `invalidAssetIds` lists decoded files whose checksum does not match the
  archive manifest;
- `packageChecksumValid` reports whether the document package checksum is
  intact;
- `isPortable` is true only when the package checksum is valid and both asset
  lists are empty.

The archive manifest also records `embedded`, `sizeBytes`, `checksum`, and a
`portable` flag. A UI or export job must surface the affected asset IDs and
allow the user to add/relink the source, or explicitly continue with a
non-portable package. It must not silently replace a missing binary with a
preview URL or a machine-local path.

## Openverse provenance

Openverse items retain the provider asset ID, source URL, creator, license,
license URL, and attribution when saved to the project library. These values
remain metadata and are copied into the `DocumentAsset.metadata` reference on
canvas insertion. See [asset-library-sources.md](asset-library-sources.md) for
provider and proxy rules.
