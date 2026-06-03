import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../../anime/providers/anime_provider.dart';
import '../../tag/providers/tag_provider.dart';
import '../../roi/providers/roi_provider.dart';
import '../services/media_asset_service.dart';
import '../controllers/poi_controller.dart';

class PoiCreateScreen extends ConsumerStatefulWidget {
  final String? roiId;
  final String? editPoiId;

  /// Optional path to a photo (typically from the Anime Camera) that
  /// should be archived as a `user_photo` MediaAsset for this POI
  /// once it's created. Only honoured on the create path — ignored
  /// when [editPoiId] is set, since "edit POI" isn't about adding
  /// media.
  final String? capturedPhotoPath;

  const PoiCreateScreen({
    super.key,
    this.roiId,
    this.editPoiId,
    this.capturedPhotoPath,
  });

  @override
  ConsumerState<PoiCreateScreen> createState() => _PoiCreateScreenState();
}

class _PoiCreateScreenState extends ConsumerState<PoiCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  final _businessHoursController = TextEditingController();
  final _contactInfoController = TextEditingController();

  String? _roiId;
  List<String> _selectedAnimeIds = [];
  List<String> _selectedTagIds = [];
  bool _isLoading = false;
  // Existing cover URI on the edit path, threaded back through savePoi so a
  // full-row update doesn't wipe it. Null on the create path.
  String? _existingCoverUri;

  @override
  void initState() {
    super.initState();
    _roiId = widget.roiId;
    if (widget.editPoiId != null) {
      _loadExistingPoi();
    }
  }

  Future<void> _loadExistingPoi() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final poi = await db.getPoiById(widget.editPoiId!);
      _nameController.text = poi.name;
      _descController.text = poi.description ?? '';
      _addressController.text = poi.address ?? '';
      _latController.text = poi.lat.toString();
      _lngController.text = poi.lng.toString();
      _businessHoursController.text = poi.businessHours ?? '';
      _contactInfoController.text = poi.contactInfo ?? '';
      _roiId = poi.roiId;
      _existingCoverUri = poi.coverImageUri;

      final animes = await db.watchAnimesForPoi(poi.id).first;
      final tags = await db.watchTagsForPoi(poi.id).first;
      _selectedAnimeIds = animes.map((a) => a.id).toList();
      _selectedTagIds = tags.map((t) => t.id).toList();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _addressController.dispose();
    _latController.dispose();
    _lngController.dispose();
    _businessHoursController.dispose();
    _contactInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.editPoiId != null;
    // Option A: drive the Save button off the controller's loading state so
    // a second tap can't fire a duplicate insert while the first is in flight.
    final isSaving = ref.watch(poiControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Location' : 'New Location'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name *',
                      hintText: 'e.g., Toyosato Elementary School',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _RoiPickerField(
                    currentRoiId: _roiId,
                    onChanged: (id) => setState(() => _roiId = id),
                  ),
                  const SizedBox(height: 16),
                  _AnimePickerField(
                    selectedIds: _selectedAnimeIds,
                    onChanged: (ids) =>
                        setState(() => _selectedAnimeIds = ids),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressController,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      hintText: 'Formatted physical address',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latController,
                          decoration: const InputDecoration(
                            labelText: 'Latitude *',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (double.tryParse(v.trim()) == null) {
                              return 'Invalid number';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextFormField(
                          controller: _lngController,
                          decoration: const InputDecoration(
                            labelText: 'Longitude *',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            if (double.tryParse(v.trim()) == null) {
                              return 'Invalid number';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _TagPickerField(
                    selectedIds: _selectedTagIds,
                    onChanged: (ids) => setState(() => _selectedTagIds = ids),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _businessHoursController,
                    decoration: const InputDecoration(
                      labelText: 'Business Hours',
                      hintText: 'e.g., Mon-Fri 09:00-17:00',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _contactInfoController,
                    decoration: const InputDecoration(
                      labelText: 'Contact Info',
                      hintText: 'Phone, website, etc.',
                    ),
                  ),
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: isSaving ? null : _save,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(isEditing ? Icons.save : Icons.add_location),
                    label: Text(isEditing ? 'Save Changes' : 'Create Location'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // The UI only collects strings and passes them to the Controller.
    // The controller persists the POI (plus anime/tag links) in one
    // transaction and returns its id, or null on failure.
    final poiId = await ref.read(poiControllerProvider.notifier).savePoi(
      id: widget.editPoiId,
      roiId: _roiId,
      name: _nameController.text,
      description: _descController.text,
      address: _addressController.text,
      latStr: _latController.text,
      lngStr: _lngController.text,
      businessHours: _businessHoursController.text,
      contactInfo: _contactInfoController.text,
      animeIds: _selectedAnimeIds,
      tagIds: _selectedTagIds,
      coverImageUri: _existingCoverUri,
    );

    // Save failed: surface the error and stay on the form.
    if (poiId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save. Please check your input.')),
        );
      }
      return;
    }

    // Camera capture-then-create-POI flow: archive the temp capture
    // as a `user_photo` MediaAsset under the new POI before we pop.
    // Silently no-op when the file has already gone (rare) or when
    // we're on the edit path.
    if (widget.editPoiId == null && widget.capturedPhotoPath != null) {
      final photoFile = File(widget.capturedPhotoPath!);
      if (await photoFile.exists()) {
        await persistMediaAsset(
          db: ref.read(databaseProvider),
          source: photoFile,
          poiId: poiId,
          type: 'user_photo',
        );
      }
    }

    if (mounted) context.pop();
  }
}

class _RoiPickerField extends ConsumerWidget {
  final String? currentRoiId;
  final ValueChanged<String?> onChanged;

  const _RoiPickerField({required this.currentRoiId, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roisAsync = ref.watch(allRoisProvider);
    final currentName = roisAsync.maybeWhen(
      data: (rois) {
        if (currentRoiId == null) return null;
        try {
          return rois.firstWhere((r) => r.id == currentRoiId).name;
        } catch (_) {
          return null;
        }
      },
      orElse: () => null,
    );

    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<String?>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _RoiPickerSheet(currentRoiId: currentRoiId),
        );
        if (picked == _kRoiCleared) {
          onChanged(null);
        } else if (picked != null) {
          onChanged(picked);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Region',
          hintText: 'Tap to select (optional)',
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        isEmpty: currentName == null,
        child: Text(currentName ?? ''),
      ),
    );
  }
}

const String _kRoiCleared = '__cleared__';

class _RoiPickerSheet extends ConsumerWidget {
  final String? currentRoiId;

  const _RoiPickerSheet({required this.currentRoiId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roisAsync = ref.watch(allRoisProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              'Region',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: roisAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Error: $err')),
              ),
              data: (rois) => ListView(
                shrinkWrap: true,
                children: [
                  if (currentRoiId != null)
                    ListTile(
                      leading: const Icon(Icons.clear),
                      title: const Text('No region'),
                      onTap: () => Navigator.pop(context, _kRoiCleared),
                    ),
                  ...rois.map((roi) => ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(roi.name),
                        selected: roi.id == currentRoiId,
                        trailing: roi.id == currentRoiId
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, roi.id),
                      )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimePickerField extends ConsumerWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _AnimePickerField({
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animesAsync = ref.watch(allAnimesProvider);
    final selectedNames = animesAsync.maybeWhen(
      data: (animes) => animes
          .where((a) => selectedIds.contains(a.id))
          .map((a) => a.name)
          .toList(),
      orElse: () => <String>[],
    );

    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<List<String>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _AnimePickerSheet(selectedIds: selectedIds),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Anime Series',
          hintText: 'Tap to select or add',
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        isEmpty: selectedNames.isEmpty,
        child: selectedNames.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedNames
                      .map((n) => Chip(
                            label: Text(n),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),
      ),
    );
  }
}

class _AnimePickerSheet extends ConsumerStatefulWidget {
  final List<String> selectedIds;

  const _AnimePickerSheet({required this.selectedIds});

  @override
  ConsumerState<_AnimePickerSheet> createState() => _AnimePickerSheetState();
}

class _AnimePickerSheetState extends ConsumerState<_AnimePickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final animesAsync = ref.watch(allAnimesProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Anime', style: Theme.of(context).textTheme.titleMedium),
            trailing: FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: const Text('Done'),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: animesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Error: $err')),
              ),
              data: (animes) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...animes.map((anime) => FilterChip(
                          label: Text(anime.name),
                          selected: _selected.contains(anime.id),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _selected.add(anime.id);
                            } else {
                              _selected.remove(anime.id);
                            }
                          }),
                        )),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add new anime'),
                      onPressed: () async {
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (_) => const _AddEntityDialog(
                            title: 'Add Anime',
                            hint: 'e.g., K-On!',
                          ),
                        );
                        if (newName == null || newName.isEmpty) return;
                        final db = ref.read(databaseProvider);
                        final id = const Uuid().v4();
                        await db.insertAnime(AnimesCompanion.insert(
                          id: id,
                          name: newName,
                          createdAt: DateTime.now().millisecondsSinceEpoch,
                        ));
                        setState(() => _selected.add(id));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagPickerField extends ConsumerWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  const _TagPickerField({required this.selectedIds, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(allTagsProvider);
    final selectedNames = tagsAsync.maybeWhen(
      data: (tags) => tags
          .where((t) => selectedIds.contains(t.id))
          .map((t) => t.name)
          .toList(),
      orElse: () => <String>[],
    );

    return InkWell(
      onTap: () async {
        final picked = await showModalBottomSheet<List<String>>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _TagPickerSheet(selectedIds: selectedIds),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Tags',
          hintText: 'Tap to select or add',
          suffixIcon: Icon(Icons.arrow_drop_down),
        ),
        isEmpty: selectedNames.isEmpty,
        child: selectedNames.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: selectedNames
                      .map((n) => Chip(
                            label: Text(n),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ),
      ),
    );
  }
}

class _TagPickerSheet extends ConsumerStatefulWidget {
  final List<String> selectedIds;

  const _TagPickerSheet({required this.selectedIds});

  @override
  ConsumerState<_TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends ConsumerState<_TagPickerSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final tagsAsync = ref.watch(allTagsProvider);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text('Tags', style: Theme.of(context).textTheme.titleMedium),
            trailing: FilledButton(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              child: const Text('Done'),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: tagsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Error: $err')),
              ),
              data: (tags) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...tags.map((tag) => FilterChip(
                          label: Text(tag.name),
                          selected: _selected.contains(tag.id),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _selected.add(tag.id);
                            } else {
                              _selected.remove(tag.id);
                            }
                          }),
                        )),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: const Text('Add new tag'),
                      onPressed: () async {
                        final newName = await showDialog<String>(
                          context: context,
                          builder: (_) => const _AddEntityDialog(
                            title: 'Add Tag',
                            hint: 'e.g., rain-safe',
                          ),
                        );
                        if (newName == null || newName.isEmpty) return;
                        final db = ref.read(databaseProvider);
                        final id = const Uuid().v4();
                        await db.insertTag(TagsCompanion.insert(
                          id: id,
                          name: newName,
                          createdAt: DateTime.now().millisecondsSinceEpoch,
                        ));
                        setState(() => _selected.add(id));
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddEntityDialog extends StatefulWidget {
  final String title;
  final String hint;

  const _AddEntityDialog({required this.title, required this.hint});

  @override
  State<_AddEntityDialog> createState() => _AddEntityDialogState();
}

class _AddEntityDialogState extends State<_AddEntityDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
        decoration: InputDecoration(hintText: widget.hint),
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
          child: const Text('Add'),
        ),
      ],
    );
  }
}
