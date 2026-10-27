# Plan de sécurité

Objectif : définir la sécurité de MicroCRM à partir de l'application telle qu'elle est. Le plan couvre :
- ce qui est exposé ;
- les risques identifiés ;
- les mesures déjà en place dans la CI/CD ;
- les actions restantes, par ordre de priorité ;
- les critères de blocage et les risques acceptés.

État au **27/10/2026**. Le plan s'appuie sur :
- l'analyse SonarQube Cloud ([13 Analyse des résultats SonarQube](13-analyse-sonar.md)) ;
- les exceptions Trivy ([09 Déploiement](09-deploiement.md), « Exceptions de sécurité ») ;
- une revue de la configuration (Dockerfile, Compose, Caddy, Spring).

## 1. Périmètre et exposition

MicroCRM est une application de **démonstration**. Elle n'est **pas déployée en production** : elle tourne en local (Compose) et ses images sont publiées dans GHCR.

| Composant | Exposition | Données / rôle |
|---|---|---|
| Front (Angular servi par Caddy) | ports 80 et 443, HTTPS avec certificat interne de Caddy | interface utilisateur |
| Back (Spring Boot, Spring Data REST) | port **8080 publié directement sur l'hôte**, en HTTP. Le navigateur l'appelle sur `http://localhost:8080` | API CRUD sur `persons` et `organizations` : **données personnelles** (prénom, nom, e-mail, téléphone, bio) |
| Base de données | HSQLDB **en mémoire**, dans le conteneur back | données perdues à chaque redémarrage |
| Actuator | profil `dev` : `health`, `metrics`, `prometheus` ; profil `prod` : `health` seul (valeur par défaut) | santé et métriques |
| Stack ELK (projet Compose séparé) | Kibana 5601, Elasticsearch 9200, en local | logs et métriques ; TLS et authentification activés |
| Images Docker | GHCR, `ghcr.io/mikedel88/microcrm-{back,front}` | livrables, avec attestation de provenance |
| CI/CD | GitHub Actions : `ci.yml`, `cd.yml`, `release.yml` | secrets `SONAR_TOKEN_BACK`, `SONAR_TOKEN_FRONT`, `RELEASE_TOKEN` |

**Point clé** : l'API n'a **ni authentification ni autorisation**. Toute personne qui atteint le port 8080 peut lire, créer, modifier et supprimer toutes les données. Ce n'est pas un problème tant que l'application reste en local. Mais c'est le premier verrou à poser avant toute mise en ligne.

## 2. Risques identifiés

| # | Risque | Source | Gravité si l'application était exposée | État |
|---|---|---|---|---|
| R1 | API sans authentification ni contrôle d'accès | revue de code (Spring Data REST sans Spring Security) | **Élevée** | ouvert |
| R2 | CORS ouvert à toutes les origines (`allowedOrigins("*")`, `@CrossOrigin`) | Sonar `java:S5122` × 3 | **Élevée** | ouvert |
| R3 | CVE CRITICAL de Tomcat 10.1.20 et Spring Framework 6.1.6 (Spring Boot 3.2.5) | Trivy | **Élevée** | **accepté jusqu'au 31/01/2027** (`.trivyignore`) |
| R4 | Back joignable en HTTP sur le port 8080, sans passer par Caddy | revue (`compose.yml`, `environment*.ts`) | Moyenne | ouvert |
| R5 | Aucun en-tête HTTP de sécurité côté front (CSP, HSTS, `X-Frame-Options`, `X-Content-Type-Options`) | revue (`misc/docker/Caddyfile`) | Moyenne | ouvert |
| R6 | Feuille CSS Bulma chargée depuis `cdn.jsdelivr.net` sans contrôle d'intégrité | Sonar `Web:S5725` | Faible | ouvert |
| R7 | Contrôles CI retirés le 26/10/2026 : détection de secrets (gitleaks), revue des dépendances, `npm audit`, CodeQL | historique de `ci.yml` (commit `3a85223`) | Moyenne : une fuite de secret ou une dépendance vulnérable ne serait plus détectée avant fusion | ouvert |
| R8 | Pas de surveillance des CVE publiées après la fusion (aucun scan planifié, pas de Dependabot) | revue de `.github/` | Moyenne | ouvert |
| R9 | Erreurs de l'API ignorées côté front (promesses non gérées, appel asynchrone dans un constructeur) | Sonar `typescript:S9383` × 12, `S7059` | Moyenne : masque les incidents, invisible dans ELK | ouvert |
| R10 | Base en mémoire, sans sauvegarde ni secret de connexion | revue (`application-prod.properties`) | Faible en démonstration ; à traiter avant production | accepté (démonstration) |
| R11 | Filebeat et Metricbeat exécutés en root avec accès à `docker.sock` | revue (`compose.elk.yml`) | Faible : supervision locale uniquement | accepté (nécessaire à la collecte) |

Sonar ne détecte ni R1, ni R4, ni R5 : ces risques viennent de l'architecture et de la configuration, pas d'un motif de code. La revue complète donc l'analyse statique.

## 3. Mesures en place

| Domaine | Mesure | Où | État |
|---|---|---|---|
| Analyse du code | SAST SonarQube Cloud (profil *Sonar way comprehensive*) sur le back (Java) et le front (TypeScript, HTML, CSS), à chaque PR et push sur `main` | `ci.yml`, job `sonar` | ✅ |
| Analyse du code | Quality gate **bloquant** (`sonar.qualitygate.wait=true`) : 0 nouvelle vulnérabilité, notes A, hotspots 100 % revus | `ci.yml` | ✅ |
| Processus | Fusion uniquement par PR, check `ci-ok` requis sur `develop` et `main` | protection de branche | ✅ |
| Images | Scan Trivy **avant push** : une CVE CRITICAL corrigeable bloque la publication | `cd.yml`, job `build` | ✅ |
| Images | Exceptions Trivy documentées et **datées** (expiration le 31/01/2027) | `.trivyignore` | ✅ |
| Images | Attestation de provenance (workflow et commit) | `cd.yml` | ✅ |
| Images | Utilisateur non root (`app`) dans les deux images ; versions de base fixées (`node:20-alpine`, `caddy:2.11.7-alpine`, `eclipse-temurin:17-jre-alpine`) | `Dockerfile` | ✅ |
| CI/CD | Moindre privilège : `contents: read` par défaut, droits élargis job par job | workflows | ✅ |
| CI/CD | Échec de publication signalé par une issue `publish-failure` | `cd.yml`, job `notify-failure` | ✅ |
| Secrets | Secrets dans GitHub (tokens Sonar, `RELEASE_TOKEN`) ; `.env.elk` ignoré par git, seul `.env.elk.example` est versionné | dépôt | ✅ |
| Secrets | Détection automatique des secrets | – | ❌ retirée de la CI (R7) |
| Dépendances | Installations reproductibles : `package-lock.json` + `npm ci`, wrapper Gradle | front, back | ✅ |
| Dépendances | Audit des dépendances à chaque PR et surveillance planifiée | – | ❌ retirés (R7, R8) |
| CI/CD | Actions figées sur une version majeure (`@v7`…) | workflows | ⚠️ partiel : pas d'épinglage par SHA |
| Supervision | Logs centralisés (ELK, TLS et authentification), suivi des `ERROR` du back | `compose.elk.yml`, [11](11-supervision-elk.md) | ✅ (non représentatif sans production, voir [12](12-dora-kpi.md)) |

## 4. Plan d'action

Les actions sont classées par priorité. Les numéros d'alertes renvoient à la liste des alertes prioritaires de [13 Analyse des résultats SonarQube](13-analyse-sonar.md), section 6.

### Priorité 1 : corriger les vulnérabilités du code

| Action | Risque | Détail |
|---|---|---|
| Supprimer le besoin de CORS : servir l'API derrière Caddy sur la même origine (`reverse_proxy /api/* back:8080`) et faire pointer le front sur `/api` | R2, R4 | Corrige les alertes 1 à 3. Le port 8080 n'a plus besoin d'être publié, et l'API passe en HTTPS. À défaut, restreindre `allowedOrigins` à l'origine du front, lue par environnement, et retirer les `@CrossOrigin` |
| Embarquer Bulma dans le build Angular (paquet npm) au lieu du CDN, ou ajouter `integrity` et `crossorigin` | R6 | Corrige l'alerte 4 et supprime la dépendance à un tiers à l'exécution |

### Priorité 2 : rétablir les contrôles de la CI

| Action | Risque | Détail |
|---|---|---|
| Réintroduire la détection de secrets (gitleaks sur tout l'historique, `.gitleaksignore` déjà présent) | R7 | Bloquant |
| Réintroduire la revue des dépendances des PR (`dependency-review`, échec à partir de `high`) et `npm audit` (d'abord informatif, puis `high`) | R7 | Ces jobs existaient avant le 26/10 : il suffit de les réactiver |
| Activer Dependabot (npm, Gradle, GitHub Actions, Docker) ou un scan Trivy planifié des images publiées | R8 | Détecte les CVE publiées après la fusion |

### Priorité 3 : durcir l'exposition

| Action | Risque | Détail |
|---|---|---|
| Ajouter les en-têtes de sécurité dans le Caddyfile : `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy` | R5 | La CSP sera plus simple une fois Bulma embarqué (priorité 1) |
| Ne plus publier le port 8080 hors développement local | R4 | Découle de la priorité 1 |

### Priorité 4 : fiabilité qui masque des incidents

| Action | Risque | Détail |
|---|---|---|
| Gérer les erreurs des appels à l'API (`await` + `try/catch`, ou `.catch`) et afficher un message ; déplacer le chargement du constructeur de `person-details` vers `ngOnInit` | R9 | Corrige les alertes 5 à 17. Les tests des services front, cas d'erreur compris, s'ajoutent à cette action |
| Passer à l'injection par constructeur dans `InitialDataFixture` | – | Corrige les alertes 18 et 19 |

### Priorité 5 : prérequis avant toute mise en production

Ces actions ne sont pas utiles tant que l'application reste une démonstration locale. Elles deviennent **obligatoires** avant toute exposition.

| Action | Risque | Détail |
|---|---|---|
| Ajouter l'authentification et l'autorisation (Spring Security, par exemple OIDC ou jeton), avec des droits par opération (lecture, écriture, suppression) | R1 | Premier verrou : sans lui, les autres mesures ne protègent pas les données |
| Monter de version Spring Boot (surcharge Tomcat 10.1.58, puis Spring Boot 4) et vider `.trivyignore` | R3 | **Avant le 31/01/2027**, date d'expiration des exceptions : Trivy bloquera alors la publication |
| Remplacer HSQLDB par une base persistante, avec des identifiants lus depuis des secrets d'environnement, et une sauvegarde | R10 | – |
| Limiter Actuator à `health` et le protéger ; ne pas exposer `metrics` et `prometheus` publiquement | – | Déjà le cas en profil `prod`, à vérifier sur l'environnement cible |

## 5. Critères de blocage

**En place :**
- Quality gate SonarQube Cloud en échec : la PR ne peut pas être fusionnée.
- Tests back ou front en échec (`ci-ok`).
- CVE CRITICAL corrigeable dans une image (hors exception datée) : l'image n'est pas publiée, aucune version n'est créée.

**À rétablir (priorité 2) :**
- Secret détecté dans le code ou l'historique.
- Dépendance de sévérité `high` ou plus ajoutée par une PR.

**Après résorption de la dette existante :** ajouter au quality gate une condition sur la note de sécurité du **code global**, pas seulement du nouveau code. L'ajouter aujourd'hui bloquerait toutes les PR à cause des 3 alertes CORS héritées.

## 6. Risques acceptés

| Risque | Justification | Limite |
|---|---|---|
| R3 : CVE de Spring Boot 3.2.5 | Le back est volontairement conservé sur les versions du code de départ ; l'application n'est pas exposée | Expiration le **31/01/2027**, réexamen obligatoire |
| R10 : base en mémoire | Données de démonstration, recréées au démarrage | Jusqu'à la mise en production |
| R11 : Beats en root avec `docker.sock` | Nécessaire pour lire les logs et métriques des conteneurs ; stack locale | Tant que la supervision reste locale |
| Issues Sonar *Accepted* (8, accessibilité et import inutile) | Sans impact de sécurité | À revoir avec les corrections d'accessibilité ([13](13-analyse-sonar.md)) |

Un risque accepté doit toujours avoir une justification, une limite (date ou condition) et un responsable de réexamen.

## 7. Suivi

| Indicateur | Source | Cible |
|---|---|---|
| Vulnérabilités Sonar (code global) | SonarQube Cloud | 0 ; note sécurité A (aujourd'hui C pour le back, B pour le front) |
| Quality gate | SonarQube Cloud | `OK` sur chaque PR |
| Exceptions `.trivyignore` | dépôt | 0 avant le 31/01/2027 |
| Échecs de publication (issues `publish-failure`) | GitHub | analysés à chaque occurrence |
| Erreurs `ERROR` du back | Kibana | à suivre une fois l'application en production ([12](12-dora-kpi.md)) |

Revue de ce plan : à chaque montée de version majeure, avant toute mise en production, et au plus tard à l'expiration des exceptions Trivy.
