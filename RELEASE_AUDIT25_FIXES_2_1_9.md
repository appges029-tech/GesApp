# GesApp 2.1.9+40 — Corrections audit 25 %

Date : 2 octobre 2026
Base : GesApp 2.1.8+39

Corrections appliquées sans élargir le périmètre métier :

1. Isolation Supabase : suppression de l'UPDATE direct de `organization_members` pour les gestionnaires et maintien du changement de mot de passe via RPC minimal.
2. Paiements : validation stricte des `dueIds` contre l'élève/la famille et l'année scolaire avant allocation.
3. Trésorerie : règlements fournisseurs intégrés au solde disponible et à la caisse théorique ; contrôle de caisse ouverte et de fonds suffisants avant règlement.
4. Administrateur lecture seule : garde métier ajoutée à l'annulation des lots de facturation et à l'activation/désactivation des dépenses récurrentes ; actions masquées dans l'UI.
5. Sauvegarde V4 : restauration des pièces jointes génériques encore manquantes après la restauration média standard.

Des tests de non-régression ont été ajoutés. L'environnement de correction ne contient pas Flutter/Dart ; ils doivent être exécutés dans CI ou sur une machine Flutter avant diffusion binaire.
