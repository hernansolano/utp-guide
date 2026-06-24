# Cambia el entorno activo (grafo + balizas) copiando uno de assets/data/entornos/.
# Uso:  ./tools/entorno.ps1 pasillo_exp2     (4 balizas, rectángulo)
#       ./tools/entorno.ps1 pasillo_exp2_3b  (3 balizas, triángulo)
#       ./tools/entorno.ps1 aula             (aula, major 99)
param([string]$nombre)

$ent = "assets/data/entornos"
if (-not $nombre -or -not (Test-Path "$ent/$nombre")) {
    Write-Host "Entornos disponibles:"
    Get-ChildItem $ent -Directory | ForEach-Object { Write-Host "  - $($_.Name)" }
    Write-Host "`n('piso4_nuevo' = mapa completo del piso 4; 'aula' = major 99.)"
    exit 1
}
Copy-Item "$ent/$nombre/grafo.json" "assets/data/grafo.json" -Force
Copy-Item "$ent/$nombre/beacon_config.json" "assets/data/beacon_config.json" -Force
Write-Host "Entorno activo: $nombre"
Write-Host "Reinicia la app (detener y 'flutter run') para que cargue el nuevo mapa."
