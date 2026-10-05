import 'package:flutter/material.dart';

abstract final class AppBreakpoints {
  static const compact = 600.0;
  static const tablet = 900.0;
  static const desktop = 1200.0;
  static const wide = 1600.0;
}

abstract final class ResponsiveLayout {
  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < AppBreakpoints.compact;

  static bool isTablet(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return width >= AppBreakpoints.compact && width < AppBreakpoints.desktop;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 380) return const EdgeInsets.all(12);
    if (width < AppBreakpoints.compact) return const EdgeInsets.all(16);
    if (width < AppBreakpoints.desktop) return const EdgeInsets.all(20);
    return const EdgeInsets.all(24);
  }

  static int gridColumns(
    double width, {
    int phone = 1,
    int tablet = 2,
    int desktop = 3,
    int wide = 4,
  }) {
    if (width >= AppBreakpoints.wide) return wide;
    if (width >= AppBreakpoints.desktop) return desktop;
    if (width >= AppBreakpoints.compact) return tablet;
    return phone;
  }
}

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.maxWidth = 1280,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: padding ?? ResponsiveLayout.pagePadding(context),
            child: child,
          ),
        ),
      );
}


class ResponsiveDialogContent extends StatelessWidget {
  const ResponsiveDialogContent({
    super.key,
    required this.child,
    this.maxWidth = 520,
    this.minWidth = 0,
  });

  final Widget child;
  final double maxWidth;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInsets = screenWidth < 380 ? 24.0 : 48.0;
    final available = (screenWidth - horizontalInsets).clamp(minWidth, maxWidth).toDouble();
    return SizedBox(width: available, child: child);
  }
}

class ResponsiveDataTable extends StatefulWidget {
  const ResponsiveDataTable({
    super.key,
    required this.headers,
    required this.rows,
  });

  final List<String> headers;
  final List<List<String>> rows;

  @override
  State<ResponsiveDataTable> createState() => _ResponsiveDataTableState();
}

class _ResponsiveDataTableState extends State<ResponsiveDataTable> {
  late final ScrollController _horizontalController;

  @override
  void initState() {
    super.initState();
    _horizontalController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AppBreakpoints.compact) {
            return ListView.separated(
              padding: ResponsiveLayout.pagePadding(context),
              itemCount: widget.rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final row = widget.rows[index];
                return Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < widget.headers.length && i < row.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    widget.headers[i],
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text(row[i])),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
          return Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: widget.headers
                      .map((header) => DataColumn(
                            label: Text(header, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ))
                      .toList(),
                  rows: widget.rows
                      .map((row) => DataRow(
                            cells: row.map((value) => DataCell(Text(value))).toList(),
                          ))
                      .toList(),
                ),
              ),
            ),
          );
        },
      );
}

class ResponsiveFormRow extends StatelessWidget {
  const ResponsiveFormRow({
    super.key,
    required this.children,
    this.breakpoint = 680,
    this.spacing = 10,
  });

  final List<Widget> children;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < breakpoint) {
            return Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1) SizedBox(height: spacing),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                Expanded(child: children[index]),
                if (index != children.length - 1) SizedBox(width: spacing),
              ],
            ],
          );
        },
      );
}
