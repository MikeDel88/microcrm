# Plan de sécurité

Objectif : définir comment la sécurité et la qualité du code seront contrôlées dans la future CI/CD : rôle de SonarQube Cloud, problèmes surveillés et bonnes pratiques à respecter.

## Rôle de SonarQube Cloud

SonarQube Cloud servira de **point de contrôle central de la qualité et de la sécurité du code** :

- **Analyse statique automatique** du back (Java) et du front (TypeScript), à chaque pull request et à chaque push sur la branche principale.
- **Import de la couverture** produite par les tests front et back.
- **Quality gate bloquante** : si les seuils ne sont pas respectés, la CI échoue et la PR ne peut pas être fusionnée.
- **Suivi dans le temps** : historique, dette technique, tendance de la couverture.
- **Principe « Clean as You Code »** : les exigences s'appliquent d'abord au *nouveau code*. L'existant est corrigé progressivement, sans bloquer le projet.

## Types de problèmes surveillés

| Catégorie | Exemples possibles dans MicroCRM | Exigence (nouveau code) |
|-----------|----------------------------------|-------------------------|
| **Vulnérabilités** | Configuration CORS trop permissive, exposition de données sensibles | 0 |
| **Security hotspots** | CORS ouvert à `*`, conteneurs exécutés en root, URL en dur | 100 % revus |
| **Bugs** | `Optional.get()` sans vérification, null non géré | 0 |
| **Code smells** | `any` en TypeScript, imports inutilisés, code dupliqué | Maintenabilité A |
| **Couverture** | Services et composants non testés | Seuil minimal, relevé progressivement |
| **Duplication** | Blocs copiés entre services front | Sous le seuil défini |

## Bonnes pratiques attendues dans la CI

**Gestion des secrets**
- Aucun secret dans le dépôt : ni token, ni mot de passe, ni clé.
- Les secrets (tokens Sonar, accès au registre d'images) sont stockés dans les secrets du dépôt GitHub et injectés uniquement dans les jobs qui en ont besoin.
- Les fichiers `.env` sont ignorés par git. Seul un fichier `.env.example` sans valeurs réelles est versionné.
- Une détection automatique des secrets est lancée sur tout l'historique git.
- Chaque job a le minimum de permissions nécessaire (lecture seule par défaut).

**Gestion des dépendances**
- Les installations sont reproductibles : lockfile, `npm ci`, wrapper Gradle.
- Les dépendances ajoutées ou modifiées sont auditées à chaque PR.
- Un scan planifié surveille les CVE publiées après la fusion.
- Les dépendances (Spring Boot, Angular) sont mises à jour régulièrement.

**Code et images**
- Une analyse SAST complète SonarQube Cloud.
- Les images Docker ont des versions de base fixes et tournent avec un utilisateur non root.
- Les images sont scannées avant toute publication.

**Processus**
- La branche principale est protégée : fusion uniquement par PR, avec la CI au vert.
- Les versions des actions CI sont figées.

## Critères de blocage

- Quality gate SonarQube Cloud en échec.
- Secret détecté dans le code ou l'historique.
- Vulnérabilité critique dans une dépendance ou une image.
- Tests en échec.
