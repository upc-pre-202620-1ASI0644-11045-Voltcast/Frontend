import '../../../core/format.dart';

/// `raw` -> `cleaning` -> `ready` | `failed`. A file that complements another
/// waits in `awaiting_confirmation` until the user confirms the merge.
enum DatasetStatus {
  raw('raw', 'En cola'),
  cleaning('cleaning', 'Procesando'),
  awaitingConfirmation('awaiting_confirmation', 'Esperando tu confirmación'),
  ready('ready', 'Listo'),
  failed('failed', 'Con error');

  const DatasetStatus(this.value, this.label);

  final String value;
  final String label;

  static DatasetStatus parse(String value) => DatasetStatus.values.firstWhere(
    (s) => s.value == value,
    orElse: () => DatasetStatus.failed,
  );
}

/// Present only once the file is `ready`.
class DatasetSummary {
  const DatasetSummary({
    required this.sections,
    required this.cellCount,
    required this.days,
    required this.newCells,
    this.dateFrom,
    this.dateTo,
  });

  /// Cells per section: {A: 150, B: 150}.
  final Map<String, int> sections;
  final int cellCount;
  final int days;
  final int newCells;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  factory DatasetSummary.fromJson(Map<String, dynamic> json) => DatasetSummary(
    sections: {
      for (final e in (json['sections'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
    cellCount: (json['n_cells'] as num? ?? 0).toInt(),
    days: (json['days'] as num? ?? 0).toInt(),
    newCells: (json['new_cells'] as num? ?? 0).toInt(),
    dateFrom: json['date_from'] is String
        ? parseApiDate(json['date_from'] as String)
        : null,
    dateTo: json['date_to'] is String
        ? parseApiDate(json['date_to'] as String)
        : null,
  );
}

/// What the merge would produce; present while `awaiting_confirmation`.
class MergeSummary {
  const MergeSummary({
    required this.baseFrom,
    required this.baseTo,
    required this.newFrom,
    required this.newTo,
    required this.gapDays,
    required this.overlapDays,
    required this.mergedDays,
    required this.baseDatasetId,
  });

  final DateTime baseFrom, baseTo, newFrom, newTo;
  final int gapDays, overlapDays, mergedDays, baseDatasetId;

  factory MergeSummary.fromJson(Map<String, dynamic> json) {
    DateTime day(String group, String key) =>
        parseApiDate((json[group] as Map<String, dynamic>)[key] as String);
    return MergeSummary(
      baseFrom: day('base', 'date_from'),
      baseTo: day('base', 'date_to'),
      newFrom: day('new', 'date_from'),
      newTo: day('new', 'date_to'),
      gapDays: (json['gap_days'] as num? ?? 0).toInt(),
      overlapDays: (json['overlap_days'] as num? ?? 0).toInt(),
      mergedDays: (json['merged_days'] as num? ?? 0).toInt(),
      baseDatasetId: (json['base_dataset_id'] as num? ?? 0).toInt(),
    );
  }
}

class Dataset {
  const Dataset({
    required this.id,
    required this.filename,
    required this.status,
    required this.rowCount,
    required this.processedRowCount,
    required this.createdAt,
    this.errorMessage,
    this.summary,
    this.merge,
    this.baseDatasetId,
  });

  final int id;
  final String filename;
  final DatasetStatus status;
  final String? errorMessage;
  final int rowCount;
  final int processedRowCount;
  final DateTime createdAt;
  final DatasetSummary? summary;
  final MergeSummary? merge;
  final int? baseDatasetId;

  /// Being processed by the backend: worth asking again soon.
  bool get isProcessing =>
      status == DatasetStatus.raw || status == DatasetStatus.cleaning;
  bool get isReady => status == DatasetStatus.ready;

  Dataset withSummaryFrom(Dataset? old) =>
      old?.summary == null || summary != null
      ? this
      : Dataset(
          id: id,
          filename: filename,
          status: status,
          rowCount: rowCount,
          processedRowCount: processedRowCount,
          createdAt: createdAt,
          errorMessage: errorMessage,
          summary: old!.summary,
          merge: merge,
          baseDatasetId: baseDatasetId,
        );

  factory Dataset.fromJson(Map<String, dynamic> json) {
    final status = DatasetStatus.parse(json['upload_status'] as String);
    final summary = json['summary'] is Map<String, dynamic>
        ? json['summary'] as Map<String, dynamic>
        : null;
    return Dataset(
      id: json['id'] as int,
      filename: json['filename'] as String,
      status: status,
      errorMessage: json['error_message'] as String?,
      rowCount: (json['row_count'] as num? ?? 0).toInt(),
      processedRowCount: (json['processed_row_count'] as num? ?? 0).toInt(),
      createdAt: parseApiDateTime(json['created_at'] as String),
      // The same `summary` key holds a different shape while it awaits confirmation.
      summary: status == DatasetStatus.ready && summary != null
          ? DatasetSummary.fromJson(summary)
          : null,
      merge: status == DatasetStatus.awaitingConfirmation && summary != null
          ? MergeSummary.fromJson(summary)
          : null,
      baseDatasetId: (json['base_dataset_id'] as num?)?.toInt(),
    );
  }
}
