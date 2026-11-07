"""Aides progressives des fiches interactives.

Pour chaque item, trois aides au plus, de la plus vague à la plus précise :
  QCM            : éliminer une option, en éliminer une autre (ou le nombre
                   de bonnes réponses), puis une piste tirée du « Pourquoi » ;
  question       : notions à mobiliser, plan de réponse, idée principale ;
  exercice       : outils, première commande, piste ;
  lab, défi      : démarche (étapes), outils, commandes clés ;
  Break & Fix    : outils de diagnostic, premières commandes, cause racine.

Elles sont tirées du corrigé. Un fichier `aides.md` à côté de l'énoncé peut
fournir des aides rédigées, qui remplacent celles-ci pour l'item concerné :

    ## Q33.1

    Première aide (Markdown libre : texte, commandes…)

    ---

    Deuxième aide
"""
from __future__ import annotations

import hashlib
import re
import shlex
from pathlib import Path

FENCE_RE = re.compile(r"^(\s{0,3})(`{3,}|~{3,})\s*([\w+-]*)")
SHELL = {"bash", "sh", "shell", "zsh", ""}
MOTS_SHELL = {"for", "do", "done", "if", "then", "else", "elif", "fi", "while", "until", "case",
              "esac", "in", "function", "{", "}", "(", ")", "!", "[", "[[", "]]", "]", "test",
              "local", "return", "exit", "break", "continue", "true", "false", ":", "export", "set",
              "unset", "source", ".", "cd", "echo", "printf", "sleep", "clear", "read", "trap",
              "shift", "wait", "eval", "declare", "readonly", "let", "alias", "EOF", "else"}
BANALS = MOTS_SHELL | {"mkdir", "rm", "cp", "mv", "touch", "ln", "cat", "ls", "tee", "less", "more",
                       "bash", "sh", "head", "tail", "chmod", "chown", "install", "date", "seq"}
SOUS_COMMANDES = {"git", "systemctl", "apt", "apt-get", "dnf", "yum", "docker", "podman", "kubectl",
                  "ip", "nmcli", "pcs", "zfs", "zpool", "btrfs", "restic", "borg", "reprepro", "virsh",
                  "qm", "pvesm", "pct", "tofu", "terraform", "helm", "ipa", "sssctl", "dkms", "ansible-galaxy",
                  "lvm", "mdadm", "cryptsetup", "firewall-cmd", "ufw", "nft", "snap", "flatpak", "pip",
                  "pipx", "npm", "loginctl", "timedatectl", "hostnamectl", "resolvectl", "networkctl",
                  "journalctl", "perf", "trace-cmd", "createrepo_c", "rpmbuild", "gpg", "openssl", "ssh-keygen",
                  "docker-compose", "compose", "k3s", "crictl", "semanage", "restorecon", "aa-status",
                  "setfacl", "getfacl", "tune2fs", "xfs_admin", "lvcreate", "uv", "poetry", "cargo", "go"}
PREFIXES = {"sudo", "env", "time", "nohup", "exec", "command", "builtin", "nice", "ionice", "stdbuf",
            "unbuffer", "doas"}
HOTE_RE = re.compile(r"^#\s*((?:lab-[a-z0-9-]+|nœud|depuis le shell Proxmox|depuis le nœud|"
                     r"sur le nœud|poste|depuis lab-[a-z0-9-]+)[^#]*?)\s*$", re.I)


# --------------------------------------------------------------------- outils
def blocs(md: str) -> tuple[list[tuple[str, list[str]]], list[str]]:
    """(blocs de code [(langage, lignes)], lignes de prose hors code)."""
    out: list[tuple[str, list[str]]] = []
    prose: list[str] = []
    cour: list[str] | None = None
    fence = lang = ""
    for ligne in md.split("\n"):
        nue = re.sub(r"^(>\s?)+", "", ligne)
        m = FENCE_RE.match(nue)
        if cour is None:
            if m:
                fence, lang, cour = m.group(2), m.group(3).lower(), []
            else:
                prose.append(ligne)
            continue
        if m and m.group(2)[0] == fence[0] and len(m.group(2)) >= len(fence) and not m.group(3):
            out.append((lang, cour))
            cour = None
            continue
        cour.append(nue)
    return out, prose


def commandes(md: str, avant: int | None = None) -> list[tuple[str, str]]:
    """[(hôte ou '', ligne de commande)] des blocs shell et console du corrigé."""
    sortie: list[tuple[str, str]] = []
    bl, _ = blocs(md if avant is None else md[:avant])
    for lang, lignes in bl:
        if lang == "console":
            for li in lignes:
                if li.startswith("$ "):
                    sortie.append(("", li[2:].strip()))
            continue
        if lang not in SHELL or (lignes and lignes[0].startswith("#!")):
            continue
        hote = ""
        heredoc = None
        suite = ""
        for li in lignes:
            if heredoc:
                if li.strip() == heredoc:
                    heredoc = None
                continue
            s = li.rstrip()
            if not s.strip():
                continue
            if s.lstrip().startswith("#"):
                m = HOTE_RE.match(s.strip())
                if m:
                    hote = m.group(1).strip()
                continue
            if suite:
                s = suite + " " + s.strip()
                suite = ""
            if s.endswith("\\"):
                suite = s[:-1].rstrip()
                continue
            if guillemet_ouvert(s):     # chaîne sur plusieurs lignes : la commande continue
                suite = s
                continue
            h = re.search(r"<<-?\s*['\"]?([A-Za-z_]+)['\"]?", s)
            if h and "<<<" not in s:
                heredoc = h.group(1)
            sortie.append((hote, s.strip()))
    return sortie


def guillemet_ouvert(s: str) -> bool:
    sans_commentaire = re.sub(r"\s+#(?:\s.*)?$", "", s)
    for essai in (sans_commentaire, s):
        try:
            shlex.split(essai)
            return False
        except ValueError:
            continue
    return True


def outil(ligne: str) -> str:
    code = ligne.split(" #")[0]
    code = re.split(r"\s(?:\|\||&&|\||;)\s", code)[0]
    try:
        toks = shlex.split(code, posix=True)
    except ValueError:
        toks = code.split()
    i = 0
    while i < len(toks):
        t = toks[i]
        if t in PREFIXES:
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or (toks[i - 1] in ("-u", "-g", "-n", "-c")
                                                                and not toks[i].startswith("-"))):
                if toks[i] in ("-u", "-g", "-n", "-c") and i + 1 < len(toks):
                    i += 2
                else:
                    i += 1
            continue
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", t):
            i += 1
            continue
        if t in ("timeout", "watch") and i + 1 < len(toks):
            i += 1
            while i < len(toks) and (toks[i].startswith("-") or re.match(r"^\d+[smh]?$", toks[i])):
                i += 1
            continue
        break
    if i >= len(toks):
        return ""
    nom = toks[i]
    if "=" in nom or "[" in nom:
        return ""
    if nom.startswith(("/", "./", "~/", "../")):
        nom = nom.split("/")[-1]
    if not re.match(r"^[a-z][a-z0-9._+-]*$", nom):
        return ""
    if nom in SOUS_COMMANDES:
        for t in toks[i + 1:]:
            if t.startswith("-"):
                continue
            if re.match(r"^[a-z][a-z0-9-]*$", t):
                return f"{nom} {t}"
            break
    return nom


def outils(cmds: list[tuple[str, str]], maxi: int = 8, exclus: set | None = None) -> list[str]:
    """Outils dans l'ordre d'apparition, sans les commandes banales (sauf s'il ne reste qu'elles)."""
    exclus = exclus or set()
    tous: list[str] = []
    for _, c in cmds:
        o = outil(c)
        if o and o.split()[0] not in MOTS_SHELL and o.split()[0] not in exclus and o not in tous:
            tous.append(o)
    choisis = [o for o in tous if o.split()[0] not in BANALS]
    return (choisis or tous)[:maxi]


UTILES_EXCLUS = MOTS_SHELL | {"mkdir", "rm", "cp", "mv", "touch", "ln", "tee", "bash", "sh", "install",
                              "date", "seq", "chmod", "chown"}


def utiles(cmds: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """Commandes qui font avancer (lire, diagnostiquer, configurer), sans la plomberie."""
    return [(h, c) for h, c in cmds if outil(c) and outil(c).split()[0] not in UTILES_EXCLUS]


def sans_commentaire(c: str) -> str:
    """Retire le commentaire de fin (souvent la sortie attendue : ce serait la réponse)."""
    nu = re.sub(r"\s+#(?:\s.*)?$", "", c)
    return nu if nu and not guillemet_ouvert(nu) else c


def bloc_bash(cmds: list[tuple[str, str]]) -> str:
    lignes = []
    hote = None
    for h, c in cmds:
        if h and h != hote:
            lignes.append(f"# {h}")
            hote = h
        lignes.append(sans_commentaire(c))
    return "```bash\n" + "\n".join(lignes) + "\n```"


def liste_code(noms: list[str]) -> str:
    return ", ".join(f"`{n}`" for n in noms)


# --------------------------------------------------------------------- prose
def alerte(md: str, titre: str) -> str:
    """Texte d'une alerte dont le titre est donné (« Pourquoi », « Piège »)."""
    lignes = md.split("\n")
    for i, li in enumerate(lignes):
        if re.match(r"^>\s?\*\*" + re.escape(titre), li):
            corps = []
            for suiv in lignes[i + 1:]:
                if not suiv.startswith(">"):
                    break
                corps.append(re.sub(r"^>\s?", "", suiv))
            return "\n".join(corps).strip()
    return ""


def paragraphes(md: str) -> list[str]:
    _, prose = blocs(md)
    texte = "\n".join(l for l in prose if not l.startswith(">"))
    out = []
    for p in re.split(r"\n\s*\n", texte):
        p = p.strip()
        if not p or p.startswith(("#", "|", "<", "---")) or re.match(r"^\*\*[^*]+\*\*\s*:?\s*$", p):
            continue
        out.append(p)
    return out


def phrases(p: str) -> list[str]:
    proteges: list[str] = []

    def garde(m):
        proteges.append(m.group(0))
        return f"\x00{len(proteges) - 1}\x00"

    t = re.sub(r"`[^`]*`", garde, re.sub(r"\s*\n\s*", " ", p))
    morceaux = re.split(r"(?<=[.!?])\s+(?=[A-ZÀ-ÝÉ«`*(\x00])", t)
    return [re.sub(r"\x00(\d+)\x00", lambda m: proteges[int(m.group(1))], x).strip() for x in morceaux if x.strip()]


def premiere_phrase(texte: str, interdit=None, prose_seule: bool = False) -> str:
    """Première phrase substantielle (de préférence avec du code ou du gras)."""
    if not texte:
        return ""
    candidates: list[str] = []
    for p in paragraphes(texte):
        if re.match(r"^(\*|-|\d+\.)\s+", p):
            if prose_seule:
                continue
            p = re.sub(r"^(\*|-|\d+\.)\s+", "", re.sub(r"\s*\n\s*", " ", p))
            p = re.split(r"\s(?:\*|-|\d+\.)\s", p)[0]
        p = re.sub(r"^\*\*R[ée]ponse[^*]*\*\*\s*:?\s*", "", p)
        for ph in phrases(p):
            if len(ph) < 25 or ph.rstrip().endswith(":"):
                continue
            if interdit and interdit(ph):
                continue
            candidates.append(ph)
        if len(candidates) >= 3:
            break
    for ph in candidates[:3]:
        if "`" in ph or "**" in ph:
            return ph
    return candidates[0] if candidates else ""


def notions(md: str, maxi: int = 6) -> list[str]:
    _, prose = blocs(md)
    vus: list[str] = []
    for li in prose:
        if re.match(r"^\s*>?\s*\*\*[^*]+\*\*\s*:?\s*$", li):     # intertitres
            continue
        for m in re.finditer(r"\*\*([^*\n]{2,60}?)\*\*", li):
            t = m.group(1).strip().strip(":").strip()
            if re.match(r"^(R[ée]ponses?|Pourquoi|Pi[èe]ge|Cause racine|Correctif|Pr[ée]vention|"
                        r"D[ée]marche|[ÉE]tapes?|Attention|Astuce|Note|Variante)", t):
                continue
            if len(t.split()) > 5 or len(t) < 3 or t.endswith("."):
                continue
            # un mot courant mis en gras pour l'insistance n'est pas une notion
            if " " not in t and re.fullmatch(r"[a-zàâçéèêëîïôûùüÿœ']+", t):
                continue
            if t.lower() not in (v.lower() for v in vus):
                vus.append(t)
    return vus[:maxi]


def elements(md: str) -> list[str]:
    """Éléments de liste de premier niveau (lignes de suite jointes), hors alertes et code."""
    _, prose = blocs(md)
    out: list[list[str]] = []
    cour: list[str] | None = None
    for li in prose:
        if li.startswith(">"):
            cour = None
            continue
        m = re.match(r"^(?:\d+\.|\*|-)\s+(.*)$", li)
        if m:
            cour = [m.group(1).strip()]
            out.append(cour)
            continue
        if not li.strip():
            cour = None
            continue
        if cour is not None and not li.startswith(("#", "|", "<")):
            cour.append(li.strip())
    return [" ".join(x) for x in out]


def tableau(md: str) -> tuple[list[str], list[list[str]]]:
    """Premier tableau Markdown de la prose : (en-têtes, lignes)."""
    _, prose = blocs(md)
    lignes = []
    for li in prose:
        if li.startswith(">"):
            continue
        if li.strip().startswith("|"):
            lignes.append(li.strip())
        elif lignes:
            break
    if len(lignes) < 3:
        return [], []

    def cellules(l: str) -> list[str]:
        l = l.replace("\\|", "\x00")
        return [c.strip().replace("\x00", "|") for c in l.strip("|").split("|")]

    tetes = cellules(lignes[0])
    corps = [cellules(l) for l in lignes[2:] if not re.match(r"^\|[\s:|-]+\|$", l)]
    return tetes, corps


def structure_script(md: str) -> str:
    """Squelette du premier script du corrigé : sections, fonctions, outils."""
    bl, _ = blocs(md)
    for lang, lignes in bl:
        if lang in SHELL and lignes and lignes[0].startswith("#!"):
            fonctions = [m.group(1) for li in lignes
                         for m in [re.match(r"^\s*(?:function\s+)?([a-z_][a-z0-9_]*)\s*\(\)\s*\{?", li)] if m]
            sections = []
            for li in lignes[1:]:
                m = re.match(r"^#\s*(?:[-=#]{2,}\s*)?(\d+\.\s.+?|[A-ZÉÈÀa-zé][^#]{3,60}?)\s*[-=#]{2,}\s*$", li) \
                    or re.match(r"^#\s*(\d+[.)]\s.+)$", li)
                if m:
                    sections.append(re.sub(r"^\d+[.)]\s*", "", m.group(1).strip()))
            cmds = [("", li.strip()) for li in lignes if li.strip() and not li.lstrip().startswith("#")]
            ot = outils(cmds, exclus=set(fonctions))
            morceaux = []
            if sections:
                morceaux.append("Les grandes parties du script :\n\n" + "\n".join(f"1. {x}" for x in sections[:8]))
            if fonctions:
                morceaux.append("Fonctions : " + liste_code([f + "()" for f in fonctions[:8]]) + ".")
            if ot:
                morceaux.append("Outils appelés : " + liste_code(ot) + ".")
            return "\n\n".join(morceaux)
    return ""


def termes_code(md: str, maxi: int = 7) -> list[str]:
    """Éléments techniques cités en `code` dans la prose (hors alertes)."""
    _, prose = blocs(md)
    vus: list[str] = []
    for li in prose:
        if li.startswith(">"):
            continue
        for m in re.finditer(r"`([^`\n]{1,40})`", li):
            t = m.group(1).strip()
            if t and t not in vus:
                vus.append(t)
    return vus[:maxi]


def sql(md: str) -> tuple[list[str], list[str]]:
    """(fonctions et vues PostgreSQL citées, premières requêtes) des blocs SQL."""
    bl, _ = blocs(md)
    noms: list[str] = []
    requetes: list[str] = []
    for lang, lignes in bl:
        if lang not in ("sql", "psql", "postgresql"):
            continue
        texte = "\n".join(l for l in lignes if not l.strip().startswith("--"))
        for m in re.finditer(r"\b(pg_[a-z_]+|n_dead_tup|n_live_tup)\b", texte):
            if m.group(1) not in noms:
                noms.append(m.group(1))
        for q in re.split(r";\s*\n", texte):
            q = re.sub(r"\s+--.*$", "", q.strip(), flags=re.M).strip()
            if q:
                requetes.append(q.rstrip(";") + ";")
    return noms[:8], requetes[:2]


def briques_yaml(md: str) -> list[str]:
    """Modules Ansible, filtres Jinja, objets Kubernetes, actions de CI cités dans les blocs YAML."""
    bl, _ = blocs(md)
    vus: list[str] = []

    def ajoute(x: str):
        if x not in vus:
            vus.append(x)
    for lang, lignes in bl:
        if lang not in ("yaml", "yml", "jinja", "j2"):
            continue
        texte = "\n".join(lignes)
        for m in re.finditer(r"^\s*(?:-\s+)?((?:ansible|community|kubernetes|containers)\.[\w.]+):", texte, re.M):
            ajoute(m.group(1))
        for m in re.finditer(r"^kind:\s*(\w+)", texte, re.M):
            ajoute(m.group(1))
        for m in re.finditer(r"uses:\s*([\w./-]+)", texte):
            ajoute(m.group(1))
        for expr in re.findall(r"\{\{(.*?)\}\}", texte, re.S):
            for f in re.findall(r"\|\s*([a-z_][a-z0-9_]*)", expr):
                ajoute(f)
    return vus[:10]


def modules_python(md: str) -> list[str]:
    bl, _ = blocs(md)
    vus: list[str] = []
    for lang, lignes in bl:
        if lang not in ("python", "py", "python3"):
            continue
        for li in lignes:
            m = re.match(r"^\s*(?:from\s+([\w.]+)\s+import|import\s+([\w.]+))", li)
            if m:
                n = (m.group(1) or m.group(2)).split(".")[0]
                if n not in vus and n != "__future__":
                    vus.append(n)
    return vus[:8]


def plan(md: str, maxi: int = 6) -> list[str]:
    """Débuts des éléments de liste de premier niveau du corrigé."""
    items = []
    for texte in elements(md):
        mots = texte.split()
        court = " ".join(mots[:12])
        if len(mots) > 12:
            court = court.rstrip(",;:") + " …"
        # ne pas couper un code ou un gras en deux
        if court.count("`") % 2:
            court = court.replace(" …", "") + "` …"
        if court.count("**") % 2:
            court = court.replace(" …", "") + "** …"
        items.append(court)
    return items[:maxi] if len(items) >= 2 else []


def etapes(md: str) -> list[str]:
    out = []
    for li in md.split("\n"):
        m = re.match(r"^\*\*([ÉE]tapes?\s[^*]+?)\*\*\s*$", li) or re.match(r"^#{4,5}\s+(.+)$", li)
        if m:
            out.append(m.group(1).strip())
    return out


def par_etape(md: str) -> list[tuple[str, str]]:
    """[(titre d'étape, morceau de corrigé)]."""
    lignes = md.split("\n")
    out: list[tuple[str, list[str]]] = []
    for li in lignes:
        m = re.match(r"^\*\*([ÉE]tapes?\s[^*]+?)\*\*\s*$", li) or re.match(r"^#{4,5}\s+(.+)$", li)
        if m:
            out.append((m.group(1).strip(), []))
        elif out:
            out[-1][1].append(li)
    return [(t, "\n".join(c)) for t, c in out]


def majuscule(t: str) -> str:
    return t[:1].upper() + t[1:] if t and t[0].islower() else t


def cause_racine(md: str) -> str:
    m = re.search(r"^\*\*Cause racine[^*]*\*\*\s*:?\s*(.+?)(?:\n\s*\n|\Z)", md, re.M | re.S)
    if not m:
        return ""
    ph = phrases(m.group(1))
    return majuscule(ph[0]) if ph else ""


# --------------------------------------------------------------------- aides
def _graine(ident: str) -> int:
    return int(hashlib.sha256(ident.encode()).hexdigest()[:8], 16)


def aides_qcm(ident: str, options: list[str], rep: list[str], md: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    if not rep or not options:
        return out
    fausses = [o for o in options if o not in rep]
    g = _graine(ident)
    ordre = sorted(fausses, key=lambda o: (g >> (ord(o) - 97)) & 7) if fausses else []
    if len(rep) > 1:
        out.append(("Combien ?", f"Il y a **{len(rep)} bonnes réponses** parmi les {len(options)}."))
        if ordre and len(options) - 1 > len(rep):      # sinon l'élimination donnerait tout
            out.append(("Élimination", f"La réponse **{ordre[0]})** est fausse."))
    else:
        if ordre and len(options) - 1 >= 2:            # pas d'élimination sur un vrai/faux
            out.append(("Élimination", f"La réponse **{ordre[0]})** est fausse : écarte-la."))
        if len(ordre) >= 2 and len(options) - 2 >= 2:
            out.append(("Élimination", f"La réponse **{ordre[1]})** est fausse aussi : "
                        f"il reste {len(options) - 2} candidates."))

    def trahit(ph: str) -> bool:
        return bool(re.search(r"(?:^|[\s(])[a-h]\)|[Rr][ée]ponse", ph))

    piste = premiere_phrase(alerte(md, "Pourquoi"), trahit)
    if piste:
        out.append(("Piste", piste))
    return out[:3]


def aides_ecrit(genre: str, md: str) -> list[tuple[str, str]]:
    out = _aides_ecrit(genre, md)
    if len(out) < 2:
        noms, requetes = sql(md)
        if noms and genre in ("exercice", "lab", "defi", "jalon", "breakfix", "incident"):
            out.insert(0, ("SQL", "Les fonctions et vues PostgreSQL utiles : " + liste_code(noms) + "."))
            if requetes:
                out.insert(1, ("Première requête", "```sql\n" + requetes[0] + "\n```"))
    if len(out) < 3:
        by = briques_yaml(md)
        if len(by) >= 2 and not any(t == "Briques" for t, _ in out):
            out.insert(0, ("Briques", "Les briques à assembler (modules, filtres, objets) : " + liste_code(by) + "."))
    if len(out) < 2:
        tc = termes_code(md)
        if len(tc) >= 3:
            out.insert(0, ("Éléments à citer", "Les éléments techniques qu'une bonne réponse mentionne : "
                           + liste_code(tc) + "."))
    if len(out) < 2:
        deja = " ".join(x for _, x in out)
        for titre, texte in (("Piège à éviter", premiere_phrase(alerte(md, "Piège"))),
                             ("Piste", premiere_phrase(alerte(md, "Pourquoi"))),
                             ("Piste", premiere_phrase(md))):
            if texte and texte[:40] not in deja and len(out) < 3:
                if titre == "Piste" and any(t == "Piste" for t, _ in out):
                    continue
                out.append((titre, texte))
                deja += " " + texte
            if len(out) >= 2:
                break
    return out[:3]


def _aides_ecrit(genre: str, md: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    cmds = commandes(md)
    if genre in ("breakfix", "incident"):
        m = re.search(r"^\*\*(?:Correctif|R[ée]paration|Solution)", md, re.M)
        diag = commandes(md, m.start()) if m else []
        if not diag:
            m = re.search(r"^\*\*Cause racine", md, re.M)
            diag = (commandes(md, m.start()) if m else []) or cmds
        ot = outils(diag)
        if ot:
            out.append(("Outils de diagnostic", f"Les outils qui font parler la machine ici : {liste_code(ot)}."))
        u = utiles(diag)[:3]
        if u:
            out.append(("Par où commencer", "Les premières commandes de diagnostic :\n\n" + bloc_bash(u)))
        cr = cause_racine(md)
        if cr:
            out.append(("Cause racine", cr))
        elif len(out) < 3:
            p = premiere_phrase(alerte(md, "Pourquoi"))
            if p:
                out.append(("Piste", p))
        return out[:3]

    if genre in ("lab", "defi", "jalon"):
        et = par_etape(md)
        if len(et) >= 2:
            out.append(("Démarche", "Les étapes du corrigé :\n\n" + "\n".join(f"1. {t}" for t, _ in et)))
            ot = outils(cmds)
            if ot:
                out.append(("Outils", f"Les outils à mobiliser : {liste_code(ot)}."))
            cles = []
            dejas: set[str] = set()
            for titre, morceau in et:
                for h, c in utiles(commandes(morceau)):
                    if c not in dejas:
                        cles.append((titre, (h, c)))
                        dejas.add(c)
                        break
            if cles:
                lignes = []
                for titre, (h, c) in cles[:6]:
                    lignes.append(f"# {titre.replace(chr(96), '')}" + (f" ({h})" if h else ""))
                    lignes.append(sans_commentaire(c))
                out.append(("Commandes clés", "Une commande de départ par étape :\n\n```bash\n"
                            + "\n".join(lignes) + "\n```"))
            return out[:3]
        ot = outils(cmds)
        no = notions(md)
        sq = structure_script(md)
        mp = modules_python(md)
        if ot:
            out.append(("Outils", f"Les outils à mobiliser : {liste_code(ot)}."))
        elif mp:
            out.append(("Modules Python", f"Les modules utiles : {liste_code(mp)}."))
        elif no:
            out.append(("Notions", "Les notions en jeu : " + ", ".join(no) + "."))
        if sq:
            out.append(("Structure", sq))
        u = utiles(cmds)
        if u:
            out.append(("Premières commandes", bloc_bash(u[:3])))
            if len(u) > 3:
                out.append(("Suite", "Et ensuite :\n\n" + bloc_bash(u[3:7])))
        if len(out) < 3:
            p = premiere_phrase(alerte(md, "Pourquoi")) or premiere_phrase(md)
            if p:
                out.append(("Piste", p))
        return out[:3]

    if genre == "exercice":
        ot = outils(cmds)
        mp = modules_python(md)
        if ot:
            out.append(("Outils", f"Les outils à utiliser (voir leur `man`) : {liste_code(ot)}."))
        elif mp:
            out.append(("Modules Python", f"Les modules utiles : {liste_code(mp)}."))
        sq = structure_script(md)
        if sq and not cmds:
            out.append(("Structure", sq))
        u = utiles(cmds) or cmds
        if u:
            out.append(("Première commande", "Commence par :\n\n" + bloc_bash(u[:1])))
        p = premiere_phrase(alerte(md, "Pourquoi"))
        if p:
            out.append(("Piste", p))
        if len(out) < 2:
            no = notions(md)
            if no:
                out.insert(0, ("Notions", "Les notions en jeu : " + ", ".join(no) + "."))
        return out[:3]

    # question ouverte (et défaut)
    tetes, lignes = tableau(md)
    if len(lignes) >= 2 and len(tetes) >= 2:
        out.append(("Plan", f"Les {len(lignes)} éléments à couvrir ({tetes[0].lower()}) :\n\n"
                    + "\n".join(f"1. {l[0]}" for l in lignes[:10])))
        premier = lignes[0]
        detail = " ; ".join(f"*{t}* : {c}" for t, c in zip(tetes[1:], premier[1:]) if c)
        out.append(("Exemple", f"Pour le premier, **{premier[0]}** — {detail}."))
        p = premiere_phrase(alerte(md, "Pourquoi"))
        if p:
            out.append(("Piste", p))
        return out[:3]
    pl = plan(md)
    texte_plan = " ".join(pl)
    no = [n for n in notions(md) if f"**{n}" not in texte_plan]
    if len(no) >= 3:
        out.append(("Notions", "Les notions à mobiliser : " + ", ".join(no) + "."))
    if pl:
        out.append(("Plan", "Un plan de réponse possible :\n\n" + "\n".join(f"1. {x}" for x in pl)))
    p = premiere_phrase(md, prose_seule=True) or premiere_phrase(md)
    if p and not any(p[:40] in md2 for _, md2 in out):
        out.append(("Piste", p))
    if len(out) < 2:
        ot = outils(cmds)
        if ot:
            out.insert(0, ("Outils", f"Les outils concernés : {liste_code(ot)}."))
    return out[:3]


# --------------------------------------------------------------------- rédigées
def redigees(path: Path) -> dict[str, list[str]]:
    """aides.md : {'q33-1': [md aide 1, md aide 2…]} (identifiant en minuscules)."""
    if not path.exists():
        return {}
    out: dict[str, list[str]] = {}
    cle = None
    cour: list[str] = []
    fence = ""

    def clore():
        if cle is not None:
            morceaux, buf, f2 = [], [], ""
            for li in cour:
                m = FENCE_RE.match(li)
                if m:
                    f2 = "" if f2 else m.group(2)
                if not f2 and re.match(r"^---\s*$", li):
                    morceaux.append("\n".join(buf).strip())
                    buf = []
                else:
                    buf.append(li)
            morceaux.append("\n".join(buf).strip())
            out[cle] = [x for x in morceaux if x]

    for li in path.read_text(encoding="utf-8").split("\n"):
        m = FENCE_RE.match(li)
        if m:
            fence = "" if fence else m.group(2)
        if not fence and li.startswith("## "):
            clore()
            cle = li[3:].strip().lower().replace(".", "-")
            cour = []
            continue
        if cle is not None:
            cour.append(li)
    clore()
    return out
