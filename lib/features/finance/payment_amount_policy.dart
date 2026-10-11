/// A cashier-entered partial amount is never silently overwritten by
/// selecting or deselecting months or family members.
String suggestedPaymentAmount({
  required String current,
  required int selectedRemaining,
  required bool editedByCashier,
}) {
  if (editedByCashier) return current;
  return selectedRemaining > 0 ? selectedRemaining.toString() : '';
}
