# Conception générale — GesApp V1

## 1. Vision

GesApp est une application mobile de gestion scolaire administrative et financière. La V1 ne couvre pas les notes, bulletins, moyennes ni emplois du temps. Elle vise une installation autonome par établissement et un fonctionnement quotidien totalement hors ligne.

## 2. UX

Navigation principale : Accueil, Élèves, Finances, Dépenses, Rapports, Paramètres.

Palette retenue :
- primaire : #1877F2
- fond clair : #F0F2F5
- surfaces : #FFFFFF
- texte : #1C1E21
- texte secondaire : #65676B
- succès : #31A24C
- alerte : #F7B928
- erreur : #E41E3F

Le design reprend la lisibilité, la sobriété et les contrastes de cette famille de couleurs sans copier l'interface d'un autre produit.

## 3. Architecture

Présentation Flutter -> état Riverpod -> services métier -> repositories -> SQLite local.

Services transversaux : moteur financier, génération PDF, sauvegarde/restauration, chiffrement, journal d'audit, alertes.

## 4. Règles comptables essentielles

- Un paiement est enregistré comme transaction immuable ; une correction passe par une opération d'annulation/contre-passation.
- Les tarifs sont historisés avec dates de validité.
- Les dus sont matérialisés par période pour préserver l'historique.
- Les paiements partiels sont alloués à des échéances précises.
- Un forfait familial doit éviter une double facturation individuelle.
- Les indicateurs proviennent des transactions persistées, jamais d'un simple état UI.

## 5. Offline-first

SQLite est la source de vérité locale. La sauvegarde cloud ne participe pas au chemin critique. Google Drive sert uniquement au transport de sauvegardes chiffrées et à la restauration.

## 6. Sécurité

- verrouillage PIN/mot de passe ;
- chiffrement de l'archive de sauvegarde avant upload ;
- journalisation des changements sur paiements, dépenses et tarifs ;
- aucune suppression destructive d'une transaction comptable validée.
