
#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly REPO="https://github.com/mttomaz/tlauncher-arch.git"
readonly JAR_URL="https://tlauncher.org/jar"
readonly INSTALL_DIR="/usr/share/tlauncher"
readonly LAUNCHER="/usr/bin/tlauncher"
readonly ICON="/usr/share/icons/tlauncher.png"
readonly DESKTOP="/usr/share/applications/tlauncher.desktop"

TMP_DIR=""

info() {
    printf '\n\033[1;32m[INFO]\033[0m %s\n' "$*"
}

warn() {
    printf '\n\033[1;33m[AVISO]\033[0m %s\n' "$*" >&2
}

die() {
    printf '\n\033[1;31m[ERRO]\033[0m %s\n' "$*" >&2
    exit 1
}

cleanup_tmp() {
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}
trap cleanup_tmp EXIT

[[ "$(id -u)" -ne 0 ]] ||
    die "Executa este script como utilizador normal, sem sudo."

for cmd in sudo pacman git wget unzip install find; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Comando necessário não encontrado: $cmd"
done

sudo -v

printf '%s\n' \
    "Este instalador irá atualizar o sistema e instalar dependências." \
    "O TLauncher será descarregado de tlauncher.org." \
    "Não existe, neste script, uma verificação independente da assinatura do JAR."

read -r -p "Queres continuar? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || die "Instalação cancelada."

# Evita pacman -Sy e atualizações parciais.
info "A atualizar o sistema e a instalar dependências..."
sudo pacman -Syu --needed \
    git wget unzip jre-openjdk pciutils

# Não sobrescrever uma instalação existente silenciosamente.
if [[ -e "$INSTALL_DIR" || -e "$LAUNCHER" ||
      -e "$ICON" || -e "$DESKTOP" ]]; then
    warn "Foi encontrada uma instalação anterior ou ficheiros existentes."
    read -r -p "Queres substituir os ficheiros conhecidos? [y/N] " answer
    [[ "$answer" =~ ^[Yy]$ ]] ||
        die "Instalação cancelada. Nenhum ficheiro foi substituído."
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/tlauncher-install.XXXXXX")"

info "A obter os ficheiros do instalador..."
git clone --depth 1 "$REPO" "$TMP_DIR/repo"

SRC="$TMP_DIR/repo/src"

for file in tlauncher tlauncher.png tlauncher.desktop; do
    [[ -f "$SRC/$file" ]] ||
        die "Ficheiro obrigatório ausente: src/$file"
done

[[ -s "$SRC/tlauncher" ]] ||
    die "O script de lançamento está vazio."

info "A descarregar o arquivo do TLauncher..."
mkdir -p "$TMP_DIR/download" "$TMP_DIR/unpacked"

wget --https-only --show-progress \
    -O "$TMP_DIR/download/tlauncher-archive" \
    "$JAR_URL"

[[ -s "$TMP_DIR/download/tlauncher-archive" ]] ||
    die "O arquivo descarregado está vazio."

# Testar o arquivo antes de o extrair.
unzip -t "$TMP_DIR/download/tlauncher-archive" ||
    die "O ficheiro descarregado não passou no teste ZIP."

unzip -q "$TMP_DIR/download/tlauncher-archive" \
    -d "$TMP_DIR/unpacked"

mapfile -t jars < <(
    find "$TMP_DIR/unpacked" -maxdepth 1 \
        -type f -name '*.jar' -print
)

[[ "${#jars[@]}" -eq 1 ]] ||
    die "Esperava exatamente um JAR na raiz do arquivo; encontrados: ${#jars[@]}. Verifica o formato do download."

info "A preparar os ficheiros..."

# Validar o launcher antes de o instalar.
bash -n "$SRC/tlauncher" ||
    die "O script de lançamento contém erros de sintaxe."

# Instalar o JAR com nome previsível.
sudo install -d "$INSTALL_DIR"
sudo install -m 0644 "${jars[0]}" "$INSTALL_DIR/tlauncher.jar"

# Copiar recursos adicionais do arquivo, excluindo o JAR original.
while IFS= read -r -d '' file; do
    rel="${file#"$TMP_DIR/unpacked"/}"
    sudo install -D -m 0644 "$file" "$INSTALL_DIR/$rel"
done < <(
    find "$TMP_DIR/unpacked" -maxdepth 1 \
        -type f ! -name '*.jar' -print0
)

# Instalar os ficheiros da interface.
sudo install -D -m 0755 "$SRC/tlauncher" "$LAUNCHER"
sudo install -D -m 0644 "$SRC/tlauncher.png" "$ICON"
sudo install -D -m 0644 "$SRC/tlauncher.desktop" "$DESKTOP"

info "A verificar a instalação..."
[[ -x "$LAUNCHER" ]] || die "O launcher não é executável."
[[ -s "$INSTALL_DIR/tlauncher.jar" ]] ||
    die "O JAR instalado está vazio."

info "Instalação concluída."
printf '%s\n' \
    "Podes iniciar o TLauncher pelo menu de aplicações." \
    "Não o executes como root."

warn "O JAR não foi verificado por assinatura ou hash independente."
