#!/usr/bin/env bash
# Diagnóstico de quedas do VS Code Remote-SSH no VPS (jarvis-vps)
#
# Como usar (NA MÁQUINA REMOTA, via terminal SSH comum, fora do VS Code):
#   ssh jarvis-vps
#   bash diagnostico-vscode-vps.sh | tee /tmp/diagnostico-vscode.txt
#
# Depois cole o conteúdo de /tmp/diagnostico-vscode.txt na conversa.

set -u
LINHA="=============================================================="

secao() {
  echo ""
  echo "$LINHA"
  echo ">> $1"
  echo "$LINHA"
}

secao "1. Memória e swap (causa nº 1 de queda: falta de RAM)"
free -h
echo ""
echo "Swap configurado: $(swapon --show --noheadings | wc -l) dispositivo(s)"
swapon --show 2>/dev/null || echo "(sem swap ativo)"

secao "2. OOM Killer — o kernel matou processos por falta de memória?"
if command -v journalctl >/dev/null 2>&1; then
  sudo journalctl -k --since "-7 days" 2>/dev/null | grep -iE "out of memory|oom-kill|killed process" | tail -30 \
    || echo "(nenhum registro de OOM nos últimos 7 dias — bom sinal)"
else
  sudo dmesg 2>/dev/null | grep -iE "out of memory|oom-kill|killed process" | tail -30 \
    || echo "(nenhum registro de OOM no dmesg)"
fi

secao "3. Top 15 processos por consumo de memória agora"
ps aux --sort=-%mem | head -16

secao "4. Processos do vscode-server (duplicados/zumbis?)"
pgrep -af "vscode-server" || echo "(nenhum processo vscode-server ativo)"
echo ""
echo "Instalações em ~/.vscode-server/cli e bin:"
du -sh ~/.vscode-server 2>/dev/null || true
ls ~/.vscode-server/cli/servers 2>/dev/null || true

secao "5. Espaço em disco (disco cheio derruba o servidor)"
df -h / /home /tmp /run 2>/dev/null | sort -u
echo ""
echo "Uso de /run/user/1001 (tmpDir usado pelo VS Code):"
du -sh /run/user/1001 2>/dev/null || echo "(/run/user/1001 não existe AGORA — se você está logado, isso é um problema!)"

secao "6. systemd-logind — sessão do usuário sendo encerrada? (causa nº 2)"
echo "Linger (mantém processos do usuário vivos sem sessão ativa):"
loginctl show-user "$USER" -p Linger 2>/dev/null || echo "(loginctl indisponível)"
echo ""
echo "KillUserProcesses (se =yes, o systemd MATA o vscode-server ao fechar a sessão):"
grep -iE "^\s*KillUserProcesses" /etc/systemd/logind.conf 2>/dev/null || echo "KillUserProcesses não definido (padrão: no)"
echo ""
echo "Sessões ativas:"
loginctl list-sessions 2>/dev/null || true

secao "7. Configuração de keepalive do sshd (causa nº 3: timeout de rede)"
sudo sshd -T 2>/dev/null | grep -iE "clientalive|tcpkeepalive|maxstartups|maxsessions" \
  || grep -iE "clientalive|tcpkeepalive" /etc/ssh/sshd_config 2>/dev/null \
  || echo "(não foi possível ler a config do sshd — rode com sudo)"

secao "8. Desconexões SSH recentes no log do servidor"
if command -v journalctl >/dev/null 2>&1; then
  sudo journalctl -u ssh -u sshd --since "-2 days" 2>/dev/null \
    | grep -iE "disconnect|timeout|closed|reset" | tail -30 \
    || echo "(nada relevante nos últimos 2 dias)"
fi

secao "9. Últimas linhas do log do vscode-server"
LOG=$(ls -t ~/.vscode-server/.cli.*.log 2>/dev/null | head -1)
if [ -n "${LOG:-}" ]; then
  echo "Arquivo: $LOG"
  tail -40 "$LOG"
else
  echo "(nenhum log .cli.*.log encontrado)"
fi

secao "10. Limites de inotify (watchers de arquivos)"
echo "max_user_watches:   $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null)"
echo "max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null)"

secao "FIM — cole todo o resultado acima na conversa"
