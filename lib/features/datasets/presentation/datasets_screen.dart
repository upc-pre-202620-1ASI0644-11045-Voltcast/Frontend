import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/page_header.dart';
import '../data/dataset.dart';
import 'datasets_controller.dart';
import 'excel_picker.dart';

StatusPill datasetPill(DatasetStatus status) => switch (status) {
  DatasetStatus.raw => StatusPill.of(status.label, StatusPill.grey),
  DatasetStatus.cleaning => StatusPill.of(status.label, StatusPill.amber),
  DatasetStatus.awaitingConfirmation => StatusPill.of(
    status.label,
    StatusPill.blue,
  ),
  DatasetStatus.ready => StatusPill.of(status.label, StatusPill.green),
  DatasetStatus.failed => StatusPill(
    status.label,
    background: AppColors.errorSoft,
    color: AppColors.error,
  ),
};

void _back(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/settings');

enum _Filter {
  all('Todos'),
  ready('Listos'),
  failed('Con error');

  const _Filter(this.label);

  final String label;
}

/// Uploaded historical files, newest first, with the upload button.
class DatasetsScreen extends StatefulWidget {
  const DatasetsScreen({super.key, this.pick = pickExcelFile});

  final ExcelPicker pick;

  @override
  State<DatasetsScreen> createState() => _DatasetsScreenState();
}

class _DatasetsScreenState extends State<DatasetsScreen> {
  bool _uploading = false;
  String _query = '';
  _Filter _filter = _Filter.all;

  /// Why the last upload was refused; the screen stays where it is.
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    // After this frame: load() notifies, which must not happen while building.
    Future.microtask(context.read<DatasetsController>().load);
  }

  Future<void> _upload() async {
    final controller = context.read<DatasetsController>();
    final messenger = ScaffoldMessenger.of(context);
    final ready = controller.items.where((d) => d.isReady).toList();
    // Asked before the picker: a file may complement one that is already ready.
    final choice = ready.isEmpty
        ? (base: null as int?)
        : await _askBase(context, ready);
    if (choice == null || !mounted) return;
    final file = await widget.pick();
    if (file == null) return;
    final lower = file.name.toLowerCase();
    if (!lower.endsWith('.xlsx') && !lower.endsWith('.xlsm')) {
      // The picker already filters, but a drag-and-drop or another picker may not.
      setState(
        () => _uploadError =
            'El formato no es compatible. Sube un archivo de Excel (.xlsx o .xlsm).',
      );
      return;
    }
    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      await controller.upload(
        file.name,
        file.bytes,
        baseDatasetId: choice.base,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text('«${file.name}» se subió correctamente y se está procesando.'),
        ),
      );
    } on ApiException catch (e) {
      _uploadError = e.message;
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DatasetsController>();
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Biblioteca de datos',
              title: 'Archivos históricos',
              onBack: () => _back(context),
              trailing: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c.items.length} ${c.items.length == 1 ? 'archivo' : 'archivos'} · Excel',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _uploading || c.trainingRunning ? null : _upload,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Subir Excel'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      minimumSize: const Size(0, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_uploading) const LinearProgressIndicator(minHeight: 3),
            Expanded(child: _body(c)),
          ],
        ),
      ),
    );
  }

  Widget _body(DatasetsController c) {
    if (!c.hasLoaded) {
      return c.loading
          ? const Center(child: CircularProgressIndicator())
          : LoadErrorView(
              message: c.error ?? 'No se pudo cargar.',
              onRetry: c.load,
            );
    }
    final shown = c.items.where((d) {
      final matches = switch (_filter) {
        _Filter.all => true,
        _Filter.ready => d.isReady,
        _Filter.failed => d.status == DatasetStatus.failed,
      };
      return matches &&
          d.filename.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (c.trainingRunning) ...[
            ClipRRect(
              borderRadius: AppRadius.medium,
              child: const NoticeBanner(
                icon: Icons.model_training,
                text: 'Hay un entrenamiento en curso; espera a que termine para subir un archivo.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_uploadError != null) ...[
            ErrorBanner(_uploadError!),
            const SizedBox(height: 12),
          ],
          if (c.error != null) ...[
            ErrorBanner(c.error!),
            const SizedBox(height: 12),
          ],
          if (c.items.isEmpty)
            const SizedBox(
              height: 320,
              child: EmptyState(
                icon: Icons.upload_file,
                title: 'Aún no hay archivos',
                message: 'Sube un archivo de Excel con las lecturas de voltaje de las celdas.',
              ),
            ),
          if (c.items.isNotEmpty) ...[
            SearchField(
              hint: 'Buscar archivo…',
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final f in _Filter.values)
                  ChoiceChip(
                    label: Text(f.label),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    showCheckmark: false,
                    shape: const StadiumBorder(side: BorderSide.none),
                    backgroundColor: AppColors.field,
                    selectedColor: AppColors.blue,
                    labelStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _filter == f ? Colors.white : AppColors.ink,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    'Ningún archivo coincide.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          ],
          for (final d in shown) _DatasetCard(dataset: d),
        ],
      ),
    );
  }
}

/// "Este archivo complementa a: …". Null when the user backs out; `base` null
/// when the file stands alone.
Future<({int? base})?> _askBase(BuildContext context, List<Dataset> ready) {
  return showDialog<({int? base})>(
    context: context,
    builder: (context) {
      int? selected;
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text(
            'Este archivo complementa a:',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: SingleChildScrollView(
            child: RadioGroup<int?>(
              groupValue: selected,
              onChanged: (v) => setState(() => selected = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const RadioListTile<int?>(
                    value: null,
                    title: Text('Ninguno, es un archivo nuevo'),
                  ),
                  for (final d in ready)
                    RadioListTile<int?>(
                      value: d.id,
                      title: Text(d.filename),
                      subtitle: d.summary?.dateFrom == null
                          ? null
                          : Text(
                              '${formatShortDate(d.summary!.dateFrom!)} – ${formatShortDate(d.summary!.dateTo!)}',
                            ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, (base: selected)),
              child: const Text('Elegir archivo'),
            ),
          ],
        ),
      );
    },
  );
}

class _DatasetCard extends StatelessWidget {
  const _DatasetCard({required this.dataset});

  final Dataset dataset;

  @override
  Widget build(BuildContext context) {
    final d = dataset;
    final s = d.summary;
    const small = TextStyle(fontSize: 13, color: AppColors.muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: AppRadius.large,
        child: InkWell(
          borderRadius: AppRadius.large,
          onTap: () => context.push('/datasets/${d.id}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ExcelIcon(size: 64),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          datasetPill(d.status),
                          const SizedBox(height: 8),
                          Text(
                            d.filename,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(formatDateTime(d.createdAt), style: small),
                        ],
                      ),
                    ),
                  ],
                ),
                if (d.status == DatasetStatus.cleaning && d.rowCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(
                      value: d.processedRowCount / d.rowCount,
                      minHeight: 5,
                    ),
                  ),
                const Divider(height: 24, color: Color(0xFFF0F1F4)),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s != null
                            ? '${s.cellCount} celdas · ${s.days} días'
                            : d.status == DatasetStatus.failed
                            ? 'Revisar estructura'
                            : '',
                        style: d.status == DatasetStatus.failed
                            ? small.copyWith(color: AppColors.error)
                            : small,
                      ),
                    ),
                    const Text(
                      'Ver detalle',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.blue,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.blue,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
