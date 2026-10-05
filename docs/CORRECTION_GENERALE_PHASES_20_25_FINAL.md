# GesApp — Correction générale finale, phases 20 à 25

Version applicative : **1.2.0+13**  
Schéma SQLite : **V22**

Cette livraison poursuit directement `GesApp_correction_generale_phases_11_19.zip` et clôt la série de corrections issue de l'audit approfondi.

## Phase 20 — Remboursements et trésorerie

- Un remboursement partiel possède maintenant son propre moyen de remboursement, sa caisse/compte et sa référence externe.
- Il n'est plus supposé sortir automatiquement du compte ayant reçu le paiement d'origine.
- Les règles de compatibilité moyen de paiement ↔ type de compte et l'obligation d'ouverture de caisse restent appliquées.
- Les soldes de caisse utilisent `payment_refunds.cash_account_id` avec repli sur l'ancien compte uniquement pour les historiques antérieurs à V20.
- Le diagnostic contrôle les remboursements sans compte de trésorerie valide.

## Phase 21 — Dépenses récurrentes

- Nouvelle table `recurring_expense_templates`.
- Modèles mensuels, trimestriels et annuels.
- Catégorie, montant, bénéficiaire, description, moyen de paiement, compte et jour prévu configurables.
- Une échéance récurrente crée une **demande de dépense**, jamais une dépense comptabilisée silencieusement.
- La prochaine date est recalculée après génération.
- Les modèles peuvent être désactivés/réactivés et sont audités.
- Une alerte locale est créée lorsqu'un modèle arrive à échéance dans les trois jours.

## Phase 22 — Rapports administratifs, audit et notifications actionnables

- Nouveau rapport `Effectifs et statuts administratifs` par cycle/classe/statut.
- Nouveau rapport `Dossiers élèves incomplets` avec pièces présentes/requises/manquantes.
- Le journal d'audit peut être exporté en CSV UTF-8, jusqu'à 5 000 lignes correspondant au filtre courant.
- Les seuils d'alertes sont configurables : retard élevé, retard critique, échéances à venir, capacité des classes et ancienneté de sauvegarde.
- Toucher une alerte GesApp ouvre maintenant l'écran métier correspondant quand c'est possible : élève/dette, recouvrement, sauvegarde, diagnostic, dépenses récurrentes ou élèves.
- Toucher une notification Android système ouvre le centre de notifications GesApp.

## Phase 23 — Administration des référentiels

- Les familles existantes sont modifiables (nom, deux téléphones, adresse).
- Les rubriques de paiement sont modifiables (nom et périodicité) avec journalisation.
- La grille tarifaire expose maintenant son historique complet : début, fin de validité, cible et montant.
- Le rapport historiquement nommé « Grand livre » est renommé **Livre de trésorerie** tant qu'aucun plan comptable général n'est implémenté.

## Phase 24 — Parcours scolaire et compatibilité Web

- Nouvelle table `student_class_movements`.
- Les changements de classe au cours d'une même année ne disparaissent plus lorsque `student_enrollments.classroom_id` est mis à jour.
- La fiche élève affiche les mouvements de classe avec année, ancienne classe, nouvelle classe, date et motif.
- Le logo établissement utilise désormais le même stockage média abstrait que les photos : chemin local sur IO et data URL sur Web. La sélection du logo ne dépend plus de `PlatformFile.path` sur navigateur.
- Les nouvelles tables métier sont ajoutées au schéma JSON portable ; les tables techniques de plateforme restent exclues.

## Phase 25 — CI/CD et qualité de release

Trois workflows GitHub Actions sont fournis :

- `.github/workflows/build_apk.yml` : analyse, tests et APK release ;
- `.github/workflows/build-web.yml` : analyse, tests, build Web, artifact `web-build` et déploiement GitHub Pages ;
- `.github/workflows/release-check.yml` : quality gate manuel ou sur tag `v*`, Android + Web.

Flutter est fixé à **3.47.1 stable**, Java à **17**, et le build Android conserve le core library desugaring nécessaire à `flutter_local_notifications`.

Le `base-href` Web reste configurable avec la variable GitHub `WEB_BASE_HREF`, valeur par défaut `/GesApp/`.

## Migration

- **V20** : moyen, compte et référence sur les remboursements.
- **V21** : modèles de dépenses récurrentes.
- **V22** : historique intra-annuel des changements de classe.

Le schéma V22 complet a été exécuté avec SQLite localement et `PRAGMA integrity_check` retourne `ok`.

## Validation finale obligatoire en CI

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
dart run sqflite_common_ffi_web:setup --force
flutter build web --release --base-href="/GesApp/"
```

Aucune fonctionnalité des phases 1 à 19 n'a été retirée.
