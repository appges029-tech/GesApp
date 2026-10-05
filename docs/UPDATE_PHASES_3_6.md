# GesApp — Chantiers 3 à 6

Base: version issue des chantiers 1–2. Migration SQLite V7.

## Chantier 3 — Élèves / inscriptions
- écran de création désormais réutilisable en modification ;
- correction nom, prénom, sexe, naissance, classe, famille, responsable ;
- champs complémentaires : nationalité, adresse, établissement d'origine ;
- détection préventive des doublons nom/prénom/date de naissance ;
- recherche élargie au parent/tuteur et téléphone ;
- table `student_guardians` introduite et responsable principal synchronisé ;
- historique annuel V5/V6 conservé.

## Chantier 4 — Finances
- sélection explicite des échéances lors d'un encaissement ;
- paiement sans échéance / dépassement transformé en avoir (`payer_credits`) ;
- référence transaction, numéro payeur et opérateur Mobile Money ;
- rattachement d'un paiement à une caisse/compte ;
- infrastructure des moyens de paiement configurables (`payment_methods`) ;
- remboursement partiel côté repository avec restauration des allocations ;
- annulation d'un paiement invalide aussi l'avoir issu de ce paiement.

## Chantier 5 — Caisse / trésorerie
- comptes initiaux : caisse principale, Mobile Money, banque ;
- ouverture de session de caisse avec fond initial ;
- calcul du solde théorique depuis encaissements et dépenses du compte ;
- comptage physique, écart et clôture ;
- clôture réservée au Directeur.

## Chantier 6 — Dépenses
- date réelle de dépense saisissable ;
- numéro interne `DEP-AAAA-xxxxxx` ;
- fournisseur/bénéficiaire ;
- moyen de paiement ;
- caisse/compte ;
- référence externe ;
- modèle prêt pour justificatif (`proof_path`) et approbation (`approval_status`).

## Points volontairement reportés
Cette passe pose le noyau des chantiers 3–6. Restent à finaliser dans une passe de durcissement : import CSV/Excel massif avec écran de prévisualisation, UI d'administration des moyens de paiement, pièce jointe de dépense depuis caméra/fichier, dépenses récurrentes, workflow complet demande→approbation→paiement, lots de facturation/simulation/annulation de génération, utilisation automatique des avoirs futurs et écran UI de remboursement partiel.

## Validation requise
L'environnement de génération ne contient pas Flutter/Dart. Exécuter obligatoirement `flutter analyze`, `flutter test` puis un build Android CI avant fusion en production.
