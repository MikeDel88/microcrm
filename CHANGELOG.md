## [1.1.2](https://github.com/MikeDel88/microcrm/compare/v1.1.1...v1.1.2) (2026-10-26)


### Bug Fixes

* **ci:** enable tests and SonarQube analysis on push to main, update docs and workflows ([046aadc](https://github.com/MikeDel88/microcrm/commit/046aadc453d6256ab8f56cebecac7ec9bc29c382))

## [1.1.1](https://github.com/MikeDel88/microcrm/compare/v1.1.0...v1.1.1) (2026-10-26)


### Bug Fixes

* **sonar:** back end with sonar plugin for config and front with sonar-project.properties ([4d70797](https://github.com/MikeDel88/microcrm/commit/4d707973a13d2b8f4f82ee662b07388680199373))

# [1.1.0](https://github.com/MikeDel88/microcrm/compare/v1.0.0...v1.1.0) (2026-10-22)


### Bug Fixes

* config filebeat to collect logs. ([4643994](https://github.com/MikeDel88/microcrm/commit/464399416cd1bf7e096d3ec6283e189f9f3b2fbf))
* **sonar:** use lowercase project keys and wait for quality gate ([cc3f228](https://github.com/MikeDel88/microcrm/commit/cc3f228a0bde03fc532f0743a94883275d49c47c))
* update gitleaksignore to exclude curl-auth-user from analysis ([cfecfaa](https://github.com/MikeDel88/microcrm/commit/cfecfaa5f1bcb63cbcac4d50c66b9f84763084a8))


### Features

* add ELK with config for each element. ([9c0afed](https://github.com/MikeDel88/microcrm/commit/9c0afedd8cdb431cf4099b9d5e4ced222b1db884))
* update ci and cd and documentation ([4669d61](https://github.com/MikeDel88/microcrm/commit/4669d615dc752e2a7ca78a2917949196ffef26e2))

# 1.0.0 (2026-10-16)


### Bug Fixes

* **cd:** scan image before release because must detect CVE in first. ([21c067f](https://github.com/MikeDel88/microcrm/commit/21c067fc8e3646c0e2fb13050c19f6dc18214dd8))
* change quality of code with linter and checkstyle reports. ([36e9ce5](https://github.com/MikeDel88/microcrm/commit/36e9ce5ce74d6659ff6a160897b5fd29770ecd7f))
* **ci:** add always in ci-ok. ([018488c](https://github.com/MikeDel88/microcrm/commit/018488cf82c78c22672bcb74e2bf873d2a88a97e))
* **ci:** add buildx into needs in ci-ok. ([34972ef](https://github.com/MikeDel88/microcrm/commit/34972ef8634730bc4432d08ce0f46b7d6f327e6e))
* **ci:** change gradle version in Dockerfile ([8237329](https://github.com/MikeDel88/microcrm/commit/8237329f7e72251db97386379789209479c9554a))
* **ci:** change npm audit level high -> none. ([7158df1](https://github.com/MikeDel88/microcrm/commit/7158df1cd8daeb6b0f89a2cc289d08b280e71608))
* **ci:** fix cmd for launch back test. ([7a8496e](https://github.com/MikeDel88/microcrm/commit/7a8496ec07f4a2431af6f7239f6a77036c11eaaf))
* **ci:** fix codeql version with init and analyze ([2c22db1](https://github.com/MikeDel88/microcrm/commit/2c22db17fb1341b6ec6f37287205b485cdc4cc16))
* **ci:** fix problem in syntax yaml. ([60afee8](https://github.com/MikeDel88/microcrm/commit/60afee8b717b3ccbfbfc3d92acae32b4d9c0b4be))
* **ci:** update minor version of springboot. ([c9a7717](https://github.com/MikeDel88/microcrm/commit/c9a7717c814fee4dcededa64020bd9d2852c1318))
* **ci:** update version for actions. ([ab5ee23](https://github.com/MikeDel88/microcrm/commit/ab5ee23f4ae19a2f8e349cbbf233e7e23f1f029b))
* **ci:** upgrade spring boot version > 3.5.16. ([0a4f350](https://github.com/MikeDel88/microcrm/commit/0a4f350f318fa932feb54759eb01f590ff7ddb6c))
* **ci:** upgrade spring boot version > 4.0.8 + gradle > 8.14.5 ([977f814](https://github.com/MikeDel88/microcrm/commit/977f814e61673e722addf0352299477578e28c3e))
* **docker:** change Dockerfile with optimization. ([86e3e9b](https://github.com/MikeDel88/microcrm/commit/86e3e9b9e8c0cafbecdb5ba6861ba058c3d3b4e9))
* **Linter:** add config ESLint ([e544b17](https://github.com/MikeDel88/microcrm/commit/e544b17cd7b44dbfdc05cbf3581244d19c49adae))
* **security:** ext tomcat and jackson version for CVE report by trivy. ([ba9f350](https://github.com/MikeDel88/microcrm/commit/ba9f3504fb9c3747a49f2fba58edd445e1a22726))
* **test:** with new version spring boot, update dependency. test ([9abb304](https://github.com/MikeDel88/microcrm/commit/9abb30432af2ef90028e41af7c7656d1eb14732d))
