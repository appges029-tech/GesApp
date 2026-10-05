# GesApp — Module Patrimoine

Version applicative : **1.4.0+15**  
Schéma SQLite : **V24**

## Périmètre implémenté

Le module **Patrimoine** est ajouté comme domaine principal à côté des Élèves, Finances, Dépenses, RH, Rapports et Réglages.

Il couvre :

- registre des biens avec numéro d’inventaire automatique `PAT-AAAA-xxxxx` ;
- catégories configurables ;
- localisations hiérarchiques : site, bâtiment, étage, salle/local, dépôt ;
- valeur d’acquisition, fournisseur, mode d’acquisition, marque, modèle et numéro de série ;
- état du bien et statut patrimonial ;
- responsable/employé affecté ;
- historique des mouvements et affectations ;
- maintenance préventive/corrective, prestataire, coût, prochaine échéance ;
- création d’une demande de dépense GesApp depuis une maintenance payante ;
- campagnes d’inventaire physique avec résultats trouvé/manquant/déplacé/endommagé ;
- sortie du patrimoine : vente, don, réforme, perte ou destruction ;
- documents et justificatifs patrimoniaux ;
- rapports par catégorie, localisation et statut avec PDF/Excel ;
- alertes offline pour garanties, maintenances et inventaires ouverts ;
- diagnostic d’intégrité patrimoniale ;
- inclusion des tables et médias patrimoine dans le JSON portable ;
- sauvegardes locales compatibles grâce au stockage sous le répertoire GesApp.

## Tables ajoutées en V24

- `asset_categories`
- `asset_locations`
- `assets`
- `asset_assignments`
- `asset_movements`
- `asset_maintenance`
- `asset_inventory_sessions`
- `asset_inventory_items`
- `asset_documents`
- `asset_disposals`

## Intégrations

- **RH** : un bien peut être affecté à un employé actif.
- **Dépenses** : une maintenance peut générer une demande de dépense en attente d’approbation.
- **Audit** : créations, modifications, mouvements, sorties et inventaires sont tracés.
- **Notifications** : garanties à moins de 30 jours, maintenance à venir et inventaire ouvert depuis plus de 30 jours.
- **Sauvegarde / JSON** : données et fichiers patrimoniaux sont portables.
- **Rapports** : synthèses patrimoniales exportables.

## Validation structurelle effectuée

- schéma V24 des 10 tables patrimoniales exécuté sous SQLite ;
- `PRAGMA integrity_check = ok` sur le sous-schéma testé ;
- contrôle des clés étrangères du domaine ;
- contrôle structurel des nouveaux fichiers Dart.

La validation finale de compilation reste à effectuer dans GitHub Actions avec `flutter analyze`, `flutter test`, build APK et build Web.
