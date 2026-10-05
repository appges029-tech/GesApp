# GesApp 2.1.0+31 — Multitenant Supabase

Schéma SQLite : **V28**

Cette version ajoute au socle final 2.0 :

- tenant par établissement ;
- premier créateur = Administrateur ;
- Administrateur en lecture seule sur toutes les données métier ;
- Administrateur autorisé à gérer les comptes Gestionnaires ;
- connexion Administrateur par Google OAuth ;
- connexion Gestionnaire par code établissement + identifiant + mot de passe ;
- mot de passe temporaire à remplacer au premier accès ;
- cache de session pour continuité offline après une première authentification ;
- synchronisation snapshot chiffrée toutes les 10 minutes si nécessaire ;
- compteur de révision SQLite automatique ;
- prévention des conflits entre appareils ;
- RLS Supabase par tenant ;
- bucket privé `gesapp-backups` ;
- Edge Functions d'administration des gestionnaires ;
- callbacks OAuth Android/iOS.

Les secrets de déploiement Supabase ne sont pas inclus dans le dépôt. La clé `service_role` est interdite dans le binaire Flutter.
