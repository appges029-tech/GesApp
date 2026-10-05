# GesApp — Refonte Windows Fluent adaptative

Date : 20 septembre 2026  
Projet audité : GesApp `2.1.7+38`  
Portée : couche présentation Windows, responsivité desktop et composants UI partagés  
Principe : aucune modification volontaire de la logique métier, des repositories, des schémas SQLite, de Supabase, des calculs financiers ou des services PDF/export.

## 1. Objectif

Donner à GesApp une expérience réellement adaptée à Windows sans transformer l'application en une réécriture multiplateforme risquée. La version Windows doit ressembler et se comporter comme un logiciel de gestion desktop : navigation latérale stable, densité d'information adaptée, formulaires lisibles, actions regroupées en barre de commandes, tableaux exploitant la largeur disponible, interactions souris/clavier visibles, thèmes clair/sombre cohérents et absence de débordement lors du redimensionnement de la fenêtre.

Android, Web et les comportements métier existants doivent rester fonctionnellement inchangés.

## 2. État actuel constaté

Le projet possède déjà une base solide :

- `AppBreakpoints` : 600 / 900 / 1200 / 1600 px ;
- `ResponsiveContent`, `ResponsiveDialogContent`, `ResponsiveDataTable` et `ResponsiveFormRow` ;
- un shell principal mobile/desktop dans `lib/app/home_shell.dart` ;
- une navigation latérale Material `NavigationRail` à partir de 900 px ;
- thème clair/sombre centralisé dans `lib/core/theme/app_theme.dart` ;
- un contenu desktop limité à 1600 px ;
- plusieurs écrans déjà partiellement adaptatifs.

Mais l'interface reste principalement pensée comme une application Material mobile agrandie :

- 65 écrans de fonctionnalités utilisent un `Scaffold` ;
- 62 utilisent un `AppBar` ;
- 20 utilisent un `FloatingActionButton` ;
- 61 utilisent un `ListView` ;
- seulement quelques écrans utilisent directement `LayoutBuilder` ;
- les données denses sont souvent représentées sous forme de cartes/listes même sur grand écran ;
- les composants responsive partagés sont encore peu généralisés.

La refonte doit donc consolider la couche UI autour de composants desktop communs au lieu de réécrire chaque écran de manière indépendante.

## 3. Choix d'architecture

### 3.1 Stratégie retenue

Conserver `MaterialApp`, le `Navigator`, Riverpod, les routes actuelles et tous les widgets métier. Introduire une couche Windows dédiée reposant sur les composants Flutter déjà présents, avec un langage visuel et comportemental Fluent.

Cette première passe n'ajoute pas `fluent_ui` comme dépendance obligatoire. La raison est la stabilité : le projet annonce actuellement un plancher Dart `>=3.5.0`, tandis que les versions récentes de `fluent_ui` ont un plancher SDK plus élevé. Ajouter ou épingler une version tierce sans connaître précisément le SDK Flutter de la machine de livraison augmenterait le risque de casse de résolution de dépendances.

La fidélité Windows sera obtenue par :

- structure de navigation inspirée de `NavigationView` ;
- géométrie, densité, états hover/focus/selected et hiérarchie Fluent ;
- comportement adaptatif selon la largeur de fenêtre ;
- composants Material encapsulés dans des widgets Windows partagés ;
- police système Windows lorsque disponible, sans embarquer de fichier de police externe ;
- conservation de l'identité bleue actuelle de GesApp.

Une migration ultérieure vers `fluent_ui` pourra être faite derrière les mêmes abstractions, sans toucher aux écrans métier.

### 3.2 Isolation par plateforme

Créer une détection UI pure Flutter, sans import direct de `dart:io` dans les widgets partagés :

- Windows natif : `defaultTargetPlatform == TargetPlatform.windows && !kIsWeb` ;
- Android/Web/autres : interface actuelle ou variante Material responsive.

Ainsi, aucune dépendance à Windows ne doit casser la compilation Web ou Android.

## 4. Socle UI Windows partagé

Créer `lib/core/windows/` avec des composants de présentation uniquement.

### `windows_ui.dart`

Expose les constantes et helpers Windows : détection de plateforme, densité, rayons, largeurs maximales, espacements et règles de largeur de page.

### `windows_page_scaffold.dart`

Responsabilité : fournir une structure de page cohérente.

Sur Windows :

- titre et sous-titre en en-tête de contenu plutôt qu'un grand `AppBar` mobile ;
- zone d'actions à droite ;
- contenu centré avec largeur maximale configurable ;
- padding desktop cohérent ;
- fond de page distinct des panneaux ;
- support d'un état de chargement/erreur sans modifier la logique de données.

Sur mobile/Web : délègue au comportement Material existant ou permet à l'écran de conserver son `Scaffold` actuel.

### `windows_command_bar.dart`

Responsabilité : remplacer les FAB desktop et regrouper les commandes d'une page.

Comportements :

- action principale visible ;
- actions secondaires en boutons compacts ;
- tooltips sur les actions icône seule ;
- overflow menu si la fenêtre devient trop étroite ;
- aucune commande métier n'est modifiée, seulement son emplacement visuel.

### `windows_filter_panel.dart`

Responsabilité : présenter recherche et filtres de façon desktop.

- recherche toujours visible ;
- filtres principaux sur une ligne ou grille adaptative ;
- filtres secondaires dans un panneau repliable ;
- boutons Effacer / Appliquer alignés à droite ;
- version compacte empilée sur mobile.

### `windows_data_view.dart`

Responsabilité : proposer une représentation adaptative de collections métier.

- petit écran : cartes/liste existante ;
- Windows étroit : liste dense ;
- Windows large : tableau ou lignes structurées ;
- scroll vertical natif ;
- scroll horizontal uniquement si les colonnes métier ne peuvent réellement pas être condensées ;
- actions de ligne accessibles par menu ou bouton compact.

### `windows_form_section.dart`

Responsabilité : normaliser les formulaires.

- largeur maximale de formulaire ;
- sections nommées ;
- 1 colonne sous contrainte ;
- 2 colonnes sur largeur moyenne ;
- 2 à 3 colonnes uniquement pour les champs courts et indépendants ;
- champs longs (adresse, observation, notes) en pleine largeur ;
- espacement constant ;
- aucun texte sélectionné ou label ne doit provoquer un overflow.

## 5. Shell principal Windows

Fichier principal : `lib/app/home_shell.dart`.

### Mobile

Conserver le modèle actuel :

- barre de navigation inférieure ;
- quatre destinations prioritaires + `Plus` ;
- bottom sheet pour les modules secondaires.

### Windows

Remplacer l'aspect actuel du `NavigationRail` par un shell type NavigationView :

- volet gauche compact entre 900 et 1199 px ;
- volet développé à partir de 1200 px ;
- largeur développée environ 240–260 px ;
- sélection claire et non surdimensionnée ;
- icône + libellé ;
- Réglages placé visuellement en bas du volet ;
- zone de marque GesApp sobre en tête ;
- contenu séparé par une bordure légère plutôt qu'une ombre forte ;
- maintien de l'`IndexedStack` pour préserver l'état des modules ;
- maintien du bandeau `Mode Administrateur` et de la logique de déconnexion.

Le shell Windows ne doit pas introduire de nouveau système de routes.

## 6. Thème Windows

Étendre `AppTheme` avec une variante Windows choisie dans `GesApp` selon la plateforme.

### Typographie

- utiliser la police système ; sur Windows, laisser Flutter s'appuyer sur la pile système plutôt que fournir une police externe ;
- poids Regular/Semibold privilégiés ;
- titres moins massivement en `w800/w900` ;
- sentence case ;
- ellipsis pour les libellés courts quand nécessaire ;
- aucun texte d'interface critique inférieur à une taille lisible.

### Géométrie

Sur Windows :

- rayons plus sobres, environ 6–10 px pour contrôles/panneaux ordinaires ;
- boutons moins hauts que les contrôles tactiles mobiles ;
- champs autour de 36–42 px de hauteur selon leur contenu ;
- cartes remplacées autant que possible par panneaux/bordures légères ;
- ombres minimales ;
- accent bleu GesApp conservé.

Le thème mobile garde les dimensions tactiles actuelles.

### États d'interaction

Tous les composants interactifs desktop doivent avoir :

- hover visible ;
- focus clavier visible ;
- pressed/selected clair ;
- disabled identifiable ;
- tooltip sur action icône seule.

## 7. Migration par module

### Tableau de bord

`lib/features/dashboard/dashboard_screen.dart`

- en-tête de page Windows ;
- commandes thème/notifications dans la barre d'en-tête ;
- grille KPI exploitant mieux les écrans larges ;
- solde/recettes/dépenses présentés dans un panneau desktop moins proche d'une carte mobile géante ;
- largeur maximale cohérente ;
- conservation intégrale des providers et calculs.

### Élèves

`students_screen.dart` et écrans associés.

- recherche + filtres dans `WindowsFilterPanel` ;
- `Inscrire` devient action principale de command bar sur Windows ;
- import, vérification et familles deviennent actions secondaires ;
- grand écran : lignes/tableau dense avec identité, classe, famille/statut et actions ;
- mobile : cartes actuelles conservées ;
- formulaire élève migré vers sections adaptatives.

### Finances

`finance_screen.dart`, `payments_screen.dart`, `payment_form_screen.dart` et sous-modules.

- pages hub en grilles desktop structurées ;
- paiements en tableau/liste dense ;
- recherche élève toujours facilement accessible ;
- saisie de paiement en formulaire multi-colonnes contrôlé ;
- actions d'impression, reçu, export et ajout regroupées dans command bar ;
- aucun changement aux règles de paiement, comptabilité, recouvrement ou numérotation.

### Dépenses

- liste desktop dense ;
- filtres en panneau ;
- ajout de dépense en command bar plutôt que FAB ;
- formulaires avec sections ;
- preuves/pièces jointes inchangées fonctionnellement.

### RH

- hub RH adapté au desktop ;
- employés, congés, présences et paie exploitent les tableaux lorsque pertinent ;
- formulaires employé/paie/congé structurés en sections ;
- aucun changement de calcul de paie ni de repository.

### Patrimoine

- conserver les améliorations responsive 2.1.6 ;
- unifier avec les nouveaux panneaux, formulaires et command bars ;
- registre des biens en vue dense desktop ;
- inventaires et maintenance conservent les dialogues adaptatifs existants.

### Rapports

- filtres horizontaux/adaptatifs ;
- tableaux desktop privilégiés ;
- cartes mobiles conservées ;
- exports/PDF inchangés.

### Réglages

`settings_screen.dart`

Sur Windows :

- navigation interne en deux panneaux lorsque la largeur le permet ;
- catégories à gauche, contenu/destination à droite ou ouverture de page cohérente ;
- suppression de l'effet « longue liste de cartes mobiles » ;
- sur mobile, conserver la liste actuelle.

## 8. Formulaires et prévention des overflows

Règles obligatoires pour tous les formulaires migrés :

1. Aucun `Row` contenant des champs sans `Expanded`, `Flexible`, contrainte ou bascule responsive.
2. Les `DropdownButtonFormField` doivent pouvoir afficher une valeur longue sans pousser une icône hors écran.
3. Les libellés, erreurs de validation et aides peuvent passer à la ligne.
4. Les actions en bas de formulaire passent en colonne si l'espace est insuffisant.
5. Les champs de date, montant et code peuvent partager une ligne ; les adresses, observations et descriptions restent pleine largeur.
6. Les dialogues utilisent `ResponsiveDialogContent` ou son successeur commun.
7. Tester au minimum des largeurs de contenu de 360, 600, 900, 1200 et 1600 px.

## 9. Clavier, souris et accessibilité

Windows doit supporter correctement :

- ordre de tabulation logique ;
- focus visible ;
- Enter pour confirmer une action sûre lorsqu'un formulaire le permet ;
- Escape pour fermer les dialogues non destructifs ;
- tooltips ;
- cibles souris compactes mais accessibles ;
- curseur/hover cohérents ;
- contrastes clair/sombre ;
- mise à l'échelle Windows sans texte coupé.

Les raccourcis métier globaux ne seront pas introduits dans cette mission afin de ne pas modifier involontairement les comportements existants.

## 10. Contraintes de non-régression

Les fichiers suivants ne doivent pas être modifiés pour des raisons de design, sauf nécessité de compilation démontrée :

- `lib/data/repositories/**` ;
- `lib/core/db/**` ;
- `lib/core/cloud/**` ;
- `lib/services/finance_engine.dart` ;
- services PDF, export, sauvegarde, synchronisation et documents ;
- modèles de données ;
- schémas/contraintes SQL.

La refonte ne doit changer ni :

- montant calculé ;
- état financier ;
- droits administrateur/gestionnaire ;
- identifiants de documents ;
- comportement de sauvegarde/synchronisation ;
- données enregistrées ;
- règles de paie ;
- logique d'inventaire ;
- règles d'inscription élève.

## 11. Tests et validation

### Tests existants

Après chaque lot :

- `flutter analyze` ;
- tests ciblés du composant/écran modifié ;
- `flutter test` complet.

### Tests UI à ajouter

Créer des widget tests pour :

- shell mobile conservant la navigation basse ;
- shell Windows compact ;
- shell Windows développé ;
- bascule liste/tableau selon largeur ;
- command bar remplaçant le FAB sur Windows ;
- formulaires en 1 puis 2 colonnes ;
- longues valeurs de dropdown sans overflow ;
- thème clair/sombre des composants Windows.

### Build

Quand le SDK Flutter/Windows est disponible :

- `flutter build windows` ;
- `flutter build apk --debug` ou build Android équivalent pour vérifier qu'aucun import Windows n'a contaminé le mobile ;
- si la cible Web reste supportée : `flutter build web`.

L'environnement de travail actuel ne fournit pas `flutter`/`dart`; aucune affirmation de compilation réussie ne sera faite tant que ces commandes n'auront pas été exécutées dans un environnement équipé.

## 12. Critères d'acceptation

La mission est considérée conforme lorsque :

- Windows possède une navigation latérale adaptative de type Fluent ;
- le mobile conserve son modèle de navigation ;
- les FAB ordinaires ne sont plus le mécanisme principal d'action sur Windows ;
- les listes métier importantes disposent d'une présentation desktop dense ;
- les formulaires principaux sont adaptatifs et sans overflow aux largeurs testées ;
- hover/focus/tooltips sont présents sur les actions desktop ;
- thèmes clair/sombre restent cohérents ;
- aucune logique métier n'a été déplacée dans les widgets Windows ;
- les tests existants restent verts dans un environnement Flutter ;
- le build Windows est validé avant livraison finale si l'outil est disponible.

## 13. Fichiers principalement concernés

Nouveaux :

- `lib/core/windows/windows_ui.dart`
- `lib/core/windows/windows_page_scaffold.dart`
- `lib/core/windows/windows_command_bar.dart`
- `lib/core/windows/windows_filter_panel.dart`
- `lib/core/windows/windows_data_view.dart`
- `lib/core/windows/windows_form_section.dart`
- tests widgets associés dans `test/`

Modifiés en priorité :

- `lib/app/gesapp_app.dart`
- `lib/app/home_shell.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/layout/responsive_layout.dart`
- `lib/features/dashboard/dashboard_screen.dart`
- `lib/features/students/students_screen.dart`
- `lib/features/students/student_form_screen.dart`
- `lib/features/finance/finance_screen.dart`
- `lib/features/finance/payments_screen.dart`
- `lib/features/finance/payment_form_screen.dart`
- `lib/features/expenses/expenses_screen.dart`
- `lib/features/expenses/expense_form_screen.dart`
- `lib/features/hr/hr_screen.dart`
- `lib/features/hr/employees_screen.dart`
- `lib/features/assets/assets_screen.dart`
- `lib/features/assets/asset_list_screen.dart`
- `lib/features/reports/reports_screen.dart`
- `lib/features/settings/settings_screen.dart`

Les sous-écrans supplémentaires seront migrés vers les composants partagés lorsqu'ils utilisent les mêmes patterns, sans réécriture de leur logique de données.
