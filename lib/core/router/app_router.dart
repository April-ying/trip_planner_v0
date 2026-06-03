import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/roi/screens/roi_list_screen.dart';
import '../../features/roi/screens/roi_detail_screen.dart';
import '../../features/roi/screens/roi_edit_screen.dart';
import '../../features/anime/screens/anime_edit_screen.dart';
import '../../features/anime/screens/bangumi_search_screen.dart';
import '../../features/tag/screens/tag_edit_screen.dart';
import '../../features/poi/screens/poi_detail_screen.dart';
import '../../features/poi/screens/poi_create_screen.dart';
import '../../features/poi/screens/poi_browse_screen.dart';
import '../../features/poi/screens/pois_by_filter_screen.dart';
import '../../features/poi/screens/photo_edit_screen.dart';
import '../../features/calendar/screens/calendar_screen.dart';
import '../../features/camera/screens/camera_screen.dart';
import '../../features/ticket/screens/ticket_screen.dart';
import '../../features/home/screens/sync_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/vlog/pages/vlog_preview_page.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/rois',
      builder: (context, state) => const RoiListScreen(),
    ),
    GoRoute(
      path: '/rois/:roiId',
      builder: (context, state) => RoiDetailScreen(
        roiId: state.pathParameters['roiId']!,
      ),
    ),
    GoRoute(
      path: '/rois/:roiId/edit',
      builder: (context, state) => RoiEditScreen(
        roiId: state.pathParameters['roiId']!,
      ),
    ),
    GoRoute(
      path: '/rois/:roiId/pois/new',
      builder: (context, state) => PoiCreateScreen(
        roiId: state.pathParameters['roiId']!,
      ),
    ),
    GoRoute(
      path: '/rois/:roiId/pois/:poiId/edit',
      builder: (context, state) => PoiCreateScreen(
        roiId: state.pathParameters['roiId']!,
        editPoiId: state.pathParameters['poiId'],
      ),
    ),
    GoRoute(
      path: '/pois',
      builder: (context, state) => PoiBrowseScreen(
        initialTab: state.uri.queryParameters['tab'],
      ),
    ),
    GoRoute(
      // Create a POI not tied to a region (e.g. from an Anime Camera capture).
      path: '/pois/new',
      builder: (context, state) {
        final capturedPath = state.uri.queryParameters['capturedPath'];
        return PoiCreateScreen(
          capturedPhotoPath:
              capturedPath != null ? Uri.decodeComponent(capturedPath) : null,
        );
      },
    ),
    GoRoute(
      path: '/pois/:poiId/edit',
      builder: (context, state) => PoiCreateScreen(
        editPoiId: state.pathParameters['poiId'],
      ),
    ),
    GoRoute(
      path: '/pois/:poiId',
      builder: (context, state) => PoiDetailScreen(
        poiId: state.pathParameters['poiId']!,
      ),
    ),
    GoRoute(
      // Photo editor — opens against `path`, optionally overlaying `ref`
      // (with `refId` linking the saved MediaAsset to a ReferenceImage row).
      // `upload=1` marks the save as `uploaded_image` rather than `user_photo`.
      path: '/pois/:poiId/photo-edit',
      builder: (context, state) {
        final qp = state.uri.queryParameters;
        final source = qp['path'];
        if (source == null) {
          return const Scaffold(
            body: Center(child: Text('Missing source path.')),
          );
        }
        return PhotoEditScreen(
          poiId: state.pathParameters['poiId']!,
          sourcePath: Uri.decodeComponent(source),
          referencePath: qp['ref'] != null
              ? Uri.decodeComponent(qp['ref']!)
              : null,
          referenceImageId: qp['refId'],
          wasUpload: qp['upload'] == '1',
        );
      },
    ),
    GoRoute(
      path: '/anime/:animeId',
      builder: (context, state) => PoisByAnimeScreen(
        animeId: state.pathParameters['animeId']!,
      ),
    ),
    GoRoute(
      path: '/tag/:tagId',
      builder: (context, state) => PoisByTagScreen(
        tagId: state.pathParameters['tagId']!,
      ),
    ),
    GoRoute(
      // animeId of 'new' opens the create form.
      path: '/animes/:animeId/edit',
      builder: (context, state) => AnimeEditScreen(
        animeId: state.pathParameters['animeId']!,
      ),
    ),
    GoRoute(
      // tagId of 'new' opens the create form.
      path: '/tags/:tagId/edit',
      builder: (context, state) => TagEditScreen(
        tagId: state.pathParameters['tagId']!,
      ),
    ),
    GoRoute(
      path: '/import/bangumi',
      builder: (context, state) => const BangumiSearchScreen(),
    ),
    GoRoute(
      path: '/calendar',
      builder: (context, state) => const CalendarScreen(),
    ),
    GoRoute(
      path: '/camera',
      builder: (context, state) => CameraScreen(
        poiId: state.uri.queryParameters['poiId'],
      ),
    ),
    GoRoute(
      path: '/tickets',
      builder: (context, state) => const TicketScreen(),
    ),
    GoRoute(
      path: '/vlog',
      builder: (context, state) => const VlogPreviewPage(),
    ),
    GoRoute(
      path: '/sync',
      builder: (context, state) => const SyncScreen(),
    ),
    GoRoute(
      path: '/map',
      builder: (context, state) => const MapScreen(),
    ),
  ],
);
