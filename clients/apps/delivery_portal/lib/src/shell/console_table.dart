import 'package:delivery_design_system/delivery_design_system.dart';
import 'package:flutter/material.dart';

import 'console_chrome.dart';

/// One column of a [ConsoleTable].
///
/// Widths are the design's: a flexible first column that carries the name, then fixed columns for
/// everything that should line up down the page. Give exactly one column [flex] unless you have a
/// reason not to.
class ConsoleColumn {
  const ConsoleColumn({
    required this.label,
    this.width,
    this.flex = 0,
    this.alignRight = false,
  }) : assert(width != null || flex > 0, 'a column needs a width or a flex');

  final String label;

  /// Fixed width in logical pixels — 150 for a category, 120 for a status, 100 for a count.
  final double? width;

  /// Takes the remaining width. The design gives this to the "name" column only.
  final int flex;

  /// The design right-aligns the actions column and nothing else.
  final bool alignRight;
}

/// One row's worth of cells, plus what happens when it is clicked.
class ConsoleTableRow {
  const ConsoleTableRow({required this.cells, this.onTap});

  /// Must be the same length as the table's columns.
  final List<Widget> cells;

  final VoidCallback? onTap;
}

/// The console's data table.
///
/// Figma `table-card` (3:2735): a white card clipping a slate header row over rows separated by 1px
/// hairlines — no zebra striping, 24 across and 16 down in every cell, and a fixed height per row
/// that comes from a 40px thumbnail plus its padding.
///
/// Scrolls sideways rather than compressing: the design's column widths are what make four tables
/// on four screens read as one table, and squeezing "Out for Delivery" into 80px to fit a laptop
/// would lose that for nothing.
class ConsoleTable extends StatelessWidget {
  const ConsoleTable({
    super.key,
    required this.columns,
    required this.rows,
    this.minWidth = 900,
    this.empty,
    this.footer,
  });

  final List<ConsoleColumn> columns;
  final List<ConsoleTableRow> rows;

  /// Below this the card scrolls horizontally instead of shrinking its columns.
  final double minWidth;

  /// Shown in place of the rows when there are none — an empty-state line, usually.
  final Widget? empty;

  /// Pinned under the last row inside the card: a pager, a total, a "showing 20 of 400".
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: ConsoleSurface.card(),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width =
              constraints.maxWidth.isFinite && constraints.maxWidth > minWidth
                  ? constraints.maxWidth
                  : minWidth;

          final Widget table = SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _HeaderRow(columns: columns),
                if (rows.isEmpty && empty != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ConsoleMetrics.cellPaddingX,
                      vertical: DeliverySpacing.xl,
                    ),
                    child: empty!,
                  )
                else
                  for (int i = 0; i < rows.length; i++)
                    _BodyRow(
                      columns: columns,
                      row: rows[i],
                      // The card's own border draws the last hairline, so the last row does not.
                      divided: i < rows.length - 1 || footer != null,
                    ),
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ConsoleMetrics.cellPaddingX,
                      vertical: ConsoleMetrics.cellPaddingY,
                    ),
                    child: footer!,
                  ),
              ],
            ),
          );

          if (constraints.maxWidth.isFinite && constraints.maxWidth >= minWidth) {
            return table;
          }
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: table,
          );
        },
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<ConsoleColumn> columns;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConsoleMetrics.cellPaddingX,
        vertical: ConsoleMetrics.cellPaddingY,
      ),
      decoration: const BoxDecoration(
        color: DeliveryColors.background,
        border: Border(bottom: BorderSide(color: DeliveryColors.border)),
      ),
      child: Row(
        children: <Widget>[
          for (final ConsoleColumn column in columns)
            _slot(
              column: column,
              child: Text(
                column.label,
                overflow: TextOverflow.ellipsis,
                textAlign: column.alignRight ? TextAlign.right : TextAlign.left,
                style: ConsoleText.tableHeader,
              ),
            ),
        ],
      ),
    );
  }
}

class _BodyRow extends StatelessWidget {
  const _BodyRow({
    required this.columns,
    required this.row,
    required this.divided,
  });

  final List<ConsoleColumn> columns;
  final ConsoleTableRow row;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ConsoleMetrics.cellPaddingX,
        vertical: ConsoleMetrics.cellPaddingY,
      ),
      decoration: BoxDecoration(
        border: divided
            ? const Border(bottom: BorderSide(color: DeliveryColors.border))
            : null,
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < columns.length; i++)
            _slot(
              column: columns[i],
              child: i < row.cells.length ? row.cells[i] : const SizedBox.shrink(),
            ),
        ],
      ),
    );

    if (row.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: row.onTap,
        hoverColor: DeliveryColors.background,
        child: content,
      ),
    );
  }
}

/// Places one cell in its column's slot — flexible or fixed, left or right.
Widget _slot({required ConsoleColumn column, required Widget child}) {
  final Widget aligned = Align(
    alignment: column.alignRight ? Alignment.centerRight : Alignment.centerLeft,
    child: child,
  );
  if (column.flex > 0) {
    return Expanded(flex: column.flex, child: aligned);
  }
  return SizedBox(width: column.width, child: aligned);
}

/// The design's row-end action buttons: a 26px tinted square around a 14px glyph.
///
/// [destructive] swaps the rose tint for the red one — the design uses `#fef2f2` behind the trash
/// glyph and `#fff1f2` behind the pencil, which are all but the same colour and carry two different
/// meanings. Here that is [DeliveryAccent.critical] against [DeliveryColors.brandSoft].
class ConsoleRowAction extends StatelessWidget {
  const ConsoleRowAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        destructive ? DeliveryAccent.critical.color : DeliveryColors.brand;
    final Color fill =
        destructive ? DeliveryAccent.critical.tint : DeliveryColors.brandSoft;
    final bool on = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: on ? fill : DeliveryColors.background,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 14,
              color: on ? foreground : DeliveryColors.faint,
            ),
          ),
        ),
      ),
    );
  }
}

/// The name cell the design draws on most tables: a 40px rounded thumbnail beside a SemiBold label.
class ConsoleNameCell extends StatelessWidget {
  const ConsoleNameCell({
    super.key,
    required this.name,
    this.leading,
    this.secondary,
  });

  final String name;

  /// The 40px square. Null draws nothing rather than a placeholder box — a table of grey squares
  /// says less than a table of names.
  final Widget? leading;

  /// A second line under the name, in the muted tier.
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(DeliveryRadius.sm),
            child: SizedBox(width: 40, height: 40, child: leading),
          ),
          const SizedBox(width: DeliverySpacing.md - DeliverySpacing.xs),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: ConsoleText.cellStrong,
              ),
              if (secondary != null)
                Text(
                  secondary!,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: DeliveryColors.muted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
