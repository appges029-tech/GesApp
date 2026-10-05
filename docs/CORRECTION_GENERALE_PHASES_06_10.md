# Correction générale GesApp — Phases 06 à 10

Version applicative : **0.9.0+10**  
Schéma SQLite : **V17**

Cette livraison poursuit directement la base des phases 02–05. La phase 5 (transferts internes) est conservée intégralement et sert de socle aux nouveaux contrôles.

## Phase 6 — Moyens de paiement et comptes configurables

- Les moyens de paiement ne sont plus codés en dur dans les formulaires.
- Chaque moyen est associé explicitement à un type de compte : `cash`, `mobile` ou `bank`.
- La référence de transaction peut être rendue obligatoire par moyen de paiement.
- Nouvel écran **Réglages > Paiements & comptes** : création, modification et activation/désactivation des moyens de paiement et des caisses/comptes.
- Les formulaires Encaissement et Dépense chargent cette configuration dynamiquement.
- Un compte déjà utilisé ne peut plus changer de type ni de solde initial rétroactivement.
- Les anciennes bases sont migrées automatiquement en V15.

## Phase 7 — Justificatifs de dépenses

- Le champ `proof_path` est désormais exploité par l'interface.
- Ajout de PDF ou image depuis le formulaire de dépense.
- Sur Android/Desktop, le justificatif est copié dans les documents GesApp.
- Sur Web, le fichier est conservé sous forme de données embarquées compatibles avec le mécanisme multiplateforme.
- Consultation/téléchargement depuis la liste des dépenses.
- Les sauvegardes et exports JSON continuent d'embarquer les justificatifs référencés.

## Phase 8 — Simulation et lots de génération des échéances

- Nouvelle simulation avant toute génération : élèves examinés, échéances nouvelles, échéances déjà existantes et montant total attendu.
- Chaque génération validée crée un **lot de facturation** (`billing_batches`).
- Les échéances créées sont reliées au lot par `billing_batch_id`.
- Historique des lots récents dans l'écran de génération.
- Un lot peut être annulé tant qu'aucune de ses échéances n'a reçu de règlement.
- Migration V16.

## Phase 9 — Module de recouvrement

- Nouvel écran **Finances > Recouvrement**.
- Liste des échéances réellement en retard avec élève, classe, famille, responsable, téléphone, solde et ancienneté.
- Historique des actions de recouvrement.
- Actions : relance, promesse de paiement, visite ou note.
- Canaux : téléphone, SMS, e-mail, présentiel ou application.
- Enregistrement de la personne contactée, du résultat, du montant/date promis et de la prochaine relance.
- Les prochaines relances peuvent générer une alerte opérationnelle locale.
- Migration V17.

## Phase 10 — Rapports de recouvrement

Ajout de trois rapports décisionnels :

- **Recouvrement par cycle** ;
- **Recouvrement par classe** ;
- **Recouvrement par rubrique**.

Chaque rapport expose : nombre d'élèves, nombre d'échéances, montant attendu, montant payé/affecté, reste à recouvrer et taux de recouvrement. Les filtres d'année scolaire, cycle, classe, famille et période restent applicables.

## Compatibilité JSON

`billing_batches` et `recovery_actions` font partie du schéma JSON portable. Les anciens exports JSON restent importables. Pour un export antérieur à V15, GesApp reconstruit automatiquement le type de compte des anciens moyens de paiement afin que Mobile Money et Virement ne soient pas interprétés comme de l'espèce.

## Contrôles réalisés dans l'environnement de correction

- Analyse lexicale des délimiteurs sur tous les fichiers Dart de `lib/` et `test/` : aucune structure non fermée détectée.
- Exécution des 59 instructions SQL du schéma frais V17 dans SQLite : `PRAGMA integrity_check = ok`.
- Simulation de migration du schéma V14 vers V17 : `PRAGMA integrity_check = ok`, aucune violation de clé étrangère ; Espèces/Mobile Money/Virement correctement reclassés en `cash/mobile/bank`.

Le SDK Flutter n'étant pas disponible dans l'environnement de préparation, la validation finale reste à effectuer par CI : `flutter pub get`, `flutter analyze`, `flutter test`, build Android et build Web.
