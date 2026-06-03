import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/database.dart';
import '../../../core/providers/database_provider.dart';
import '../controllers/anime_controller.dart';

class AnimeEditScreen extends ConsumerStatefulWidget {
  /// Pass null or "new" for create.
  final String? animeId;

  const AnimeEditScreen({super.key, required this.animeId});

  bool get isNew => animeId == null || animeId == 'new';

  @override
  ConsumerState<AnimeEditScreen> createState() => _AnimeEditScreenState();
}

class _AnimeEditScreenState extends ConsumerState<AnimeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _isLoading = false;
  Anime? _existing;

  @override
  void initState() {
    super.initState();
    if (!widget.isNew) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(databaseProvider);
      final anime = await db.getAnimeById(widget.animeId!);
      if (anime == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Anime not found.')),
          );
          context.pop();
        }
        return;
      }
      _existing = anime;
      _nameController.text = anime.name;
      _descController.text = anime.description ?? '';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New Anime' : 'Edit Anime'),
        actions: [
          if (!widget.isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
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
                      hintText: 'e.g., K-On!',
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descController,
                    decoration: const InputDecoration(labelText: 'Description'),
                    maxLines: 4,
                  ),
                  if (_existing?.bangumiId != null) ...[
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Bangumi ID',
                        helperText: 'Imported from Anitabi',
                      ),
                      child: Text(_existing!.bangumiId!),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(widget.isNew ? 'Create' : 'Save'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    final success = await ref.read(animeControllerProvider.notifier).saveAnime(
      isNew: widget.isNew,
      id: widget.animeId,
      name: _nameController.text,
      description: _descController.text,
    );

    if (success && mounted) {
      context.pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save anime. Please try again.')),
      );
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.isNew) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Anime?'),
        content: Text(
          'This will remove "${_nameController.text}" and unlink it from all POIs. The POIs themselves are not deleted.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    await ref.read(databaseProvider).deleteAnime(widget.animeId!);
    if (mounted) context.pop();
  }
}
