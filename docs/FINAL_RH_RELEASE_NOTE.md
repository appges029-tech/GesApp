# GesApp — Base finale consolidée avec RH

Version applicative : 1.3.0+14  
Schéma SQLite : V23

Cette archive est la base consolidée GesApp comprenant les corrections générales précédentes et le module Ressources humaines.

## RH intégré
- Personnel et matricules employés
- Services et postes
- Affectations historisées
- Contrats
- Présences / absences / retards
- Congés et permissions
- Documents RH
- Avances sur salaire
- Structure salariale
- Périodes et calcul de paie
- Validation / paiement de la paie
- Bulletin de paie PDF
- Dépense salariale automatique
- Rapports RH
- Alertes RH offline
- Sauvegarde et export/import JSON des données RH

## Validation CI obligatoire avant production

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web --release --base-href="/GesApp/"
```

Le SDK Flutter n'étant pas disponible dans l'environnement de génération, cette archive n'est déclarée compilée qu'après succès de la CI GitHub.
