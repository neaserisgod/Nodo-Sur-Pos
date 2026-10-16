# Deja en el repositorio el número de compilación que subió publicar_release.ps1 (lo usa publicar-beta.yml): sin esto, la
# próxima corrida intentaría publicar el mismo número. Si pubspec.yaml no cambió, no hace nada.
$ErrorActionPreference = "Stop"
$rama = $env:GITHUB_REF_NAME
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add pubspec.yaml
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host "pubspec.yaml no cambió."; exit 0 }
$v = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
git commit -m "Publicada la beta $v [skip ci]"
git pull --rebase origin $rama
git push origin "HEAD:$rama"
if ($LASTEXITCODE -ne 0) { throw "No se pudo subir el cambio de pubspec.yaml (¿la rama está protegida?). La versión SÍ quedó publicada: pasá el número de compilación $v a mano antes de la próxima." }
