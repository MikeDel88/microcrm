# Évolutions (non mises en place)

| Évolution | Pourquoi | Prérequis |
|-----------|----------|-----------|
| Déploiement automatisé (`deploy.yml`, SSH + Compose), environnements test / pré-prod / prod, approbation pour la prod | La pipeline s'arrête aujourd'hui à la publication GHCR | Hébergement défini |
| Retour arrière automatique et `rollback.yml` | Revenir sur un déploiement en échec | Environnement déployé |
| Rejouer test de fumée et scan **avant** le push de l'image sur `main` | L'image `:sha` est publiée avant son scan ; le test de fumée n'est exécuté que sur la PR | – |
| Nightly (suite sans cache, audit) et weekly (rebuild sans cache, scan) | Détecter les dérives sans commit | Workflows à écrire |
| Tests end-to-end | Valider les parcours | Outil choisi (Cypress, Playwright) |
| Base persistante, sauvegarde et test de restauration | Aujourd'hui HSQLDB en mémoire | PostgreSQL ou HSQLDB fichier + volume |
| Dependabot, hadolint, SBOM (Trivy/Syft), signature (cosign) | Chaîne d'approvisionnement | – |
| `npm audit` bloquant | Aujourd'hui informatif (`none`) | Corriger les vulnérabilités front existantes |
| URL de l'API lue à l'exécution (proxy `/api` dans Caddy ou configuration servie) | L'image ne fonctionne qu'en local | – |
| HTTPS avec nom de domaine, en-têtes de sécurité (CSP, HSTS) | Mise en production réelle | Domaine |
| Image unique (Spring Boot sert le front) | Remplacerait Caddy, URL d'API relative ; abandonne le HTTPS automatique et l'indépendance front/back (voir [05 § 2](05-conteneurisation.md#2-suppression-de-la-cible-standalone)) | Décision d'architecture |
| Authentification, CORS restreint, journalisation | Risques A01, A02, A07, A09 | Décision fonctionnelle |
| Second relecteur obligatoire, `CODEOWNERS` | Équipe de plusieurs personnes | – |
| Commitlint sur les titres de PR | Garantir des commits conventionnels pour semantic-release | – |
| Refermer automatiquement les issues `publish-failure` | Elles restent ouvertes tant qu'on ne les ferme pas | – |
