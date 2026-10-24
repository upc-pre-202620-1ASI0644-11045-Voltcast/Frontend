import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/dialogs.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_buttons.dart';
import '../../../core/widgets/app_header.dart';
import '../../../core/widgets/app_widgets.dart';
import '../../../core/widgets/auth_visuals.dart';
import '../../../core/widgets/screen_header.dart';
import '../data/cell.dart';
import 'barcode_export.dart';
import 'cells_screen.dart' show LoadErrorView;
import 'inventory_controller.dart';

/// Signature of the download step; injectable so tests do not open a share sheet.
typedef BarcodeDownloader = Future<void> Function({required GlobalKey boundaryKey, required String fileName});

class BarcodeScreen extends StatefulWidget {
  const BarcodeScreen({super.key, this.initialCellId, this.downloader = shareBarcodePng});

  final int? initialCellId;
  final BarcodeDownloader downloader;

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final _barcodeKey = GlobalKey();
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialCellId;
  }

  Future<void> _generate(InventoryController inventory, Cell cell) =>
      runAction(context, () => inventory.generateBarcode(cell), 'Código generado para la celda ${cell.name}.');

  Future<void> _download(Cell cell) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.downloader(boundaryKey: _barcodeKey, fileName: 'codigo-celda-${cell.name}.png');
    } catch (_) {
      // Share sheets can fail for platform reasons (no handler, cancelled
      // permission); there is nothing useful to show beyond a plain message.
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo exportar el código. Inténtalo de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: 'Código de barras',
              subtitle: 'Identificación de celdas',
              onBack: () => context.canPop() ? context.pop() : context.go('/cells'),
            ),
            Expanded(child: _body(inventory)),
          ],
        ),
      ),
    );
  }

  Widget _body(InventoryController inventory) {
    if (!inventory.hasLoaded) {
      if (inventory.loading) {
        return const Center(child: CircularProgressIndicator(color: AppColors.blue));
      }
      return LoadErrorView(message: inventory.loadError ?? 'No se pudo cargar.', onRetry: inventory.load);
    }

    final cells = inventory.activeCells;
    if (cells.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Align(
          alignment: Alignment.topCenter,
          child: InfoBox(text: 'No hay celdas activas. Crea una celda para generar su código.'),
        ),
      );
    }

    // Falls back to the first cell when nothing (or a disabled cell) is selected.
    final cell = cells.firstWhere((c) => c.id == _selectedId, orElse: () => cells.first);
    final cathode = inventory.cathodeOf(cell)?.serialCode;
    final anode = inventory.anodeOf(cell)?.serialCode;
    final busy = inventory.isCellBusy(cell.id);

    return RefreshIndicator(
      color: AppColors.blue,
      onRefresh: inventory.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          AppCard(
            padding: const EdgeInsets.all(18),
            child: AppDropdown<Cell>(
              label: 'Celda',
              value: cell,
              items: {for (final c in cells) c: 'Celda ${c.name}'},
              onChanged: (c) => setState(() => _selectedId = c?.id),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFF0F1F4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'VISTA PREVIA',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.6,
                                color: AppColors.ink,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text('Generado dinámicamente', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                          ],
                        ),
                      ),
                      StatusPill.of(
                        cell.hasBarcode ? 'Disponible' : 'Pendiente',
                        cell.hasBarcode ? StatusPill.green : StatusPill.amber,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF0F1F4)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  child: cell.hasBarcode
                      ? Center(child: _BarcodeImage(boundaryKey: _barcodeKey, value: cell.barcodeValue!, cellName: cell.name))
                      : _PendingNotice(hasPair: inventory.hasCompletePair(cell)),
                ),
                const Divider(height: 1, color: Color(0xFFF0F1F4)),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _PairCell(label: 'Cátodo', serial: cathode)),
                      const VerticalDivider(width: 1, color: Color(0xFFF0F1F4)),
                      Expanded(child: _PairCell(label: 'Ánodo', serial: anode)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (cell.hasBarcode)
            PrimaryButton(
              label: 'Descargar PNG',
              onPressed: busy ? null : () => _download(cell),
            )
          else
            PrimaryButton(
              label: 'Generar código',
              loading: busy,
              onPressed: inventory.hasCompletePair(cell) ? () => _generate(inventory, cell) : null,
            ),
        ],
      ),
    );
  }
}

/// The Code 128 barcode plus its printed value, on a white background so the
/// exported PNG is ready to print.
class _BarcodeImage extends StatelessWidget {
  const _BarcodeImage({required this.boundaryKey, required this.value, required this.cellName});

  final GlobalKey boundaryKey;
  final String value;
  final String cellName;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: boundaryKey,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: value,
              width: 260,
              height: 96,
              drawText: false,
              color: const Color(0xFF111827),
              errorBuilder: (context, error) => Text('No se pudo dibujar el código: $error'),
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontSize: 14, letterSpacing: 1.2, color: Color(0xFF111827)),
            ),
            const SizedBox(height: 2),
            Text('VOLTCAST · CELDA $cellName', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.hasPair});

  final bool hasPair;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.qr_code_2, size: 56, color: AppColors.hint),
        const SizedBox(height: 12),
        const Text(
          'Esta celda aún no tiene código.',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          hasPair
              ? 'Genera el código para poder descargarlo.'
              : 'Asigna un cátodo y un ánodo a la celda para poder generarlo.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.muted),
        ),
      ],
    );
  }
}

class _PairCell extends StatelessWidget {
  const _PairCell({required this.label, required this.serial});

  final String label;
  final String? serial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
          const SizedBox(height: 6),
          Text(
            serial ?? 'Sin asignar',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: serial == null ? FontWeight.w400 : FontWeight.w700,
              color: serial == null ? AppColors.hint : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}
