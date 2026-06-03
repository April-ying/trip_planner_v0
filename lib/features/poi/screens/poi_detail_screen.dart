import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../providers/poi_provider.dart';
import '../../roi/providers/roi_provider.dart';
import '../../anime/providers/anime_provider.dart';
import '../../tag/providers/tag_provider.dart';
import '../../../core/utils/schedule_utils.dart';

class PoiDetailScreen extends ConsumerWidget {
  final String poiId;

  const PoiDetailScreen({super.key, required this.poiId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poiAsync = ref.watch(poiByIdProvider(poiId));
    final mediaAsync = ref.watch(mediaAssetsByPoiProvider(poiId));
    final referenceImagesAsync =
        ref.watch(referenceImagesByPoiProvider(poiId));
    final chunksAsync = ref.watch(timeChunksByPoiProvider(poiId));

    return Scaffold(
      appBar: AppBar(
        title: poiAsync.when(
          data: (poi) => Text(poi.name),
          loading: () => const Text('Loading...'),
          error: (_, _) => const Text('Error'),
        ),
        actions: [
          poiAsync.when(
            data: (poi) => PopupMenuButton<String>(
              onSelected: (action) =>
                  _handleAction(context, ref, action, poi),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      body: poiAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (poi) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ROI breadcrumb
              if (poi.roiId != null)
                Consumer(
                  builder: (context, ref, _) {
                    final roiAsync = ref.watch(roiByIdProvider(poi.roiId!));
                    return roiAsync.maybeWhen(
                      data: (roi) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => context.push('/rois/${poi.roiId}'),
                          child: Row(
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                roi.name,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      orElse: () => const SizedBox.shrink(),
                    );
                  },
                ),

              // Anime hero chips (m:n via PoiAnimes)
              Consumer(
                builder: (context, ref, _) {
                  final animesAsync = ref.watch(animesForPoiProvider(poi.id));
                  return animesAsync.maybeWhen(
                    data: (animes) {
                      if (animes.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: animes
                              .map((anime) => ActionChip(
                                    avatar: Icon(
                                      Icons.movie_outlined,
                                      size: 20,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                    ),
                                    label: Text(
                                      anime.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                    backgroundColor: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    onPressed: () =>
                                        context.push('/anime/${anime.id}'),
                                  ))
                              .toList(),
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                },
              ),

              // Description
              if (poi.description != null) ...[
                Text(
                  poi.description!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
              ],

              // Info card (address + gps + hours + contact)
              Card(
                margin: EdgeInsets.zero,
                child: Column(
                  children: [
                    if (poi.address != null)
                      ListTile(
                        leading: const Icon(Icons.location_on_outlined),
                        title: Text(poi.address!),
                        dense: true,
                      ),
                    ListTile(
                      leading: const Icon(Icons.gps_fixed),
                      title: Text('${poi.lat}, ${poi.lng}'),
                      dense: true,
                    ),
                    if (poi.businessHours != null)
                      ListTile(
                        leading: const Icon(Icons.access_time),
                        title: Text(poi.businessHours!),
                        dense: true,
                      ),
                    if (poi.contactInfo != null)
                      ListTile(
                        leading: const Icon(Icons.contact_phone_outlined),
                        title: Text(poi.contactInfo!),
                        dense: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tags (m:n via PoiTags)
              Consumer(
                builder: (context, ref, _) {
                  final tagsAsync = ref.watch(tagsForPoiProvider(poi.id));
                  return tagsAsync.maybeWhen(
                    data: (tags) {
                      if (tags.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Icon(
                                Icons.label_outline,
                                size: 18,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: tags
                                    .map((tag) => ActionChip(
                                          label: Text(tag.name),
                                          visualDensity: VisualDensity.compact,
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          onPressed: () =>
                                              context.push('/tag/${tag.id}'),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  );
                },
              ),

              // Schedule section
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Schedule',
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () =>
                        _showScheduleDialog(context, ref, poi.id),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              chunksAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (err, _) => Text('Error: $err'),
                data: (chunks) {
                  if (chunks.isEmpty) {
                    return const Text('Not scheduled yet. Tap + to add.');
                  }
                  return Column(
                    children: chunks
                        .map((chunk) => Card(
                              child: ListTile(
                                leading: _statusIcon(chunk.status),
                                title: Text(chunk.date ?? 'Backlog'),
                                subtitle: chunk.startTime != null
                                    ? Text(
                                        '${chunk.startTime} - ${chunk.endTime ?? '?'}')
                                    : null,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) =>
                                      handleTimeChunkAction(
                                          context, ref, action, chunk),
                                  itemBuilder: (context) {
                                    final List<PopupMenuEntry<String>> menuItems = [];
                                    if (chunk.status != 'backlog') {
                                      if (chunk.status != 'scheduled') {
                                        menuItems.add(const PopupMenuItem(
                                          value: 'scheduled',
                                          child: Text('Schedule'),
                                        ));
                                      }
                                      if (chunk.status != 'completed'){
                                        menuItems.add(const PopupMenuItem(
                                            value: 'completed', child: Text('Complete')));
                                      }
                                      if (chunk.status != 'skipped'){
                                        menuItems.add(const PopupMenuItem(
                                            value: 'skipped', child: Text('Skip')));
                                      }
                                      menuItems.add(const PopupMenuItem(
                                        value: 'backlog', child: Text('To Backlog')));
                                      menuItems.add(const PopupMenuDivider());
                                    }
                                    menuItems.add(const PopupMenuItem(value: 'edit', child: Text('Edit')));
                                    menuItems.add(const PopupMenuItem(value: 'delete', child: Text('Delete')));
                                    return menuItems;
                                  }
                                ),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),

              // Reference Images section
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Reference Images',
                      style: Theme.of(context).textTheme.titleMedium),
                  FilledButton.tonalIcon(
                    onPressed: () => _addReferenceImage(context, ref, poi.id),
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              referenceImagesAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (err, _) => Text('Error: $err'),
                data: (images) {
                  if (images.isEmpty) {
                    return const Text(
                      'No reference images. Add anime screenshots to overlay in camera.',
                    );
                  }
                  return Column(
                    children: images
                        .map((image) => _ReferenceImageTile(
                              image: image,
                              title: _referenceImageTitle(image),
                              onRename: () =>
                                  _renameReferenceImage(context, ref, image),
                              onDelete: () =>
                                  _deleteReferenceImage(context, ref, image),
                              onPreview: () => _showFullscreenImage(
                                context,
                                uri: image.localUri,
                                title: 'Reference Image',
                              ),
                            ))
                        .toList(),
                  );
                },
              ),

              // Media section
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Media Assets',
                      style: Theme.of(context).textTheme.titleMedium),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Take photo',
                        onPressed: () =>
                            context.push('/camera?poiId=${poi.id}'),
                        icon: const Icon(Icons.camera_alt),
                      ),
                      IconButton(
                        tooltip: 'Add image',
                        onPressed: () =>
                            _addImageToMediaAssets(context, ref, poi.id),
                        icon: const Icon(Icons.add_photo_alternate),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              mediaAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (err, _) => Text('Error: $err'),
                data: (assets) {
                  if (assets.isEmpty) {
                    return const Text('No media assets yet.');
                  }
                  final referenceImagesById =
                      referenceImagesAsync.maybeWhen(
                    data: (refs) => {for (final r in refs) r.id: r},
                    orElse: () => <String, ReferenceImage>{},
                  );
                  return Column(
                    children: assets.map((asset) {
                      final linkedRef = asset.referenceImageId != null
                          ? referenceImagesById[asset.referenceImageId]
                          : null;
                      return _MediaAssetTile(
                        asset: asset,
                        onRename: () => _renameMediaAsset(context, ref, asset),
                        onDelete: () => _deleteMediaAsset(context, ref, asset),
                        onPreview: _isPreviewableImage(asset)
                            ? () => _showImagePreview(context, asset)
                            : null,
                        onEdit: _isPreviewableImage(asset)
                            ? () => _editMediaAsset(context, asset, linkedRef)
                            : null,
                        title: _mediaAssetTitle(asset),
                        icon: _iconForType(asset.type),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleAction(
      BuildContext context, WidgetRef ref, String action, Poi poi) {
    switch (action) {
      case 'edit':
        context.push('/pois/${poi.id}/edit');
        break;
      case 'delete':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Location?'),
            content: Text('This will permanently delete "${poi.name}".'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final db = ref.read(databaseProvider);
                  await db.deletePoi(poi.id);
                  if (context.mounted) {
                    Navigator.pop(ctx);
                    context.pop();
                  }
                },
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        break;
    }
  }

  void _showScheduleDialog(
      BuildContext context, WidgetRef ref, String poiId) {
    DateTime? selectedDate;
    final startController = TextEditingController(text: '10:00');
    final endController = TextEditingController(text: '12:00');
    String status = 'backlog';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Time Slot'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'backlog', label: Text('Backlog')),
                  ButtonSegment(value: 'scheduled', label: Text('Schedule')),
                ],
                selected: {status},
                onSelectionChanged: (s) =>
                    setDialogState(() => status = s.first),
              ),
              const SizedBox(height: 16),
              if (status == 'scheduled') ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: Text(selectedDate != null
                      ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                      : 'Select Date'),
                  onTap: () async {
                    final picked = await showMonthCalendarPicker(
                      context: ctx,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime(DateTime.now().year + 20),
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startController,
                        decoration:
                            const InputDecoration(labelText: 'Start'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: endController,
                        decoration:
                            const InputDecoration(labelText: 'End'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final db = ref.read(databaseProvider);
                db.insertTimeChunk(TimeChunksCompanion.insert(
                  id: const Uuid().v4(),
                  poiId: poiId,
                  date: Value(selectedDate != null
                      ? DateFormat('yyyy-MM-dd').format(selectedDate!)
                      : null),
                  startTime: Value(status == 'scheduled'
                      ? startController.text.trim()
                      : null),
                  endTime: Value(status == 'scheduled'
                      ? endController.text.trim()
                      : null),
                  status: Value(status),
                ));
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(String status) {
    return switch (status) {
      'completed' => const Icon(Icons.check_circle, color: Colors.green),
      'scheduled' => const Icon(Icons.schedule, color: Colors.blue),
      'skipped' => const Icon(Icons.skip_next, color: Colors.orange),
      _ => const Icon(Icons.inbox, color: Colors.grey),
    };
  }

  Widget _iconForType(String type) {
    return switch (type) {
      'reference_frame' => const Icon(Icons.image),
      'user_photo' => const Icon(Icons.camera_alt),
      'uploaded_image' => const Icon(Icons.save_alt),
      'comparison_image' => const Icon(Icons.compare),
      'ticket_qr' => const Icon(Icons.qr_code),
      'audio_bgm' => const Icon(Icons.music_note),
      _ => const Icon(Icons.attachment),
    };
  }

  String _mediaAssetTitle(MediaAsset asset) {
    final fileName = p.basenameWithoutExtension(asset.localUri);
    return fileName.isEmpty ? asset.type : fileName;
  }

  Future<void> _renameMediaAsset(
    BuildContext context,
    WidgetRef ref,
    MediaAsset asset,
  ) async {
    final oldFile = File(asset.localUri);
    final currentName = p.basenameWithoutExtension(asset.localUri);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        title: 'Rename Image',
        initialName: currentName,
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;
    if (!context.mounted) return;

    final sanitizedName = p.basenameWithoutExtension(_sanitizeFileName(newName));
    if (sanitizedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid image name.')),
      );
      return;
    }

    if (!await oldFile.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image file not found: ${asset.localUri}')),
      );
      return;
    }

    final extension = p.extension(asset.localUri).isEmpty
        ? '.jpg'
        : p.extension(asset.localUri);
    final newPath = await _nextAvailableMediaPath(
      p.dirname(asset.localUri),
      sanitizedName,
      extension,
      asset.localUri,
    );

    try {
      await oldFile.rename(newPath);

      await ref.read(databaseProvider).updateMediaAssetLocalUri(
            asset.id,
            newPath,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image renamed.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _deleteMediaAsset(
    BuildContext context,
    WidgetRef ref,
    MediaAsset asset,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Image?'),
        content: Text('This will remove "${_mediaAssetTitle(asset)}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;

    try {
      final file = File(asset.localUri);
      if (await file.exists()) {
        await file.delete();
      }

      await ref.read(databaseProvider).deleteMediaAsset(asset.id);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image deleted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  String _sanitizeFileName(String input) {
    return input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  Future<String> _nextAvailableMediaPath(
    String directory,
    String baseName,
    String extension,
    String currentPath,
  ) async {
    var candidate = p.join(directory, '$baseName$extension');
    var suffix = 1;

    while (candidate != currentPath && await File(candidate).exists()) {
      candidate = p.join(directory, '$baseName-$suffix$extension');
      suffix += 1;
    }

    return candidate;
  }

  bool _isPreviewableImage(MediaAsset asset) {
    final uri = asset.localUri.toLowerCase();
    final isKnownImageType = asset.type == 'user_photo' ||
        asset.type == 'uploaded_image' ||
        asset.type == 'comparison_image' ||
        asset.type == 'reference_frame' ||
        asset.type == 'ticket_qr';
    final hasImageExtension = uri.endsWith('.jpg') ||
        uri.endsWith('.jpeg') ||
        uri.endsWith('.png') ||
        uri.endsWith('.webp') ||
        uri.endsWith('.gif') ||
        uri.endsWith('.heic');

    return isKnownImageType || hasImageExtension;
  }

  void _showImagePreview(BuildContext context, MediaAsset asset) {
    _showFullscreenImage(context, uri: asset.localUri, title: asset.type);
  }

  void _showFullscreenImage(
    BuildContext context, {
    required String uri,
    required String title,
  }) {
    final imageFile = File(uri);

    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<bool>(
              future: imageFile.exists(),
              builder: (context, snapshot) {
                final exists = snapshot.data ?? false;

                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                if (!exists) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Image file not found:\n$uri',
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return InteractiveViewer(
                  minScale: 0.75,
                  maxScale: 4,
                  child: Center(
                    child: Image.file(imageFile, fit: BoxFit.contain),
                  ),
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: AppBar(
                  backgroundColor: Colors.black54,
                  foregroundColor: Colors.white,
                  title: Text(title),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _referenceImageTitle(ReferenceImage image) {
    final fileName = p.basenameWithoutExtension(image.localUri);
    return fileName.isEmpty ? 'Reference' : fileName;
  }

  /// Pick an image from the gallery and drop the user into the photo
  /// editor against it. The file is copied into the app's temp
  /// directory first so the editor can freely overwrite it with the
  /// edited bytes without touching the gallery item or the picker's
  /// cache; once the editor saves, that temp copy gets archived into
  /// permanent app storage with `type = uploaded_image`.
  Future<void> _addImageToMediaAssets(
    BuildContext context,
    WidgetRef ref,
    String poiId,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!context.mounted) return;

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = p.extension(picked.path).isEmpty
          ? '.jpg'
          : p.extension(picked.path);
      final tempPath = p.join(
        tempDir.path,
        'upload_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await File(picked.path).copy(tempPath);

      if (!context.mounted) return;
      context.push(
        '/pois/$poiId/photo-edit'
        '?path=${Uri.encodeComponent(tempPath)}'
        '&upload=1',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load image: $e')),
      );
    }
  }

  /// Open the photo editor on an existing media asset. Copies it to a temp file
  /// first so editing is non-destructive — saving creates a NEW asset and the
  /// original is preserved. Passes the paired reference (if any) so Match Color
  /// / Compose are available.
  Future<void> _editMediaAsset(
    BuildContext context,
    MediaAsset asset,
    ReferenceImage? linkedRef,
  ) async {
    final src = File(asset.localUri);
    if (!await src.exists()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File not found.')),
        );
      }
      return;
    }
    try {
      final tempDir = await getTemporaryDirectory();
      final ext = p.extension(asset.localUri).isEmpty
          ? '.jpg'
          : p.extension(asset.localUri);
      final tempPath = p.join(
        tempDir.path,
        'edit_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      await src.copy(tempPath);
      if (!context.mounted) return;
      final qs = <String, String>{'path': Uri.encodeComponent(tempPath)};
      if (linkedRef != null) {
        qs['ref'] = Uri.encodeComponent(linkedRef.localUri);
        qs['refId'] = asset.referenceImageId!;
      }
      final query = qs.entries.map((e) => '${e.key}=${e.value}').join('&');
      context.push('/pois/${asset.poiId}/photo-edit?$query');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit failed: $e')),
      );
    }
  }

  Future<void> _addReferenceImage(
    BuildContext context,
    WidgetRef ref,
    String poiId,
  ) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!context.mounted) return;

    try {
      final newPath = await _copyReferenceImageToStorage(File(picked.path));
      await ref.read(databaseProvider).insertReferenceImage(
            ReferenceImagesCompanion.insert(
              id: const Uuid().v4(),
              poiId: poiId,
              localUri: newPath,
            ),
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reference image added.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add reference image: $e')),
      );
    }
  }

  Future<void> _renameReferenceImage(
    BuildContext context,
    WidgetRef ref,
    ReferenceImage image,
  ) async {
    final oldFile = File(image.localUri);
    final currentName = p.basenameWithoutExtension(image.localUri);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameDialog(
        title: 'Rename Reference Image',
        initialName: currentName,
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName) return;
    if (!context.mounted) return;

    final sanitizedName = p.basenameWithoutExtension(_sanitizeFileName(newName));
    if (sanitizedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid image name.')),
      );
      return;
    }

    if (!await oldFile.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image file not found: ${image.localUri}')),
      );
      return;
    }

    final extension = p.extension(image.localUri).isEmpty
        ? '.jpg'
        : p.extension(image.localUri);
    final newPath = await _nextAvailableMediaPath(
      p.dirname(image.localUri),
      sanitizedName,
      extension,
      image.localUri,
    );

    try {
      await oldFile.rename(newPath);

      await ref.read(databaseProvider).updateReferenceImageLocalUri(
            image.id,
            newPath,
          );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image renamed.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rename failed: $e')),
      );
    }
  }

  Future<void> _deleteReferenceImage(
    BuildContext context,
    WidgetRef ref,
    ReferenceImage image,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Reference Image?'),
        content: Text('This will remove "${_referenceImageTitle(image)}".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) return;
    if (!context.mounted) return;

    try {
      final file = File(image.localUri);
      if (await file.exists()) {
        await file.delete();
      }

      await ref.read(databaseProvider).deleteReferenceImage(image.id);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reference image deleted.')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<String> _copyReferenceImageToStorage(File source) async {
    final appDir = await getApplicationDocumentsDirectory();
    final refDir = Directory(p.join(appDir.path, 'reference_images'));
    if (!await refDir.exists()) {
      await refDir.create(recursive: true);
    }

    final extension =
        p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final newPath = p.join(refDir.path, '${const Uuid().v4()}$extension');
    await source.copy(newPath);
    return newPath;
  }
}

class _MediaAssetTile extends StatelessWidget {
  final MediaAsset asset;
  final String title;
  final Widget icon;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback? onPreview;
  final VoidCallback? onEdit;

  const _MediaAssetTile({
    required this.asset,
    required this.title,
    required this.icon,
    required this.onRename,
    required this.onDelete,
    required this.onPreview,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: icon,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        asset.localUri,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      contentPadding: EdgeInsets.zero,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Save to device',
            icon: const Icon(Icons.download),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Gal.putImage(asset.localUri);
                messenger.showSnackBar(
                  const SnackBar(content: Text('Saved to gallery.')),
                );
              } on GalException catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Save failed: ${e.type.message}')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: onEdit,
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              if (v == 'rename') onRename();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
          IconButton(
            tooltip: 'Preview',
            icon: const Icon(Icons.open_in_full),
            onPressed: onPreview,
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  final String title;
  final String initialName;

  const _RenameDialog({required this.title, required this.initialName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Image name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

class _ReferenceImageTile extends StatelessWidget {
  final ReferenceImage image;
  final String title;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _ReferenceImageTile({
    required this.image,
    required this.title,
    required this.onRename,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Image.file(
              File(image.localUri),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Colors.black12,
                child: Icon(Icons.broken_image),
              ),
            ),
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          image.localUri,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: onPreview,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Rename',
              icon: const Icon(Icons.edit_outlined),
              onPressed: onRename,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: onDelete,
            ),
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.open_in_full),
              onPressed: onPreview,
            ),
          ],
        ),
      ),
    );
  }
}
