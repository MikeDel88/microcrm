# Sécurité

## 1. Contrôles en place

| Contrôle | Outil | Quand | Bloquant |
|----------|-------|-------|----------|
| Secrets | Gitleaks | Push et PR | Oui |
| Qualité et sécurité du code | SonarQube Cloud (quality gate) | Push et PR | Selon le gate |
| SAST | CodeQL (Java/Kotlin, JavaScript/TypeScript) | PR | Selon la configuration GitHub |
| Dépendances et licences | Dependency Review | PR | Oui, à partir de *high* |
| Dépendances front | `npm audit` | PR | Non (`--audit-level=none`, informatif) |
| Image | Trivy, sévérité **CRITICAL**, `ignore-unfixed` | PR vers `main` (sur images compose) ; `cd.yml` sur `main` avant release | Oui |
| Provenance | Attestation GitHub des images publiées | Fusion sur `develop` / `main` | – |

Dependabot, hadolint, SBOM et scans planifiés ne sont pas en place (voir [06](06-evolutions.md)).

## 2. Secrets

- Aucun secret dans le dépôt ; `SONAR_TOKEN` et `RELEASE_TOKEN` dans les secrets Actions ([02](02-mise-en-place.md)).
- Permissions des workflows minimales : `contents: read` par défaut, élargi par job (`packages: write`, `issues: write`, `contents: write` pour `release`).
- `RELEASE_TOKEN` : fine-grained, limité au dépôt, avec expiration ; en cas de fuite, le révoquer et en créer un autre.

## 3. Spring Boot 4 et CVE (historique)

Le scan Trivy sur `main` a révélé des CVE dans les dépendances du back. Chronologie :

**État initial** (premier commit `323c2e1`) : Spring Boot **3.2.5**, plugin `dependency-management` 1.1.4, Gradle **8.7**, images `node` et `gradle:jdk17` non épinglées. Seule la partie Spring Boot / Gradle est détaillée ci-dessous.

| Étape | Avant → après | Commit |
|-------|---------------|--------|
| 1 | Spring Boot 3.2.5 → 3.4.5 (insuffisant) | `c9a7717` |
| 2 | Spring Boot 3.4.5 → 3.5.16, `dependency-management` 1.1.4 → 1.1.7 (insuffisant) | `0a4f350` |
| 3 | Spring Boot 3.5.16 → **4.0.8**, Gradle 8.7 → **8.14.5** (wrapper) | `977f814` |
| 4 | Gradle du `Dockerfile` aligné sur le wrapper (`gradle:8.14.5-jdk17-alpine`) | `8237329` |
| 5 | Adaptation des tests à Spring Boot 4 (modules de test redécoupés) | `9abb304` |
| 6 | Spring Boot 4.0.8 → **4.1.1** et surcharge de **Tomcat (11.0.25)** et **Jackson BOM (3.1.7)** dans `build.gradle` (`ext[...]`) | `ba9f350` |
| 7 | Sévérité Trivy ramenée de `HIGH,CRITICAL` à **CRITICAL** seulement | `5bcde2a` |

Autre ajustement de seuil : `npm audit` est passé de `--audit-level=high` à `none` (`7158df1`), donc informatif.

Version actuelle : Spring Boot **4.1.1**, Gradle **8.14.5**.

- Tests : ajout de `spring-boot-starter-data-jpa-test`, imports `DataJpaTest` (`org.springframework.boot.data.jpa.test.autoconfigure`) et `TestEntityManager` (`org.springframework.boot.jpa.test.autoconfigure`).
- Les surcharges Tomcat et Jackson sont à retirer dès que Spring Boot embarque ces versions ou plus récentes.
- Une montée majeure impacte aussi le build (Gradle, `Dockerfile`) et les tests : la CI sert à le valider.

## 4. Risques connus de l'application (non corrigés)

| Constat | Catégorie OWASP |
|---------|-----------------|
| Aucune authentification ; Spring Data REST expose lecture et écriture | A01, A07 |
| `@CrossOrigin` sans restriction (`PersonRepository`, `OrganizationRepository`) | A02 |
| Pas d'en-têtes de sécurité dans le `Caddyfile` | A02 |
| Pas de journalisation de sécurité | A09 |
| URL de l'API en dur (`http://localhost:8080`) dans `environment.production.ts` : l'image ne fonctionne que si le navigateur est sur la machine qui l'héberge | A02 |
| Base HSQLDB en mémoire : données perdues à chaque redémarrage | – |

## 5. Traiter une vulnérabilité

1. Le job (`scan`, Dependency Review, Sonar) échoue : lire le rapport.
2. Mettre à jour la dépendance ou l'image de base (ou surcharger la version dans `build.gradle` en attendant Spring Boot).
3. Si aucun correctif n'existe, Trivy l'ignore déjà (`ignore-unfixed`).
4. Relancer ; la fusion ou la release reprend une fois le job vert.
