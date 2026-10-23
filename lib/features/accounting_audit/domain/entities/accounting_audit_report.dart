enum AuditSeverity { error, warning }

extension AuditSeverityLabel on AuditSeverity {
  String get arabicLabel {
    switch (this) {
      case AuditSeverity.error:
        return 'خطأ';
      case AuditSeverity.warning:
        return 'تنبيه';
    }
  }
}

class AccountingAuditIssue {
  const AccountingAuditIssue({
    required this.code,
    required this.scope,
    required this.referenceId,
    required this.message,
    required this.severity,
    this.valueKind,
    this.currency,
    this.expected,
    this.actual,
  });

  final String code;
  final String scope;
  final String referenceId;
  final String message;
  final AuditSeverity severity;
  final String? valueKind;
  final String? currency;
  final int? expected;
  final int? actual;

  bool get isError => severity == AuditSeverity.error;

  factory AccountingAuditIssue.fromMap(Map<String, dynamic> map) {
    final severityName = map['severity'] as String? ?? 'error';
    final severity = AuditSeverity.values.firstWhere(
      (candidate) => candidate.name == severityName,
      orElse: () => AuditSeverity.error,
    );

    return AccountingAuditIssue(
      code: map['code'] as String? ?? 'UNKNOWN',
      scope: map['scope'] as String? ?? 'unknown',
      referenceId: map['referenceId'] as String? ?? '',
      message: map['message'] as String? ?? 'Unknown accounting issue.',
      severity: severity,
      valueKind: map['valueKind'] as String?,
      currency: map['currency'] as String?,
      expected: _intOrNull(map['expected']),
      actual: _intOrNull(map['actual']),
    );
  }

  static int? _intOrNull(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }
}

class AccountingAuditReport {
  const AccountingAuditReport({
    required this.storeId,
    required this.generatedAt,
    required this.accountsChecked,
    required this.journalEntriesChecked,
    required this.journalLinesChecked,
    required this.partiesChecked,
    this.indexedLineDiscoveryChecked = 0,
    this.orphanDiscoveryCoverage = '',
    required this.partyLedgerEntriesChecked,
    required this.productsChecked,
    required this.inventoryMovementsChecked,
    required this.issues,
    this.isComplete = true,
    this.isPointInTimeConsistent = false,
    this.serverStatus = '',
    this.reportedIssueCount,
    this.reportedErrorCount,
    this.issuesTruncated = false,
  });

  final String storeId;
  final DateTime generatedAt;
  final int accountsChecked;
  final int journalEntriesChecked;
  final int journalLinesChecked;
  final int indexedLineDiscoveryChecked;
  final String orphanDiscoveryCoverage;
  final int partiesChecked;
  final int partyLedgerEntriesChecked;
  final int productsChecked;
  final int inventoryMovementsChecked;
  final List<AccountingAuditIssue> issues;

  /// Whether the server examined the entire requested data scope.
  final bool isComplete;

  /// Whether all sources were read in one transactionally consistent snapshot.
  final bool isPointInTimeConsistent;
  final String serverStatus;
  final int? reportedIssueCount;
  final int? reportedErrorCount;
  final bool issuesTruncated;

  bool get isHealthy =>
      isComplete &&
      serverStatus != 'issues_found' &&
      errorCount == 0 &&
      issues.every((issue) => !issue.isError);
  int get errorCount =>
      reportedErrorCount ?? issues.where((issue) => issue.isError).length;
  int get warningCount => (reportedIssueCount ?? issues.length) - errorCount;

  factory AccountingAuditReport.fromMap(Map<String, dynamic> map) {
    final checked = _map(map['checked']);
    final rawIssues = map['issues'];
    final issues = rawIssues is List
        ? rawIssues
            .whereType<Map<Object?, Object?>>()
            .map(
              (issue) => AccountingAuditIssue.fromMap(
                Map<String, dynamic>.from(issue),
              ),
            )
            .toList(growable: false)
        : const <AccountingAuditIssue>[];

    return AccountingAuditReport(
      storeId: map['storeId'] as String? ?? '',
      generatedAt:
          DateTime.tryParse(map['generatedAt'] as String? ?? '')?.toUtc() ??
              DateTime.now().toUtc(),
      accountsChecked: _int(checked['accounts']),
      journalEntriesChecked: _int(checked['journalEntries']),
      journalLinesChecked: _int(checked['journalLines']),
      indexedLineDiscoveryChecked: _int(checked['indexedLineDiscovery']),
      orphanDiscoveryCoverage:
          map['orphanDiscoveryCoverage'] as String? ?? '',
      partiesChecked: _int(checked['parties']),
      partyLedgerEntriesChecked: _int(checked['partyLedgerEntries']),
      productsChecked: _int(checked['products']),
      inventoryMovementsChecked: _int(checked['inventoryMovements']),
      issues: List.unmodifiable(issues),
      isComplete: map['complete'] != false && map['status'] != 'incomplete',
      isPointInTimeConsistent: map['consistency'] == 'atomic',
      serverStatus: map['status'] as String? ?? '',
      reportedIssueCount:
          map['issueCount'] is int ? map['issueCount'] as int : null,
      reportedErrorCount:
          map['errorCount'] is int ? map['errorCount'] as int : null,
      issuesTruncated: map['issuesTruncated'] == true,
    );
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return const <String, dynamic>{};
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return 0;
  }
}
