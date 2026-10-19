import 'package:flutter/foundation.dart';

import '../../../../core/money/money.dart';
import 'account.dart';

class TrialBalanceLine {
  const TrialBalanceLine({
    required this.account,
    required this.debit,
    required this.credit,
  });

  final Account account;
  final Money debit;
  final Money credit;

  Money get balance => debit - credit;
}

class TrialBalance {
  TrialBalance({
    required Iterable<TrialBalanceLine> lines,
  }) : lines = List.unmodifiable(lines);

  final List<TrialBalanceLine> lines;

  Money get totalDebit {
    if (lines.isEmpty) {
      return const Money.zero();
    }
    return lines
        .map((line) => line.debit)
        .reduce((left, right) => left + right);
  }

  Money get totalCredit {
    if (lines.isEmpty) {
      return const Money.zero();
    }
    return lines
        .map((line) => line.credit)
        .reduce((left, right) => left + right);
  }

  bool get isBalanced => totalDebit == totalCredit;

  @override
  String toString() => describeIdentity(this);
}
