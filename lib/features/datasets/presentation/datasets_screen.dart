import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/load_error.dart';
import '../../../core/widgets/screen_header.dart';
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
    context.canPop() ? context.pop() : context.go('/model');

/// Uploaded historical files, newest first, with the upload button.
class DatasetsScreen extends StatefulWidget {
  const DatasetsScreen({super.key, this.pick = pickExcelFile});

  final ExcelPicker pick;

  @override
  State<DatasetsScreen> createState() => _DatasetsScreenState();
}

class _DatasetsScreenState extends State<DatasetsScreen> {
  bool _uploading = false;

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
    final ready = controller.items.where((d) => d.isReady).toList();
    // Asked before the picker: a file may complement one that is already ready.
    final choice = ready.isEmpty
        ? (base: null as int?)
        : await _askBase(context, ready);
    if (choice == null || !mounted) return;
    final file = await widget.pick();
    if (file == null) return;
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
            ScreenHeader(
              title: 'Archivos históricos',
              subtitle: '.xlsx o .xlsm · máx. 100 MB',
              onBack: () => _back(context),
              action: HeaderAction(
                label: 'Subir archivo',
                onPressed: _uploading || c.trainingRunning ? null : _upload,
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
                text:
                    'Hay un entrenamiento en curso; espera a que termine para subir un archivo.',
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
          for (final d in c.items) _DatasetCard(dataset: d),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: AppRadius.large,
        child: InkWell(
          borderRadius: AppRadius.large,
          onTap: () => context.push('/datasets/${d.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.table_chart_outlined,
                      color: AppColors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        d.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    datasetPill(d.status),
                    Text(
                      formatDateTime(d.createdAt),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
                if (d.status == DatasetStatus.cleaning && d.rowCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: LinearProgressIndicator(
                      value: d.processedRowCount / d.rowCount,
                      minHeight: 5,
                    ),
                  ),
                if (d.status == DatasetStatus.failed)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Fue rechazado. Toca para ver la causa.',
                      style: TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
