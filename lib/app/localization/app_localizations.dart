import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

class CreativeStudioLocalizations {
  final Locale locale;

  const CreativeStudioLocalizations(this.locale);

  static const supportedLocales = [Locale('en'), Locale('id')];
  static const delegate = _CreativeStudioLocalizationsDelegate();

  bool get isIndonesian => locale.languageCode == 'id';

  String get appTitle =>
      isIndonesian ? 'Creative Canvas Studio' : 'Creative Canvas Studio';
  String get importTitle =>
      isIndonesian ? 'Impor diagram / dokumen' : 'Import diagram / document';
  String get exportTitle => isIndonesian ? 'Ekspor' : 'Export';
  String get save => isIndonesian ? 'Simpan' : 'Save';
  String get cancel => isIndonesian ? 'Batal' : 'Cancel';
  String get close => isIndonesian ? 'Tutup' : 'Close';
  String get retry => isIndonesian ? 'Coba lagi' : 'Retry';
  String get unavailable => isIndonesian ? 'Tidak tersedia' : 'Unavailable';
  String get offline => isIndonesian ? 'Offline' : 'Offline';
  String get projectLibraryUnavailable => isIndonesian
      ? 'LIBRARY PROYEK TIDAK TERSEDIA'
      : 'PROJECT LIBRARY UNAVAILABLE';
  String get projectLibraryUnavailableDescription => isIndonesian
      ? 'Library proyek lokal tidak dapat dibaca. Coba lagi tanpa kehilangan pekerjaan lokal.'
      : 'The local project library could not be read. Retry without losing local work.';
  String get projectLoading =>
      isIndonesian ? 'Memuat proyek' : 'Loading project';
  String get projectNotFound =>
      isIndonesian ? 'Proyek tidak ditemukan' : 'Project not found';
  String get projectUnavailable =>
      isIndonesian ? 'Proyek tidak tersedia' : 'Project unavailable';
  String get projectNotFoundDescription => isIndonesian
      ? 'Proyek lokal ini mungkin sudah dipindahkan atau dihapus. Kembali ke library untuk memilih proyek lain.'
      : 'This local project may have been moved or deleted. Return to the library to choose another project.';
  String get projectUnavailableDescription => isIndonesian
      ? 'Proyek tidak dapat dimuat sekarang. Coba lagi; pekerjaan lokal yang tersimpan tetap dipertahankan.'
      : 'The project could not be loaded right now. Retry; saved local work is preserved.';
  String get projectAuthRequired => isIndonesian
      ? 'Masuk diperlukan untuk membuka proyek kolaborasi'
      : 'Sign in required for this collaboration project';
  String get projectAuthRequiredDescription => isIndonesian
      ? 'Masuk kembali untuk memuat data cloud proyek ini. Proyek lokal lain tetap tersedia.'
      : 'Sign in again to load this project’s cloud data. Other local projects remain available.';
  String get projectMembershipRequired => isIndonesian
      ? 'Gabung ulang untuk membuka proyek kolaborasi'
      : 'Rejoin to open this collaboration project';
  String get projectMembershipRequiredDescription => isIndonesian
      ? 'Sesi akun sebelumnya telah dibersihkan dari perangkat ini. Masukkan Room ID lagi untuk memulihkan akses; proyek lokal tetap aman.'
      : 'The previous account session was cleared from this device. Enter the Room ID again to restore access; local projects remain safe.';
  String get projectRejoinAction =>
      isIndonesian ? 'GABUNG ULANG' : 'REJOIN ROOM';
  String get projectActionUnavailable => isIndonesian
      ? 'Aksi proyek tidak tersedia sekarang. Coba lagi.'
      : 'This project action is unavailable right now. Try again.';
  String get homeRefreshProjects =>
      isIndonesian ? 'Muat ulang proyek' : 'Refresh projects';
  String get homeJoinCollaborationRoom =>
      isIndonesian ? 'Gabung ke ruang kolaborasi' : 'Join collaboration room';
  String get homeBackendIntegrations =>
      isIndonesian ? 'Integrasi backend' : 'Backend integrations';
  String get homeEditCollaborationProfile =>
      isIndonesian ? 'Edit profil kolaborasi' : 'Edit collaboration profile';
  String get homeSignInToCollaborate =>
      isIndonesian ? 'Masuk untuk berkolaborasi' : 'Sign in to collaborate';
  String get homeSignOut => isIndonesian ? 'Keluar' : 'Sign out';
  String get homeMoreActions => isIndonesian ? 'Aksi lainnya' : 'More actions';
  String get homeProjectLibraryTitle =>
      isIndonesian ? 'Pustaka proyek' : 'Project library';
  String get homeProjectLibraryDescription => isIndonesian
      ? 'Semua proyek canvas Anda di satu tempat.'
      : 'Your canvas projects, in one place.';
  String get homeTemplateAction => isIndonesian ? 'TEMPLATE' : 'TEMPLATE';
  String get homeNewDocumentAction =>
      isIndonesian ? 'DOKUMEN BARU' : 'NEW DOCUMENT';
  String get homeSearchLabel =>
      isIndonesian ? 'Cari dokumen' : 'Search documents';
  String get homeSearchHint => isIndonesian
      ? 'Cari berdasarkan nama dokumen'
      : 'Search by document name';
  String get homeSortLabel => isIndonesian ? 'Urutkan' : 'Sort by';
  String get homeSortLastModified =>
      isIndonesian ? 'Perubahan terbaru' : 'Last modified';
  String get homeSortName => isIndonesian ? 'Nama' : 'Name';
  String get homeSortCreated => isIndonesian ? 'Dibuat' : 'Created';
  String get homeClearFilters =>
      isIndonesian ? 'HAPUS FILTER' : 'CLEAR FILTERS';
  String get homeEmptyTrashAction =>
      isIndonesian ? 'KOSONGKAN SAMPAH' : 'EMPTY TRASH';
  String get homeMoveAllToTrashAction =>
      isIndonesian ? 'PINDAHKAN SEMUA KE SAMPAH' : 'MOVE ALL TO TRASH';
  String get homeNoMatchesTitle =>
      isIndonesian ? 'TIDAK ADA HASIL' : 'NO MATCHES';
  String homeNoMatchesMessage(String query) => isIndonesian
      ? 'Tidak ada dokumen yang cocok dengan "$query" di tampilan ini.'
      : 'No documents match "$query" in this view.';
  String get homeClearSearch =>
      isIndonesian ? 'HAPUS PENCARIAN' : 'CLEAR SEARCH';
  String get homeStatusActive => isIndonesian ? 'Aktif' : 'Active';
  String get homeStatusArchived => isIndonesian ? 'Arsip' : 'Archived';
  String get homeStatusTrash => isIndonesian ? 'Sampah' : 'Trash';
  String get homeNoActiveDocumentsTitle =>
      isIndonesian ? 'BELUM ADA DOKUMEN AKTIF' : 'NO ACTIVE DOCUMENTS';
  String get homeArchiveEmptyTitle =>
      isIndonesian ? 'ARSIP KOSONG' : 'ARCHIVE EMPTY';
  String get homeTrashEmptyTitle =>
      isIndonesian ? 'SAMPAH KOSONG' : 'TRASH IS EMPTY';
  String get homeNoActiveDocumentsMessage => isIndonesian
      ? 'Mulai dengan canvas kosong atau gunakan template untuk membentuk ide berikutnya.'
      : 'Start with a blank canvas or use a template to shape your next idea.';
  String get homeArchivedDocumentsMessage => isIndonesian
      ? 'Dokumen yang diarsipkan tetap di sini sampai Anda siap memulihkannya.'
      : 'Archived documents stay here until you are ready to bring them back.';
  String get homeTrashedDocumentsMessage => isIndonesian
      ? 'Dokumen yang dihapus dapat dipulihkan dari sini sebelum dihapus permanen.'
      : 'Deleted documents can be restored from here before they are permanently removed.';
  String get homeUseTemplateAction =>
      isIndonesian ? 'GUNAKAN TEMPLATE' : 'USE TEMPLATE';
  String get homeViewActiveDocumentsAction =>
      isIndonesian ? 'LIHAT DOKUMEN AKTIF' : 'VIEW ACTIVE DOCUMENTS';
  String get homeBackToLibraryAction =>
      isIndonesian ? 'KEMBALI KE PUSTAKA' : 'BACK TO LIBRARY';
  String get homeRefreshTooltip => homeRefreshProjects;
  String homeStatusSemanticsLabel(String status, int count) =>
      isIndonesian ? '$status, $count dokumen' : '$status, $count documents';
  String homeMoveDocumentsToTrashSuccess(int count) => isIndonesian
      ? '$count dokumen dipindahkan ke Sampah di perangkat ini.'
      : '$count documents moved to this device’s Trash.';
  String homeEmptyTrashSuccess(int count) => isIndonesian
      ? '$count dokumen lokal dihapus permanen.'
      : '$count local documents permanently deleted.';
  String get homeDocumentRenamedSuccess =>
      isIndonesian ? 'Nama dokumen diubah.' : 'Document renamed.';
  String get homeDocumentUnpinnedSuccess =>
      isIndonesian ? 'Sematan dokumen dilepas.' : 'Document unpinned.';
  String get homeDocumentPinnedSuccess =>
      isIndonesian ? 'Dokumen disematkan.' : 'Document pinned.';
  String get homeDocumentArchivedSuccess =>
      isIndonesian ? 'Dokumen diarsipkan.' : 'Document archived.';
  String get homeDocumentRestoredSuccess =>
      isIndonesian ? 'Dokumen dipulihkan.' : 'Document restored.';
  String get homeDocumentDuplicatedSuccess =>
      isIndonesian ? 'Dokumen diduplikasi.' : 'Document duplicated.';
  String get homeDocumentDeletedSuccess => isIndonesian
      ? 'Dokumen dipindahkan ke Sampah.'
      : 'Document moved to Trash.';
  String get homeDocumentPermanentlyDeletedSuccess => isIndonesian
      ? 'Dokumen dihapus permanen.'
      : 'Document permanently deleted.';

  String homeOpenDocumentSemanticsLabel(String name) =>
      isIndonesian ? 'Buka dokumen $name' : 'Open document $name';
  String get homeProjectActionsTooltip =>
      isIndonesian ? 'Aksi proyek' : 'Project actions';
  String get homeProjectPinAction => isIndonesian ? 'Sematkan' : 'Pin';
  String get homeProjectUnpinAction => isIndonesian ? 'Lepas sematan' : 'Unpin';
  String get homeProjectRenameAction => isIndonesian ? 'Ubah nama' : 'Rename';
  String get homeProjectDuplicateAction =>
      isIndonesian ? 'Duplikat' : 'Duplicate';
  String get homeProjectRestoreAction => isIndonesian ? 'Pulihkan' : 'Restore';
  String get homeProjectDeletePermanentlyAction =>
      isIndonesian ? 'Hapus permanen' : 'Delete permanently';
  String get homeProjectDeleteAction => isIndonesian ? 'Hapus' : 'Delete';
  String get homeProjectArchiveAction => isIndonesian ? 'Arsipkan' : 'Archive';
  String get homeProjectAdoptAction =>
      isIndonesian ? 'Adopsi ke cloud' : 'Adopt to cloud';
  String get homeProjectAdoptTitle =>
      isIndonesian ? 'Adopsi proyek ke cloud?' : 'Adopt project to cloud?';
  String homeProjectAdoptDescription(String name) => isIndonesian
      ? '“$name” akan diunggah dan dimiliki oleh akun cloud yang sedang masuk. Salinan lokal tetap tersedia.'
      : '“$name” will be uploaded and owned by the signed-in cloud account. Your local copy remains available.';
  String get homeProjectAdoptConfirm =>
      isIndonesian ? 'ADOPSI KE CLOUD' : 'ADOPT TO CLOUD';
  String get homeProjectAdoptSuccess =>
      isIndonesian ? 'Proyek diadopsi ke cloud.' : 'Project adopted to cloud.';
  String get homeProjectAdoptFailure => isIndonesian
      ? 'Proyek tidak dapat diadopsi. Data lokal tetap aman; periksa akun dan coba lagi.'
      : 'Project could not be adopted. Local data is safe; verify the account and retry.';
  String get homeProjectAdoptRequiresSignIn => isIndonesian
      ? 'Masuk ke akun cloud sebelum mengadopsi proyek.'
      : 'Sign in to a cloud account before adopting a project.';
  String homeProjectModifiedLabel(String date) =>
      isIndonesian ? 'DIUBAH $date' : 'MODIFIED $date';
  String homeProjectCollaborationRoomLabel(String roomCode, String role) {
    if (!isIndonesian) return 'ROOM $roomCode / ${role.toUpperCase()}';
    final localizedRole = switch (role.toLowerCase()) {
      'owner' => 'PEMILIK',
      'editor' => 'EDITOR',
      'commenter' => 'KOMENTATOR',
      'viewer' => 'PENONTON',
      'member' => 'ANGGOTA',
      _ => role.toUpperCase(),
    };
    return 'RUANG $roomCode / $localizedRole';
  }

  String get homeRenameDocumentSemanticsLabel =>
      isIndonesian ? 'Ubah nama dokumen' : 'Rename document';
  String get homeRenameDocumentTitle =>
      isIndonesian ? 'Ubah nama dokumen' : 'Rename document';
  String get homeDocumentNameLabel =>
      isIndonesian ? 'Nama dokumen' : 'Document name';
  String get homeDocumentNameHint =>
      isIndonesian ? 'Masukkan nama dokumen' : 'Enter document name';

  String get homeConfirmEmptyTrashSemanticsLabel =>
      isIndonesian ? 'Konfirmasi pengosongan sampah' : 'Confirm empty trash';
  String get homeConfirmMoveAllToTrashSemanticsLabel => isIndonesian
      ? 'Konfirmasi pemindahan semua dokumen ke sampah'
      : 'Confirm moving all documents to trash';
  String get homeDeleteAllPermanentlyTitle =>
      isIndonesian ? 'Hapus semua secara permanen?' : 'Delete all permanently?';
  String get homeMoveAllToTrashTitle =>
      isIndonesian ? 'Pindahkan semua ke Sampah?' : 'Move all to Trash?';
  String homeDeleteAllPermanentlyDescription(int count) => isIndonesian
      ? 'Tindakan ini menghapus permanen $count dokumen lokal beserta riwayatnya dari perangkat ini. Workspace cloud bersama tidak dihapus. Tindakan ini tidak dapat dibatalkan.'
      : 'This permanently removes $count local documents and their history from this device. Shared cloud workspaces are not deleted. This action cannot be undone.';
  String homeMoveAllToTrashDescription(int count, String status) => isIndonesian
      ? 'Tindakan ini memindahkan $count dokumen $status ke Sampah di perangkat ini. Anda dapat memulihkannya nanti. Workspace cloud bersama tidak berubah.'
      : 'This moves $count $status documents to this device’s Trash. You can restore them later. Shared cloud workspaces are not changed.';
  String get homeDeleteConfirmationWord => isIndonesian ? 'HAPUS' : 'DELETE';
  String homeDeleteConfirmationLabel(String word) => isIndonesian
      ? 'Ketik $word untuk mengonfirmasi'
      : 'Type $word to confirm';
  String get homeDeleteConfirmationHint => homeDeleteConfirmationWord;
  String get homeDeleteAllPermanentlyAction =>
      isIndonesian ? 'HAPUS SEMUA PERMANEN' : 'DELETE ALL PERMANENTLY';
  String get homeMoveAllToTrashConfirmAction =>
      isIndonesian ? 'PINDAHKAN SEMUA KE SAMPAH' : 'MOVE ALL TO TRASH';
  String get homeConfirmPermanentDocumentDeleteSemanticsLabel => isIndonesian
      ? 'Konfirmasi penghapusan permanen dokumen'
      : 'Confirm permanent document deletion';
  String get homeConfirmMoveDocumentToTrashSemanticsLabel => isIndonesian
      ? 'Konfirmasi pemindahan dokumen ke sampah'
      : 'Confirm moving document to trash';
  String get homeDeleteDocumentPermanentlyTitle =>
      isIndonesian ? 'Hapus permanen?' : 'Delete permanently?';
  String get homeMoveDocumentToTrashTitle =>
      isIndonesian ? 'Pindahkan ke Sampah?' : 'Move to Trash?';
  String get homeDeleteDocumentPermanentlyDescription => isIndonesian
      ? 'Dokumen lokal dan riwayatnya akan dihapus dari perangkat ini. Workspace cloud bersama tidak dihapus. Tindakan ini tidak dapat dibatalkan.'
      : 'This removes the local document and its history from this device. Shared cloud workspaces are not deleted. This action cannot be undone.';
  String get homeMoveDocumentToTrashDescription => isIndonesian
      ? 'Dokumen lokal akan dipindahkan ke Sampah di perangkat ini. Anda dapat memulihkannya nanti dari tab Sampah. Workspace cloud bersama tidak berubah.'
      : 'The local document will move to this device’s Trash. You can restore it later from the Trash tab. Shared cloud workspaces are not changed.';
  String get homeDeleteDocumentPermanentlyAction =>
      isIndonesian ? 'HAPUS PERMANEN' : 'DELETE PERMANENTLY';
  String get homeMoveDocumentToTrashAction =>
      isIndonesian ? 'PINDAHKAN KE SAMPAH' : 'MOVE TO TRASH';
  String get onboardingLocalTitle =>
      isIndonesian ? 'Bekerja lokal terlebih dahulu' : 'Work locally first';
  String get onboardingLocalBody => isIndonesian
      ? 'Buat dan edit proyek di perangkat ini meskipun layanan cloud tidak tersedia.'
      : 'Create and edit projects on this device even when cloud services are unavailable.';
  String get onboardingCreateTitle =>
      isIndonesian ? 'Buat canvas berikutnya' : 'Create your next canvas';
  String get onboardingCreateBody => isIndonesian
      ? 'Mulai dengan dokumen kosong atau template, lalu buka library proyek kapan saja.'
      : 'Start with a blank document or a template, then open the project library whenever you need it.';
  String get onboardingToolsTitle =>
      isIndonesian ? 'Kembali ke alat kerja' : 'Return to the tools';
  String get onboardingToolsBody => isIndonesian
      ? 'Gunakan menu bantuan untuk membuka panduan ini lagi, dan buka pengaturan saat siap menghubungkan integrasi.'
      : 'Use the help menu for this guide again, and open settings when you are ready to connect integrations.';
  String get onboardingLocalNote => isIndonesian
      ? 'Workspace lokal tetap tersedia saat Anda menentukan kapan ingin menghubungkan cloud.'
      : 'Your local workspace stays available while you decide when to connect the cloud.';
  String get onboardingSkip => isIndonesian ? 'LEWATI DULU' : 'SKIP FOR NOW';
  String get onboardingNext => isIndonesian ? 'LANJUT' : 'NEXT';
  String get onboardingStart =>
      isIndonesian ? 'MULAI BERKARYA' : 'START CREATING';
  String get onboardingSemanticsLabel => isIndonesian
      ? 'Panduan workspace lokal terlebih dahulu'
      : 'Local-first onboarding';
  String get workspaceHelpLabel =>
      isIndonesian ? 'Bantuan workspace' : 'Workspace help';
  String get workspaceHelpClose =>
      isIndonesian ? 'Tutup bantuan workspace' : 'Close workspace help';
  String get workspaceQuickStart =>
      isIndonesian ? 'Mulai cepat' : 'Quick start';
  String get workspaceHelpStepOne => isIndonesian
      ? 'Buat canvas kosong atau mulai dari template.'
      : 'Create a blank canvas or start from a template.';
  String get workspaceHelpStepTwo => isIndonesian
      ? 'Tambahkan node, media, dan koneksi untuk membentuk ide Anda.'
      : 'Add nodes, media, and connections to shape your idea.';
  String get workspaceHelpStepThree => isIndonesian
      ? 'Perubahan tersimpan otomatis. Buka kartu untuk melanjutkan.'
      : 'Changes save automatically. Open a card to continue.';
  String get workspaceHelpStepFour => isIndonesian
      ? 'Gunakan Bagikan atau Publikasikan saat canvas siap.'
      : 'Use Share or Publish when your canvas is ready.';
  String get workspaceResumeGuide =>
      isIndonesian ? 'LANJUTKAN PANDUAN' : 'RESUME GUIDE';
  String get settingsTitle => isIndonesian ? 'Pengaturan' : 'Settings';
  String get settingsOverview => isIndonesian ? 'Umum' : 'Overview';
  String get settingsAppearance => isIndonesian ? 'Tampilan' : 'Appearance';
  String get settingsAccessibility =>
      isIndonesian ? 'Aksesibilitas' : 'Accessibility';
  String get settingsIntegrations =>
      isIndonesian ? 'Integrasi' : 'Integrations';
  String get settingsLocalFirstDescription => isIndonesian
      ? 'Pengaturan perangkat dan workspace disimpan secara lokal terlebih dahulu.'
      : 'Device and workspace settings are stored locally first.';
  String get settingsReadinessDescription => isIndonesian
      ? 'Nilai tersimpan tetap dipertahankan saat penyimpanan atau layanan cloud belum siap.'
      : 'Saved values are retained while storage or cloud services are not ready.';
  String get settingsLoading =>
      isIndonesian ? 'Memuat pengaturan' : 'Loading settings';
  String get settingsUnavailable =>
      isIndonesian ? 'Pengaturan tidak tersedia' : 'Settings unavailable';
  String get settingsUnavailableDescription => isIndonesian
      ? 'Pengaturan lokal belum siap. Coba lagi; pekerjaan lokal tetap dipertahankan.'
      : 'Local settings are not ready. Retry; local work is preserved.';
  String get settingsReducedMotion =>
      isIndonesian ? 'Kurangi animasi' : 'Reduced motion';
  String get settingsHighContrast =>
      isIndonesian ? 'Kontras tinggi' : 'High contrast';
  String get settingsForceRtl =>
      isIndonesian ? 'Paksa arah kanan-ke-kiri' : 'Force right-to-left layout';
  String get settingsLargerText =>
      isIndonesian ? 'Teks lebih besar' : 'Larger text';
  String get recentAuditActivity =>
      isIndonesian ? 'Aktivitas audit terbaru' : 'Recent audit activity';
  String get cloudDeletionSection =>
      isIndonesian ? 'Permintaan penghapusan cloud' : 'Cloud deletion request';
  String get cloudDeletionLocalScope => isIndonesian
      ? 'Trash dan penghapusan permanen lokal hanya berdampak pada perangkat ini. Permintaan terpisah ini mengatur siklus hidup workspace cloud.'
      : 'Local Trash and permanent purge only affect this device; this separate request is for cloud workspace lifecycle.';
  String get cloudDeletionUnavailable => isIndonesian
      ? 'Status penghapusan cloud tidak tersedia. Aksi dinonaktifkan sampai status dapat diverifikasi.'
      : 'Cloud deletion status is unavailable. Actions stay disabled until status can be verified.';
  String get cloudDeletionLoading => isIndonesian
      ? 'Memuat status penghapusan cloud'
      : 'Loading cloud deletion status';
  String get cloudDeletionPending => isIndonesian
      ? 'Permintaan penghapusan cloud sedang menunggu.'
      : 'A cloud deletion request is pending.';
  String get cloudDeletionNotRequested => isIndonesian
      ? 'Tidak ada permintaan penghapusan cloud yang aktif.'
      : 'No active cloud deletion request.';
  String get cloudDeletionRequestAction =>
      isIndonesian ? 'Minta penghapusan cloud' : 'Request cloud deletion';
  String get cloudDeletionCancelAction =>
      isIndonesian ? 'Batalkan permintaan cloud' : 'Cancel cloud request';
  String get cloudDeletionRequestConfirmTitle => isIndonesian
      ? 'Kirim permintaan penghapusan cloud?'
      : 'Submit cloud deletion request?';
  String get cloudDeletionCancelConfirmTitle => isIndonesian
      ? 'Batalkan permintaan penghapusan cloud?'
      : 'Cancel cloud deletion request?';
  String get cloudDeletionRequestConfirmBody => isIndonesian
      ? 'Ini mengirim permintaan penghapusan untuk workspace cloud. Ini tidak langsung menghapus data cloud dan tidak memindahkan atau menghapus proyek lokal di perangkat ini.'
      : 'This submits a deletion request for the cloud workspace. It does not immediately delete cloud data and does not move or delete this device’s local project.';
  String get cloudDeletionCancelConfirmBody => isIndonesian
      ? 'Ini membatalkan permintaan penghapusan cloud yang tertunda. Data lokal di perangkat ini tidak berubah.'
      : 'This cancels the pending cloud deletion request. The local project on this device is unchanged.';
  String get cloudDeletionRequestSuccess => isIndonesian
      ? 'Permintaan cloud terkirim; status diperbarui dari server.'
      : 'Cloud request submitted; status refreshed from the server.';
  String get cloudDeletionCancelSuccess => isIndonesian
      ? 'Permintaan cloud dibatalkan; status diperbarui dari server.'
      : 'Cloud request cancelled; status refreshed from the server.';
  String get cloudDeletionActionFailed => isIndonesian
      ? 'Aksi penghapusan cloud gagal atau statusnya belum dapat diverifikasi.'
      : 'The cloud deletion action failed or its status could not be verified.';
  String get cloudDeletionRequesting =>
      isIndonesian ? 'Mengirim permintaan cloud…' : 'Submitting cloud request…';
  String get cloudDeletionCancelling => isIndonesian
      ? 'Membatalkan permintaan cloud…'
      : 'Cancelling cloud request…';
  String get cloudDeletionConfirmAction =>
      isIndonesian ? 'Konfirmasi' : 'Confirm';
  String get cloudDeletionOwnerOnly => isIndonesian
      ? 'Hanya pemilik workspace cloud yang dapat mengelola permintaan ini.'
      : 'Only the cloud workspace owner can manage this request.';
  String get cloudDeletionUpdatedAt =>
      isIndonesian ? 'Diminta pada' : 'Requested at';
  String get cloudDeletionRetry =>
      isIndonesian ? 'Coba muat ulang' : 'Retry status';
  String get cloudDeletionStatusUnavailableAfterAction => isIndonesian
      ? 'Aksi diproses, tetapi status cloud belum dapat diverifikasi. Muat ulang sebelum mencoba lagi.'
      : 'The action was processed, but cloud status could not be verified. Refresh before trying again.';
  String get authUnavailable => isIndonesian
      ? 'Autentikasi sedang tidak tersedia. Proyek lokal tetap dapat digunakan.'
      : 'Authentication is unavailable right now. Local projects remain available.';
  String get authSignInTitle =>
      isIndonesian ? 'Masuk ke canvas Anda' : 'Sign in to your canvas';
  String get authSignUpTitle =>
      isIndonesian ? 'Buat akun canvas Anda' : 'Create your canvas account';
  String get authResetTitle =>
      isIndonesian ? 'Atur ulang kata sandi' : 'Reset your password';
  String get authSignInAction => isIndonesian ? 'MASUK' : 'SIGN IN';
  String get authSignUpAction => isIndonesian ? 'BUAT AKUN' : 'CREATE ACCOUNT';
  String get authResetAction =>
      isIndonesian ? 'KIRIM EMAIL RESET' : 'SEND RESET EMAIL';
  String get authGoogleSignIn =>
      isIndonesian ? 'Lanjutkan dengan Google' : 'Continue with Google';
  String get authGoogleSignUp =>
      isIndonesian ? 'Daftar dengan Google' : 'Sign up with Google';
  String get authInvalidEmail => isIndonesian
      ? 'Masukkan alamat email yang valid.'
      : 'Enter a valid email address.';
  String get authWeakPassword => isIndonesian
      ? 'Kata sandi harus terdiri dari minimal 8 karakter.'
      : 'Password must be at least 8 characters.';
  String get authCooldownWait => isIndonesian
      ? 'Tunggu sampai jeda selesai sebelum meminta email lain.'
      : 'Please wait for the cooldown before requesting another email.';
  String get authSignupConfirmation => isIndonesian
      ? 'Akun dibuat. Periksa email untuk mengonfirmasi akun.'
      : 'Account created. Check your email to confirm your account.';
  String get authResetSent => isIndonesian
      ? 'Petunjuk pemulihan kata sandi telah dikirim ke email Anda.'
      : 'Password reset instructions were sent to your email.';
  String get authBrowserLoginFailed => isIndonesian
      ? 'Login browser tidak dapat dibuka. Coba lagi.'
      : 'The browser login could not be opened. Try again.';
  String get authPasswordUpdated => isIndonesian
      ? 'Kata sandi diperbarui. Workspace Anda siap digunakan.'
      : 'Password updated. Your workspace is ready.';
  String get authPasswordsMismatch =>
      isIndonesian ? 'Kata sandi tidak cocok.' : 'Passwords do not match.';
  String get authRecoveryTitle =>
      isIndonesian ? 'Buat kata sandi baru' : 'Set a new password';
  String get authRecoveryHint => isIndonesian
      ? 'Gunakan minimal 8 karakter, lalu konfirmasi kata sandi baru.'
      : 'Use at least 8 characters, then confirm the new password.';
  String get authNewPassword =>
      isIndonesian ? 'Kata sandi baru' : 'New password';
  String get authConfirmPassword =>
      isIndonesian ? 'Konfirmasi kata sandi baru' : 'Confirm new password';
  String get authRecoveryMinimum =>
      isIndonesian ? 'Minimal 8 karakter' : 'Minimum 8 characters';
  String get authRecoveryAgain =>
      isIndonesian ? 'Masukkan lagi' : 'Enter it again';
  String get authWorking => isIndonesian ? 'MEMPROSES...' : 'WORKING...';
  String get authUpdatePassword =>
      isIndonesian ? 'PERBARUI KATA SANDI' : 'UPDATE PASSWORD';
  String get authBackLocalWorkspace =>
      isIndonesian ? 'KEMBALI KE WORKSPACE LOKAL' : 'BACK TO LOCAL WORKSPACE';
  String get authCallbackTitle => isIndonesian
      ? 'Tautan autentikasi tidak tersedia'
      : 'Authentication link unavailable';
  String get authCallbackRequestLink =>
      isIndonesian ? 'MINTA TAUTAN BARU' : 'REQUEST A NEW LINK';
  String get bootstrapDeferred => isIndonesian
      ? 'Workspace lokal siap. Layanan cloud terhubung saat diperlukan.'
      : 'Local workspace ready. Cloud services connect when needed.';
  String get dismiss => isIndonesian ? 'Tutup' : 'Dismiss';
  String get bootstrapConnecting => isIndonesian
      ? 'Workspace lokal siap. Menghubungkan layanan cloud…'
      : 'Local workspace ready. Connecting cloud services…';
  String get bootstrapUnavailable => isIndonesian
      ? 'Layanan cloud tidak tersedia. Proyek lokal tetap dapat digunakan.'
      : 'Cloud services unavailable. Local projects remain available.';
  String get bootstrapNotConfigured => isIndonesian
      ? 'Layanan cloud belum dikonfigurasi. Proyek lokal tetap dapat digunakan.'
      : 'Cloud services are not configured. Local projects remain available.';
  String get fatalBootstrapTitle => isIndonesian
      ? 'Creative Canvas Studio tidak dapat dimuat.'
      : 'Creative Canvas Studio could not load.';
  String get fatalBootstrapDescription => isIndonesian
      ? 'Muat ulang aplikasi untuk mencoba lagi. Pekerjaan lokal Anda tetap tersimpan.'
      : 'Reload the app to try again. Your local work is preserved.';
  String get routeErrorTitle =>
      isIndonesian ? 'Halaman ini tidak tersedia' : 'This page is unavailable';
  String get routeErrorDescription => isIndonesian
      ? 'Halaman yang diminta tidak dapat dibuka. Kembali ke pustaka proyek untuk melanjutkan pekerjaan.'
      : 'The requested page could not be opened. Return to the project library to continue your work.';
  String get routeErrorHomeAction =>
      isIndonesian ? 'Kembali ke pustaka proyek' : 'Back to project library';
  String get authCallbackLocalSafe => isIndonesian
      ? 'Minta tautan baru untuk melanjutkan. Proyek lokal Anda aman.'
      : 'Request a new link to continue. Your local projects are safe.';
  String get authIntroLabel =>
      isIndonesian ? 'WORKSTATION KREATIF' : 'CREATIVE WORKSTATION';
  String get authIntroHeadline =>
      isIndonesian ? 'Ide Anda,\nterhubung.' : 'Your ideas,\nconnected.';
  String get authIntroDescription => isIndonesian
      ? 'Bangun sistem visual, bentuk cerita, dan berkolaborasi dari satu canvas yang fokus.'
      : 'Build visual systems, shape the story, and collaborate from one focused canvas.';
  String get authWorkspaceReady =>
      isIndonesian ? 'WORKSPACE SIAP' : 'WORKSPACE READY';
  String get authBackToCanvas =>
      isIndonesian ? 'Kembali ke canvas' : 'Back to canvas';
  String get authCardSignUpHint => isIndonesian
      ? 'Buat satu akun untuk setiap canvas yang Anda buat.'
      : 'Create one account for every canvas you make.';
  String get authCardSignInHint => isIndonesian
      ? 'Lanjutkan pekerjaan visual Anda.'
      : 'Pick up where your visual work left off.';
  String get authOrEmail => isIndonesian ? 'ATAU EMAIL' : 'OR EMAIL';
  String get authEmail => isIndonesian ? 'Email' : 'Email';
  String get authPassword => isIndonesian ? 'Kata sandi' : 'Password';
  String get authEmailHint => 'you@example.com';
  String get authPasswordMinimum =>
      isIndonesian ? 'Minimal 8 karakter' : 'Minimum 8 characters';
  String get authShowPassword =>
      isIndonesian ? 'Tampilkan kata sandi' : 'Show password';
  String get authHidePassword =>
      isIndonesian ? 'Sembunyikan kata sandi' : 'Hide password';
  String get authForgotPassword =>
      isIndonesian ? 'Lupa kata sandi?' : 'Forgot password?';
  String get authAlreadyAccount =>
      isIndonesian ? 'Sudah punya akun?' : 'Already have an account?';
  String get authNewToWorkspace => isIndonesian
      ? 'Baru di Creative Workstation?'
      : 'New to Creative Workstation?';
  String get authBackToSignIn =>
      isIndonesian ? 'Kembali ke masuk' : 'Back to sign in';
  String get authJoinTitle =>
      isIndonesian ? 'GABUNG ROOM KOLABORASI' : 'JOIN COLLAB ROOM';
  String get authJoinWorkspace =>
      isIndonesian ? 'Gabung workspace' : 'Join workspace';
  String get authJoinDescription => isIndonesian
      ? 'Masukkan Room ID dari host untuk masuk ke dokumen dan mengedit bersama secara realtime.'
      : 'Enter the host Room ID to open and edit the document together in real time.';
  String get authRoomId => 'Room ID';
  String get authRoomHint =>
      isIndonesian ? 'Contoh: 482917' : 'Example: 482917';
  String get authDisplayName => isIndonesian
      ? 'Nama yang terlihat oleh member'
      : 'Name visible to members';
  String get authDisplayNameHint =>
      isIndonesian ? 'Amber Fox 42' : 'Amber Fox 42';
  String get authDisplayNameDescription => isIndonesian
      ? 'Nama otomatis dapat diubah sebelum masuk room.'
      : 'You can change the generated name before joining.';
  String get authLoginRequired => isIndonesian
      ? 'Login diperlukan untuk masuk dan menyimpan perubahan room.'
      : 'Sign in is required to join and save room changes.';
  String get authLoginToJoin =>
      isIndonesian ? 'MASUK UNTUK GABUNG' : 'SIGN IN TO JOIN';
  String get authJoinRoom => isIndonesian ? 'GABUNG ROOM' : 'JOIN ROOM';
  String get authInvalidRoom => isIndonesian
      ? 'Masukkan Room ID yang terdiri dari 6 angka.'
      : 'Enter a six-digit Room ID.';
  String get authRoomUnavailable => isIndonesian
      ? 'Room ID tidak valid atau room sudah ditutup.'
      : 'The Room ID is invalid or the room is closed.';
  static CreativeStudioLocalizations of(BuildContext context) =>
      Localizations.of<CreativeStudioLocalizations>(
        context,
        CreativeStudioLocalizations,
      ) ??
      const CreativeStudioLocalizations(Locale('en'));
}

class _CreativeStudioLocalizationsDelegate
    extends LocalizationsDelegate<CreativeStudioLocalizations> {
  const _CreativeStudioLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => CreativeStudioLocalizations
      .supportedLocales
      .any((supported) => supported.languageCode == locale.languageCode);

  @override
  Future<CreativeStudioLocalizations> load(Locale locale) =>
      SynchronousFuture(CreativeStudioLocalizations(locale));

  @override
  bool shouldReload(_CreativeStudioLocalizationsDelegate old) => false;
}
