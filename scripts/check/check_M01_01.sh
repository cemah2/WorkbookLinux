#!/usr/bin/env bash
# check_M01_01.sh — vérifie le lab L1.1 (shell du poste d'admin standardisé)
set -uo pipefail
PASS=0; FAIL=0
ok()  { printf '  [ OK ] %s\n' "$1"; PASS=$((PASS+1)); }
ko()  { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL+1)); }
echo "== Vérification L1.1 =="
# Les réglages interactifs se testent dans un shell de login
# INTERACTIF (bash -lic) : un bash -lc s'arrête à la garde du
# .bashrc et ne verrait rien.

# --- 1. ~/bin/hostinfo --------------------------------------------------
if [ -x "$HOME/bin/hostinfo" ]; then
  ok "~/bin/hostinfo existe et est exécutable"
else
  ko "~/bin/hostinfo absent ou sans droit d'exécution (chmod +x)"
fi

sortie=$(cd /tmp && bash -lic 'hostinfo' 2>/dev/null)
if printf '%s' "$sortie" | grep -qi 'uptime'; then
  ok "hostinfo est appelable sans chemin depuis /tmp"
else
  ko "hostinfo introuvable depuis /tmp : ~/bin est-il dans PATH ?"
fi

# --- 2. PATH ------------------------------------------------------------
lpath=$(bash -lic 'printf %s "$PATH"' 2>/dev/null)
case ":$lpath:" in
  *":$HOME/bin:"*) ok "~/bin est présent dans le PATH d'un shell de login" ;;
  *) ko "~/bin absent du PATH de login (regarde ~/.bashrc et ~/.profile)" ;;
esac

# doublons : on relit le .bashrc une seconde fois
dbl=$(bash -lic '. ~/.bashrc >/dev/null 2>&1; printf %s "$PATH"' \
          2>/dev/null)
nb=$(printf '%s' ":$dbl:" | grep -o ":$HOME/bin:" | wc -l)
if [ "${nb:-0}" -le 1 ]; then
  ok "l'ajout au PATH est idempotent"
else
  ko "~/bin apparaît $nb fois après double sourcing (teste avant d'ajouter)"
fi

# --- 3. variables d'environnement --------------------------------------
for v in EDITOR VISUAL PAGER; do
  val=$(bash -lic "printf %s \"\${$v:-}\"" 2>/dev/null)
  if [ -n "$val" ]; then
    ok "$v est défini ($val)"
  else
    ko "$v n'est pas défini dans un shell de login"
  fi
done

lessopt=$(bash -lic 'printf %s "${LESS:-}"' 2>/dev/null)
case "$lessopt" in
  *R*X*|*X*R*) ok "LESS conserve les couleurs (-R) et l'écran (-X)" ;;
  *) ko "LESS ne contient pas -R et -X (couleurs / scrollback)" ;;
esac

# --- 4. options de shell ------------------------------------------------
for o in histappend checkwinsize; do
  if bash -lic "shopt -q $o" >/dev/null 2>&1; then
    ok "shopt $o est activé"
  else
    ko "shopt $o est désactivé (shopt -s $o dans ~/.bashrc)"
  fi
done

# --- 5. prompt ----------------------------------------------------------
ps1=$(bash -lic 'printf %s "$PS1"' 2>/dev/null)
case "$ps1" in
  *'\u'*) u=1 ;; *) u=0 ;;
esac
case "$ps1" in
  *'\h'*) h=1 ;; *) h=0 ;;
esac
case "$ps1" in
  *'\w'*|*'\W'*) w=1 ;; *) w=0 ;;
esac
if [ "$u$h$w" = "111" ]; then
  ok "PS1 affiche utilisateur, hôte et répertoire"
else
  ko "PS1 doit contenir \\u, \\h et \\w"
fi

pcmd=$(bash -lic 'printf %s "${PROMPT_COMMAND:-}"' 2>/dev/null)
if printf '%s%s' "$ps1" "$pcmd" | grep -q '\$?\|RC\|rc\|code'; then
  ok "un mécanisme de code retour est présent dans le prompt"
else
  ko "le prompt n'exploite pas \$? (code retour de la commande précédente)"
fi

# --- 6. silence en non interactif ---------------------------------------
bruit=$(bash -c '. "$HOME/.bashrc"' 2>/dev/null)
if [ -z "$bruit" ]; then
  ok "les fichiers de démarrage n'écrivent rien sur stdout"
else
  ko "sortie parasite au chargement (casse scp/rsync) : ${bruit:0:40}"
fi

if command -v ssh >/dev/null 2>&1 &&
   ssh -o BatchMode=yes -o ConnectTimeout=3 "$USER@localhost" true \
       >/dev/null 2>&1; then
  r=$(ssh -o BatchMode=yes "$USER@localhost" 'echo OK' 2>/dev/null)
  if [ "$r" = "OK" ]; then
    ok "ssh localhost 'echo OK' renvoie exactement OK"
  else
    ko "ssh localhost 'echo OK' renvoie : $r"
  fi
else
  printf '  [SKIP] ssh vers localhost indisponible, test ignoré\n'
fi

echo "Résultat : $PASS réussis, $FAIL échoués"
[ "$FAIL" -eq 0 ]
