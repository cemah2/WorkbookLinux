#!/usr/bin/env bash
# setup_M31.sh — prépare le terrain du module 31 (perf, ftrace, eBPF)
# À lancer avec sudo sur lab-web. Idempotent.
#
# Compile et installe trois programmes de charge (sources dans
# /usr/local/src/lab31/), et leurs services, NON démarrés.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "à lancer avec sudo" >&2; exit 1; }
LAB_USER="${SUDO_USER:-mathieu}"
LAB_HOME="$(getent passwd "$LAB_USER" | cut -d: -f6)"
[ -n "$LAB_HOME" ] || { echo "utilisateur $LAB_USER inconnu" >&2; exit 1; }
SRC=/usr/local/src/lab31

echo "== Préparation du module 31 =="
command -v gcc >/dev/null || {
  echo "   installation de gcc…"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -q gcc libc6-dev >/dev/null; }
install -d -m 755 "$SRC" /var/lib/lab31 /usr/local/lib/lab31
install -d -o "$LAB_USER" -g "$LAB_USER" -m 755 "$LAB_HOME/lab31" "$LAB_HOME/lab31/defi"

# ---------------------------------------------------------------------------
cat > "$SRC/lab31-calcul.c" <<'C'
/* lab31-calcul — recherche de motif volontairement naïve (module 31)
 * Usage : lab31-calcul [--rapide]
 * Affiche toutes les 5 s le nombre de passes par seconde. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define TAILLE (8u << 20)

/* compte les occurrences de motif en comparant à CHAQUE position */
__attribute__((noinline, noclone))
static unsigned long compte_naif(const char *texte, size_t n, const char *motif, size_t m)
{
    unsigned long c = 0;
    for (size_t i = 0; i + m <= n; i++) {
        size_t j = 0;
        while (j < m && texte[i + j] == motif[j])
            j++;
        if (j == m)
            c++;
    }
    return c;
}

/* même résultat, avec memmem() de la glibc */
__attribute__((noinline, noclone))
static unsigned long compte_rapide(const char *texte, size_t n, const char *motif, size_t m)
{
    unsigned long c = 0;
    const char *p = texte, *fin = texte + n;
    while ((p = memmem(p, (size_t)(fin - p), motif, m)) != NULL) {
        c++;
        p++;
    }
    return c;
}

__attribute__((noinline, noclone))
static unsigned long analyse(const char *texte, int rapide)
{
    static const char motif[] = "aaaaaaaaaaac";   /* 'c' n'apparaît jamais */
    return rapide ? compte_rapide(texte, TAILLE, motif, sizeof motif - 1)
                  : compte_naif(texte, TAILLE, motif, sizeof motif - 1);
}

__attribute__((noinline, noclone))
static unsigned long traite_documents(const char *texte, int rapide)
{
    return analyse(texte, rapide);
}

static void prepare(char *t, size_t n)
{
    unsigned int x = 12345;
    for (size_t i = 0; i < n; i++) {
        x = x * 1103515245u + 12345u;   /* texte pseudo-aléatoire, reproductible */
        t[i] = "aab"[(x >> 16) % 3];     /* alphabet pauvre : beaucoup de débuts de motif */
    }
}

__attribute__((noinline, noclone))
static void boucle(const char *texte, int rapide)
{
    unsigned long passes = 0, dernier = 0;
    struct timespec t0, t;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        dernier = traite_documents(texte, rapide);
        passes++;
        clock_gettime(CLOCK_MONOTONIC, &t);
        double dt = (double)(t.tv_sec - t0.tv_sec) + (double)(t.tv_nsec - t0.tv_nsec) / 1e9;
        if (dt >= 5.0) {
            printf("%s : %.1f passes/s (%lu occurrences par passe)\n",
                   rapide ? "rapide" : "naif", (double)passes / dt, dernier);
            fflush(stdout);
            passes = 0;
            t0 = t;
        }
    }
}

int main(int argc, char **argv)
{
    int rapide = argc > 1 && strcmp(argv[1], "--rapide") == 0;
    char *texte = malloc(TAILLE);
    if (!texte)
        return 1;
    prepare(texte, TAILLE);
    boucle(texte, rapide);
    return 0;
}
C

cat > "$SRC/lab31-ecrit.c" <<'C'
/* lab31-ecrit — écrit 2 Mo avec des write() de taille réglable (module 31)
 * Usage : lab31-ecrit [--tampon N] [fichier]      (défaut : 1 octet par write) */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    size_t tampon = 1;
    const char *chemin = "/var/tmp/lab31-sortie";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--tampon") == 0 && i + 1 < argc)
            tampon = strtoul(argv[++i], NULL, 10);
        else
            chemin = argv[i];
    }
    if (tampon == 0)
        tampon = 1;
    const size_t total = 2u << 20;
    char *buf = malloc(tampon);
    if (!buf)
        return 1;
    memset(buf, 'x', tampon);
    int fd = open(chemin, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        perror(chemin);
        return 1;
    }
    for (size_t fait = 0; fait < total;) {
        size_t n = total - fait < tampon ? total - fait : tampon;
        ssize_t r = write(fd, buf, n);
        if (r < 0) {
            perror("write");
            return 1;
        }
        fait += (size_t)r;
    }
    close(fd);
    printf("%zu octets écrits par blocs de %zu\n", total, tampon);
    return 0;
}
C

cat > "$SRC/lab31-journal.c" <<'C'
/* lab31-journal — « requêtes » durables : calcul, journal, fsync (module 31)
 * Usage : lab31-journal [--groupe N] [fichier]     (fsync toutes les N requêtes) */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double maintenant(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

__attribute__((noinline, noclone))
static void calcul(void)            /* quelques dizaines de microsecondes de « métier » */
{
    volatile unsigned long x = 0;
    for (unsigned long i = 0; i < 20000; i++)
        x += i * i;
}

__attribute__((noinline, noclone))
static int enregistre(int fd, unsigned long n, unsigned groupe)
{
    char ligne[96];
    int l = snprintf(ligne, sizeof ligne, "commande %lu acceptee\n", n);
    if (write(fd, ligne, (size_t)l) != l)
        return -1;
    if ((n + 1) % groupe == 0 && fsync(fd) != 0)   /* la ligne est sur le disque */
        return -1;
    return 0;
}

int main(int argc, char **argv)
{
    unsigned groupe = 1;
    const char *chemin = "/var/lib/lab31/journal.log";
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--groupe") == 0 && i + 1 < argc)
            groupe = (unsigned)strtoul(argv[++i], NULL, 10);
        else
            chemin = argv[i];
    }
    if (groupe == 0)
        groupe = 1;
    int fd = open(chemin, O_WRONLY | O_CREAT | O_APPEND, 0640);
    if (fd < 0) {
        perror(chemin);
        return 1;
    }
    unsigned long n = 0, nb = 0;
    double cumul = 0, pire = 0, t0 = maintenant();
    for (;;) {
        double a = maintenant();
        calcul();
        if (enregistre(fd, n++, groupe) != 0) {
            perror("journal");
            return 1;
        }
        double d = maintenant() - a;
        cumul += d;
        if (d > pire)
            pire = d;
        nb++;
        if (n % 100000 == 0 && lseek(fd, 0, SEEK_END) > (50L << 20))
            if (ftruncate(fd, 0) != 0)     /* le journal de démonstration ne grossit pas sans fin */
                perror("ftruncate");
        double dt = maintenant() - t0;
        if (dt >= 5.0) {
            printf("%.0f requêtes/s, latence moyenne %.3f ms, pire %.2f ms (fsync toutes les %u)\n",
                   (double)nb / dt, cumul / (double)nb * 1e3, pire * 1e3, groupe);
            fflush(stdout);
            nb = 0;
            cumul = pire = 0;
            t0 = maintenant();
        }
    }
}
C

# --- compilation : optimisé, symboles, pointeurs de cadre ----------------------
for p in lab31-calcul lab31-ecrit lab31-journal; do
  gcc -O2 -g -fno-omit-frame-pointer -Wall -o "/usr/local/bin/$p" "$SRC/$p.c"
done
echo "   programmes : /usr/local/bin/lab31-{calcul,ecrit,journal} (sources : $SRC)"

# --- services, non démarrés ----------------------------------------------------
cat > /etc/systemd/system/lab31-calcul.service <<'EOF'
[Unit]
Description=lab31-calcul : charge CPU du module 31

[Service]
ExecStart=/usr/local/bin/lab31-calcul
Nice=5
EOF
cat > /etc/systemd/system/lab31-journal.service <<'EOF'
[Unit]
Description=lab31-journal : requêtes durables du module 31

[Service]
ExecStart=/usr/local/bin/lab31-journal
EOF
systemctl daemon-reload
echo "   services lab31-calcul et lab31-journal installés (non démarrés)"

# --- bilan --------------------------------------------------------------------------
echo
echo "== Prérequis =="
ok()    { printf '  [ OK ] %s\n' "$1"; }
avert() { printf '  [AVERT] %s\n' "$1"; }
[ -r /sys/kernel/btf/vmlinux ] && ok "BTF du noyau présent (/sys/kernel/btf/vmlinux)" \
                               || avert "pas de BTF : bpftrace sera limité"
grep -qw pmu /proc/cpuinfo 2>/dev/null || grep -q 'arch_perfmon' /proc/cpuinfo \
  && ok "compteurs matériels exposés à la VM (arch_perfmon)" \
  || avert "pas de compteurs matériels : perf utilisera cpu-clock (type de CPU « host » ?)"
for c in perf bpftrace trace-cmd execsnoop-bpfcc; do
  command -v "$c" >/dev/null && ok "$c présent" || avert "$c absent (voir 31.1 : paquets)"
done
[ -d "$LAB_HOME/FlameGraph" ] && ok "FlameGraph cloné" \
  || avert "git clone https://github.com/brendangregg/FlameGraph.git ~/FlameGraph"
