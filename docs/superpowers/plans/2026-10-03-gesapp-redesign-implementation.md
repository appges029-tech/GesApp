# GesApp Premium Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved premium GesApp UI/UX redesign across all 64 existing screens while preserving the audited business logic, permissions, persistence, synchronization, calculations, and exports.

**Architecture:** Introduce one central Material 3 design system under `lib/core/design_system/`, adapt the existing responsive/Windows wrappers to delegate to it, then migrate the product progressively by module. Existing repositories/providers remain the source of truth; screens adapt their current `AsyncValue`/model data into reusable presentation components without adding a parallel business layer.

**Tech Stack:** Flutter 3.47.x, Dart 3.13.x, Material 3, Riverpod 2.6.1, existing SQLite/Supabase stack, `fl_chart: ^1.2.0` for reusable dashboard charts, `flutter_test`, `integration_test`, built-in Flutter golden testing.

**Spec:** `docs/superpowers/specs/2026-10-03-gesapp-redesign-design.md`

## Global Constraints

- Keep `useMaterial3: true` and the existing Riverpod/providers/repositories architecture.
- Keep the breakpoints `600 / 900 / 1200 / 1600` as the product-wide source of responsive behavior.
- Desktop expanded sidebar width is exactly `252 px`; compact desktop sidebar is constrained to `72–80 px` and implemented at `76 px`.
- Do not change SQLite/Supabase schemas, financial calculations, permissions, authentication, offline/cloud strategy, payroll, assets, or recovery rules for visual reasons.
- Preserve every existing feature and action across the 64 screens; do not simplify by deleting functionality.
- Mobile (`<600 px`) must expose essential data/actions without horizontal business-content scrolling.
- All product copy remains French and existing FCFA/XAF formatters stay authoritative.
- Light and dark themes are implemented together; no end-of-project automatic inversion pass.
- Interactive mobile targets must be at least `44x44` logical pixels; focus indicators must remain visibly distinct on desktop/Web.
- Status must never be communicated by color alone: every badge includes readable text and, where useful, an icon.
- Existing administrator read-only behavior must remain effective after every migration task.
- Each task must leave the application analyzable/testable before the next task begins.

## Review Focus

1. **Administrator read-only leakage:** migrated screens must not re-expose create/edit/delete/import/restore controls. Pin with widget tests in Tasks 4, 7, 8, 10, 11, and 13.
2. **390 px overflow / accidental horizontal scrolling:** every list/detail/form family must be pumped at `390x844` and assert no Flutter overflow exceptions. Pin in Tasks 3 and 6–13.
3. **Breakpoint transitions after live window resizing:** navigation and list/table representations must switch without losing the selected module or throwing layout errors. Pin in Tasks 3 and 4.
4. **Async loading/error/empty states:** migrated screens must show the shared skeleton/error/empty primitives rather than blank pages or indefinite spinners. Pin in Tasks 2 and 6–13.
5. **Dark-theme/accessibility regressions:** critical screens must preserve status semantics, focus order, readable labels, and visible focus rings in both themes. Pin in Tasks 2, 4, 5, and 14.

---

### Task 1: Design Tokens, Theme Foundation, and Test Harness

**Files:**
- Create: `lib/core/design_system/gesapp_colors.dart`
- Create: `lib/core/design_system/gesapp_spacing.dart`
- Create: `lib/core/design_system/gesapp_radius.dart`
- Create: `lib/core/design_system/gesapp_typography.dart`
- Create: `lib/core/design_system/gesapp_elevation.dart`
- Create: `lib/core/design_system/gesapp_breakpoints.dart`
- Create: `lib/core/design_system/gesapp_theme_extensions.dart`
- Create: `lib/core/design_system/gesapp_component_theme.dart`
- Create: `test/helpers/gesapp_widget_test_harness.dart`
- Create: `test/helpers/gesapp_golden_sizes.dart`
- Create: `test/design_system_tokens_test.dart`
- Modify: `lib/core/theme/app_colors.dart`
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `lib/core/layout/responsive_layout.dart`
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `GesAppColors`, `GesAppSpacing`, `GesAppRadius`, `GesAppTypography`, `GesAppElevation`, `GesAppBreakpoints`, `GesAppThemeExtension`.
- Produces: `GesAppComponentTheme.apply(ThemeData base, {required bool compactDesktop}) -> ThemeData`.
- Produces: `pumpGesApp(WidgetTester tester, Widget child, {Size size, Brightness brightness}) -> Future<void>` for later widget/golden tests.
- Compatibility: `AppColors` remains as a deprecated alias/facade to semantic `GesAppColors` values; `AppBreakpoints` retains its public names but delegates to `GesAppBreakpoints`.

- [ ] **Step 1: Write failing token/theme tests**

Create `test/design_system_tokens_test.dart` with assertions for the exact reference colors (`#071D3B`, `#1877F2`, `#F5F7FB`, `#12B76A`, `#F79009`, `#F04438`), exact breakpoints `600/900/1200/1600`, desktop widths `252/76`, and light/dark `ThemeData` exposing `GesAppThemeExtension`.

- [ ] **Step 2: Run the new tests and verify they fail**

Run: `flutter test test/design_system_tokens_test.dart`

Expected: FAIL because `lib/core/design_system/*` does not exist yet.

- [ ] **Step 3: Implement the tokens and theme bridge**

Keep tokens semantic rather than screen-specific. Move existing values behind the new design system, preserve public `AppColors`/`AppBreakpoints` access during migration, and make `AppTheme.light/dark/windowsLight/windowsDark` consume the same semantic source.

- [ ] **Step 4: Add the shared widget/golden harness**

`pumpGesApp` must set an explicit surface size, install `AppTheme.light` or `AppTheme.dark`, settle frames, and reset the test view after each test. Define constants for `390x844`, `768x1024`, `1024x768`, `1440x900`, `1600x1000`.

- [ ] **Step 5: Add chart dependency and bump the redesign development version**

Modify `pubspec.yaml` to `version: 2.3.0+44` and add `fl_chart: ^1.2.0`. Run `flutter pub get` and commit the resulting lockfile update if `pubspec.lock` is tracked.

- [ ] **Step 6: Verify**

Run: `dart format lib/core/design_system lib/core/theme lib/core/layout test/helpers test/design_system_tokens_test.dart`

Run: `flutter analyze`

Run: `flutter test test/design_system_tokens_test.dart`

Expected: all PASS/no analyzer errors.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/design_system lib/core/theme lib/core/layout test/helpers test/design_system_tokens_test.dart
git commit -m "feat(ui): add GesApp design system foundations"
```

### Task 2: Atomic Components and Unified Data States

**Files:**
- Create: `lib/core/design_system/components/gesapp_panel.dart`
- Create: `lib/core/design_system/components/gesapp_page_header.dart`
- Create: `lib/core/design_system/components/gesapp_status_badge.dart`
- Create: `lib/core/design_system/components/gesapp_money_value.dart`
- Create: `lib/core/design_system/components/gesapp_kpi_card.dart`
- Create: `lib/core/design_system/components/gesapp_metric_card.dart`
- Create: `lib/core/design_system/components/gesapp_empty_state.dart`
- Create: `lib/core/design_system/components/gesapp_error_state.dart`
- Create: `lib/core/design_system/components/gesapp_loading_skeleton.dart`
- Create: `lib/core/design_system/components/gesapp_confirm_dialog.dart`
- Create: `lib/core/design_system/components/gesapp_activity_item.dart`
- Create: `test/design_system_components_test.dart`

**Interfaces:**
- Produces: `enum GesAppStatusTone { success, warning, danger, info, neutral }`.
- Produces: `GesAppStatusBadge({required String label, required GesAppStatusTone tone, IconData? icon})`.
- Produces: `GesAppPageHeader({required String title, String? description, Widget? primaryAction, List<Widget> actions = const [], Widget? breadcrumb, bool readOnly = false})`.
- Produces: `GesAppPanel({required Widget child, EdgeInsetsGeometry? padding, String? semanticLabel})`.
- Produces: `GesAppEmptyState`, `GesAppErrorState(onRetry:)`, and `GesAppLoadingSkeleton` for all later async screens.
- Consumes: `Formatters`/existing amount formatting; `GesAppMoneyValue` must not introduce independent FCFA formatting rules.

- [ ] **Step 1: Write failing component tests**

Assert: status badges contain visible text; warning/danger/success differ semantically; page header hides write actions when `readOnly=true`; primary controls have at least `44x44`; error state exposes a retry action; dark/light themes render without exceptions.

- [ ] **Step 2: Run tests and confirm failure**

Run: `flutter test test/design_system_components_test.dart`

Expected: FAIL because components are absent.

- [ ] **Step 3: Implement components with no repository imports**

Every component accepts prepared values/callbacks only. Do not import any file under `lib/data/repositories/` from `lib/core/design_system/`.

- [ ] **Step 4: Add accessibility semantics**

`GesAppStatusBadge` and `GesAppMoneyValue` expose meaningful semantic labels; icon-only actions in shared headers/dialogs require tooltip/semantic labels.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze`

Run: `flutter test test/design_system_components_test.dart`

```bash
git add lib/core/design_system/components test/design_system_components_test.dart
git commit -m "feat(ui): add reusable GesApp presentation primitives"
```

### Task 3: Responsive Composites and Legacy Compatibility Bridges

**Files:**
- Create: `lib/core/design_system/components/gesapp_filter_bar.dart`
- Create: `lib/core/design_system/components/gesapp_responsive_list.dart`
- Create: `lib/core/design_system/components/gesapp_data_table.dart`
- Create: `lib/core/design_system/components/gesapp_entity_card.dart`
- Create: `lib/core/design_system/components/gesapp_entity_header.dart`
- Create: `lib/core/design_system/components/gesapp_info_section.dart`
- Create: `lib/core/design_system/components/gesapp_form_section.dart`
- Create: `lib/core/design_system/components/gesapp_section_tabs.dart`
- Create: `lib/core/design_system/components/gesapp_module_card.dart`
- Create: `lib/core/design_system/components/gesapp_chart_card.dart`
- Create: `test/responsive_components_test.dart`
- Modify: `lib/core/layout/responsive_layout.dart`
- Modify: `lib/core/windows/windows_page_scaffold.dart`
- Modify: `lib/core/windows/windows_panels.dart`
- Modify: `lib/core/windows/windows_filter_panel.dart`
- Modify: `lib/core/windows/windows_ui.dart`

**Interfaces:**
- Produces: `GesAppResponsiveList<T>({required List<T> items, required Widget Function(BuildContext,T) mobileItemBuilder, required Widget Function(BuildContext,List<T>) desktopBuilder, double switchWidth = 600})`.
- Produces: `GesAppDataTable<T>` with typed rows, column descriptors, row action builder, and a required `mobileCardBuilder` so mobile never relies on horizontal table scrolling.
- Produces: `GesAppEntityHeader`, `GesAppInfoSection`, `GesAppFormSection`, `GesAppSectionTabs`, and `GesAppModuleCard` used by module migrations.
- Compatibility: `WindowsPageScaffold`, `WindowsPanel`, `WindowsModuleCard`, `WindowsModuleGrid`, and `WindowsFilterPanel` retain their constructors and delegate internally to design-system components.

- [ ] **Step 1: Write failing responsive tests**

Pump representative components at `390`, `768`, `1024`, `1440`, and resize one widget from `1440` to `390`. Assert no `RenderFlex overflow`, selected state survives rebuild, `GesAppDataTable` uses the mobile card builder below 600, and legacy wrappers still render.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/responsive_components_test.dart`

- [ ] **Step 3: Implement typed adaptive composites**

Use `LayoutBuilder` for local component structure and `MediaQuery.sizeOf` only for app-window-level choices. Do not detect Android/Windows/iOS to choose layouts.

- [ ] **Step 4: Bridge legacy wrappers**

Keep old call sites compiling while visually routing them through the new panels/module cards/filter treatment. Do not delete the legacy files in this task.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze`

Run: `flutter test test/responsive_components_test.dart test/windows_fluent_layout_test.dart`

```bash
git add lib/core/design_system/components lib/core/layout lib/core/windows test/responsive_components_test.dart
git commit -m "feat(ui): add adaptive component system and legacy bridges"
```

### Task 4: Global Shell, Sidebar, Topbar, and Navigation

**Files:**
- Create: `lib/core/design_system/navigation/gesapp_navigation.dart`
- Create: `lib/core/design_system/navigation/gesapp_sidebar.dart`
- Create: `lib/core/design_system/navigation/gesapp_top_bar.dart`
- Create: `lib/core/design_system/navigation/gesapp_page_shell.dart`
- Create: `lib/core/design_system/navigation/gesapp_more_sheet.dart`
- Create: `test/home_shell_redesign_test.dart`
- Modify: `lib/app/home_shell.dart`
- Modify: `lib/app/app_navigation.dart`

**Interfaces:**
- Produces: `class GesAppDestination { String id; String label; IconData icon; IconData selectedIcon; Widget page; }`.
- Produces: one canonical destination list for `dashboard, students, finance, expenses, hr, assets, reports, settings`.
- Produces: mobile destinations `dashboard, students, finance, reports, more` and desktop expanded/compact variants from the same list.
- Produces: `GesAppTopBar({required ValueChanged<String> onSearchSubmitted, required VoidCallback onNotifications, required Widget profile})`.
- Global search rule: direct module-name matches navigate immediately; student/payment/report queries delegate only to already public search/navigation flows. No new DB/index/provider is introduced.
- Preserves: current cloud lifecycle synchronization, `OperatorSession.isAdmin` banner/behavior, and sign-out flow.

- [ ] **Step 1: Write failing shell tests**

Assert exact expanded width `252`, compact width `76`, bottom navigation below 600, selected destination preserved through a `1440 -> 1000 -> 390 -> 1440` resize, tooltips on compact icons, admin read-only banner still visible, and no write permission is inferred from navigation state.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/home_shell_redesign_test.dart`

- [ ] **Step 3: Implement shared destination model and shell**

Replace duplicated `NavigationDestination`/`NavigationRailDestination` construction with `GesAppDestination`. The desktop shell owns the navy sidebar and topbar; page bodies own page headers, not separate desktop `AppBar`s.

- [ ] **Step 4: Implement lightweight topbar search routing**

Search must always offer module navigation. Only call existing screen/provider search entry points where a stable public API already exists; otherwise open the relevant module with the query passed as initial UI filter when supported.

- [ ] **Step 5: Verify admin/read-only and lifecycle behavior**

Run: `flutter test test/home_shell_redesign_test.dart test/audit75_regression_test.dart integration_test/audit75_flows_test.dart -d windows` when Windows integration execution is available; otherwise keep the integration command for Task 15.

- [ ] **Step 6: Commit**

```bash
git add lib/core/design_system/navigation lib/app test/home_shell_redesign_test.dart
git commit -m "feat(ui): redesign GesApp adaptive application shell"
```

### Task 5: Dashboard Redesign and Shared Charts

**Files:**
- Create: `lib/features/dashboard/widgets/dashboard_kpi_grid.dart`
- Create: `lib/features/dashboard/widgets/dashboard_revenue_chart.dart`
- Create: `lib/features/dashboard/widgets/dashboard_payment_distribution.dart`
- Create: `lib/features/dashboard/widgets/dashboard_recent_activity.dart`
- Create: `test/dashboard_redesign_test.dart`
- Create: `test/goldens/dashboard_light_1440.png` (generated)
- Create: `test/goldens/dashboard_dark_1440.png` (generated)
- Create: `test/goldens/dashboard_mobile_390.png` (generated)
- Modify: `lib/features/dashboard/dashboard_screen.dart`

**Interfaces:**
- Consumes only existing `dashboardProvider` and `establishmentProvider` outputs.
- Produces chart widgets that accept plain numeric/label series; chart widgets must not import repositories/providers.
- `DashboardRevenueChart` uses `fl_chart` line chart; `DashboardPaymentDistribution` uses a pie/donut chart; both expose a textual semantic summary.

- [ ] **Step 1: Write failing dashboard widget tests**

Test KPI rendering with fixture data, setup banner preservation, loading/error states, 390 px no-overflow behavior, dark rendering, and semantic text equivalents for both charts.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/dashboard_redesign_test.dart`

- [ ] **Step 3: Migrate dashboard using existing providers**

Replace local `_KpiCard`/hero presentation helpers with the shared components. Keep every provider invalidation/refresh callback intact.

- [ ] **Step 4: Generate and inspect golden baselines**

Run: `flutter test test/dashboard_redesign_test.dart --update-goldens`

Manually compare the generated desktop layout against `docs/superpowers/specs/assets/gesapp-redesign-reference.png` for visual hierarchy, not literal fictional data.

- [ ] **Step 5: Verify and commit**

Run: `flutter analyze`

Run: `flutter test test/dashboard_redesign_test.dart`

```bash
git add lib/features/dashboard test/dashboard_redesign_test.dart test/goldens
git commit -m "feat(ui): redesign dashboard with adaptive KPI and chart layout"
```

### Task 6: Students and Families — 8 Screens

**Files:**
- Create: `lib/features/students/widgets/student_list_item.dart`
- Create: `lib/features/students/widgets/student_identity_header.dart`
- Create: `lib/features/students/widgets/student_detail_sections.dart`
- Create: `test/students_redesign_test.dart`
- Create/update goldens: `test/goldens/students_*`, `test/goldens/student_detail_*`
- Modify all 8 screens:
  - `lib/features/students/students_screen.dart`
  - `lib/features/students/student_detail_screen.dart`
  - `lib/features/students/student_form_screen.dart`
  - `lib/features/students/families_screen.dart`
  - `lib/features/students/family_detail_screen.dart`
  - `lib/features/students/student_guardians_screen.dart`
  - `lib/features/students/student_bulk_import_screen.dart`
  - `lib/features/students/document_verification_screen.dart`

**Interfaces:**
- `StudentListItem` accepts existing `Student` data plus callbacks; no repository access.
- Student detail uses `GesAppEntityHeader` and sections/tabs for identity, schooling, guardians, finance/documents/history only where the current screen already exposes those flows.
- Existing navigation routes, import service, document verification, and guardian mutations are preserved.

- [ ] **Step 1: Write failing students tests**

At `1440`: assert table/list headers, filters, row actions, and detail sections. At `390`: assert cards replace wide rows, all primary actions remain reachable, and no horizontal overflow occurs. Add an admin session case asserting mutation controls are absent/disabled.

- [ ] **Step 2: Run failing tests**

Run: `flutter test test/students_redesign_test.dart`

- [ ] **Step 3: Migrate list/detail reference screens first**

Migrate `students_screen.dart` and `student_detail_screen.dart`; treat them as the canonical list/detail pattern for later HR/assets tasks.

- [ ] **Step 4: Migrate forms/families/guardians/import/verification**

Reuse `GesAppFormSection`, `GesAppInfoSection`, `GesAppFilterBar`, shared async states, and existing callbacks/services unchanged.

- [ ] **Step 5: Golden + regression verification**

Run: `flutter test test/students_redesign_test.dart --update-goldens`

Run: `flutter test test/students_redesign_test.dart test/security_hr_asset_repository_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/features/students test/students_redesign_test.dart test/goldens
git commit -m "feat(ui): migrate students and families to premium design system"
```

### Task 7: Finance Hub, Tables, and Read-Oriented Screens — 8 Screens

**Files:**
- Create: `lib/features/finance/widgets/finance_summary_cards.dart`
- Create: `lib/features/finance/widgets/finance_transaction_row.dart`
- Create: `test/finance_redesign_lists_test.dart`
- Modify:
  - `lib/features/finance/finance_screen.dart`
  - `lib/features/finance/payments_screen.dart`
  - `lib/features/finance/dues_screen.dart`
  - `lib/features/finance/cash_screen.dart`
  - `lib/features/finance/recovery_screen.dart`
  - `lib/features/finance/accounting_screen.dart`
  - `lib/features/finance/supplier_accounting_screen.dart`
  - `lib/features/finance/bank_reconciliation_screen.dart`

**Interfaces:**
- Hub uses `GesAppModuleCard` only; all existing module routes stay intact.
- Tables use `GesAppDataTable<T>` with explicit `mobileCardBuilder`.
- Money display delegates to existing formatters through `GesAppMoneyValue`.
- No finance repository/service method signatures change.

- [ ] **Step 1: Write failing finance-list tests**

Cover desktop filters/tables, mobile cards, paid/pending/late status text, zero/large FCFA values, loading/error/empty states, and admin read-only actions.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/finance_redesign_lists_test.dart`

- [ ] **Step 3: Migrate finance hub and payment/dues views**

Preserve existing provider subscriptions, filters, export/PDF buttons, and callbacks; only replace presentation structure.

- [ ] **Step 4: Migrate cash/recovery/accounting/supplier/bank views**

Keep all calculations sourced from existing repositories. Do not recompute balances in widgets.

- [ ] **Step 5: Regression verification**

Run: `flutter test test/finance_redesign_lists_test.dart test/finance_repository_test.dart test/finance_engine_test.dart test/audit50_regression_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/features/finance test/finance_redesign_lists_test.dart
git commit -m "feat(ui): redesign finance hubs and financial tables"
```

### Task 8: Finance Forms, Configuration, Generation, and Verification — 8 Screens

**Files:**
- Create: `test/finance_redesign_forms_test.dart`
- Modify:
  - `lib/features/finance/payment_form_screen.dart`
  - `lib/features/finance/dues_generation_screen.dart`
  - `lib/features/finance/packages_screen.dart`
  - `lib/features/finance/fee_categories_screen.dart`
  - `lib/features/finance/fee_grid_screen.dart`
  - `lib/features/finance/manual_journal_entry_screen.dart`
  - `lib/features/finance/accounting_settings_screen.dart`
  - `lib/features/finance/receipt_verification_screen.dart`

**Interfaces:**
- All long forms use `GesAppFormSection`; fields remain bound to current controllers/models.
- Primary submit handlers and validation logic remain the current implementations.
- Desktop may render short fields in two columns; mobile always renders one column.

- [ ] **Step 1: Write failing form/config tests**

Cover `390`/`1024` layouts, inline validation, submit/loading states, destructive confirmations, keyboard focus traversal for representative payment/manual-entry forms, and admin read-only behavior.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/finance_redesign_forms_test.dart`

- [ ] **Step 3: Migrate form/config screens without moving validation into components**

Presentation components receive current error text/callbacks; business validation stays in screen/provider/service code where it currently lives.

- [ ] **Step 4: Regression verification**

Run: `flutter test test/finance_redesign_forms_test.dart test/payment_notice_batch_pdf_service_test.dart test/receipt_service_test.dart test/receipt_printing_preferences_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/finance test/finance_redesign_forms_test.dart
git commit -m "feat(ui): redesign finance forms and configuration screens"
```

### Task 9: Expenses — 3 Screens

**Files:**
- Create: `test/expenses_redesign_test.dart`
- Modify:
  - `lib/features/expenses/expenses_screen.dart`
  - `lib/features/expenses/expense_form_screen.dart`
  - `lib/features/expenses/recurring_expenses_screen.dart`

**Interfaces:**
- Expense list uses the same finance list grammar and status badges.
- Recurrence enabled/disabled state must remain sourced from the existing repository data and must not be toggled by visual rebuilds.

- [ ] **Step 1: Write failing tests**

Cover list/table-to-card transition, recurrence status text, form field stacking, proof/document actions, async states, and admin read-only controls.

- [ ] **Step 2: Run failing tests**

Run: `flutter test test/expenses_redesign_test.dart`

- [ ] **Step 3: Migrate three screens using shared finance/form primitives**

- [ ] **Step 4: Verify regression and commit**

Run: `flutter test test/expenses_redesign_test.dart test/audit75_regression_test.dart`

```bash
git add lib/features/expenses test/expenses_redesign_test.dart
git commit -m "feat(ui): migrate expenses to shared financial design language"
```

### Task 10: Human Resources — 9 Screens

**Files:**
- Create: `lib/features/hr/widgets/employee_list_item.dart`
- Create: `lib/features/hr/widgets/employee_identity_header.dart`
- Create: `test/hr_redesign_test.dart`
- Modify all 9 HR screens:
  - `lib/features/hr/hr_screen.dart`
  - `lib/features/hr/employees_screen.dart`
  - `lib/features/hr/employee_detail_screen.dart`
  - `lib/features/hr/employee_form_screen.dart`
  - `lib/features/hr/attendance_screen.dart`
  - `lib/features/hr/leave_screen.dart`
  - `lib/features/hr/payroll_screen.dart`
  - `lib/features/hr/hr_reports_screen.dart`
  - `lib/features/hr/hr_configuration_screen.dart`

**Interfaces:**
- Employee list/detail intentionally mirror the Student list/detail component grammar.
- Existing HR repository, payroll calculations, attendance/leave mutations, PDF generation, and permissions stay unchanged.

- [ ] **Step 1: Write failing HR tests**

Test 390/1440 list/detail/form rendering, employee status badges, attendance/leave/payroll states, error recovery (including prior indefinite-loading failure mode), and admin read-only actions.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/hr_redesign_test.dart`

- [ ] **Step 3: Migrate employees/detail/form, then attendance/leave/payroll/reports/config**

- [ ] **Step 4: Verify**

Run: `flutter test test/hr_redesign_test.dart test/security_hr_asset_repository_test.dart test/audit100_regression_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/hr test/hr_redesign_test.dart
git commit -m "feat(ui): redesign human resources module"
```

### Task 11: Assets and Patrimony — 8 Screens

**Files:**
- Create: `lib/features/assets/widgets/asset_list_item.dart`
- Create: `lib/features/assets/widgets/asset_identity_header.dart`
- Create: `test/assets_redesign_test.dart`
- Modify all 8 assets screens:
  - `lib/features/assets/assets_screen.dart`
  - `lib/features/assets/asset_list_screen.dart`
  - `lib/features/assets/asset_detail_screen.dart`
  - `lib/features/assets/asset_form_screen.dart`
  - `lib/features/assets/asset_inventory_screen.dart`
  - `lib/features/assets/asset_maintenance_screen.dart`
  - `lib/features/assets/asset_reports_screen.dart`
  - `lib/features/assets/asset_configuration_screen.dart`

**Interfaces:**
- Asset detail uses the same `GesAppEntityHeader + GesAppSectionTabs + GesAppInfoSection` structure as Student/Employee.
- Asset status labels normalize visually but keep exact underlying status values and repository rules.

- [ ] **Step 1: Write failing asset tests**

Cover list/detail/form at mobile/desktop sizes, inventory closed state, maintenance/out-of-service presentation, sale amount display, empty/error states, and admin read-only controls.

- [ ] **Step 2: Run tests and verify failure**

Run: `flutter test test/assets_redesign_test.dart`

- [ ] **Step 3: Migrate eight screens without changing asset lifecycle rules**

- [ ] **Step 4: Verify**

Run: `flutter test test/assets_redesign_test.dart test/security_hr_asset_repository_test.dart test/audit50_regression_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/assets test/assets_redesign_test.dart
git commit -m "feat(ui): redesign patrimony and asset workflows"
```

### Task 12: Reports and Notifications — 3 Screens

**Files:**
- Create: `test/reports_notifications_redesign_test.dart`
- Modify:
  - `lib/features/reports/reports_screen.dart`
  - `lib/features/reports/payment_notices_screen.dart`
  - `lib/features/notifications/notifications_screen.dart`

**Interfaces:**
- Reports catalog uses module/report cards with existing generation callbacks.
- Payment notices use finance filters/table/card patterns and preserve selected school-year context.
- Notifications group by existing category/time data, expose read/unread text/icon state, and keep current alert repository behavior.

- [ ] **Step 1: Write failing tests**

Cover report cards, historical school-year label, notification category/read states, empty/error states, and 390 px layout.

- [ ] **Step 2: Run tests**

Run: `flutter test test/reports_notifications_redesign_test.dart`

- [ ] **Step 3: Migrate screens and preserve generation/navigation callbacks**

- [ ] **Step 4: Verify PDF/report regressions and commit**

Run: `flutter test test/reports_notifications_redesign_test.dart test/payment_notice_batch_pdf_service_test.dart test/audit75_regression_test.dart`

```bash
git add lib/features/reports lib/features/notifications test/reports_notifications_redesign_test.dart
git commit -m "feat(ui): redesign reports and notifications"
```

### Task 13: Settings and Security — 16 Screens

**Files:**
- Create: `test/settings_security_redesign_test.dart`
- Create/update goldens: `test/goldens/settings_hub_*`, `test/goldens/long_form_*`
- Modify 14 settings screens:
  - `lib/features/settings/settings_screen.dart`
  - `lib/features/settings/appearance_screen.dart`
  - `lib/features/settings/audit_log_screen.dart`
  - `lib/features/settings/backup_screen.dart`
  - `lib/features/settings/classes_screen.dart`
  - `lib/features/settings/cloud_sync_screen.dart`
  - `lib/features/settings/data_integrity_screen.dart`
  - `lib/features/settings/document_requirements_screen.dart`
  - `lib/features/settings/establishment_screen.dart`
  - `lib/features/settings/notification_settings_screen.dart`
  - `lib/features/settings/payment_accounts_screen.dart`
  - `lib/features/settings/receipt_printing_settings_screen.dart`
  - `lib/features/settings/school_years_screen.dart`
  - `lib/features/settings/security_settings_screen.dart`
- Modify 2 security screens:
  - `lib/features/security/first_run_setup_screen.dart`
  - `lib/features/security/lock_screen.dart`

**Interfaces:**
- `SettingsScreen` becomes categorized hub using `GesAppModuleCard`.
- Backup/platform split files (`backup_screen_io.dart`, `backup_screen_web.dart`, stubs) remain business/platform implementations and are only visually wrapped when reachable from the main screen.
- Security flows stay focused/minimal and reuse theme/form/error primitives; no auth/session behavior changes.

- [ ] **Step 1: Write failing settings/security tests**

Test categorized settings hub, representative long form at 390/1024, theme switch, admin inability to reach manual restore/mutation controls, cloud-Web unsupported state, first-run/lock flows, and 44 px controls.

- [ ] **Step 2: Run tests**

Run: `flutter test test/settings_security_redesign_test.dart`

- [ ] **Step 3: Migrate settings hub and all subpages**

Preserve every existing callback, permission guard, platform split, and validation rule.

- [ ] **Step 4: Migrate first-run and lock screens**

Use the design tokens but keep them distraction-free; do not add the full sidebar/topbar around authentication/lock flows.

- [ ] **Step 5: Generate/verify goldens and regression tests**

Run: `flutter test test/settings_security_redesign_test.dart --update-goldens`

Run: `flutter test test/settings_security_redesign_test.dart test/audit100_regression_test.dart test/supabase_config_test.dart`

- [ ] **Step 6: Commit**

```bash
git add lib/features/settings lib/features/security test/settings_security_redesign_test.dart test/goldens
git commit -m "feat(ui): redesign settings and security surfaces"
```

### Task 14: Dark Theme, Accessibility, Legacy Cleanup, and 64-Screen Visual Matrix

**Files:**
- Create: `docs/qa/gesapp-redesign-screen-matrix.md`
- Create: `test/accessibility_redesign_test.dart`
- Create: `test/redesign_golden_test.dart`
- Modify: `lib/core/theme/theme_controller.dart` only if necessary to expose stable light/dark test switching without changing persistence behavior.
- Modify: `lib/core/windows/windows_page_scaffold.dart`
- Modify: `lib/core/windows/windows_panels.dart`
- Modify: `lib/core/windows/windows_filter_panel.dart`
- Modify: `lib/core/layout/responsive_layout.dart`
- Modify migrated screens only where Task 14 discovers theme/accessibility inconsistencies.

**Interfaces:**
- QA matrix has one row per 64 screen and columns: `390 light`, `390 dark`, `768`, `1024`, `1440 light`, `1440 dark`, `keyboard`, `read-only`, `loading`, `empty`, `error`, `verified`.
- Legacy wrappers are deleted only if `rg 'Windows(PageScaffold|Panel|ModuleCard|ModuleGrid|FilterPanel)|ResponsiveDataTable' lib` proves there are no unmigrated consumers. Otherwise retain them as thin facades.

- [ ] **Step 1: Write failing accessibility tests**

Cover focus visibility for keyboard controls, semantics on status badges/chart summaries, tooltip on icon-only compact navigation, no color-only status, dark-theme rendering of dashboard/student/payment/settings reference screens, and `390` overflow checks.

- [ ] **Step 2: Build the 64-screen QA matrix before final cleanup**

List every screen under `lib/features/**/*_screen.dart` exactly once. Mark each dimension only after it has a test or manual inspection result.

- [ ] **Step 3: Run tests and fix only redesign-related failures**

Run: `flutter test test/accessibility_redesign_test.dart test/redesign_golden_test.dart`

- [ ] **Step 4: Remove dead local presentation helpers and obsolete wrappers**

Use `rg`/analyzer evidence. Do not remove wrappers still used by any screen.

- [ ] **Step 5: Verify all 64 matrix rows are complete**

No row may remain unverified or unchecked before Task 15.

- [ ] **Step 6: Commit**

```bash
git add lib/core lib/features test docs/qa/gesapp-redesign-screen-matrix.md
git commit -m "refactor(ui): finalize accessibility themes and legacy cleanup"
```

### Task 15: Full Regression, Multi-Platform Builds, Release Notes, and Final Review

**Files:**
- Create: `docs/RELEASE_REDESIGN_2_3_0.md`
- Modify: `docs/CURRENT_RELEASE.md`
- Modify: `docs/FINAL_STATUS.md` if those files are the current release-status sources.
- Modify: `.github/workflows/*` only if a platform build requires a redesign-specific CI correction; do not change CI speculatively.

**Interfaces:**
- Release candidate: `GesApp 2.3.0+44`.
- No release claim is made until every verification command below has evidence from the exact final tree.

- [ ] **Step 1: Format and analyze the exact final tree**

Run: `dart format --set-exit-if-changed lib test integration_test`

Run: `flutter analyze`

Expected: exit 0, no analyzer errors.

- [ ] **Step 2: Run the full unit/widget/golden suite**

Run: `flutter test`

Expected: all tests PASS and all committed goldens match.

- [ ] **Step 3: Run integration tests on an available supported target**

Preferred Windows command:

`flutter test integration_test -d windows`

If Windows integration test execution is blocked by environment/tooling rather than product code, record the exact blocker and run the equivalent supported desktop/device target; do not mark Windows integration PASS without executing it.

- [ ] **Step 4: Build Web**

If `web/` is not present, run the project’s documented web scaffold/setup path first. Then:

`dart run sqflite_common_ffi_web:setup --force`

`flutter build web --release`

Expected: exit 0 and `build/web/` produced.

- [ ] **Step 5: Build Windows**

Run on Windows host:

`flutter build windows --release`

Expected: exit 0 and release bundle produced.

- [ ] **Step 6: Build Android**

Run:

`flutter build apk --release --split-per-abi`

Expected: exit 0 and ARM64 APK among outputs.

- [ ] **Step 7: Manual visual acceptance**

Using the QA matrix, inspect at least Dashboard, Students list/detail, Payments, Settings hub, one long form, one empty state, one error state, and one read-only state at reference sizes. Confirm visual hierarchy against `docs/superpowers/specs/assets/gesapp-redesign-reference.png` without forcing fictional content.

- [ ] **Step 8: Request final code review**

Use `superpowers:requesting-code-review` against the complete branch, with review focus on: permission regressions, responsive overflows, duplicated business logic, async-state regressions, and dead legacy presentation code.

- [ ] **Step 9: Fix review findings and rerun affected verification**

Any code change after a PASS invalidates the corresponding verification evidence; rerun the relevant analyze/tests/builds.

- [ ] **Step 10: Write release notes with exact evidence**

`docs/RELEASE_REDESIGN_2_3_0.md` must list the design-system migration, 64-screen coverage, test/build commands actually executed, known limitations (if any), and hashes/paths of produced binaries when available.

- [ ] **Step 11: Commit final release metadata**

```bash
git add docs .github/workflows pubspec.yaml pubspec.lock
git commit -m "chore(release): prepare GesApp 2.3.0 redesign release"
```

## Implementation Order and Review Gates

The task order is mandatory because later modules depend on interfaces defined earlier:

`1 Tokens → 2 Atomic components → 3 Responsive composites → 4 Shell → 5 Dashboard → 6 Students → 7/8 Finance → 9 Expenses → 10 HR → 11 Assets → 12 Reports/Notifications → 13 Settings/Security → 14 Accessibility/Cleanup → 15 Full verification`.

A reviewer may reject any module migration without blocking already accepted earlier tasks. Business/repository changes discovered during implementation are out of redesign scope: stop that task, document the separate bug, and either fix it in an isolated bugfix task/branch or leave it for explicit approval rather than smuggling it into the redesign.
