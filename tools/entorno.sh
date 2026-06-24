#!/usr/bin/env bash
# Cambia el entorno activo (grafo + balizas) copiando uno de assets/data/entornos/.
# Version Mac/Linux del helper (en Windows usa tools/entorno.ps1).
# Uso (desde donde sea):
#   bash tools/entorno.sh pasillo_exp2          # 4 balizas, rectangulo compacto
#   bash tools/entorno.sh pasillo_exp2_3b       # 3 balizas, triangulo compacto
#   bash tools/entorno.sh pasillo_exp2_3b_esq   # 3 balizas, norte en esquinas
#   bash tools/entorno.sh aula                  # aula, major 99
#   bash tools/entorno.sh piso4_nuevo           # mapa completo del piso 4
#   bash tools/entorno.sh                       # lista los entornos
set -e
cd "$(dirname "$0")/.."
ent="assets/data/entornos"
nombre="$1"
if [ -z "$nombre" ] || [ ! -d "$ent/$nombre" ]; then
  echo "Entornos disponibles:"
  ls -1 "$ent"
  echo ""
  echo "('piso4_nuevo' = mapa completo del piso 4; 'aula' = major 99.)"
  exit 1
fi
cp "$ent/$nombre/grafo.json" assets/data/grafo.json
cp "$ent/$nombre/beacon_config.json" assets/data/beacon_config.json
echo "Entorno activo: $nombre"
echo "Reinicia la app (detener y 'flutter run') para que cargue el nuevo mapa."
