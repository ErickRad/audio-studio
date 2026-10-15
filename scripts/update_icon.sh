
#!/usr/bin/env bash

set -Eeuo pipefail

# Executa a partir da raiz do projeto, independentemente
# do diretório em que o script for chamado.
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

SOURCE="assets/icons/audio_studio.png"
WINDOWS_ICON="windows/runner/resources/app_icon.ico"
WINDOWS_RC="windows/runner/Runner.rc"
LINUX_ICON="linux/runner/resources/app_icon.png"
DESKTOP_FILE="$HOME/.local/share/applications/audiostudio.desktop"

log() {
    printf '\n[Audio Studio] %s\n' "$1"
}

fail() {
    printf '\n[ERRO] %s\n' "$1" >&2
    exit 1
}

# 1. Verificar a imagem de origem.
[[ -f "$SOURCE" ]] || fail "Imagem não encontrada: $SOURCE"

# 2. Verificar as ferramentas necessárias.
command -v flutter >/dev/null 2>&1 ||
    fail "Flutter não encontrado no PATH."

command -v python3 >/dev/null 2>&1 ||
    fail "Python 3 não encontrado."

# 3. Verificar Pillow.
python3 -c 'from PIL import Image' 2>/dev/null ||
    fail "Pillow não está instalado. Execute: python3 -m pip install Pillow"

# 4. Gerar o ícone ICO do Windows.
log "Gerando ícone do Windows..."

mkdir -p "$(dirname "$WINDOWS_ICON")"

python3 - "$SOURCE" "$WINDOWS_ICON" <<'PY'
import sys
from PIL import Image

source, destination = sys.argv[1:3]

image = Image.open(source).convert("RGBA")

if image.width != image.height:
    print(
        f"Aviso: imagem não quadrada ({image.width}x{image.height}). "
        "Ela será redimensionada para um ícone quadrado.",
        file=sys.stderr,
    )

image.save(
    destination,
    format="ICO",
    sizes=[
        (16, 16),
        (24, 24),
        (32, 32),
        (48, 48),
        (64, 64),
        (128, 128),
        (256, 256),
    ],
)

print(f"Gerado: {destination}")
PY

# 5. Atualizar o ícone de recursos do Linux, se aplicável.
if [[ -d "$(dirname "$LINUX_ICON")" ]]; then
    log "Atualizando ícone de recursos do Linux..."
    cp "$SOURCE" "$LINUX_ICON"
fi

# 6. Regenerar os ícones das plataformas configuradas
# no bloco flutter_launcher_icons do pubspec.yaml.
log "Regenerando os ícones Flutter..."

flutter pub get
dart run flutter_launcher_icons

# 7. Conferir a referência do ícone no Windows.
if [[ -f "$WINDOWS_RC" ]]; then
    if grep -Fq 'resources\\app_icon.ico' "$WINDOWS_RC"; then
        log "Runner.rc já referencia resources\\app_icon.ico."
    else
        printf '\n[AVISO] Confira a referência do ícone em %s.\n' \
            "$WINDOWS_RC"
        grep -nE 'ICON|IDI_APP_ICON' "$WINDOWS_RC" || true
    fi
fi

# 8. Atualizar o atalho instalado do Linux, se existir.
if [[ -f "$DESKTOP_FILE" ]]; then
    log "Atualizando o ícone do atalho do Linux..."

    # Usa o caminho absoluto da imagem dentro do projeto.
    ICON_PATH="$PROJECT_DIR/$SOURCE"

    if grep -q '^Icon=' "$DESKTOP_FILE"; then
        sed -i "s|^Icon=.*|Icon=$ICON_PATH|" "$DESKTOP_FILE"
    else
        printf '\nIcon=%s\n' "$ICON_PATH" >> "$DESKTOP_FILE"
    fi

    # Atualiza o banco de atalhos quando a ferramenta existir.
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database \
            "$HOME/.local/share/applications" || true
    fi
fi

log "Atualização dos ícones concluída."
