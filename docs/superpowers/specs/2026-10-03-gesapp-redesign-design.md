# GesApp — Refonte UI/UX Premium 2026

**Date :** 2026-10-03  
**Base produit :** GesApp 2.2.2+43  
**Référence visuelle :** `docs/superpowers/specs/assets/gesapp-redesign-reference.png`  
**Portée :** refonte de la couche présentation sur les 64 écrans existants, sans modification volontaire de la logique métier, des calculs financiers, de la sécurité, de SQLite/Supabase, des règles de permissions ni des exports métier.

## 1. Intention produit

GesApp doit devenir une application de gestion scolaire perçue comme professionnelle, claire, fiable et cohérente sur Windows, Web, tablette et mobile. Le redesign doit reprendre le langage visuel de la maquette de référence : navigation bleu marine, surfaces claires, hiérarchie forte, cartes KPI, tableaux propres, statuts colorés, fiches structurées et responsive sans scroll horizontal inutile sur mobile.

Le redesign doit améliorer la lisibilité et la vitesse d’usage sans supprimer ni simplifier les fonctionnalités déjà présentes. Un utilisateur doit reconnaître immédiatement le module courant, retrouver ses actions principales et consulter les données importantes sans chercher dans plusieurs zones de l’écran.

## 2. Critères de réussite

La mission est réussie lorsque :

1. les 64 écrans utilisent le même système de design et les mêmes composants de base ;
2. aucun écran mobile métier ne nécessite de scroll horizontal pour accéder aux informations essentielles ou aux actions ;
3. la navigation desktop reprend la logique de la maquette avec sidebar, topbar et contenu central ;
4. les écrans de liste ont une présentation desktop en tableau/liste dense et une présentation mobile en cartes ;
5. les écrans de détail Élève, Employé et Bien patrimonial utilisent une structure commune ;
6. les états chargement, vide, erreur, lecture seule et désactivé sont cohérents ;
7. thème clair et thème sombre restent fonctionnels ;
8. navigation clavier, focus visible, hover et tailles de cibles tactiles sont traités ;
9. les tests existants restent verts et des golden/widget tests couvrent les composants critiques ;
10. aucun changement de logique métier n'est introduit par la refonte.

## 3. Contraintes non négociables

- Conserver Flutter Material 3 (`useMaterial3: true`).
- Conserver Riverpod et les providers/repositories existants.
- Conserver les breakpoints de référence `600 / 900 / 1200 / 1600` déjà définis dans `AppBreakpoints`.
- Conserver `252 px` pour la sidebar desktop étendue et `72–80 px` pour sa version compacte.
- Ne pas modifier les schémas SQLite/Supabase pour des besoins purement visuels.
- Ne pas modifier les calculs, permissions ou règles de sécurité sauf bug prouvé hors redesign.
- Ne pas créer de seconde architecture UI parallèle durable ; les anciens wrappers doivent être adaptés ou remplacés progressivement.
- Éviter les dépendances UI supplémentaires. Une dépendance de graphiques peut être ajoutée seulement si elle remplace du code graphique complexe et si elle est utilisée dans plusieurs écrans.
- Les contenus affichés doivent rester en français et compatibles avec les formats FCFA/XAF existants.

## 4. Architecture visuelle cible

### 4.1 Design system central

Créer `lib/core/design_system/` comme source unique des règles visuelles :

- `gesapp_colors.dart` — palette sémantique ;
- `gesapp_spacing.dart` — grille d'espacement ;
- `gesapp_radius.dart` — rayons ;
- `gesapp_typography.dart` — hiérarchie de texte ;
- `gesapp_elevation.dart` — ombres/bordures ;
- `gesapp_breakpoints.dart` — façade sur les breakpoints existants ;
- `gesapp_theme_extensions.dart` — tokens spécifiques non couverts par `ColorScheme` ;
- `gesapp_component_theme.dart` — thèmes boutons, champs, chips, tables, dialogs.

`AppTheme`, `AppColors`, `ResponsiveLayout` et `WindowsUi` ne doivent pas être brutalement supprimés. Ils sont d'abord adaptés pour déléguer aux nouveaux tokens afin de ne pas casser les écrans non encore migrés.

### 4.2 Tokens de couleur

Palette claire de référence :

- Navy navigation : `#071D3B` ;
- Bleu primaire : `#1877F2` ;
- Bleu accent : `#2563EB` ;
- Bleu pâle : `#EAF2FF` ;
- Fond application : `#F5F7FB` ;
- Surface : `#FFFFFF` ;
- Surface secondaire : `#F8FAFC` ;
- Texte primaire : `#162033` ;
- Texte secondaire : `#667085` ;
- Bordure : `#E4E7EC` ;
- Succès : `#12B76A` ;
- Attention : `#F79009` ;
- Erreur : `#F04438` ;
- Information : `#2E90FA`.

Le thème sombre doit utiliser des équivalents sémantiques et non des inversions automatiques naïves. Les états réussite/attention/erreur doivent conserver une lisibilité équivalente.

### 4.3 Espacement, rayons et élévation

Grille principale : multiples de `4`, avec rythme préféré `8 / 12 / 16 / 24 / 32`.

- cartes standard : rayon `12–16` ;
- grandes cartes dashboard : rayon `16–20` ;
- inputs/boutons : rayon `10–12` desktop, `12–14` mobile ;
- badges : rayon pilule ;
- bordures : 1 px sémantique ;
- ombres : faibles et rares, préférer bordure + contraste de surface sur desktop.

## 5. Shell et navigation

### 5.1 Desktop large ≥ 1200 px

Structure :

- sidebar navy étendue `252 px` ;
- logo GesApp en haut ;
- navigation principale verticale ;
- groupe secondaire en bas : année scolaire, réglages/déconnexion selon contexte ;
- topbar fixe dans la zone contenu ;
- recherche globale ;
- notifications ;
- avatar/nom/rôle ;
- contenu centré avec largeur maximale 1480–1600 px.

Navigation cible :

1. Tableau de bord
2. Élèves
3. Finances
4. Dépenses
5. RH
6. Patrimoine
7. Rapports / Documents
8. Paramètres

Le module Finances peut afficher des sous-destinations dans son espace interne sans transformer toute la navigation globale en menu complexe.

### 5.2 Desktop compact 900–1199 px

- sidebar compacte `72–80 px` ;
- icônes seules ;
- tooltip sur hover/focus ;
- topbar conservée ;
- grilles limitées à 2–3 colonnes selon contenu.

### 5.3 Tablette 600–899 px

- navigation rail compacte ou drawer selon largeur utile ;
- actions secondaires regroupées ;
- grilles 2 colonnes ;
- tableaux transformés en listes structurées si la largeur utile ne permet pas une lecture confortable.

### 5.4 Mobile < 600 px

Bottom navigation :

- Accueil
- Élèves
- Finances
- Rapports
- Plus

Le menu Plus donne accès à Dépenses, RH, Patrimoine et Paramètres. Aucun module ne doit devenir inaccessible.

## 6. Topbar et entêtes de page

Créer un `GesAppTopBar` partagé pour desktop/tablette large. Il contient : recherche, notifications, profil, éventuellement année scolaire.

La recherche de topbar est une **commande de navigation/recherche fédérée légère**, pas un nouveau moteur métier. Elle peut rechercher les destinations/modules immédiatement et déléguer aux recherches déjà existantes (élèves, paiements, rapports) lorsqu'un provider/repository public le permet. Aucun nouvel index global, table SQLite, endpoint Supabase ou cache métier n'est créé uniquement pour le redesign. Si une donnée ne dispose pas déjà d'une API de recherche stable, la topbar doit proposer d'ouvrir le module concerné plutôt que dupliquer sa logique.

Créer `GesAppPageHeader` :

- titre ;
- description courte facultative ;
- breadcrumb facultatif pour sous-modules ;
- action primaire ;
- actions secondaires regroupées ;
- statut lecture seule quand nécessaire.

Sur mobile, les actions non prioritaires vont dans un menu `…` ou une bottom sheet. Les FAB ne sont conservés que lorsqu'ils représentent une création réellement centrale.

## 7. Bibliothèque de composants

Créer des composants réutilisables avec API simple et sémantique :

- `GesAppPageShell`
- `GesAppSidebar`
- `GesAppTopBar`
- `GesAppPageHeader`
- `GesAppPanel`
- `GesAppKpiCard`
- `GesAppMetricCard`
- `GesAppStatusBadge`
- `GesAppFilterBar`
- `GesAppResponsiveList`
- `GesAppDataTable`
- `GesAppEntityCard`
- `GesAppEntityHeader`
- `GesAppInfoSection`
- `GesAppFormSection`
- `GesAppEmptyState`
- `GesAppErrorState`
- `GesAppLoadingSkeleton`
- `GesAppConfirmDialog`
- `GesAppMoneyValue`
- `GesAppActivityItem`
- `GesAppChartCard`
- `GesAppSectionTabs`

Les composants doivent être découplés des repositories. Ils reçoivent des données préparées et des callbacks.

## 8. Patrons d'écran

### 8.1 Dashboard

Le dashboard cible doit contenir :

- bandeau de contexte établissement ;
- 4 KPI principaux ;
- solde/recettes/dépenses ;
- courbe ou série d'évolution ;
- répartition des paiements ;
- derniers paiements ;
- activité récente ;
- accès aux alertes.

Les données réelles existantes sont utilisées. Aucune donnée fictive de la maquette ne doit être codée en dur.

### 8.2 Écrans de liste

Patron : `PageHeader → FilterBar → résumé éventuel → liste/table → pagination/chargement`.

Desktop : tableau lisible, colonnes utiles, actions en fin de ligne.  
Mobile : cartes verticales avec identité, 3–5 informations prioritaires et menu d'actions ; détail complet accessible au clic.

### 8.3 Écrans de détail

Patron commun Élève / Employé / Bien :

- `EntityHeader` avec identité, statut, métadonnées principales et actions ;
- `SectionTabs` ou navigation secondaire ;
- panneaux d'informations ;
- historique/document/finance selon entité ;
- actions sensibles clairement séparées.

### 8.4 Formulaires

- largeur maximale 720–900 px selon complexité ;
- champs groupés en sections nommées ;
- 1 colonne mobile, 2 colonnes desktop pour les champs courts ;
- bouton primaire toujours visible en fin de formulaire ;
- validations inline ;
- message d'erreur global seulement pour les erreurs non rattachables à un champ.

### 8.5 Modules hub

`FinanceScreen`, `HrScreen`, `AssetsScreen`, `SettingsScreen` deviennent des hubs cohérents : cartes de module, catégorie, description, compteur/état éventuel, action claire. Ils réutilisent `GesAppModuleCard` plutôt que plusieurs implémentations différentes.

## 9. Migration des 64 écrans

### Dashboard — 1
- `dashboard_screen.dart` : migration complète vers le nouveau shell/KPI/charts/activité.

### Élèves — 8
- `students_screen.dart` : liste responsive principale.
- `student_detail_screen.dart` : fiche entité de référence.
- `student_form_screen.dart` : formulaire structuré.
- `families_screen.dart` : liste responsive.
- `family_detail_screen.dart` : fiche famille.
- `student_guardians_screen.dart` : responsables/tuteurs.
- `student_bulk_import_screen.dart` : workflow import.
- `document_verification_screen.dart` : écran utilitaire compact.

### Finances — 16
Standardiser tous les écrans vers trois patrons : hub, liste/table financière, configuration/formulaire. Préserver tous les calculs et workflows existants.

### Dépenses — 3
Liste, formulaire, récurrences : même grammaire visuelle que Finances.

### RH — 9
`employees_screen.dart` et `employee_detail_screen.dart` servent de références pour liste + fiche ; présence, congés, paie et rapports utilisent les mêmes primitives.

### Patrimoine — 8
Hub, liste, fiche, formulaire, inventaire, maintenance, rapports et configuration migrés vers le même système.

### Rapports — 2
Catalogue de rapports plus visuel et écran appels de paiement aligné avec le design financier.

### Notifications — 1
Liste par catégorie, badge de lecture, regroupement temporel, état vide.

### Sécurité — 2
Premier démarrage et écran verrouillage gardent une identité plus focalisée mais partagent les tokens et composants.

### Paramètres — 14
Réglages transformés en hub catégorisé et sous-pages cohérentes ; les écrans complexes conservent leur logique existante.

## 10. Responsive et comportement adaptatif

Utiliser `LayoutBuilder` sur les conteneurs qui changent de structure. `MediaQuery` reste acceptable pour les décisions globales liées à la fenêtre.

Règles :

- < 600 : contenu empilé, listes en cartes, actions regroupées ;
- 600–899 : 2 colonnes, navigation compacte, tables seulement si lisibles ;
- 900–1199 : shell desktop compact ;
- 1200–1599 : shell desktop complet ;
- ≥ 1600 : densité confortable, grilles 4 colonnes uniquement si utile.

Le design ne doit pas exploiter la totalité d'un écran ultrawide avec des lignes excessivement longues ; conserver une largeur maximale de contenu.

## 11. Accessibilité et interaction

- cible tactile recommandée ≥ 44 px sur mobile ;
- focus clavier visible de 2 px minimum autour des contrôles interactifs ;
- ordre de tabulation logique ;
- tooltips sur icônes sans libellé ;
- contraste suffisant entre texte/fond et badges/fond ;
- ne jamais transmettre un statut uniquement par couleur ; ajouter texte/icône ;
- `Semantics` sur actions critiques, graphiques résumés et informations non triviales ;
- hover desktop/Web sur cartes et actions ;
- état pressed/focus/disabled uniforme ;
- pas d'action destructive en un clic sans confirmation adaptée.

## 12. États de données

Chaque écran asynchrone doit gérer explicitement :

- chargement initial : skeleton ou indicateur contextuel ;
- rechargement : conserver les données et montrer un indicateur discret ;
- vide : message + prochaine action utile ;
- erreur récupérable : message + bouton Réessayer ;
- erreur métier : message utilisateur compréhensible ;
- lecture seule : actions masquées ou désactivées selon les règles existantes ;
- offline/synchronisation : conserver les indicateurs déjà existants, harmonisés visuellement.

## 13. Thème sombre

Le redesign doit être développé simultanément en clair et sombre, pas converti à la fin. Chaque composant doit être testé dans les deux thèmes. Les images/illustrations utilisées doivent rester lisibles ou recevoir un traitement de surface adapté.

## 14. Graphiques

Le dashboard peut utiliser une dépendance de graphique si elle satisfait :

- maintenance active ;
- support Flutter stable actuel ;
- interactions souris/touch ;
- thèmes clair/sombre ;
- accessibilité minimale ;
- absence de dépendance métier.

Le graphique doit rester un résumé visuel : les valeurs importantes restent disponibles sous forme de texte.

## 15. Compatibilité avec l'architecture existante

Flux recommandé :

`Provider/Repository existant → ViewModel/AsyncValue existant → adaptation légère de présentation → composant GesApp`.

Les composants ne doivent pas appeler directement SQLite/Supabase. Les écrans continuent d'utiliser les providers et services existants.

`WindowsPageScaffold`, `WindowsPanel`, `WindowsModuleCard` et `ResponsiveDataTable` deviennent des façades temporaires vers les nouveaux composants pendant la migration. Ils seront supprimés seulement lorsque plus aucun écran ne dépend d'eux.

## 16. Stratégie de migration

Ordre imposé :

1. Design tokens + thème + tests.
2. Composants atomiques.
3. Nouveau shell/navigation/topbar.
4. Dashboard.
5. Élèves.
6. Finances.
7. Dépenses.
8. RH.
9. Patrimoine.
10. Rapports + Notifications.
11. Paramètres + Sécurité.
12. Harmonisation thème sombre/accessibilité.
13. Nettoyage des wrappers legacy.
14. Vérification complète multi-plateforme.

Chaque module doit rester compilable et testable avant le suivant.

## 17. Tests et validation

### Unit/widget tests

- tokens et helpers ;
- composants `StatusBadge`, `KpiCard`, `FilterBar`, `PageHeader` ;
- comportement responsive tableau ↔ cartes ;
- navigation compacte/étendue ;
- états lecture seule ;
- formulaires critiques.

### Golden tests

Tailles de référence :

- mobile : `390 × 844` ;
- tablette : `768 × 1024` ;
- desktop compact : `1024 × 768` ;
- desktop complet : `1440 × 900` ;
- wide : `1600 × 1000` pour shell/dashboard.

Goldens prioritaires :

- Dashboard clair/sombre ;
- Liste Élèves desktop/mobile ;
- Fiche Élève desktop/mobile ;
- Paiements/Appels de paiement ;
- Hub Paramètres ;
- formulaire long ;
- état vide/erreur/lecture seule.

### Validation finale

- `flutter analyze` ;
- `flutter test` ;
- tests d'intégration ;
- build Windows ;
- build Web ;
- build Android ;
- revue visuelle sur tailles de référence ;
- navigation clavier desktop/Web ;
- test tactile mobile ;
- vérification du mode sombre.

## 18. Performance

- éviter les listes imbriquées non bornées ;
- conserver pagination/chargement progressif existants ;
- utiliser `const` quand possible ;
- isoler les rebuilds Riverpod ;
- graphiques hors rebuilds inutiles ;
- éviter les ombres lourdes répétées ;
- images élèves/personnel chargées à taille adaptée ;
- animations courtes et non bloquantes (150–250 ms).

## 19. Non-objectifs

Cette mission ne comprend pas :

- nouvelle logique comptable ;
- nouveau système d'authentification ;
- modification du modèle de données ;
- nouvelle stratégie offline/cloud ;
- modification des calculs de paie, patrimoine ou recouvrement ;
- refonte du contenu fonctionnel hors adaptation nécessaire à la présentation ;
- suppression d'une fonctionnalité existante pour simplifier le design.

## 20. Critères d'acceptation finale

La refonte est acceptée uniquement si :

- les 64 écrans ont été vérifiés ;
- le design est cohérent entre modules ;
- aucune action utile n'est cachée par le responsive ;
- l'application n'introduit pas de scroll horizontal métier sur mobile ;
- les statuts sont lisibles sans dépendre seulement des couleurs ;
- clair/sombre fonctionnent ;
- administrateur lecture seule reste respecté ;
- les tests métier existants restent verts ;
- les nouveaux tests visuels/widgets passent ;
- les builds ciblés passent ;
- la navigation et les flows métier existants ne régressent pas.

## 21. Décision d'architecture

L'option retenue est **Design System central + migration progressive module par module**. Cette approche offre la fidélité visuelle maximale à la maquette tout en minimisant le risque de régression fonctionnelle. La réécriture complète du frontend et la retouche isolée écran par écran sont explicitement écartées.
