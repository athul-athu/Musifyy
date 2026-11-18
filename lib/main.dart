import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/screens/local_sync_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/local_sync_service.dart';
import 'package:musify/services/logger_service.dart';
import 'package:musify/services/playlist_sharing.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/update_manager.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/utilities/playlist_utils.dart';
import 'package:musify/utilities/sharing_intent.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

late MusifyAudioHandler audioHandler;
StreamSubscription<String?>? sharingIntentSubscription;
StreamSubscription<Uri?>? appLinksSubscription;

final logger = Logger();
final appLinks = AppLinks();

bool isFdroidBuild = false;
bool isUpdateChecked = false;

class Musify extends StatefulWidget {
  const Musify({super.key});

  static Future<void> updateAppState(
    BuildContext context, {
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? useSystemColor,
  }) async {
    final state = context.findAncestorStateOfType<_MusifyState>() ??
        NavigationManager.parentNavigatorKey.currentContext
            ?.findAncestorStateOfType<_MusifyState>();
    state?.changeSettings(
      newThemeMode: newThemeMode,
      newLocale: newLocale,
      newAccentColor: newAccentColor,
      systemColorStatus: useSystemColor,
    );
  }

  @override
  _MusifyState createState() => _MusifyState();
}

class _MusifyState extends State<Musify> with WidgetsBindingObserver {
  void changeSettings({
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? systemColorStatus,
  }) {
    setState(() {
      if (newThemeMode != null) {
        themeMode = newThemeMode;
        brightness = getBrightnessFromThemeMode(newThemeMode);
      }
      if (newLocale != null) {
        languageSetting = newLocale;
      }
      if (newAccentColor != null) {
        if (systemColorStatus != null &&
            useSystemColor.value != systemColorStatus) {
          useSystemColor.value = systemColorStatus;
          addOrUpdateData<bool>(
            'settings',
            'useSystemColor',
            systemColorStatus,
          );
        }
        primaryColorSetting = newAccentColor;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final platformDispatcher = PlatformDispatcher.instance;

    // This callback is called every time the brightness changes.
    platformDispatcher.onPlatformBrightnessChanged = () {
      if (themeMode == ThemeMode.system) {
        setState(() {
          brightness = platformDispatcher.platformBrightness;
        });
      }
    };

    offlineMode.addListener(_onOfflineModeChanged);
    LocalSyncService.instance.incomingPairingRequest.addListener(
      showIncomingPairingDialog,
    );

    if (isMobilePlatform) {
      sharingIntentSubscription = ReceiveSharingIntent.getTextStream().listen(
        (String? value) async {
          await consumeYoutubeSharedTextIntent(
            value,
            audioHandler: audioHandler,
            onError: (error, stackTrace) {
              logger.log(
                'Error while playing shared song:',
                error: error,
                stackTrace: stackTrace,
              );
            },
          );
        },
        onError: (err) {
          logger.log('getTextStream error:', error: err);
        },
      );
    }

    try {
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/licenses/paytone.txt',
        );
        yield LicenseEntryWithLineBreaks(['paytoneOne'], license);
      });
    } catch (e, stackTrace) {
      logger.log(
        'License Registration Error',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (!isFdroidBuild) {
      if (shouldWeCheckUpdates.value == true) {
        if (!isUpdateChecked && kReleaseMode) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!offlineMode.value) {
              checkAppUpdates();
            }
            isUpdateChecked = true;
          });
        }
      } else {
        if (shouldWeCheckUpdates.value == null) {
          // show dialog that asks user if they want to enable update checks
          SchedulerBinding.instance.addPostFrameCallback((_) {
            showUpdateCheckDialog(NavigationManager().context);
          });
        } else {
          SchedulerBinding.instance.addPostFrameCallback((_) async {
            if (!offlineMode.value) {
              await fetchAnnouncementOnly();
            }
          });
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(LocalSyncService.instance.syncOnResume());
    }
    super.didChangeAppLifecycleState(state);
    // Persist listening stats when the app leaves the foreground. This is the
    // reliable moment to snapshot and flush: unlike widget dispose, these
    // callbacks are delivered before the OS suspends or terminates the process.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      listeningStatsService.recordListeningSessionProgress(
        wasPlaying: audioHandler.audioPlayer.playing,
      );
      unawaited(listeningStatsService.flush());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    offlineMode.removeListener(_onOfflineModeChanged);
    PlatformDispatcher.instance.onPlatformBrightnessChanged = null;

    LocalSyncService.instance.incomingPairingRequest.removeListener(
      showIncomingPairingDialog,
    );
    unawaited(LocalSyncService.instance.dispose());
    Hive.close();
    unawaited(sharingIntentSubscription?.cancel());
    unawaited(appLinksSubscription?.cancel());
    super.dispose();
  }

  void _onOfflineModeChanged() {
    // Force rebuild when offline mode changes
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        final colorScheme = getAppColorScheme(
          lightColorScheme,
          darkColorScheme,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: true,
            statusBarBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: MaterialApp.router(
            themeMode: themeMode,
            darkTheme: getAppTheme(colorScheme),
            theme: getAppTheme(colorScheme),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: languageSetting,
            routerConfig: NavigationManager.router,
          ),
        );
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initialisation();

  runApp(const Musify());
}

Future<void> _initStorageAndHive() async {
  if (kIsWeb) {
    applicationDirPath = '';
    await Hive.initFlutter();
    return;
  }

  final Directory storageDir;
  if (isDesktopPlatform) {
    storageDir = await getApplicationSupportDirectory();
    if (!await storageDir.exists()) {
      await storageDir.create(recursive: true);
    }
    await _migrateLegacyHiveStorage(storageDir);
  } else {
    storageDir = await getApplicationDocumentsDirectory();
  }

  applicationDirPath = storageDir.path;
  await FilePaths.ensureDirectoriesExist();
  Hive.init(storageDir.path);
}

Future<void> _migrateLegacyHiveStorage(Directory targetDir) async {
  try {
    final legacyDocDir = await getApplicationDocumentsDirectory();
    if (legacyDocDir.path == targetDir.path) return;

    const boxNames = ['settings', 'user', 'userNoBackup', 'cache'];
    for (final boxName in boxNames) {
      final legacyFile = File('${legacyDocDir.path}/$boxName.hive');
      final targetFile = File('${targetDir.path}/$boxName.hive');

      if (await legacyFile.exists() && !await targetFile.exists()) {
        try {
          await legacyFile.copy(targetFile.path);
          logger.log('Migrated $boxName.hive to app support directory');
        } catch (e) {
          logger.log('Failed to migrate $boxName.hive', error: e);
        }
      }
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error during legacy storage migration',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

Future<void> _openBoxes() async {
  const boxNames = ['settings', 'user', 'userNoBackup', 'cache'];
  for (final boxName in boxNames) {
    if (Hive.isBoxOpen(boxName)) continue;
    try {
      await Hive.openBox(boxName);
    } catch (e, stackTrace) {
      logger.log(
        'Error opening Hive box "$boxName", attempting recovery:',
        error: e,
        stackTrace: stackTrace,
      );
      if (boxName == 'cache') {
        try {
          await Hive.deleteBoxFromDisk('cache');
          await Hive.openBox('cache');
        } catch (_) {}
      } else {
        try {
          if (applicationDirPath.isNotEmpty) {
            final lockFile = File('$applicationDirPath/$boxName.lock');
            if (await lockFile.exists()) {
              await lockFile.delete();
            }
          }
          await Hive.openBox(boxName);
        } catch (retryError) {
          logger.log('Retry failed for Hive box "$boxName": $retryError');
        }
      }
    }
  }
}

Future<void> initialisation() async {
  try {
    await _initStorageAndHive();
    await _openBoxes();
  } catch (e, stackTrace) {
    logger.log(
      'Storage/Hive Initialization Error',
      error: e,
      stackTrace: stackTrace,
    );
  }

  try {
    await LocalSyncService.instance.initialise();
  } catch (e, stackTrace) {
    logger.log(
      'Local sync could not start',
      error: e,
      stackTrace: stackTrace,
    );
  }

  try {
    audioHandler = await AudioService.init(
      builder: MusifyAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.athul.musifyy',
        androidNotificationChannelName: 'Musify',
        androidNotificationIcon: 'drawable/ic_launcher_foreground',
        androidShowNotificationBadge: true,
        androidStopForegroundOnPause: false,
        // Handed to Android Auto on the browsable root. Without the search
        // flag the car never offers a search box, and without the content
        // style keys it falls back to an undifferentiated list of everything.
        androidBrowsableRootExtras: {
          AndroidContentStyle.supportedKey: true,
          AndroidContentStyle.browsableHintKey:
              AndroidContentStyle.gridItemHintValue,
          AndroidContentStyle.playableHintKey:
              AndroidContentStyle.listItemHintValue,
          'android.media.browse.SEARCH_SUPPORTED': true,
        },
      ),
    );
  } catch (e, stackTrace) {
    logger.log(
      'AudioService Initialization Error',
      error: e,
      stackTrace: stackTrace,
    );
  }

  // Init router
  NavigationManager.instance;

  if (!kIsWeb) {
    try {
      // Listen to incoming links while app is running
      appLinksSubscription = appLinks.uriLinkStream.listen(
        handleIncomingLink,
        onError: (err) {
          logger.log('URI link error:', error: err);
        },
      );
    } on PlatformException {
      logger.log('Failed to get initial uri');
    }
  }

  if (isFdroidBuild && !offlineMode.value) {
    await fetchAnnouncementOnly();
  }
}

void handleIncomingLink(Uri? uri) async {
  if (uri == null || uri.scheme != 'musify' || uri.host != 'playlist') return;

  if (uri.pathSegments.length < 2 || uri.pathSegments[0] != 'custom') return;

  try {
    final encodedPlaylist = uri.pathSegments[1];
    final playlist = await PlaylistSharingService.decodeAndExpandPlaylist(
      encodedPlaylist,
    );

    if (playlist == null) {
      _showPlaylistError();
      return;
    }

    // Ensure the incoming playlist has a unique id so it can be removed later
    if (playlist['ytid'] == null || playlist['ytid'].toString().isEmpty) {
      playlist['ytid'] = PlaylistUtils.generateCustomPlaylistId();
    }

    // Check for duplicate by title and song ytids
    final incomingYtids = (playlist['list'] as List<dynamic>)
        .map((s) => s['ytid'].toString())
        .toList();

    final isDuplicate = PlaylistUtils.playlistExists(
      playlist,
      incomingYtids,
      userCustomPlaylists.value,
    );

    if (isDuplicate) {
      showToast(
        NavigationManager().context,
        NavigationManager().context.l10n!.playlistAlreadyExists,
      );
    } else {
      userCustomPlaylists.value = [...userCustomPlaylists.value, playlist];
      unawaited(
        addOrUpdateData<List>(
          'user',
          'customPlaylists',
          userCustomPlaylists.value,
        ),
      );
      showToast(
        NavigationManager().context,
        '${NavigationManager().context.l10n!.addedSuccess}!',
      );
    }
  } catch (e) {
    _showPlaylistError();
  }
}

void _showPlaylistError() {
  showToast(
    NavigationManager().context,
    NavigationManager().context.l10n!.failedToLoadPlaylist,
  );
}
