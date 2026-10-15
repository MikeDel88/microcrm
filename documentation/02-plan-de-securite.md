# Plan de sécurité

> **Scénario A (pipeline idéal).** La version adaptée à l'état actuel du projet figure au chapitre 5.

## 1. Objectifs et démarche

L'objectif est d'**anticiper les failles les plus courantes** avant qu'elles n'atteignent la production, en s'appuyant sur le référentiel **OWASP Top 10** (édition 2025, qui remplace celle de 2021). Pour chaque catégorie, le plan indique :

- le **risque concret pour MicroCRM**, au regard du code et de la configuration actuels ;
- le **contrôle automatisé** dans la CI/CD, et à quel moment il s'exécute ;
- la **mesure de prévention** à mettre en place dans l'application ou l'infrastructure.

Les contrôles automatisés ne couvrent qu'une partie des risques (une faille de conception ou d'autorisation ne se détecte pas par un outil). Ils sont complétés par la revue de code obligatoire sur chaque PR.

## 2. Constats sur MicroCRM

Éléments relevés dans le dépôt, qui orientent les priorités :

| Constat | Source | Catégorie OWASP concernée |
|---------|--------|---------------------------|
| Aucune authentification ni autorisation : pas de Spring Security, et `spring-boot-starter-data-rest` expose les dépôts `Person` et `Organization` en lecture et écriture | `back/build.gradle`, `*Repository.java` | A01 Broken Access Control, A07 |
| `@CrossOrigin` sans restriction : toute origine peut appeler l'API | `PersonRepository.java`, `OrganizationRepository.java` | A02 Security Misconfiguration |
| Aucun en-tête de sécurité HTTP (CSP, HSTS, X-Content-Type-Options…) dans `Caddyfile` | `misc/docker/Caddyfile` | A02 |
| Pas de configuration de journalisation ni d'alerte | `application.properties` | A09 |
| Images Docker non épinglées, exécution en root | `Dockerfile` | A02, A03 |
| Aucun outil d'analyse de code ni de dépendances | `build.gradle`, `package.json` | A03 |

Ces constats sont des **hypothèses de travail** à confirmer par les scans ; ils ne constituent pas un audit.

## 3. Couverture de l'OWASP Top 10 (2025)

| Catégorie | Risque pour MicroCRM | Contrôle automatisé | Prévention |
|-----------|----------------------|---------------------|------------|
| **A01 Broken Access Control** (inclut SSRF) | API ouverte à tous, lecture et écriture ; accès direct aux objets par identifiant | Revue de code ; tests d'intégration vérifiant qu'une requête non authentifiée est refusée (une fois l'authentification en place) | Introduire Spring Security ; refus par défaut ; limiter les ressources exposées par Spring Data REST (`@RepositoryRestResource(exported = false)` sur ce qui ne doit pas l'être) |
| **A02 Security Misconfiguration** | CORS ouvert, en-têtes absents, conteneur en root, console ou endpoints de débogage activés | Scan de configuration des images et du `Dockerfile` (Trivy, `hadolint`) | Restreindre CORS aux origines connues ; en-têtes dans Caddy ; utilisateur non-root ; configuration distincte par environnement |
| **A03 Software Supply Chain Failures** | Dépendances Gradle et npm vulnérables ou compromises ; images de base non maîtrisées ; actions GitHub tierces | Dependency Review et Dependabot, `npm audit`, OWASP Dependency-Check, Trivy ; épinglage des actions par SHA | Fichiers de verrouillage (`package-lock.json`, verrouillage Gradle) ; images épinglées par version ou digest ; mises à jour régulières ; **SBOM de chaque image livrée** |
| **A04 Cryptographic Failures** | Trafic non chiffré, secrets ou données personnelles en clair | Détection de secrets (Gitleaks) ; scan de configuration | HTTPS partout (Caddy gère TLS) ; aucun secret dans le code ; chiffrement des sauvegardes (partie 1, § 3.6) |
| **A05 Injection** | Requêtes construites par concaténation ; XSS dans l'interface Angular | CodeQL (Java et TypeScript) | Spring Data JPA et requêtes paramétrées ; ne jamais contourner l'échappement d'Angular (`bypassSecurityTrust…`, `innerHTML`) ; validation des entrées côté serveur |
| **A06 Insecure Design** | Absence de modèle de menaces ; données de contacts personnelles (RGPD) | Non automatisable | Revue de conception sur les nouvelles fonctionnalités ; minimisation des données ; anonymisation hors production |
| **A07 Authentication Failures** | Aucune authentification | Tests d'intégration sur les accès protégés | Authentification robuste (mots de passe hachés, limitation des tentatives, sessions ou jetons à durée limitée) ; réutiliser une solution éprouvée plutôt que d'écrire la sienne |
| **A08 Software or Data Integrity Failures** | Image ou artefact modifié entre le build et le déploiement ; pipeline altéré | Épinglage des actions ; signature des images (cosign, optionnel) ; revue des modifications de `.github/workflows` | Déployer l'image construite et testée, jamais une reconstruction (partie 3, § 4) ; protéger les fichiers de workflow |
| **A09 Security Logging & Alerting Failures** | Pas de trace des accès refusés ni des erreurs ; pas d'alerte | Tests vérifiant la présence de journaux sur les échecs d'accès | Journaliser les événements de sécurité (sans données sensibles) ; centraliser les logs ; alerter sur les anomalies |
| **A10 Mishandling of Exceptional Conditions** | Erreurs renvoyant des traces techniques ; comportement non défini en cas d'échec | Tests d'intégration sur les cas d'erreur ; CodeQL | Gestionnaire d'erreurs global (`@ControllerAdvice`) renvoyant des messages génériques ; ne pas désactiver un contrôle en cas d'exception (échec fermé) |

## 4. Contrôles automatisés : quand et avec quel seuil

| Contrôle | Outil | Push `features/*` `fix/*` | PR vers `develop` | PR vers `main` | Nuit | Semaine |
|----------|-------|:---:|:---:|:---:|:---:|:---:|
| Détection de secrets | Gitleaks / secret scanning | oui | oui | oui | | |
| Qualité et sécurité du code, quality gate | SonarQube Cloud | oui | oui | oui | | |
| Analyse statique du code (SAST) | CodeQL | | oui | oui | | oui |
| Vulnérabilités et licences des dépendances | PR : Dependency Review, `npm audit`, OWASP Dependency-Check ; nuit : `npm audit`, OWASP Dependency-Check (Dependency Review n'existe que sur PR) | | oui | oui | oui | |
| Scan de configuration (`Dockerfile`) | `hadolint`, Trivy config | | oui | oui | | |
| Scan des images construites | Trivy | | | oui | | oui |
| Génération et rescan du SBOM | CycloneDX, Trivy / Syft, Grype | | | | | oui (rescan) ; génération à chaque fusion sur `develop` / `main` |
| Mises à jour de dépendances | Dependabot | | | | | automatique (hebdomadaire) |

Les colonnes reprennent le calendrier de la partie 1. La détection de secrets s'exécute dès le push, car un secret commité est à traiter immédiatement, même sur une branche de travail.

### Rôle de SonarQube Cloud dans la CI

SonarQube Cloud (service en ligne, ex-SonarCloud) est l'outil central de **contrôle de la qualité et de la sécurité du code source**. Il s'exécute dans le workflow `ci.yml` à chaque push sur `features/*` et `fix/*`, sur chaque PR, et après chaque fusion sur `develop` et `main` (pour maintenir l'état de référence de ces branches).

| Fonction | Ce qu'il apporte | Lien OWASP |
|----------|------------------|------------|
| **Vulnérabilités** | Détection de failles dans le code Java et TypeScript | A05 Injection, A01, A04 |
| **Security Hotspots** | Points sensibles à examiner par un humain (CORS, cryptographie, désérialisation…) : le relecteur doit les marquer comme sûrs ou à corriger | A02, A04, A06 |
| **Fiabilité (bugs)** | Erreurs probables : accès nul, ressource non fermée, gestion d'exception défaillante | A10 |
| **Maintenabilité** | Code smells, complexité, duplication, dette technique | Qualité (partie 1) |
| **Couverture** | Lit les rapports JaCoCo (back) et LCOV de Karma (front) et suit leur évolution | Partie 1, § 5 |
| **Quality gate** | Verdict réussi / échoué appliqué au **code nouveau ou modifié** ; son résultat est un statut de la PR | Condition de fusion |
| **Retour dans la PR** | Commentaires et résumé directement dans la pull request | Revue de code |

**Mise en œuvre**

- Analyse pilotée par la CI (et non l'analyse automatique du service), pour pouvoir importer les rapports de couverture : plugin Gradle `org.sonarqube` côté back, action `SonarSource/sonarqube-scan-action` côté front.
- Un jeton `SONAR_TOKEN` est stocké dans GitHub Secrets (voir § 5). Il n'est pas accessible aux PR venant de forks : l'analyse n'y tourne pas.
- Le statut du quality gate est une **vérification requise** de la protection de branche (§ 6) : une PR dont le gate échoue ne peut pas être fusionnée.
- Le gate par défaut (« Sonar way ») exige notamment : aucune nouvelle vulnérabilité ni bug, hotspots revus, couverture du code nouveau ≥ 80 %, duplication ≤ 3 %. La couverture actuelle du back étant faible, ce seuil est à **adapter au départ** (partie 1, § 5, phase 1 puis phase 2).

**Complémentarité avec CodeQL**

- Les deux outils font de l'analyse statique et se recoupent en partie. Sonar couvre en plus la qualité, la couverture et le suivi des hotspots ; CodeQL détecte certaines failles par analyse de flux de données. On les garde **tous les deux** pour augmenter la couverture, et on traite une alerte commune une seule fois.
- Sonar ne remplace pas l'analyse des dépendances (Dependency Review, `npm audit`, Trivy) : il n'examine que le code du projet, pas les bibliothèques tierces.

### SBOM (inventaire des composants)

Un **SBOM** (*Software Bill of Materials*) est la liste de tous les composants d'un livrable : bibliothèques, versions, licences, paquets du système. Il répond aux catégories **A03** (chaîne d'approvisionnement) et **A08** (intégrité) : lorsqu'une vulnérabilité est annoncée, il permet de savoir immédiatement si une version livrée est concernée, sans reconstruire ni réanalyser.

| Niveau | Outil | Contenu | Format |
|--------|-------|---------|--------|
| Back (Gradle) | Plugin `org.cyclonedx.bom` (`./gradlew cyclonedxBom`) | Dépendances Java | CycloneDX (JSON) |
| Front (npm) | `npm sbom --sbom-format cyclonedx` ou `@cyclonedx/cyclonedx-npm` | Dépendances Node | CycloneDX (JSON) |
| **Image Docker** (référence) | Trivy (`trivy image --format cyclonedx`) ou Syft | Dépendances applicatives **et** paquets de l'OS, du JRE et de Caddy | CycloneDX (JSON) |

- **Quand** : à chaque fusion sur `develop` et `main`, sur l'image publiée (même SHA), dans le workflow de publication. Pas à chaque push : l'inventaire n'a de valeur que pour un livrable.
- **Stockage** : le SBOM est publié comme artefact du workflow et **joint à la release** `vX.Y.Z` ; il est conservé aussi longtemps que l'image correspondante (partie 3, § 3.4).
- **Exploitation** : le SBOM est rescanné (Trivy ou Grype) lors du contrôle hebdomadaire, ce qui détecte les vulnérabilités **publiées après** le build d'une image déjà livrée. Les mêmes seuils de gravité s'appliquent.
- **Licences** : il sert aussi de base à la vérification des licences incompatibles avec le projet.
- **Limites** : un SBOM décrit les composants, il n'indique pas qu'une vulnérabilité est exploitable dans MicroCRM ; la qualification reste manuelle (§ 7). Un SBOM de dépôt (export GitHub, format SPDX) est plus simple mais ne voit pas l'image finale ; il ne remplace pas le SBOM d'image.

### Seuils de gravité

| Gravité (CVSS) | PR vers `develop` | PR vers `main` | Scans nocturne / hebdomadaire |
|----------------|-------------------|----------------|-------------------------------|
| Critique (≥ 9,0) | Bloque | Bloque | Issue ouverte |
| Élevée (7,0 – 8,9) | Bloque | Bloque | Issue ouverte |
| Moyenne (4,0 – 6,9) | Avertit | Avertit | Suivi |
| Faible | Informe | Informe | – |

- Les vulnérabilités **sans correctif disponible** ne bloquent pas automatiquement : elles sont enregistrées dans un fichier d'exceptions (par exemple `.trivyignore`) avec justification, responsable et **date d'expiration**.
- Ces seuils sont une proposition de départ, à ajuster après un premier scan : le bruit initial pourrait être trop important pour bloquer immédiatement.

## 5. Gestion des secrets

- Aucun secret dans le dépôt : ni mot de passe, ni jeton, ni clé, y compris dans l'historique Git.
- Les secrets de la CI/CD sont stockés dans **GitHub Secrets**, rattachés à un **environnement** (test, pré-production, production ; le développement local n'utilise aucun secret réel) : un secret de production n'est jamais lisible par un workflow de test ou de pré-production (partie 3, § 4).
- Permissions minimales pour les workflows : `permissions: contents: read` par défaut, élargi workflow par workflow (par exemple `issues: write` pour les issues nocturnes).
- Les PR provenant de forks n'ont pas accès aux secrets.
- En cas de fuite : le secret est **révoqué et remplacé immédiatement** ; le supprimer de l'historique ne suffit pas.

## 6. Protection des branches et revues

Appliquées à `develop` **et** `main` via les règles de protection de branche GitHub :

| Règle | Valeur |
|-------|--------|
| Push direct | Interdit, administrateurs inclus |
| Pull request obligatoire | Oui |
| Approbation | Au moins 1 relecteur (second compte), nouvelle approbation si le code change. *Variante solo : sans second compte, l'approbation n'est pas exigée, mais la PR et les vérifications obligatoires restent requises* |
| Vérifications requises | Tests, qualité (quality gate SonarQube Cloud), sécurité et dépendances ; build de l'image et test de fumée ; sur `main`, en plus le scan des images |
| Branche à jour | La branche doit être à jour avec la cible avant fusion |
| Conversations | Tous les commentaires de revue résolus |
| Force-push et suppression | Interdits |
| Historique | Commits signés (optionnel) |

- Les modifications de `.github/workflows/**` et du `Dockerfile` sont soumises à relecture attentive (fichier `CODEOWNERS`), car elles contrôlent la chaîne de livraison (A08).
- La relecture porte une checklist de sécurité : accès, entrées utilisateur, secrets, journaux, nouvelles dépendances.

## 7. Traitement des vulnérabilités

1. **Détection** : par un contrôle automatisé, une alerte Dependabot ou un signalement.
2. **Qualification** : exploitable dans MicroCRM ou non ? Gravité réelle selon le contexte.
3. **Correction** dans les délais suivants (à valider) :

| Gravité | Délai cible |
|---------|-------------|
| Critique | 48 heures |
| Élevée | 7 jours |
| Moyenne | 30 jours |
| Faible | Selon planification |

4. **Suivi** : une issue par vulnérabilité, avec étiquette `security`.
5. **Exception** : acceptation documentée, responsable désigné, date de réexamen.
6. **Vérification** : le contrôle automatisé repasse au vert après le correctif.

### Retour d'expérience : CVE détectées par Trivy et passage à Spring Boot 4

L'ajout du scan Trivy sur les PR vers `main` (sévérités `HIGH,CRITICAL`, `exit-code: 1`, vulnérabilités sans correctif ignorées) a fait apparaître des CVE de sécurité dans les dépendances du back. Elles bloquaient la CI et ont dû être traitées avant de pouvoir fusionner.

| Étape | Action | Résultat |
|-------|--------|----------|
| 1 | Montée mineure de Spring Boot (3.4.5 → 3.5.16) | Insuffisant : des CVE restaient détectées |
| 2 | Passage à **Spring Boot 4.0.8** et **Gradle 8.14.5** (wrapper et `Dockerfile`) | CVE corrigées, scan au vert |
| 3 | Adaptation des tests | Spring Boot 4 découpe les modules de test : ajout de `spring-boot-starter-data-jpa-test` et déplacement des imports `DataJpaTest` (`org.springframework.boot.data.jpa.test.autoconfigure`) et `TestEntityManager` (`org.springframework.boot.jpa.test.autoconfigure`) |

Enseignements :

- un scan bloquant révèle la dette de dépendances : une montée de version majeure peut être la seule correction, il faut prévoir ce temps ;
- une montée majeure du framework touche aussi les tests et l'outillage de build (Gradle, `Dockerfile`), d'où l'intérêt de la CI pour valider l'ensemble ;
- les identifiants des CVE concernées sont consultables dans les rapports Trivy des exécutions de la CI.

## 8. Points à valider

- Sera-t-il introduit une authentification dans MicroCRM ? Plusieurs catégories (A01, A07) en dépendent : sans elle, le plan ne peut que signaler l'API comme ouverte.
- Faut-il aussi traiter la conformité RGPD (les données sont des contacts de personnes) ?
- Seuils de gravité et délais de correction proposés ci-dessus.
- Signature des images (cosign) : utile ou excessif pour ce projet ?

Source du référentiel : [OWASP Top 10:2025](https://owasp.org/Top10/2025/0x00_2025-Introduction/).
